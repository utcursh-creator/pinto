---
type: reference
date: 2026-04-05
project: gtm-strategy
status: active
tags: [apollo, api, b2b-prospecting, lead-generation, cold-outreach]
---

# Apollo.io API Research — B2B Prospecting Capabilities

Research date: 2026-04-05

---

## 1. Free Tier Limits

### Credits

| Credit Type | Free Tier (Corporate Domain) | Free Tier (No Corporate Domain) |
|---|---|---|
| Email credits | 10,000/month/account | 100/month/account |
| Mobile credits | 5/month | 5/month |
| Export credits | 10/month | 10/month |
| AI email composer | 5,000/month | 5,000/month |

### API Rate Limits

| Plan | Requests/Minute | Daily Limit |
|---|---|---|
| **Free** | 50 | 600 |
| **Basic** ($59/mo) | 200 | 2,000 |
| **Professional** ($99/mo) | 200 | 2,000 |
| **Organization** ($149/mo) | 200+ | Custom |

Rate limiting uses a **fixed-window strategy** — 50 requests can fire at any interval within a 60-second window, then resets. Exceeding limits returns **HTTP 429**.

### Endpoint-Specific Rate Limits (Reported)

| Endpoint Category | Per Minute | Burst |
|---|---|---|
| People Search, Enrichment, Org Enrichment | 100/min | 10/sec |
| Sequences/Campaigns | 50/min | 5/sec |
| Bulk Operations | 10/min | 2/sec |

### Free Tier Features

- 2 sequences
- Basic filtering
- 1 buying intent topic
- 2 lead scores
- Chrome extension
- Basic reporting
- **Limited API calls** (no further specification beyond rate limits above)

### Credit Costs Per Action

| Action | Credit Cost |
|---|---|
| Business email found | 1 credit |
| Mobile number revealed | 8 credits |
| Export/sync to CRM | 1 credit |
| Additional credits (overage) | ~$0.20 each |

---

## 2. People Search API

### Endpoint

```
POST https://api.apollo.io/api/v1/mixed_people/api_search
```

### Key Characteristics

- **Does NOT consume credits** (search itself is free)
- **Does NOT return** email addresses or phone numbers directly (need enrichment for that)
- Display limit: **50,000 records** (100 per page, max 500 pages)
- Designed for prospecting net new contacts

### Complete Filter Parameters

#### Person-Level Filters

| Parameter | Type | Description | Example Values |
|---|---|---|---|
| `person_titles` | array | Job titles | `["founder", "CEO", "automation lead"]` |
| `person_locations` | array | Where people live | `["California, US", "London, UK"]` |
| `person_seniorities` | array | Seniority levels | `["owner", "founder", "c_suite", "partner", "vp", "head", "director", "manager", "senior", "entry", "intern"]` |
| `contact_email_status` | array | Email verification | `["verified"]` |
| `include_similar_titles` | boolean | Expand title matching | `true` |

#### Organization-Level Filters (Applied to Person's Employer)

| Parameter | Type | Description | Example Values |
|---|---|---|---|
| `organization_num_employees_ranges` | array | Employee count ranges | `["1,10", "11,20", "21,50", "51,100"]` |
| `organization_locations` | array | Company HQ location | `["United States", "Germany"]` |
| `q_organization_domains_list` | array | Specific company domains | `["apollo.io", "hubspot.com"]` |
| `organization_ids` | array | Apollo org IDs | - |
| `revenue_range` | object | Min/max revenue | `{"min": 0, "max": 1000000}` |

#### Technology Filters (Critical for Your ICP)

| Parameter | Type | Description |
|---|---|---|
| `currently_using_any_of_technology_uids` | array | Companies using ANY of these tools |
| `currently_using_all_of_technology_uids` | array | Companies using ALL of these tools |
| `currently_not_using_any_of_technology_uids` | array | Exclude companies using these tools |

**Technology UID format**: Use underscores for spaces/dots. Examples:
- `salesforce`
- `google_analytics`
- `wordpress_org`
- `zapier` (confirmed trackable)
- `hubspot`

**Important**: Apollo tracks **1,500+ technologies**. Technology data is scraped from the web and third-party sources. The full list of supported technology UIDs is available as a CSV via the Apollo platform.

**Key question for your use case**: Whether `make_com` and `n8n` are in the tracked technology list needs to be verified by querying the API or checking in-platform. Zapier is confirmed as a trackable technology. Make.com and n8n are smaller/newer tools and may have limited coverage.

#### Job Posting Filters

| Parameter | Type | Description |
|---|---|---|
| `q_organization_job_titles` | array | Active job postings at employer |
| `organization_job_locations` | array | Where they're recruiting |
| `organization_num_jobs_range` | object | Min/max active postings |
| `organization_job_posted_at_range` | object | Date range for postings |

#### Pagination

