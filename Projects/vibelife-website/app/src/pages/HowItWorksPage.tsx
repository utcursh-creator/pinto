import { motion, useScroll, useTransform, useSpring, useMotionValueEvent } from 'framer-motion';
import { useRef, useState } from 'react';
import { NewNavbar } from '@/components/layout/NewNavbar';
import { FooterSection } from '@/components/sections/FooterSection';
import { WaitlistModal } from '@/components/ui/WaitlistModal';
import { FloatingSphere } from '@/components/animation/FloatingSphere';
import { ArrowRight, ArrowLeft, Search, Brain, Code2, Rocket, Users, Headphones } from 'lucide-react';
import { GrainOverlay } from '@/components/effects/AtmosphericEffects';
import { CustomCursor } from '@/components/animation/CustomCursor';

const processSteps = [
    {
        number: '01',
        title: 'Audit Your Backlog',
        subtitle: 'We see what\'s sitting there',
        description: 'We look at every project in your queue. Understand what your clients need, what\'s urgent, what\'s been waiting. This is where we figure out what to tackle first.',
        icon: Search,
        sphereColor: 'bg-gold',
        accentColor: 'gold'
    },
    {
        number: '02',
        title: 'Pick the Priorities',
        subtitle: '2-5 projects, highest impact',
        description: 'Not everything gets built at once. We identify the 2-5 projects that move the needle most — for your clients and for your business.',
        icon: Brain,
        sphereColor: 'bg-teal',
        accentColor: 'teal'
    },
    {
        number: '03',
        title: 'Build in Your Stack',
        subtitle: 'Your tools, your way',
        description: 'We build in n8n, Make, or whatever your team already uses. No new tools to learn. No migration headaches. Just working systems.',
        icon: Code2,
        sphereColor: 'bg-coral',
        accentColor: 'coral'
    },
    {
        number: '04',
        title: 'Deploy to Your Clients',
        subtitle: 'Configured and tested',
        description: 'We deploy directly in your client\'s environment. Their tools, their data, their workflow. Configured, tested, and ready to run.',
        icon: Rocket,
        sphereColor: 'bg-gold',
        accentColor: 'gold'
    },
    {
        number: '05',
        title: 'Document Everything',
        subtitle: 'Client-ready walkthroughs',
        description: 'Video documentation. Written SOPs. Everything your client needs to understand what they have and how it works.',
        icon: Users,
        sphereColor: 'bg-teal',
        accentColor: 'teal'
    },
    {
        number: '06',
        title: 'Support Until Adoption',
        subtitle: 'Our finish line, not delivery',
        description: 'Delivery is half the job. We stay on until your clients are actually using the systems. Weekly check-ins until it\'s embedded.',
        icon: Headphones,
        sphereColor: 'bg-coral',
        accentColor: 'coral'
    }
];

