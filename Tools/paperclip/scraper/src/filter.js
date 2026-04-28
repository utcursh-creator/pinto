// 4-stage commenter filter. Applied BEFORE BDR handoff so we never spend Apollo
// credits on commenters who are obviously not ICP. Each stage rejects fast and
// records historical state in SQLite so future runs can dedupe.
//
// Stage 1: real account (real name + has profile pic)
// Stage 2: hard exclusion (recruiter, student, UiPath, Power Automate, etc.)
// Stage 3: ICP keyword scoring (Segment 1 vs Segment 2, min score 0.25)
// Stage 4: dedupe against SQLite history of previously-seen profile URLs

import Database from 'better-sqlite3';
import path from 'path';
import fs from 'fs';
import { fileURLToPath } from 'url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const DEFAULT_DB_PATH = path.join(__dirname, '..', 'state', 'scrape-history.db');

// Segment 1: AI automation agency owners (PRIMARY ICP)
const SEGMENT_1_KEYWORDS = [
  'automation', 'automate', 'n8n', 'make.com', 'zapier', 'no-code', 'no code', 'nocode',
  'workflow', 'integration', 'agency', 'consultant', 'consulting', 'founder', 'owner',
  'ceo', 'agency owner', 'ai agent', 'ai automation', 'rpa', 'process automation',
  'fractional', 'building', 'builder', 'systems', 'ops',
];

// Segment 2: AI content creator businesses (SECONDARY ICP)
const SEGMENT_2_KEYWORDS = [
  'creator', 'educator', 'community', 'course creator', 'content creator', 'youtuber',
  'creator economy', 'fractional', 'cmo', 'consultant', 'coach', 'mentor', 'newsletter',
  'skool', 'circle community', 'paid community', 'cohort',
];

// Hard exclusions — these are checked BEFORE segment scoring and reject immediately.
// UiPath / Power Automate / Workato / Blue Prism users are explicitly excluded:
// they are NOT in the n8n / Make / Zapier ICP and routinely appear in mining results.
const EXCLUDE_KEYWORDS = [
  'student', 'looking for work', 'open to work', 'seeking', 'aspiring',
  'enterprise', 'fortune 500', 'manager at', 'director at', 'vp of', 'svp',
  'recruiter', 'talent acquisition', 'hr ', 'human resources',
  'uipath', 'power automate', 'workato', 'blue prism',
];

const PLACEHOLDER_NAMES = new Set(['LinkedIn Member', 'LinkedIn User', '']);

// Normalization: 4 keyword hits = perfect score (1.0). Below 0.25 means
// fewer than 1 hit, which we treat as no signal.
const SCORE_NORMALIZER = 4;
const MIN_SCORE = 0.25;

export class CommenterFilter {
  constructor(log, dbPath = DEFAULT_DB_PATH) {
    this.log = log;
    fs.mkdirSync(path.dirname(dbPath), { recursive: true });
    this.db = new Database(dbPath);
    this.db.exec(`
      CREATE TABLE IF NOT EXISTS scraped_commenters (
        profile_url TEXT PRIMARY KEY,
        name TEXT,
        headline TEXT,
        first_seen TEXT,
        last_seen TEXT,
        passed_filter INTEGER,
        filter_score REAL,
        segment INTEGER
      )
    `);
    this.upsertStmt = this.db.prepare(`
      INSERT INTO scraped_commenters
        (profile_url, name, headline, first_seen, last_seen, passed_filter, filter_score, segment)
      VALUES (@profile_url, @name, @headline, @first_seen, @last_seen, @passed_filter, @filter_score, @segment)
      ON CONFLICT(profile_url) DO UPDATE SET
        last_seen = excluded.last_seen,
        passed_filter = excluded.passed_filter,
        filter_score = excluded.filter_score,
        segment = excluded.segment
    `);
    this.checkStmt = this.db.prepare('SELECT 1 FROM scraped_commenters WHERE profile_url = ?');
  }

  // Stage 1: real account check
  isRealAccount(commenter) {
    const name = (commenter.name || '').trim();
    if (PLACEHOLDER_NAMES.has(name)) return false;
    if (!commenter.has_profile_image) return false;
    return true;
  }

  // Stage 2: hard exclusion via headline keyword check
  isExcluded(commenter) {
    const headline = (commenter.headline || '').toLowerCase();
    return EXCLUDE_KEYWORDS.some((kw) => headline.includes(kw));
  }

  // Stage 3: ICP keyword scoring. Returns the higher-scoring segment, or null
  // if neither segment scores above MIN_SCORE.
  scoreSegment(commenter) {
    const headline = (commenter.headline || '').toLowerCase();
    if (!headline) return { segment: null, score: 0 };

    const seg1Hits = SEGMENT_1_KEYWORDS.filter((kw) => headline.includes(kw)).length;
    const seg2Hits = SEGMENT_2_KEYWORDS.filter((kw) => headline.includes(kw)).length;

    const seg1Score = Math.min(seg1Hits / SCORE_NORMALIZER, 1.0);
    const seg2Score = Math.min(seg2Hits / SCORE_NORMALIZER, 1.0);

    if (seg1Score === 0 && seg2Score === 0) return { segment: null, score: 0 };

    // Tie goes to Segment 1 (primary ICP)
    if (seg1Score >= seg2Score) return { segment: 1, score: seg1Score };
    return { segment: 2, score: seg2Score };
  }

  // Stage 4: dedupe against SQLite history
  isDuplicate(commenter) {
    return this.checkStmt.get(commenter.profile_url) !== undefined;
  }

  // Run all 4 stages over a batch and return passed + rejection breakdown
  filter(commenters) {
    const results = {
      passed: [],
      rejected: { not_real: 0, excluded: 0, no_keywords: 0, duplicate: 0 },
    };

    for (const c of commenters) {
      // Stage 1
      if (!this.isRealAccount(c)) {
        results.rejected.not_real++;
        continue;
      }

      // Stage 2
      if (this.isExcluded(c)) {
        results.rejected.excluded++;
        this.recordHistorical(c, false, 0, null);
        continue;
      }

      // Stage 3
      const { segment, score } = this.scoreSegment(c);
      if (segment === null || score < MIN_SCORE) {
        results.rejected.no_keywords++;
        this.recordHistorical(c, false, score, null);
        continue;
      }

      // Stage 4
      if (this.isDuplicate(c)) {
        results.rejected.duplicate++;
        continue;
      }

      // Passed all 4 stages
      const enriched = { ...c, segment, filter_score: score };
      results.passed.push(enriched);
      this.recordHistorical(c, true, score, segment);
    }

    this.log.info(
      `Filter: ${results.passed.length} passed, ` +
        `not_real=${results.rejected.not_real}, ` +
        `excluded=${results.rejected.excluded}, ` +
        `no_keywords=${results.rejected.no_keywords}, ` +
        `duplicate=${results.rejected.duplicate}`
    );
    return results;
  }

  recordHistorical(commenter, passed, score, segment) {
    const now = new Date().toISOString();
    this.upsertStmt.run({
      profile_url: commenter.profile_url,
      name: commenter.name || null,
      headline: commenter.headline || null,
      first_seen: now,
      last_seen: now,
      passed_filter: passed ? 1 : 0,
      filter_score: score,
      segment,
    });
  }

  close() {
    this.db.close();
  }
}

export const _internal = {
  SEGMENT_1_KEYWORDS,
  SEGMENT_2_KEYWORDS,
  EXCLUDE_KEYWORDS,
  PLACEHOLDER_NAMES,
  MIN_SCORE,
};