| Parameter | Type | Default | Max |
|---|---|---|---|
| `page` | integer | 1 | 500 |
| `per_page` | integer | 25 | 100 |

### Response Fields (Person Object)

Each person returned includes:

- `id`, `first_name`, `last_name`, `name`
- `title`, `headline`
- `linkedin_url`, `photo_url`
- `email_status` (but NOT the actual email — need enrichment)
- `state`, `city`, `country`
- `seniority`, `departments`, `subdepartments`, `functions`
- `is_likely_to_engage`, `intent_strength`
- `employment_history[]` (array of past roles)
- `organization` object (nested company data)
- `organization_id`

### Example cURL Request

```bash
curl --request POST \
  --url 'https://api.apollo.io/api/v1/mixed_people/api_search' \
  --header 'Content-Type: application/json' \
  --header 'x-api-key: YOUR_API_KEY' \
  --data '{
    "person_titles": ["founder", "CEO", "owner"],
    "person_seniorities": ["owner", "founder", "c_suite"],
    "organization_num_employees_ranges": ["1,10"],
    "currently_using_any_of_technology_uids": ["zapier"],
    "organization_locations": ["United States", "United Kingdom", "Australia", "Canada", "Germany"],
    "per_page": 25,
    "page": 1
  }'
```

---

## 3. Data Quality for Niche Segments

### Database Size

- **210M+ contacts**, **35M+ companies**
- 65+ data attributes per contact

### Small Business Coverage (1-10 People)

**Honest assessment: Mixed.**

- Apollo's strength is mid-market and enterprise. Small businesses (1-10 people) have notably **less complete data**.
- Common issues: outdated titles, missing emails, wrong company associations for solo operators.
- Email accuracy for small/niche businesses: users report **~65% overall accuracy**, with bounce rates up to **35%** in niche segments.
- Mobile phone data described as **"abysmal"** in user reviews.

### Technology Stack Tracking

- Apollo tracks **1,500+ technologies** via web scraping and third-party data.
- Technology data is **not real-time** — refresh cadence is periodic (exact frequency undisclosed).
- **Zapier**: Confirmed as a trackable technology.
- **Make.com / n8n**: Less certain. These are smaller tools with less web footprint. Apollo's technology detection relies on JavaScript snippets, DNS records, and job postings — tools like n8n (self-hosted) would be particularly hard to detect.
- Technology tracking works better for **SaaS companies with public-facing websites** than for agencies/consultants who use tools internally.

### Data Freshness

