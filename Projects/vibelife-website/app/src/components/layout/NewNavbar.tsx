import { useState, useEffect, useRef, useCallback } from 'react';
import { Link } from 'react-router-dom';
import { motion, AnimatePresence } from 'framer-motion';
import { Button } from '@/components/ui/button';
import { ThemeToggle } from '@/components/ui/ThemeToggle';
import { Menu, X } from 'lucide-react';

export interface NewNavbarProps {
    onBookSandbox?: () => void;
}

export function NewNavbar({ onBookSandbox }: NewNavbarProps) {
    const [isScrolled, setIsScrolled] = useState(false);
    const [isVisible, setIsVisible] = useState(true);
    const [isMobileMenuOpen, setIsMobileMenuOpen] = useState(false);
    const lastScrollY = useRef(0);

    const handleScroll = useCallback(() => {
        const currentScrollY = window.scrollY;
        const isScrollingDown = currentScrollY > lastScrollY.current;

        setIsScrolled(currentScrollY > 50);

        if (currentScrollY > 200) {
            setIsVisible(!isScrollingDown || currentScrollY < 100);
        } else {
            setIsVisible(true);
        }

        lastScrollY.current = currentScrollY;
    }, []);

    useEffect(() => {
        window.addEventListener('scroll', handleScroll, { passive: true });
        return () => window.removeEventListener('scroll', handleScroll);
    }, [handleScroll]);

    return (
        <motion.nav
            className={`fixed top-0 left-0 right-0 z-50 transition-all duration-medium ${
                isScrolled
                    ? 'glass border-b border-ink-disabled/20'
                    : 'bg-transparent'
            }`}
            initial={{ y: -100 }}
            animate={{
                y: isVisible ? 0 : -100,
            }}
            transition={{ duration: 0.4, ease: [0.25, 0.1, 0.25, 1] }}
        >
            <div className="max-w-7xl mx-auto px-6 py-4">
                <div className="flex items-center justify-between">
                    <Link to="/" className="block">
                        <span className="text-xl md:text-2xl font-display text-gold">
                            VibeLife
                        </span>
                    </Link>

                    <div className="hidden md:flex items-center gap-1">
                        <Link
                            to="/how-it-works"
                            className="px-4 py-2 font-mono text-label tracking-[0.16em] uppercase text-ink-3 hover:text-ink transition-colors duration-short"
                        >
                            How It Works
                        </Link>
                        <Link
                            to="/work"
                            className="px-4 py-2 font-mono text-label tracking-[0.16em] uppercase text-ink-3 hover:text-ink transition-colors duration-short"
                        >
                            What We Build
                        </Link>
                        <Link
                            to="/resources"
                            className="px-4 py-2 font-mono text-label tracking-[0.16em] uppercase text-ink-3 hover:text-ink transition-colors duration-short"
                        >
                            Resources
                        </Link>
                    </div>

                    <div className="flex items-center gap-3">
                        <div className="hidden md:block">
                            <ThemeToggle />
                        </div>
                        <Button
                            onClick={onBookSandbox}
                            variant="gold-pill"
                            size="pill"
                            className="hidden md:inline-flex"
                        >
                            Start Your Sprint
                        </Button>
                        <button
                            className="md:hidden text-ink-2 hover:text-ink p-2 transition-colors duration-micro"
                            onClick={() => setIsMobileMenuOpen(!isMobileMenuOpen)}
                            aria-label={isMobileMenuOpen ? 'Close menu' : 'Open menu'}
                            aria-expanded={isMobileMenuOpen}
                        >
                            {isMobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
                        </button>
                    </div>
                </div>

                <AnimatePresence>
                    {isMobileMenuOpen && (
                        <motion.div
                            initial={{ opacity: 0, height: 0 }}
                            animate={{ opacity: 1, height: 'auto' }}
                            exit={{ opacity: 0, height: 0 }}
                            transition={{ duration: 0.3, ease: [0.25, 0.1, 0.25, 1] }}
                            className="md:hidden pt-4 pb-2 border-t border-ink-disabled/20 mt-4 overflow-hidden"
                        >
                            <div className="flex flex-col gap-1">
                                <Link to="/how-it-works" className="text-ink-2 hover:text-ink transition-colors text-sm uppercase tracking-wider py-2 px-2 font-mono" onClick={() => setIsMobileMenuOpen(false)}>
                                    How It Works
                                </Link>
                                <Link to="/work" className="text-ink-2 hover:text-ink transition-colors text-sm uppercase tracking-wider py-2 px-2 font-mono" onClick={() => setIsMobileMenuOpen(false)}>
                                    What We Build
                                </Link>
                                <Link to="/resources" className="text-ink-2 hover:text-ink transition-colors text-sm uppercase tracking-wider py-2 px-2 font-mono" onClick={() => setIsMobileMenuOpen(false)}>
                                    Resources
                                </Link>
                                <div className="h-px bg-ink-disabled/15 my-2" />
                                <div className="flex items-center justify-between px-2 py-2">
                                    <ThemeToggle />
                                    <Button onClick={() => { onBookSandbox?.(); setIsMobileMenuOpen(false); }} variant="gold-pill" size="pill">
                                        Start Your Sprint
                                    </Button>
                                </div>
                            </div>
                        </motion.div>
                    )}
                </AnimatePresence>
            </div>
        </motion.nav>
    );
}
