import React from "react";
import {
  AbsoluteFill,
  useCurrentFrame,
  useVideoConfig,
  interpolate,
  spring,
  Sequence,
  Easing,
} from "remotion";

// VibeLife brand palette
const C = {
  void: "#0a0a0a",
  charcoal: "#141414",
  surface: "#1c1c1c",
  gold: "#d4a574",
  goldLight: "#e8c9a0",
  goldDark: "#b8864e",
  teal: "#38b2ac",
  tealLight: "#5cd4ce",
  coral: "#e8795e",
  white: "#ffffff",
  dim: "#ffffff80",
  faint: "#ffffff40",
  ghost: "#ffffff10",
};

const EASE_OUT = Easing.bezier(0.25, 0.1, 0.25, 1);
const EASE_EXPO = Easing.bezier(0.16, 1, 0.3, 1);

// ─── Reusable animation helpers ───
const fadeIn = (frame: number, start: number, dur = 20) => ({
  opacity: interpolate(frame, [start, start + dur], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_OUT,
  }),
  transform: `translateY(${interpolate(frame, [start, start + dur], [40, 0], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_EXPO,
  })}px)`,
});

const fadeInX = (frame: number, start: number, dur = 20, dist = 60) => ({
  opacity: interpolate(frame, [start, start + dur], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_OUT,
  }),
  transform: `translateX(${interpolate(frame, [start, start + dur], [dist, 0], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_EXPO,
  })}px)`,
});

const scaleIn = (frame: number, start: number, dur = 25) => ({
  opacity: interpolate(frame, [start, start + dur], [0, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_OUT,
  }),
  transform: `scale(${interpolate(frame, [start, start + dur], [0.8, 1], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_EXPO,
  })})`,
});

// ─── Floating Orb ───
const Orb: React.FC<{
  x: number; y: number; size: number; color: string;
  frame: number; speed?: number; blur?: number; opacity?: number;
}> = ({ x, y, size, color, frame, speed = 1, blur = 80, opacity = 0.15 }) => (
  <div style={{
    position: "absolute",
    left: x, top: y + Math.sin(frame * 0.012 * speed) * 25,
    width: size, height: size,
    borderRadius: "50%",
    background: `radial-gradient(circle, ${color} 0%, transparent 70%)`,
    filter: `blur(${blur}px)`,
    opacity,
  }} />
);

// ─── Horizontal Line ───
const AnimatedLine: React.FC<{
  frame: number; start: number; dur?: number;
  y: number; color: string; width?: number;
}> = ({ frame, start, dur = 40, y, color, width = 300 }) => {
  const w = interpolate(frame, [start, start + dur], [0, width], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_EXPO,
  });
  return (
    <div style={{
      position: "absolute", left: "50%", top: y,
      transform: "translateX(-50%)",
      width: w, height: 2,
      background: `linear-gradient(90deg, transparent, ${color}, transparent)`,
      borderRadius: 1,
    }} />
  );
};

// ─── Number Counter ───
const Counter: React.FC<{
  frame: number; start: number; dur?: number;
  from: number; to: number; suffix?: string; prefix?: string;
  style?: React.CSSProperties;
}> = ({ frame, start, dur = 40, from, to, suffix = "", prefix = "", style = {} }) => {
  const val = Math.round(interpolate(frame, [start, start + dur], [from, to], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_OUT,
  }));
  return <span style={style}>{prefix}{val}{suffix}</span>;
};

// ─── Progress Ring ───
const ProgressRing: React.FC<{
  frame: number; start: number; dur?: number;
  size: number; stroke: number; color: string; progress: number;
}> = ({ frame, start, dur = 50, size, stroke, color, progress }) => {
  const r = (size - stroke) / 2;
  const circumference = 2 * Math.PI * r;
  const pct = interpolate(frame, [start, start + dur], [0, progress], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_OUT,
  });
  return (
    <svg width={size} height={size} style={{ transform: "rotate(-90deg)" }}>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none"
        stroke={`${color}15`} strokeWidth={stroke} />
      <circle cx={size / 2} cy={size / 2} r={r} fill="none"
        stroke={color} strokeWidth={stroke}
        strokeDasharray={circumference}
        strokeDashoffset={circumference * (1 - pct / 100)}
        strokeLinecap="round" />
    </svg>
  );
};