- Apollo does not disclose exact refresh cycles.
- User reports suggest data can be **6-12 months stale** for smaller companies.
- **Recommendation**: Always verify emails before sending (use a tool like NeverBounce or ZeroBounce on top of Apollo's verification).

### European Market Quality

- US data is strongest. European data, especially for smaller companies, is notably **weaker**.
- Germany coverage exists but is less comprehensive than US/UK.

---

## 4. Company Enrichment API

### Endpoint

```
GET https://api.apollo.io/api/v1/organizations/enrich?domain=example.com
```

### Request Parameters

| Parameter | Type | Description |
|---|---|---|
| `domain` | string | Company domain (no www. or @) |
| `organization_name` | string | Alternative: company name |

**Note**: This endpoint **consumes credits**.

### Response Fields (Organization Object)

**Core Details:**
- Organization ID, name, website URL
- LinkedIn URL, Twitter, Facebook profiles
- Primary domain, Alexa ranking
- Founded year, phone number

**Financial & Scale:**
- `annual_revenue` (numeric + printed format)
- `total_funding` (numeric + printed format)
- `latest_funding_round_date`, `latest_funding_stage`
- `funding_events[]` (full history with investor names and amounts)
- `estimated_num_employees`

**Operational:**
- `industry` classification + `industry_tag_ids`
- `keywords[]` (business focus descriptors)
- `secondary_industries`
- Retail location count

**Technology Stack:**
- `current_technologies[]` (with categories)
- `technology_names[]` (array)

**Additional:**
- SEO descriptions, short descriptions
- Crunchbase URL
- Suborganization data

### Bulk Enrichment

```
POST https://api.apollo.io/api/v1/organizations/bulk_enrich
```

- Up to **10 companies per call**
- Rate limit: 1/10th of single enrichment rates

---

## 5. API Authentication

### API Key Method

```
Header: x-api-key: YOUR_API_KEY
```

Or alternatively:

```
Header: Authorization: Bearer YOUR_API_KEY
```

### How to Get an API Key

1. Log into Apollo.io
2. Go to Settings > Integrations > API
3. Create a new API key (requires master key for search endpoints)

### OAuth 2.0 (Partners Only)

For partner integrations, Apollo supports OAuth 2.0 authorization flow. Not needed for direct API usage.

---

## 6. Endpoint Reference Summary

### Search Endpoints (No Credits)

| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/mixed_people/api_search` | POST | People search with filters |
| `/api/v1/mixed_companies/search` | POST | Organization search |

### Enrichment Endpoints (Consume Credits)

| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/people/match` | POST | People enrichment (1 person) |
| `/api/v1/people/bulk_match` | POST | Bulk people enrichment (up to 10) |
| `/api/v1/organizations/enrich` | GET | Organization enrichment (1 company) |
| `/api/v1/organizations/bulk_enrich` | POST | Bulk org enrichment (up to 10) |

### Other Endpoints

| Endpoint | Method | Description |
|---|---|---|
| `/api/v1/organizations/{id}` | GET | Complete org info (credits) |
| `/api/v1/organizations/{id}/job_postings` | GET | Org job postings (credits) |
| `/api/v1/people/{id}` | GET | Person details (credits) |
| `/api/v1/news_articles/search` | POST | News articles (credits) |

---

## 7. Organization Search API

### Endpoint

```
POST https://api.apollo.io/api/v1/mixed_companies/search
```

### Complete Filter Parameters

| Parameter | Type | Description |
|---|---|---|
| `q_organization_domains_list` | array | Company domains |
| `organization_locations` | array | HQ location |
| `organization_not_locations` | array | Exclude locations |
| `organization_num_employees_ranges` | array | Employee count ranges |
| `revenue_range` | object | Min/max revenue |
| `currently_using_any_of_technology_uids` | array | Technologies in use |
| `q_organization_keyword_tags` | array | Keywords (e.g., "consulting", "automation") |
| `q_organization_name` | string | Company name search |
| `latest_funding_amount_range` | object | Most recent funding |
| `total_funding_range` | object | All funding rounds |
| `latest_funding_date_range` | object | Funding date range |
| `q_organization_job_titles` | array | Active job titles |
| `organization_job_locations` | array | Job locations |
| `organization_num_jobs_range` | object | Active postings range |
| `organization_job_posted_at_range` | object | Job posting dates |

---

## 8. Practical Assessment for GTM Strategy

### What Works for Your ICP

- **Searching by employee count** (1-10 people) + **seniority** (founder/owner/c_suite) is solid.
- **Location filtering** across US, UK, Australia, Canada, Germany is fully supported.
- **Keyword tags** like "automation", "AI", "consulting" can help narrow results.
- **Job posting filters** can reveal companies actively hiring for automation roles (signal of growth/need).
- **Search is free** — you can run unlimited filtered searches without burning credits.

### What May Not Work

- **Technology detection for Make.com / n8n**: Likely limited. These tools don't leave obvious web footprints. Zapier is more detectable.
- **Small agency data quality**: 1-5 person agencies often have incomplete or stale data in Apollo. Expect ~65% accuracy.
- **European small business coverage**: Weaker than US.
- **Mobile numbers**: Essentially unusable at this scale.

### Recommended Approach

1. Use **People Search API** (free) to build target lists filtered by title + company size + location + keywords.
2. Use **Organization Search** to find companies using Zapier (as a proxy for automation-forward businesses).
3. **Enrich** only the top matches to get emails (1 credit each).
4. **Verify emails** with a secondary tool before cold outreach.
5. With free tier: 10,000 email credits/month is enough for meaningful prospecting at your scale.
6. **Rate limit reality**: 600 API calls/day on free tier means ~24 pages of search results/day (25 per page = ~600 contacts) or ~600 individual enrichments.

### Alternative Signal Strategy

Since technology detection for Make.com/n8n is unreliable, consider:
- Search for people with titles containing "automation" at small companies
- Filter by keyword tags: "AI", "automation", "workflow"
- Look for companies with job postings mentioning automation tools
- Use company enrichment on known prospects (domain-based) rather than broad tech filters

---

## Sources

- [Apollo API Documentation](https://docs.apollo.io/)
- [Apollo API Authentication](https://docs.apollo.io/reference/authentication)
- [People API Search](https://docs.apollo.io/reference/people-api-search)
- [Organization Enrichment](https://docs.apollo.io/reference/organization-enrichment)
- [Organization Search](https://docs.apollo.io/reference/organization-search)
- [API Pricing](https://docs.apollo.io/docs/api-pricing)
- [Find People Using Filters](https://docs.apollo.io/docs/find-people-using-filters)
- [Rate Limits](https://docs.apollo.io/reference/rate-limits)
- [Apollo Pricing Breakdown 2026 - Warmly](https://www.warmly.ai/p/blog/apollo-pricing)
- [Apollo API Guide - Galadon](https://galadon.com/apollo-io-api)
- [Apollo.io Review - Sparkle](https://sparkle.io/blog/apollo-io-review/)
- [Apollo MCP Server - GitHub](https://github.com/AgentX-ai/apollo-io-mcp-server)
- [Apollo Advanced Filters](https://www.apollo.io/magazine/advanced-filtering-apollo)
