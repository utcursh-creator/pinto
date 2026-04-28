import { motion } from 'framer-motion';
import { useState } from 'react';
import { Link } from 'react-router-dom';
import { NewNavbar } from '@/components/layout/NewNavbar';
import { FooterSection } from '@/components/sections/FooterSection';
import { WaitlistModal } from '@/components/ui/WaitlistModal';
import { FloatingSphere } from '@/components/animation/FloatingSphere';
import { GrainOverlay } from '@/components/effects/AtmosphericEffects';
import { CustomCursor } from '@/components/animation/CustomCursor';
import { ArrowRight, Clock, User } from 'lucide-react';

const blogPosts = [
    {
        id: 1,
        slug: 'why-domain-expertise-matters-more-than-tools',
        title: 'Why Your Domain Expertise Matters More Than Any AI Tool',
        excerpt: 'The best AI implementations don\'t start with technology. They start with what the operator already knows. Here\'s why domain depth is the real competitive advantage.',
        image: '/images/blog/blog_01.png',
        category: 'Strategy',
        readTime: '8 min',
        author: 'Utkarsh',
        date: 'Mar 10, 2026',
        featured: true
    },
    {
        id: 2,
        slug: 'ai-adoption-framework',
        title: 'The AI Adoption Framework: Why 73% of Implementations Fail',
        excerpt: 'Building AI systems is the easy part. Getting your team to actually use them? That\'s where most companies fall apart. Here\'s how we ensure adoption.',
        image: '/images/blog/blog_02.png',
        category: 'Adoption',
        readTime: '12 min',
        author: 'Utkarsh',
        date: 'Mar 3, 2026',
        featured: true
    },
    {
        id: 3,
        slug: 'step-by-step-ai-integration',
        title: 'Step-by-Step AI Integration: From Domain Knowledge to Working System',
        excerpt: 'A detailed walkthrough of how we map expertise into AI systems. Real examples, real process, no buzzwords.',
        image: '/images/blog/blog_03.png',
        category: 'Process',
        readTime: '15 min',
        author: 'Utkarsh',
        date: 'Feb 24, 2026',
        featured: false
    },
    {
        id: 4,
        slug: 'ai-roi-for-operators',
        title: 'AI ROI for Operators: Where the Real Leverage Is',
        excerpt: 'Not every process benefits equally from AI. Here\'s how to identify the highest-leverage spots in your operation — and avoid the traps.',
        image: '/images/blog/blog_04.png',
        category: 'Strategy',
        readTime: '10 min',
        author: 'Utkarsh',
        date: 'Feb 17, 2026',
        featured: false
    },
    {
        id: 5,
        slug: 'building-ai-systems-that-stick',
        title: 'Building AI Systems That Your Team Will Actually Use',
        excerpt: 'The documentation stack, training framework, and support model that reduces abandonment and turns AI from a project into a habit.',
        image: '/images/blog/blog_05.png',
        category: 'Adoption',
        readTime: '9 min',
        author: 'Utkarsh',
        date: 'Feb 10, 2026',
        featured: false
    },
    {
        id: 6,
        slug: 'generic-ai-vs-domain-ai',
        title: 'Generic AI vs Domain-Specific AI: Why One Works and the Other Doesn\'t',
        excerpt: 'Off-the-shelf AI tools solve 20% of the problem. The other 80% requires your knowledge. Here\'s what that looks like in practice.',
        image: '/images/blog/blog_06.png',
        category: 'Technology',
        readTime: '7 min',
        author: 'Utkarsh',
        date: 'Feb 3, 2026',
        featured: false
    },
];