// ════════════════════════════════════════════════════════════════
//  SCENE 1: THE HOOK  (0–7s, 0–210 frames)
//  Cinematic. Bold. Unmissable text.
// ════════════════════════════════════════════════════════════════
const SceneHook: React.FC = () => {
  const frame = useCurrentFrame();

  // Curtain wipe
  const curtainY = interpolate(frame, [0, 35], [0, -105], {
    extrapolateRight: "clamp", easing: EASE_EXPO,
  });

  const pillFade = fadeIn(frame, 15, 18);
  const line1 = fadeIn(frame, 25, 28);
  const line2 = fadeIn(frame, 55, 28);
  const subtitleFade = fadeIn(frame, 90, 20);

  // Accent line grows under headline
  const underW = interpolate(frame, [80, 125], [0, 600], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_EXPO,
  });

  // Exit
  const exitOp = interpolate(frame, [175, 208], [1, 0], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });

  return (
    <AbsoluteFill style={{ background: C.void, overflow: "hidden" }}>
      <Orb x={-150} y={100} size={700} color={C.gold} frame={frame} opacity={0.1} blur={100} />
      <Orb x={1500} y={500} size={500} color={C.teal} frame={frame} speed={0.7} opacity={0.07} blur={90} />

      {/* Curtain */}
      <div style={{ position: "absolute", inset: 0, background: C.void, transform: `translateY(${curtainY}%)`, zIndex: 10 }} />

      <div style={{
        display: "flex", flexDirection: "column", justifyContent: "center",
        alignItems: "center", height: "100%", padding: "0 140px", opacity: exitOp,
      }}>
        {/* Glass pill label */}
        <div style={{ ...pillFade, marginBottom: 48 }}>
          <div style={{
            padding: "12px 32px", borderRadius: 50,
            background: `linear-gradient(135deg, ${C.gold}12, ${C.gold}06)`,
            border: `1px solid ${C.gold}30`,
            display: "flex", alignItems: "center", gap: 12,
          }}>
            <div style={{ width: 8, height: 8, borderRadius: "50%", background: C.gold, boxShadow: `0 0 15px ${C.gold}` }} />
            <span style={{
              fontSize: 18, letterSpacing: "0.3em", color: C.gold,
              textTransform: "uppercase", fontFamily: "system-ui, -apple-system, sans-serif", fontWeight: 600,
            }}>
              For AI Automation Agencies
            </span>
          </div>
        </div>

        {/* Line 1 — huge */}
        <div style={{
          fontSize: 110, fontWeight: 800, fontFamily: "system-ui, -apple-system, sans-serif",
          color: `${C.white}55`, lineHeight: 1.05, textAlign: "center",
          letterSpacing: "-0.03em", ...line1,
        }}>
          Your sales engine works.
        </div>

        {/* Line 2 — gradient, huge */}
        <div style={{
          fontSize: 110, fontWeight: 800, fontFamily: "system-ui, -apple-system, sans-serif",
          textAlign: "center", lineHeight: 1.05, marginTop: 8,
          position: "relative", letterSpacing: "-0.03em", ...line2,
        }}>
          <span style={{
            background: `linear-gradient(135deg, ${C.coral}, ${C.gold})`,
            WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent",
          }}>
            Your delivery doesn't.
          </span>
          {/* Underline */}
          <div style={{
            position: "absolute", bottom: -12, left: "50%", transform: "translateX(-50%)",
            width: underW, height: 4, borderRadius: 2,
            background: `linear-gradient(90deg, transparent, ${C.coral}80, ${C.gold}60, transparent)`,
          }} />
        </div>

        {/* Supporting subtitle */}
        <div style={{
          fontSize: 28, color: `${C.white}50`, fontFamily: "system-ui, sans-serif",
          fontWeight: 400, textAlign: "center", marginTop: 48, maxWidth: 700,
          lineHeight: 1.5, ...subtitleFade,
        }}>
          You close deals. But your fulfillment partner ghosts, hand-offs break, and clients never adopt.
        </div>
      </div>
    </AbsoluteFill>
  );
};