function ProcessStepCard({ step, index }: { step: typeof processSteps[0], index: number }) {
    const Icon = step.icon;

    return (
        <div className="relative w-screen h-screen flex-shrink-0 flex items-center justify-center overflow-hidden">
            <FloatingSphere color={step.sphereColor} size={400} blur={120} delay={0} duration={8} position={{ top: '10%', right: '15%' }} className="opacity-20" />
            <FloatingSphere color={step.sphereColor} size={250} blur={80} delay={2} duration={6} position={{ bottom: '20%', left: '10%' }} className="opacity-15" />
            <FloatingSphere color="bg-white" size={150} blur={60} delay={4} duration={10} position={{ top: '60%', right: '30%' }} className="opacity-10" />

            <div className="absolute inset-0 bg-void">
                <div className="absolute inset-0" style={{ background: `radial-gradient(ellipse at 70% 50%, rgba(var(--color-${step.accentColor}), 0.15) 0%, transparent 50%)` }} />
            </div>

            <div className="relative z-10 max-w-6xl mx-auto px-8 md:px-16 grid md:grid-cols-2 gap-12 items-center">
                <motion.div className="space-y-8" initial={{ opacity: 0, x: -50 }} whileInView={{ opacity: 1, x: 0 }} viewport={{ once: true, margin: '-100px' }} transition={{ duration: 0.8, delay: 0.2 }}>
                    <span className={`text-${step.accentColor} text-7xl md:text-9xl font-display font-bold opacity-20`}>{step.number}</span>
                    <div>
                        <h2 className="text-4xl md:text-6xl font-display text-ink mb-3">{step.title}</h2>
                        <p className={`text-xl text-${step.accentColor}/80 font-light tracking-wide`}>{step.subtitle}</p>
                    </div>
                    <p className="text-xl text-ink-2 leading-relaxed max-w-lg">{step.description}</p>
                    <div className="flex items-center gap-3">
                        {processSteps.map((_, i) => (
                            <div key={i} className={`w-2 h-2 rounded-full transition-all duration-short ${i === index ? `bg-${step.accentColor} scale-150` : 'bg-ink-disabled'}`} />
                        ))}
                    </div>
                </motion.div>

                <motion.div className="hidden md:flex items-center justify-center" initial={{ opacity: 0, scale: 0.8, rotateY: -15 }} whileInView={{ opacity: 1, scale: 1, rotateY: 0 }} viewport={{ once: true, margin: '-100px' }} transition={{ duration: 1, delay: 0.4, type: 'spring', stiffness: 100 }}>
                    <div className="relative w-80 h-80" style={{ perspective: '1000px' }}>
                        <motion.div className={`absolute inset-0 rounded-full border border-${step.accentColor}/20`} animate={{ rotateZ: 360 }} transition={{ duration: 20, repeat: Infinity, ease: 'linear' }} />
                        <motion.div className={`absolute inset-8 rounded-full border border-${step.accentColor}/30`} animate={{ rotateZ: -360 }} transition={{ duration: 15, repeat: Infinity, ease: 'linear' }} />
                        <div className={`absolute inset-16 rounded-full bg-gradient-to-br from-${step.accentColor}/30 to-transparent blur-3xl`} />
                        <motion.div className="absolute inset-0 flex items-center justify-center" whileHover={{ scale: 1.1, rotateY: 15 }} transition={{ type: 'spring', stiffness: 300 }}>
                            <div className={`p-8 rounded-3xl bg-${step.accentColor}/10 border border-${step.accentColor}/20 backdrop-blur-xl`}>
                                <Icon className={`w-16 h-16 text-${step.accentColor}`} />
                            </div>
                        </motion.div>
                        {[...Array(5)].map((_, i) => (
                            <motion.div key={i} className={`absolute w-2 h-2 rounded-full bg-${step.accentColor}/40`} style={{ top: `${20 + Math.random() * 60}%`, left: `${20 + Math.random() * 60}%` }} animate={{ y: [0, -20, 0], opacity: [0.2, 0.6, 0.2] }} transition={{ duration: 3 + Math.random() * 2, repeat: Infinity, delay: i * 0.5 }} />
                        ))}
                    </div>
                </motion.div>
            </div>
        </div>
    );
}