function FeaturedBlogCard({ post }: { post: typeof blogPosts[0] }) {
    return (
        <motion.article
            className="group relative overflow-hidden bg-charcoal-light rounded-md shadow-neu-raised hover:shadow-neu-hover transition-all duration-medium"
            initial={{ opacity: 0, y: 14 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.6 }}
            whileHover={{ y: -5 }}
        >
            <Link to={`/resources/${post.slug}`} className="block">
                <div className="relative h-64 overflow-hidden">
                    <img
                        src={post.image}
                        alt={post.title}
                        className="w-full h-full object-cover transition-transform duration-medium group-hover:scale-105"
                        onError={(e) => {
                            e.currentTarget.src = 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 400 200"><rect fill="%231a1a1a" width="400" height="200"/><text x="50%" y="50%" fill="%23333" text-anchor="middle" dy=".3em" font-family="system-ui">Blog Image</text></svg>';
                        }}
                    />
                    <div className="absolute inset-0 bg-gradient-to-t from-charcoal via-transparent to-transparent" />
                    <span className="absolute top-4 left-4 px-3 py-1.5 font-mono text-[0.6rem] font-semibold uppercase tracking-wider bg-gold/15 text-gold rounded-full backdrop-blur-sm border border-gold/20">
                        {post.category}
                    </span>
                </div>
                <div className="p-7 space-y-4">
                    <h3 className="text-xl font-display text-ink group-hover:text-gold transition-colors duration-short line-clamp-2">
                        {post.title}
                    </h3>
                    <p className="text-ink-3 text-sm leading-relaxed line-clamp-2">
                        {post.excerpt}
                    </p>
                    <div className="flex items-center gap-4 text-[11px] text-ink-3">
                        <span className="flex items-center gap-1.5"><Clock className="w-3 h-3" />{post.readTime}</span>
                        <span className="flex items-center gap-1.5"><User className="w-3 h-3" />{post.author}</span>
                        <span>{post.date}</span>
                    </div>
                </div>
            </Link>
        </motion.article>
    );
}

function BlogCard({ post, index }: { post: typeof blogPosts[0], index: number }) {
    return (
        <motion.article
            className="group relative overflow-hidden bg-charcoal-light rounded-md shadow-neu-raised hover:shadow-neu-hover transition-all duration-medium"
            initial={{ opacity: 0, y: 14 }}
            whileInView={{ opacity: 1, y: 0 }}
            viewport={{ once: true }}
            transition={{ duration: 0.5, delay: index * 0.08 }}
            whileHover={{ y: -3 }}
        >
            <Link to={`/resources/${post.slug}`} className="flex flex-col md:flex-row">
                <div className="relative w-full md:w-48 h-40 md:h-auto overflow-hidden flex-shrink-0">
                    <img
                        src={post.image}
                        alt={post.title}
                        className="w-full h-full object-cover transition-transform duration-medium group-hover:scale-105"
                        onError={(e) => {
                            e.currentTarget.src = 'data:image/svg+xml,<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 200 200"><rect fill="%231a1a1a" width="200" height="200"/></svg>';
                        }}
                    />
                </div>
                <div className="p-6 flex flex-col justify-center space-y-3">
                    <div className="flex items-center gap-3">
                        <span className="px-2.5 py-1 font-mono text-[0.6rem] font-semibold uppercase tracking-wider bg-teal/10 text-teal rounded-full border border-teal/15">
                            {post.category}
                        </span>
                        <span className="text-[11px] text-ink-disabled">{post.date}</span>
                    </div>
                    <h3 className="text-lg font-display text-ink group-hover:text-gold transition-colors duration-short line-clamp-2">
                        {post.title}
                    </h3>
                    <p className="text-ink-3 text-sm line-clamp-2 hidden md:block leading-relaxed">
                        {post.excerpt}
                    </p>
                    <div className="flex items-center gap-3 text-[11px] text-ink-disabled">
                        <span className="flex items-center gap-1.5"><Clock className="w-3 h-3" />{post.readTime}</span>
                    </div>
                </div>
            </Link>
        </motion.article>
    );
}

