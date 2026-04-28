import { useEffect, useRef, createContext, useContext } from 'react';
import { useLocation } from 'react-router-dom';
import Lenis from 'lenis';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

const LenisContext = createContext<Lenis | null>(null);

export function useLenis() {
    return useContext(LenisContext);
}

export function SmoothScroll({ children }: { children: React.ReactNode }) {
    const { pathname } = useLocation();
    const lenisRef = useRef<Lenis | null>(null);

    useEffect(() => {
        window.scrollTo(0, 0);
        ScrollTrigger.refresh();
    }, [pathname]);

    useEffect(() => {
        const lenis = new Lenis({
            duration: 1.2,
            easing: (t) => Math.min(1, 1.001 - Math.pow(2, -10 * t)),
            orientation: 'vertical',
            gestureOrientation: 'vertical',
            smoothWheel: true,
            wheelMultiplier: 1,
            touchMultiplier: 2,
        });

        lenisRef.current = lenis;

        // Sync Lenis scroll position with GSAP ScrollTrigger
        lenis.on('scroll', ScrollTrigger.update);

        // Use GSAP ticker to drive Lenis instead of manual rAF
        const tickerCallback = (time: number) => {
            lenis.raf(time * 1000); // GSAP ticker uses seconds, Lenis expects ms
        };
        gsap.ticker.add(tickerCallback);

        // Keep GSAP lag smoothing at default to prevent frame spikes
        gsap.ticker.lagSmoothing(500, 33);

        return () => {
            gsap.ticker.remove(tickerCallback);
            lenis.destroy();
            lenisRef.current = null;
        };
    }, []);

    return (
        <LenisContext.Provider value={lenisRef.current}>
            {children}
        </LenisContext.Provider>
    );
}