export function HowItWorksPage() {
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [currentSlide, setCurrentSlide] = useState(0);
    const containerRef = useRef<HTMLDivElement>(null);
    const horizontalRef = useRef<HTMLDivElement>(null);

    const { scrollYProgress } = useScroll({ target: containerRef, offset: ['start start', 'end end'] });

    const totalSlides = processSteps.length;
    const scrollStart = 1 / (totalSlides + 1);
    const scrollEnd = totalSlides / (totalSlides + 1);

    useMotionValueEvent(scrollYProgress, 'change', (latest) => {
        const slideProgress = (latest - scrollStart) / (scrollEnd - scrollStart);
        const slideIndex = Math.round(slideProgress * (totalSlides - 1));
        setCurrentSlide(Math.max(0, Math.min(totalSlides - 1, slideIndex)));
    });

    const smoothProgress = useSpring(scrollYProgress, { stiffness: 100, damping: 30, restDelta: 0.001 });
    const x = useTransform(smoothProgress, [scrollStart, scrollEnd], ['0%', `-${(totalSlides - 1) * 100}%`]);

    const handleBookSandbox = () => setIsModalOpen(true);

    const scrollToSlide = (direction: 'prev' | 'next') => {
        if (!containerRef.current) return;
        const targetSlide = direction === 'next' ? Math.min(currentSlide + 1, totalSlides - 1) : Math.max(currentSlide - 1, 0);
        const targetProgress = scrollStart + (targetSlide / (totalSlides - 1)) * (scrollEnd - scrollStart);
        const scrollableDistance = containerRef.current.scrollHeight - window.innerHeight;
        window.scrollTo({ top: containerRef.current.offsetTop + targetProgress * scrollableDistance, behavior: 'smooth' });
    };

    return (
        <div ref={containerRef} className="bg-void min-h-screen text-ink antialiased selection:bg-gold/30">
            <CustomCursor />
            <GrainOverlay />
            <WaitlistModal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} />
            <NewNavbar onBookSandbox={handleBookSandbox} />

            <section className="relative h-screen flex items-center justify-center overflow-hidden">
                <FloatingSphere color="bg-gold" size={500} blur={150} delay={0} duration={10} position={{ top: '20%', left: '20%' }} className="opacity-15" />
                <FloatingSphere color="bg-teal" size={400} blur={120} delay={3} duration={8} position={{ bottom: '30%', right: '20%' }} className="opacity-15" />
                <div className="relative z-10 text-center px-6">
                    <motion.p className="section-label mb-8" initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }}>How We Work</motion.p>
                    <motion.h1 className="text-5xl md:text-7xl lg:text-8xl font-display mb-8" initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8, delay: 0.1 }}>
                        <span className="text-ink block">You Sell It.</span>
                        <span className="text-gold block mt-2">We Build It.</span>
                    </motion.h1>
                    <motion.p className="text-xl text-ink-2 max-w-2xl mx-auto mb-12" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.6, delay: 0.3 }}>
                        A clear, 6-step process from backlog to adoption.<br />
                        <span className="text-gold">3 weeks. Your tools. Fully documented.</span>
                    </motion.p>
                </div>
            </section>

            <section className="relative" style={{ height: `${(processSteps.length + 1) * 100}vh` }}>
                <div className="sticky top-0 h-screen overflow-hidden">
                    <motion.div ref={horizontalRef} className="flex h-full" style={{ x }}>
                        {processSteps.map((step, index) => (<ProcessStepCard key={index} step={step} index={index} />))}
                    </motion.div>
                    <div className="absolute bottom-8 left-1/2 -translate-x-1/2 flex items-center gap-6 z-20">
                        <motion.button onClick={() => scrollToSlide('prev')} className={`p-3 rounded-full border transition-all ${currentSlide > 0 ? 'border-ink-disabled/40 text-ink-2 hover:border-gold hover:text-gold cursor-pointer' : 'border-ink-disabled/30 text-ink-disabled cursor-not-allowed'}`} whileHover={currentSlide > 0 ? { scale: 1.1 } : {}} whileTap={currentSlide > 0 ? { scale: 0.95 } : {}} disabled={currentSlide === 0}>
                            <ArrowLeft className="w-5 h-5" />
                        </motion.button>
                        <span className="text-ink-3 text-sm font-mono">{String(currentSlide + 1).padStart(2, '0')} / {String(processSteps.length).padStart(2, '0')}</span>
                        <motion.button onClick={() => scrollToSlide('next')} className={`p-3 rounded-full border transition-all ${currentSlide < processSteps.length - 1 ? 'border-ink-disabled/40 text-ink-2 hover:border-gold hover:text-gold cursor-pointer' : 'border-ink-disabled/30 text-ink-disabled cursor-not-allowed'}`} whileHover={currentSlide < processSteps.length - 1 ? { scale: 1.1 } : {}} whileTap={currentSlide < processSteps.length - 1 ? { scale: 0.95 } : {}} disabled={currentSlide === processSteps.length - 1}>
                            <ArrowRight className="w-5 h-5" />
                        </motion.button>
                    </div>
                </div>
            </section>

            <section className="relative py-32 bg-gradient-to-b from-void to-charcoal overflow-hidden">
                <FloatingSphere color="bg-gold" size={600} blur={200} delay={0} duration={12} position={{ top: '50%', left: '50%' }} className="opacity-10 -translate-x-1/2 -translate-y-1/2" />
                <div className="relative z-10 max-w-4xl mx-auto px-6 text-center">
                    <motion.div initial={{ opacity: 0, y: 14 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }} transition={{ duration: 0.8 }}>
                        <p className="section-label mb-6">Ready to test the partnership?</p>
                        <h2 className="text-4xl md:text-5xl font-display text-ink mb-6">Start with the <span className="text-gold">3-Week Sandbox</span></h2>
                        <p className="text-ink-2 text-lg mb-10 max-w-xl mx-auto">We audit your backlog, pick the most urgent builds, and deliver them in your tools. You keep everything we build — even if you don't continue.</p>
                        <motion.button onClick={handleBookSandbox} className="group relative px-10 py-5 bg-gold text-void font-mono font-semibold text-lg rounded-pill shadow-neu-raised overflow-hidden" whileHover={{ scale: 1.05 }} whileTap={{ scale: 0.98 }}>
                            <span className="relative z-10 flex items-center gap-3">Book a Discovery Call <ArrowRight className="w-5 h-5 group-hover:translate-x-1 transition-transform" /></span>
                        </motion.button>
                        <p className="text-ink-3 text-sm mt-6">Limited capacity. Only taking on 3-4 new partners per quarter.</p>
                    </motion.div>
                </div>
            </section>

            <FooterSection />
        </div>
    );
}