export function ResourcesPage() {
    const [isModalOpen, setIsModalOpen] = useState(false);
    const featuredPosts = blogPosts.filter(p => p.featured);
    const regularPosts = blogPosts.filter(p => !p.featured);

    const handleBookSandbox = () => setIsModalOpen(true);

    return (
        <div className="bg-void min-h-screen text-ink antialiased selection:bg-gold/30">
            <CustomCursor />
            <GrainOverlay />
            <WaitlistModal isOpen={isModalOpen} onClose={() => setIsModalOpen(false)} />
            <NewNavbar onBookSandbox={handleBookSandbox} />

            <section className="relative pt-36 pb-24 overflow-hidden">
                <FloatingSphere color="bg-gold" size={400} blur={150} delay={0} duration={10} position={{ top: '10%', right: '10%' }} className="opacity-10" />
                <FloatingSphere color="bg-teal" size={300} blur={120} delay={2} duration={8} position={{ bottom: '20%', left: '5%' }} className="opacity-10" />

                <div className="relative z-10 max-w-6xl mx-auto px-6 text-center">
                    <motion.div className="flex items-center justify-center gap-4 mb-8" initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.6 }}>
                        <div className="h-px w-12 bg-gold/40" />
                        <span className="section-label">Resources & Insights</span>
                        <div className="h-px w-12 bg-gold/40" />
                    </motion.div>
                    <motion.h1 className="text-4xl md:text-6xl lg:text-display font-display mb-6" initial={{ opacity: 0, y: 14 }} animate={{ opacity: 1, y: 0 }} transition={{ duration: 0.8, delay: 0.1 }}>
                        <span className="text-ink">Scaling</span>{' '}
                        <span className="text-gold">AI Businesses</span>
                    </motion.h1>
                    <motion.p className="text-lg text-ink-3 max-w-xl mx-auto" initial={{ opacity: 0 }} animate={{ opacity: 1 }} transition={{ duration: 0.6, delay: 0.3 }}>
                        Lessons on fulfillment, adoption, and scaling an AI automation business without burning out.
                    </motion.p>
                </div>
            </section>

            <section className="py-16">
                <div className="max-w-6xl mx-auto px-6">
                    <motion.p className="section-label mb-10" initial={{ opacity: 0 }} whileInView={{ opacity: 1 }} viewport={{ once: true }}>Featured</motion.p>
                    <div className="grid md:grid-cols-2 gap-6">
                        {featuredPosts.map((post) => (<FeaturedBlogCard key={post.id} post={post} />))}
                    </div>
                </div>
            </section>

            <section className="py-16">
                <div className="max-w-6xl mx-auto px-6">
                    <motion.p className="section-label mb-10" initial={{ opacity: 0 }} whileInView={{ opacity: 1 }} viewport={{ once: true }}>All Articles</motion.p>
                    <div className="space-y-4">
                        {regularPosts.map((post, index) => (<BlogCard key={post.id} post={post} index={index} />))}
                    </div>
                </div>
            </section>

            <section className="py-28 bg-gradient-to-b from-transparent via-charcoal-light to-transparent">
                <div className="max-w-3xl mx-auto px-6 text-center">
                    <motion.div initial={{ opacity: 0, y: 14 }} whileInView={{ opacity: 1, y: 0 }} viewport={{ once: true }}>
                        <p className="section-label mb-5">See what we deliver</p>
                        <h2 className="text-3xl md:text-4xl font-display text-ink mb-5">Real Projects. Real Results.</h2>
                        <p className="text-ink-3 mb-10">See the systems we build for AI automation businesses.</p>
                        <Link
                            to="/work"
                            className="inline-flex items-center gap-2 px-10 py-5 bg-gold text-void font-mono font-bold text-lg rounded-pill hover:scale-105 transition-all duration-medium shadow-neu-raised"
                        >
                            View What We Deliver
                            <ArrowRight className="w-5 h-5" />
                        </Link>
                    </motion.div>
                </div>
            </section>

            <FooterSection />
        </div>
    );
}
