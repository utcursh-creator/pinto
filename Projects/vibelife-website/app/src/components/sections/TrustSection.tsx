import { FadeInView } from '@/components/animation/FadeInView';
import { ShieldCheck, Clock, Eye, Users, FileText, Headphones } from 'lucide-react';

const objections = [
    {
        objection: '"I\'ve been burned by freelancers before"',
        response: 'So have most of our partners. That\'s why we start with a 3-week sandbox — you see exactly how we work before any bigger commitment. No contract. No lock-in.',
        icon: ShieldCheck,
    },
    {
        objection: '"How do I know you can actually deliver?"',
        response: '50+ implementations. Clients like Loom and UpGrad. 2000+ reviews. We\'ve been building at this level for years — not weeks.',
        icon: Eye,
    },
    {
        objection: '"I need to stay involved in delivery"',
        response: 'You stay in control of sales and client relationships. We handle the building, documentation, and adoption support. Clear boundaries.',
        icon: Users,
    },
    {
        objection: '"What if my clients don\'t use what you build?"',
        response: 'Adoption is our finish line, not delivery. We document everything, train the end users, and support until the system is actually embedded in their workflow.',
        icon: FileText,
    },
    {
        objection: '"I should probably just hire someone"',
        response: 'You\'ve probably tried that. Hiring takes months, costs more, and you still need to manage them. We\'re operational in week one.',
        icon: Clock,
    },
    {
        objection: '"What happens after the sandbox?"',
        response: 'If it works, we talk about ongoing partnership. If it doesn\'t, you keep everything we built. Either way, you\'re ahead.',
        icon: Headphones,
    },
];

export function TrustSection() {
    return (
        <section className="relative w-full bg-charcoal py-24 md:py-32 overflow-hidden">
            <div className="absolute inset-0">
                <div className="absolute top-0 left-0 right-0 h-px bg-gradient-to-r from-transparent via-ink-disabled/20 to-transparent" />
            </div>

            <div className="relative z-10 max-w-5xl mx-auto px-6">
                <FadeInView>
                    <div className="text-center mb-14">
                        <p className="section-label mb-5">Common Questions</p>
                        <h2 className="text-3xl md:text-display-sm font-display leading-tight text-ink">
                            You're probably thinking<br />
                            <span className="text-gold">one of these things</span>
                        </h2>
                    </div>
                </FadeInView>

                <div className="grid md:grid-cols-2 gap-5">
                    {objections.map((item, i) => {
                        const Icon = item.icon;
                        return (
                            <FadeInView key={i} delay={i * 0.08}>
                                <div className="p-6 rounded-md bg-charcoal-light shadow-neu-raised hover:shadow-neu-hover transition-all duration-medium h-full">
                                    <div className="flex items-start gap-4">
                                        <div className="p-2 rounded-sm bg-charcoal flex-shrink-0">
                                            <Icon className="w-4 h-4 text-gold" />
                                        </div>
                                        <div>
                                            <p className="text-ink font-medium text-sm mb-2 italic">{item.objection}</p>
                                            <p className="text-ink-2 text-sm leading-relaxed">{item.response}</p>
                                        </div>
                                    </div>
                                </div>
                            </FadeInView>
                        );
                    })}
                </div>
            </div>
        </section>
    );
}