// ════════════════════════════════════════════════════════════════
//  SCENE 2: THE PAIN  (7–17s, 210–510 frames)
//  Three dramatic pain cards with big icons and stats
// ════════════════════════════════════════════════════════════════
const ScenePain: React.FC = () => {
  const frame = useCurrentFrame();

  const labelFade = fadeIn(frame, 5, 18);

  const pains = [
    {
      num: "01",
      headline: "The Freelancer\nVanishes",
      body: "They deliver v1, send the invoice, and ghost. Your client has a system nobody can maintain.",
      stat: { value: 73, suffix: "%", label: "churn within 90 days" },
      accent: C.coral, delay: 30,
    },
    {
      num: "02",
      headline: "The Agency\nHand-Off",
      body: "A dev shop builds it, zips the repo, walks away. Clients open a dashboard they don't understand.",
      stat: { value: 40, suffix: "K", prefix: "$", label: "average wasted per deal" },
      accent: `${C.white}70`, delay: 100,
    },
    {
      num: "03",
      headline: "Zero\nAdoption",
      body: "The tool works in a demo. Nobody trained the team. Three months later, they cancel.",
      stat: { value: 12, suffix: "%", label: "avg tool adoption rate" },
      accent: C.coral, delay: 170,
    },
  ];

  const exitOp = interpolate(frame, [270, 298], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <AbsoluteFill style={{ background: C.void, overflow: "hidden", opacity: exitOp }}>
      <Orb x={1300} y={50} size={600} color={C.coral} frame={frame} opacity={0.08} blur={100} />
      <Orb x={-100} y={600} size={400} color={C.gold} frame={frame} speed={0.5} opacity={0.05} blur={80} />

      <div style={{
        display: "flex", flexDirection: "column", justifyContent: "center",
        height: "100%", padding: "0 100px",
      }}>
        {/* Section label */}
        <div style={{ display: "flex", alignItems: "center", gap: 16, marginBottom: 56, ...labelFade }}>
          <div style={{ width: 60, height: 3, background: C.coral, borderRadius: 2 }} />
          <span style={{
            fontSize: 18, letterSpacing: "0.3em", color: C.coral,
            textTransform: "uppercase", fontFamily: "system-ui, sans-serif", fontWeight: 700,
          }}>
            Sound Familiar?
          </span>
        </div>

        {/* Pain cards — large */}
        <div style={{ display: "flex", gap: 32 }}>
          {pains.map((pain, i) => {
            const entry = fadeIn(frame, pain.delay, 26);
            return (
              <div key={i} style={{ flex: 1, ...entry }}>
                <div style={{
                  background: `linear-gradient(180deg, ${C.charcoal}, ${C.void})`,
                  border: `1px solid ${pain.accent}18`,
                  borderRadius: 28,
                  padding: "40px 36px",
                  height: "100%",
                  display: "flex", flexDirection: "column",
                  position: "relative", overflow: "hidden",
                }}>
                  {/* Background number */}
                  <div style={{
                    position: "absolute", top: -10, right: 16,
                    fontSize: 140, fontWeight: 900, fontFamily: "system-ui, sans-serif",
                    color: `${pain.accent}08`, lineHeight: 1,
                  }}>
                    {pain.num}
                  </div>

                  {/* Headline */}
                  <div style={{
                    fontSize: 36, fontWeight: 800, fontFamily: "system-ui, sans-serif",
                    color: C.white, lineHeight: 1.15, marginBottom: 16,
                    whiteSpace: "pre-line", position: "relative",
                  }}>
                    {pain.headline}
                  </div>

                  {/* Body */}
                  <div style={{
                    fontSize: 20, color: C.dim, fontFamily: "system-ui, sans-serif",
                    lineHeight: 1.6, flex: 1, position: "relative",
                  }}>
                    {pain.body}
                  </div>

                  {/* Stat */}
                  <div style={{
                    marginTop: 28, paddingTop: 20,
                    borderTop: `1px solid ${pain.accent}15`,
                    position: "relative",
                  }}>
                    <div style={{
                      fontSize: 48, fontWeight: 800, fontFamily: "system-ui, sans-serif",
                      color: pain.accent, lineHeight: 1,
                    }}>
                      <Counter frame={frame} start={pain.delay + 20} dur={35}
                        from={0} to={pain.stat.value}
                        prefix={pain.stat.prefix || ""} suffix={pain.stat.suffix}
                        style={{ color: pain.accent }}
                      />
                    </div>
                    <div style={{
                      fontSize: 20, color: C.dim, fontFamily: "system-ui, sans-serif",
                      marginTop: 8, textTransform: "uppercase", letterSpacing: "0.12em",
                    }}>
                      {pain.stat.label}
                    </div>
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </AbsoluteFill>
  );
};


// ════════════════════════════════════════════════════════════════
//  SCENE 3: THE SHIFT — "What if your engineer never left?"
//  (17–25s, 510–750 frames)
//  Big reveal → FDE title → three pillar cards with progress rings
// ════════════════════════════════════════════════════════════════
const SceneShift: React.FC = () => {
  const frame = useCurrentFrame();
  const { fps } = useVideoConfig();

  // Phase 1: Question
  const qFade = fadeIn(frame, 8, 25);
  const qOut = interpolate(frame, [65, 90], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  // Phase 2: FDE reveal
  const revealOp = interpolate(frame, [85, 110], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const titleScale = scaleIn(frame, 90, 28);

  // Pillars
  const pillars = [
    {
      word: "Embed", desc: "We join your team on day one.\nSame Slack. Same standups.\nSame goals.",
      stat: 100, statLabel: "Team Integration",
      color: C.teal, delay: 140,
    },
    {
      word: "Build", desc: "Ship production-grade AI systems\nin rapid 2-week sprint cycles.",
      stat: 95, statLabel: "On-Time Delivery",
      color: C.gold, delay: 160,
    },
    {
      word: "Ensure", desc: "Train the client's team.\nIterate until they actually use it.\nEvery single day.",
      stat: 95, statLabel: "Adoption Rate",
      color: C.teal, delay: 180,
    },
  ];

  const exitOp = interpolate(frame, [220, 238], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <AbsoluteFill style={{ background: C.void, overflow: "hidden", opacity: exitOp }}>
      <Orb x={700} y={150} size={700} color={C.gold} frame={frame} opacity={0.06} blur={120} />
      <Orb x={200} y={600} size={500} color={C.teal} frame={frame} speed={0.6} opacity={0.05} blur={90} />

      {/* Phase 1: Question */}
      <div style={{
        position: "absolute", inset: 0,
        display: "flex", flexDirection: "column",
        justifyContent: "center", alignItems: "center",
        opacity: qOut,
      }}>
        <div style={{
          fontSize: 100, fontWeight: 800, fontFamily: "system-ui, sans-serif",
          color: C.white, textAlign: "center", lineHeight: 1.1,
          letterSpacing: "-0.03em", ...qFade,
        }}>
          What if your engineer
          <br />
          <span style={{
            background: `linear-gradient(135deg, ${C.gold}, ${C.teal})`,
            WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent",
          }}>
            never left?
          </span>
        </div>
      </div>

      {/* Phase 2: FDE Reveal */}
      <div style={{
        position: "absolute", inset: 0,
        display: "flex", flexDirection: "column",
        justifyContent: "center", alignItems: "center",
        padding: "0 80px", opacity: revealOp,
      }}>
        {/* Pill label */}
        <div style={{ ...fadeIn(frame, 90, 15), marginBottom: 24 }}>
          <div style={{
            padding: "10px 26px", borderRadius: 50,
            background: `${C.teal}10`,
            border: `1px solid ${C.teal}30`,
            display: "inline-flex", alignItems: "center", gap: 10,
          }}>
            <div style={{ width: 7, height: 7, borderRadius: "50%", background: C.teal, boxShadow: `0 0 12px ${C.teal}` }} />
            <span style={{
              fontSize: 16, letterSpacing: "0.35em", color: C.teal,
              textTransform: "uppercase", fontFamily: "system-ui, sans-serif", fontWeight: 700,
            }}>
              Introducing
            </span>
          </div>
        </div>

        {/* FDE Title — massive */}
        <div style={{ marginBottom: 20, ...titleScale }}>
          <div style={{
            fontSize: 108, fontWeight: 900, fontFamily: "system-ui, sans-serif",
            textAlign: "center", lineHeight: 1.0, letterSpacing: "-0.04em",
          }}>
            <span style={{
              background: `linear-gradient(135deg, ${C.gold}, ${C.tealLight})`,
              WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent",
            }}>
              Forward Deployed
            </span>
            <br />
            <span style={{ color: C.white }}>Engineering</span>
          </div>
        </div>

        {/* Subtitle */}
        <div style={{
          fontSize: 26, color: C.dim, fontFamily: "system-ui, sans-serif",
          fontWeight: 400, textAlign: "center", maxWidth: 550, marginBottom: 56,
          lineHeight: 1.5, ...fadeIn(frame, 120, 18),
        }}>
          Pioneered by Palantir. Adapted for AI automation partnerships.
        </div>

        {/* Three pillar cards with progress rings */}
        <div style={{ display: "flex", gap: 28, width: "100%", maxWidth: 1050 }}>
          {pillars.map((p, i) => {
            const entry = fadeIn(frame, p.delay, 22);
            return (
              <div key={i} style={{ flex: 1, ...entry }}>
                <div style={{
                  background: `linear-gradient(180deg, ${C.charcoal}, ${C.void})`,
                  border: `1px solid ${p.color}20`,
                  borderRadius: 24, padding: "36px 28px",
                  textAlign: "center",
                }}>
                  {/* Progress ring + stat */}
                  <div style={{ position: "relative", width: 80, height: 80, margin: "0 auto 20px" }}>
                    <ProgressRing frame={frame} start={p.delay + 5} dur={40}
                      size={80} stroke={4} color={p.color} progress={p.stat} />
                    <div style={{
                      position: "absolute", inset: 0,
                      display: "flex", alignItems: "center", justifyContent: "center",
                      fontSize: 24, fontWeight: 800, fontFamily: "system-ui, sans-serif", color: p.color,
                    }}>
                      <Counter frame={frame} start={p.delay + 5} dur={40}
                        from={0} to={p.stat} suffix="%" style={{ color: p.color }} />
                    </div>
                  </div>

                  {/* Word */}
                  <div style={{
                    fontSize: 32, fontWeight: 800, fontFamily: "system-ui, sans-serif",
                    color: p.color, marginBottom: 12,
                  }}>
                    {p.word}
                  </div>

                  {/* Stat label */}
                  <div style={{
                    fontSize: 17, color: C.dim, fontFamily: "system-ui, sans-serif",
                    textTransform: "uppercase", letterSpacing: "0.15em", marginBottom: 16,
                  }}>
                    {p.statLabel}
                  </div>

                  {/* Description */}
                  <div style={{
                    fontSize: 18, color: C.dim, fontFamily: "system-ui, sans-serif",
                    lineHeight: 1.55, whiteSpace: "pre-line",
                  }}>
                    {p.desc}
                  </div>
                </div>
              </div>
            );
          })}
        </div>
      </div>
    </AbsoluteFill>
  );
};


// ════════════════════════════════════════════════════════════════
//  SCENE 4: THE JOURNEY  (25–37s, 750–1110 frames)
//  Premium timeline — big readable cards with animated progress
// ════════════════════════════════════════════════════════════════
const SceneJourney: React.FC = () => {
  const frame = useCurrentFrame();

  const titleFade = fadeIn(frame, 8, 20);

  const phases = [
    {
      week: "Week 1–2", title: "Deep Dive",
      items: ["Audit client workflows", "Map every pain point", "Ship first automation"],
      color: C.gold, delay: 50,
    },
    {
      week: "Week 3–6", title: "Build & Ship",
      items: ["Rapid sprint cycles", "Weekly client demos", "Real-time progress"],
      color: C.teal, delay: 115,
    },
    {
      week: "Week 7–12", title: "Adopt & Scale",
      items: ["Hands-on team training", "Workflow refinement", "95%+ adoption target"],
      color: C.gold, delay: 180,
    },
    {
      week: "Ongoing", title: "Partnership",
      items: ["Monthly check-ins", "Feature expansion", "System evolves with them"],
      color: C.teal, delay: 245,
    },
  ];

  // Timeline progress
  const lineProgress = interpolate(frame, [50, 300], [0, 100], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp", easing: EASE_OUT,
  });

  const exitOp = interpolate(frame, [340, 358], [1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  return (
    <AbsoluteFill style={{ background: C.void, overflow: "hidden", opacity: exitOp }}>
      <Orb x={-80} y={250} size={600} color={C.gold} frame={frame} opacity={0.06} blur={100} />
      <Orb x={1500} y={550} size={500} color={C.teal} frame={frame} speed={0.7} opacity={0.05} blur={90} />

      <div style={{
        display: "flex", flexDirection: "column", justifyContent: "center",
        height: "100%", padding: "50px 80px",
      }}>
        {/* Title */}
        <div style={{ marginBottom: 64, ...titleFade }}>
          <div style={{ display: "flex", alignItems: "center", gap: 14, marginBottom: 16 }}>
            <div style={{ width: 50, height: 3, background: C.gold, borderRadius: 2 }} />
            <span style={{
              fontSize: 18, letterSpacing: "0.3em", color: C.gold,
              textTransform: "uppercase", fontFamily: "system-ui, sans-serif", fontWeight: 700,
            }}>
              The Journey
            </span>
          </div>
          <div style={{
            fontSize: 72, fontWeight: 800, fontFamily: "system-ui, sans-serif",
            color: C.white, letterSpacing: "-0.03em", lineHeight: 1.05,
          }}>
            From kickoff to{" "}
            <span style={{
              background: `linear-gradient(90deg, ${C.teal}, ${C.gold})`,
              WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent",
            }}>
              full adoption
            </span>
          </div>
        </div>

        {/* Timeline with line */}
        <div style={{ position: "relative" }}>
          {/* Horizontal connecting line */}
          <div style={{
            position: "absolute", top: 0, left: 24, right: 24,
            height: 3, overflow: "hidden", borderRadius: 2,
            background: `${C.white}08`,
          }}>
            <div style={{
              width: `${lineProgress}%`, height: "100%",
              background: `linear-gradient(90deg, ${C.gold}, ${C.teal}, ${C.gold})`,
            }} />
          </div>

          <div style={{ display: "flex", gap: 24, paddingTop: 40 }}>
            {phases.map((phase, i) => {
              const entry = fadeIn(frame, phase.delay, 24);
              return (
                <div key={i} style={{ flex: 1, ...entry }}>
                  {/* Dot on timeline */}
                  <div style={{
                    width: 16, height: 16, borderRadius: "50%", background: phase.color,
                    marginTop: -48, marginBottom: 28, marginLeft: 24,
                    boxShadow: `0 0 25px ${phase.color}60`,
                    border: `3px solid ${C.void}`,
                  }} />

                  <div style={{
                    background: `linear-gradient(180deg, ${C.charcoal}, ${C.void})`,
                    border: `1px solid ${phase.color}18`,
                    borderRadius: 24, padding: "32px 28px",
                  }}>
                    {/* Week label */}
                    <span style={{
                      fontSize: 18, letterSpacing: "0.2em", color: phase.color,
                      textTransform: "uppercase", fontFamily: "system-ui, sans-serif", fontWeight: 700,
                    }}>
                      {phase.week}
                    </span>

                    <div style={{
                      fontSize: 32, fontWeight: 800, fontFamily: "system-ui, sans-serif",
                      color: C.white, margin: "12px 0 20px", lineHeight: 1.1,
                    }}>
                      {phase.title}
                    </div>

                    {/* Checklist */}
                    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
                      {phase.items.map((item, j) => {
                        const itemOp = interpolate(frame, [phase.delay + 25 + j * 10, phase.delay + 38 + j * 10], [0, 1], {
                          extrapolateLeft: "clamp", extrapolateRight: "clamp",
                        });
                        return (
                          <div key={j} style={{
                            display: "flex", alignItems: "center", gap: 12, opacity: itemOp,
                          }}>
                            <div style={{
                              width: 24, height: 24, borderRadius: 8,
                              background: `${phase.color}15`,
                              border: `1px solid ${phase.color}30`,
                              display: "flex", alignItems: "center", justifyContent: "center",
                              fontSize: 14, color: phase.color, flexShrink: 0,
                              fontWeight: 700,
                            }}>
                              ✓
                            </div>
                            <span style={{
                              fontSize: 20, color: `${C.white}90`, fontFamily: "system-ui, sans-serif",
                            }}>
                              {item}
                            </span>
                          </div>
                        );
                      })}
                    </div>
                  </div>
                </div>
              );
            })}
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};


// ════════════════════════════════════════════════════════════════
//  SCENE 5: CTA  (37–45s, 1110–1350 frames)
//  Bold closer with stat counters and particles
// ════════════════════════════════════════════════════════════════
const SceneCTA: React.FC = () => {
  const frame = useCurrentFrame();

  const tagScale = scaleIn(frame, 12, 30);
  const subFade = fadeIn(frame, 50, 20);
  const statsFade = fadeIn(frame, 75, 22);
  const logoFade = fadeIn(frame, 105, 18);

  // Ambient glow
  const glowOp = interpolate(frame, [12, 50, 200], [0, 0.12, 0.07], {
    extrapolateLeft: "clamp", extrapolateRight: "clamp",
  });

  // Rising particles
  const particles = Array.from({ length: 20 }, (_, i) => {
    const startY = 1100;
    const speed = 1.2 + (i % 5) * 0.35;
    const x = 100 + (i * 97) % 1720;
    const entryF = 30 + (i % 7) * 6;
    const op = interpolate(frame, [entryF, entryF + 20, entryF + 130], [0, 0.2 + (i % 3) * 0.06, 0], {
      extrapolateLeft: "clamp", extrapolateRight: "clamp",
    });
    return { x, y: startY - (frame - entryF) * speed, size: 2 + (i % 3), opacity: op, color: i % 2 === 0 ? C.gold : C.teal };
  });

  return (
    <AbsoluteFill style={{ background: C.void, overflow: "hidden" }}>
      {/* Ambient glow */}
      <div style={{
        position: "absolute", width: 800, height: 800, borderRadius: "50%",
        background: `radial-gradient(circle, ${C.gold} 0%, transparent 60%)`,
        top: "50%", left: "50%", transform: "translate(-50%, -50%)", opacity: glowOp,
      }} />

      {/* Particles */}
      {particles.map((p, i) => (
        <div key={i} style={{
          position: "absolute", left: p.x, top: p.y, width: p.size, height: p.size,
          borderRadius: "50%", background: p.color, opacity: p.opacity,
        }} />
      ))}

      <div style={{
        display: "flex", flexDirection: "column", justifyContent: "center",
        alignItems: "center", height: "100%", position: "relative",
      }}>
        {/* Tagline — massive */}
        <div style={{
          fontSize: 110, fontWeight: 900, fontFamily: "system-ui, sans-serif",
          textAlign: "center", lineHeight: 1.08, marginBottom: 32,
          letterSpacing: "-0.04em", ...tagScale,
        }}>
          <span style={{ color: C.gold }}>You sell.</span>{" "}
          <span style={{ color: C.white }}>We build.</span>
          <br />
          <span style={{ color: C.teal }}>They adopt.</span>
        </div>

        {/* Subtitle */}
        <div style={{
          fontSize: 26, color: C.dim, fontFamily: "system-ui, sans-serif",
          fontWeight: 400, textAlign: "center", maxWidth: 600, marginBottom: 56,
          lineHeight: 1.5, ...subFade,
        }}>
          Forward Deployed Engineering for AI automation agencies.
          <br />No long contracts. No hand-offs. Just results.
        </div>

        {/* Stats row */}
        <div style={{
          display: "flex", gap: 80, marginBottom: 56, ...statsFade,
        }}>
          {[
            { from: 0, to: 50, suffix: "+", label: "Implementations" },
            { from: 0, to: 95, suffix: "%", label: "Adoption Rate" },
            { from: 0, to: 90, suffix: " day", label: "Time to Value" },
          ].map((s, i) => (
            <div key={i} style={{ textAlign: "center" }}>
              <div style={{
                fontSize: 64, fontWeight: 900, fontFamily: "system-ui, sans-serif",
                color: C.gold, lineHeight: 1,
              }}>
                <Counter frame={frame} start={75 + i * 8} dur={35}
                  from={s.from} to={s.to} suffix={s.suffix}
                  style={{ color: C.gold }}
                />
              </div>
              <div style={{
                fontSize: 20, color: C.dim, fontFamily: "system-ui, sans-serif",
                textTransform: "uppercase", letterSpacing: "0.15em", marginTop: 10,
              }}>
                {s.label}
              </div>
            </div>
          ))}
        </div>

        {/* Logo */}
        <div style={{ ...logoFade }}>
          <span style={{
            fontSize: 44, fontFamily: "system-ui, sans-serif",
            fontWeight: 900, letterSpacing: "-0.02em",
            background: `linear-gradient(135deg, ${C.gold}, ${C.teal})`,
            WebkitBackgroundClip: "text", WebkitTextFillColor: "transparent",
          }}>
            VibeLife
          </span>
        </div>
      </div>
    </AbsoluteFill>
  );
};


// ════════════════════════════════════════════════════════════════
//  MAIN COMPOSITION
// ════════════════════════════════════════════════════════════════
export const FDEExplainer: React.FC = () => {
  return (
    <AbsoluteFill style={{ background: C.void }}>
      {/* Scene 1: Hook (0–7s) */}
      <Sequence from={0} durationInFrames={210}>
        <SceneHook />
      </Sequence>

      {/* Scene 2: Pain (7–17s) */}
      <Sequence from={210} durationInFrames={300}>
        <ScenePain />
      </Sequence>

      {/* Scene 3: The Shift (17–25s) */}
      <Sequence from={510} durationInFrames={240}>
        <SceneShift />
      </Sequence>

      {/* Scene 4: The Journey (25–37s) */}
      <Sequence from={750} durationInFrames={360}>
        <SceneJourney />
      </Sequence>

      {/* Scene 5: CTA (37–45s) */}
      <Sequence from={1110} durationInFrames={240}>
        <SceneCTA />
      </Sequence>
    </AbsoluteFill>
  );
};
