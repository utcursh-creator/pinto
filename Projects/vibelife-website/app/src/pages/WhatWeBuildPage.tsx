import { useState } from 'react';
import { NewNavbar } from '@/components/layout/NewNavbar';
import { FooterSection } from '@/components/sections/FooterSection';
import { WaitlistModal } from '@/components/ui/WaitlistModal';
import { FloatingSphere } from '@/components/animation/FloatingSphere';
import { FadeInView } from '@/components/animation/FadeInView';
import { GlowCard } from '@/components/animation/GlowCard';
import { GrainOverlay } from '@/components/effects/AtmosphericEffects';
import { CustomCursor } from '@/components/animation/CustomCursor';
import { MagneticElement } from '@/components/animation/MagneticElement';
import { AnimatedCounter } from '@/components/animation/AnimatedCounter';
import { ArrowRight, Workflow, BarChart3, FileText, Headphones, Rocket, Repeat } from 'lucide-react';

const implementations = [
    {
        title: 'Client Onboarding Automation',
        desc: 'Contracts, access provisioning, kickoff sequences — all automated. One agency went from 3-day onboarding to 20 minutes per client.',
        metric: '90% faster',
        domain: 'Operations',
        glow: 'gold' as const,
        icon: Rocket,
    },
    {
        title: 'Client Reporting Dashboards',
        desc: 'Real-time dashboards pulling from multiple sources. Built in your stack, deployed in your client\'s environment. They see results, you save hours.',
        metric: '95% adoption',
        domain: 'Reporting',
        glow: 'teal' as const,
        icon: BarChart3,
    },
    {
        title: 'Lead Enrichment Pipelines',
        desc: 'Automated research, scoring, and routing. One agency doubled their client\'s qualified pipeline in 6 weeks without adding headcount.',
        metric: '2x pipeline',
        domain: 'Sales Automation',
        glow: 'coral' as const,
        icon: Workflow,
    },
    {
        title: 'SOPs & Documentation Systems',
        desc: 'Video walkthroughs, written guides, and handoff docs generated alongside every build. Your clients understand what they have and how it works.',
        metric: 'Every project',
        domain: 'Documentation',
        glow: 'gold' as const,
        icon: FileText,
    },
    {
        title: 'Workflow Orchestration',
        desc: 'n8n, Make, Zapier — whatever your team already uses. We connect existing tools into intelligent pipelines with triggers, routing, and error handling.',
        metric: '50+ integrations',
        domain: 'Automation',
        glow: 'teal' as const,
        icon: Repeat,
    },
    {
        title: 'Adoption & Support Systems',
        desc: 'Check-in sequences, usage tracking, and escalation workflows. We don\'t just deploy — we make sure your clients actually use what we build.',
        metric: '0% churn',
        domain: 'Adoption',
        glow: 'coral' as const,
        icon: Headphones,
    },
];

