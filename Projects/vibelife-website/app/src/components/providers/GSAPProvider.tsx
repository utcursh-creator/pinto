import { useEffect, createContext, useContext } from 'react';
import gsap from 'gsap';
import { ScrollTrigger } from 'gsap/ScrollTrigger';

gsap.registerPlugin(ScrollTrigger);

const GSAPContext = createContext<{ gsap: typeof gsap; ScrollTrigger: typeof ScrollTrigger } | null>(null);

export function useGSAPContext() {
    const ctx = useContext(GSAPContext);
    if (!ctx) throw new Error('useGSAPContext must be used within GSAPProvider');
    return ctx;
}

export function GSAPProvider({ children }: { children: React.ReactNode }) {
    useEffect(() => {
        ScrollTrigger.defaults({
            toggleActions: 'play none none reverse',
        });

        return () => {
            ScrollTrigger.getAll().forEach(st => st.kill());
        };
    }, []);

    return (
        <GSAPContext.Provider value={{ gsap, ScrollTrigger }}>
            {children}
        </GSAPContext.Provider>
    );
}
