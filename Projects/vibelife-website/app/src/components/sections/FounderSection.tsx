import { FadeInView } from '@/components/animation/FadeInView';

const transformations = [
    {
        client: 'AI Automation Agency',
        problem: 'Backlog of 8 client projects, founder doing all the building',
        result: '5 projects cleared in 21 days. Founder focused on sales for the first time in months.',
        metric: '5',
        metricLabel: 'projects / 21 days',
        accent: 'gold',
    },
    {
        client: 'Marketing Automation Business',
        problem: '3 freelancers ghosted in 6 months. Clients churning from delayed delivery.',
        result: 'Full backlog cleared. Documentation and adoption support kept clients engaged.',
        metric: '0',
        metricLabel: 'churn in 90 days',
        accent: 'teal',
    },
    {
        client: 'Operations Consultancy',
        problem: 'Sold AI services but couldn\'t build at the quality clients expected.',
        result: 'Delivered enterprise-grade systems. Client NPS scores highest in company history.',
        metric: '3x',
        metricLabel: 'revenue growth',
        accent: 'gold',
    },
];

export function FounderSection() {
    return (
        <section className="relative w-full bg-void py-24 md:py-32">
            <div className="max-w-5xl mx-auto px-6">
                <FadeInView>
                    <div className="text-center mb-14">
                        <div className="flex items-center justify-center gap-4 mb-6">
                            <div className="h-px w-12 bg-ink-3/50" />
                            <span className="section-label">Before & After</span>
                            <div className="h-px w-12 bg-ink-3/50" />
                        </div>
                        <h2 className="text-3xl md:text-display-sm font-display leading-tight text-ink">
                            What changes when you<br />
                            <span className="text-gold">stop doing fulfillment yourself</span>
                        </h2>
                    </div>
                </FadeInView>

                <div className="space-y-5">
                    {transformations.map((t, i) => (
                        <FadeInView key={t.client} delay={i * 0.1}>
                            <div className="bg-charcoal-light rounded-md shadow-neu-raised overflow-hidden hover:shadow-neu-hover transition-all duration-medium">
                                <div className="px-6 pt-5 pb-0 flex items-center gap-3">
                                    <span className={`text-[10px] font-mono uppercase tracking-wider ${t.accent === 'gold' ? 'text-gold' : 'text-teal'}`}>
                                        {t.client}
                                    </span>
                                </div>

                                <div className="grid md:grid-cols-2 gap-0">
                                    {/* Before */}
                                    <div className="px-6 py-5 md:border-r border-ink-disabled/15">
                                        <p className="text-[10px] font-mono uppercase tracking-wider text-ink-disabled mb-3">The Problem</p>
                                        <p className="text-ink-3 text-sm leading-relaxed">
                                            {t.problem}
                                        </p>
                                    </div>

                                    {/* After */}
                                    <div className="px-6 py-5">
                                        <div className="flex items-center justify-between mb-3">
                                            <p className="text-[10px] font-mono uppercase tracking-wider text-ink-disabled">The Result</p>
                                            <div className={`flex items-baseline gap-1 ${t.accent === 'gold' ? 'text-gold' : 'text-teal'}`}>
                                                <span className="text-2xl font-display font-bold">{t.metric}</span>
                                                <span className="text-[10px] font-mono uppercase tracking-wider opacity-70">{t.metricLabel}</span>
                                            </div>
                                        </div>
                                        <p className="text-ink text-sm leading-relaxed">
                                            {t.result}
                                        </p>
                                    </div>
                                </div>
                            </div>
                        </FadeInView>
                    ))}
                </div>
            </div>
        </section>
    );
}