export function WhatWeBuildPage() {
    const [isModalOpen, setIsModalOpen] = useState(false);
    const handleBookSandbox = () => setIsModalOpen(true);

    return (
        <div className="bg-void min-h-screen text-ink antialiased selection:bg-gold/30">
            <CustomCursor />
            <GrainOverlay />
            <WaitlistModal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} />
            <NewNavbar onBookSandbox={handleBookSandbox} />

            <FloatingSphere size={400} color="bg-gold" blur={140} position={{ top: '5%', right: '-8%' }} duration={7} />
            <FloatingSphere size={300} color="bg-teal" blur={100} position={{ bottom: '15%', left: '-5%' }} delay={3} duration={6} />

            {/* Hero */}
            <section className="pt-36 pb-16 relative">
                <div className="max-w-6xl mx-auto px-6">
                    <FadeInView>
                        <div className="flex items-center gap-4 mb-6">
                            <div className="h-px w-12 bg-gold/40" />
                            <span className="section-label">What We Deliver</span>
                            <div className="h-px w-12 bg-gold/40" />
                        </div>
                    </FadeInView>
                    <FadeInView delay={0.1}>
                        <h1 className="text-4xl md:text-6xl lg:text-display font-display leading-tight">
                            The Systems We Build<br />
                            <span className="text-gold">For Your Clients.</span>
                        </h1>
                    </FadeInView>
                    <FadeInView delay={0.2}>
                        <p className="text-ink-3 text-lg mt-6 max-w-lg">
                            Every project starts with your backlog. We build in your tools, deploy in your client's environment, and document everything.
                        </p>
                    </FadeInView>
                </div>
            </section>

            {/* Implementation Grid */}
            <section className="py-12 md:py-24">
                <div className="max-w-5xl mx-auto px-6">
                    <FadeInView>
                        <p className="section-label mb-10">What We've Shipped</p>
                    </FadeInView>
                    <div className="grid md:grid-cols-2 lg:grid-cols-3 gap-5">
                        {implementations.map((impl, i) => (
                            <GlowCard key={impl.title} glowColor={impl.glow} delay={i * 0.08} className="group">
                                <div className="p-7">
                                    <div className="flex items-center justify-between mb-4">
                                        <impl.icon className={`w-5 h-5 ${impl.glow === 'gold' ? 'text-gold' : impl.glow === 'teal' ? 'text-teal' : 'text-coral'}`} />
                                        <div className="flex items-center gap-2">
                                            <span className={`text-[10px] px-2.5 py-1 rounded-full border font-medium ${
                                                impl.glow === 'gold' ? 'text-gold bg-gold/10 border-gold/15'
                                                : impl.glow === 'teal' ? 'text-teal bg-teal/10 border-teal/15'
                                                : 'text-coral bg-coral/10 border-coral/15'
                                            }`}>
                                                {impl.metric}
                                            </span>
                                        </div>
                                    </div>
                                    <span className="text-[10px] text-ink-disabled uppercase tracking-wider font-mono">{impl.domain}</span>
                                    <h3 className="text-ink font-semibold text-base mt-1 mb-2">{impl.title}</h3>
                                    <p className="text-ink-3 text-sm leading-relaxed">{impl.desc}</p>
                                </div>
                            </GlowCard>
                        ))}
                    </div>
                </div>
            </section>

            {/* The Pattern */}
            <section className="py-20 border-t border-b border-ink-disabled/20">
                <div className="max-w-4xl mx-auto px-6">
                    <FadeInView>
                        <p className="section-label text-center mb-8">How It Works</p>
                    </FadeInView>
                    <FadeInView delay={0.1}>
                        <div className="text-center">
                            <p className="text-2xl md:text-3xl font-display text-ink leading-relaxed">
                                Every project follows the same formula:
                            </p>
                            <p className="text-3xl md:text-4xl font-display mt-6">
                                <span className="text-gold">Your backlog</span>
                                <span className="text-ink-3"> + </span>
                                <span className="text-teal">our build capacity</span>
                            </p>
                            <p className="text-3xl md:text-4xl font-display mt-2">
                                <span className="text-ink-3">= </span>
                                <span className="text-ink">clients that actually use it.</span>
                            </p>
                        </div>
                    </FadeInView>
                </div>
            </section>

            {/* Stats */}
            <section className="py-20">
                <div className="max-w-4xl mx-auto px-6 grid grid-cols-3 gap-8 text-center">
                    <FadeInView delay={0.1}>
                        <p className="text-3xl md:text-4xl font-display text-ink"><AnimatedCounter value={50} suffix="+" /></p>
                        <p className="text-ink-3 text-xs uppercase tracking-wider mt-2">Projects Delivered</p>
                    </FadeInView>
                    <FadeInView delay={0.2}>
                        <p className="text-3xl md:text-4xl font-display text-gold"><AnimatedCounter value={95} suffix="%" /></p>
                        <p className="text-ink-3 text-xs uppercase tracking-wider mt-2">Client Retention</p>
                    </FadeInView>
                    <FadeInView delay={0.3}>
                        <p className="text-3xl md:text-4xl font-display text-teal">3 Weeks</p>
                        <p className="text-ink-3 text-xs uppercase tracking-wider mt-2">Avg Time to First Delivery</p>
                    </FadeInView>
                </div>
            </section>

            {/* CTA */}
            <section className="py-28 text-center">
                <FadeInView>
                    <p className="text-ink-3 text-sm uppercase tracking-widest mb-4">See what we could clear from your backlog</p>
                    <h2 className="text-3xl md:text-4xl font-display text-ink mb-8">Start with the 3-week sandbox.</h2>
                    <MagneticElement strength={0.3} radius={100}>
                        <button
                            onClick={handleBookSandbox}
                            className="group inline-flex items-center gap-3 px-10 py-5 bg-gold text-void font-mono font-bold text-lg rounded-pill hover:scale-105 transition-all duration-medium shadow-neu-raised"
                        >
                            Book a Discovery Call
                            <ArrowRight className="w-5 h-5 group-hover:translate-x-1 transition-transform duration-short" />
                        </button>
                    </MagneticElement>
                </FadeInView>
            </section>

            <FooterSection />
        </div>
    );
}
