import { useRef, useCallback } from 'react';
import gsap from 'gsap';

interface MagneticElementProps {
    children: React.ReactNode;
    className?: string;
    strength?: number;
    radius?: number;
}

export function MagneticElement({
    children,
    className = '',
    strength = 0.3,
    radius = 100,
}: MagneticElementProps) {
    const ref = useRef<HTMLDivElement>(null);

    // Use GSAP instead of Framer Motion state — no React re-renders on mouse move
    const handleMouseMove = useCallback((e: React.MouseEvent) => {
        if (!ref.current) return;

        const rect = ref.current.getBoundingClientRect();
        const centerX = rect.left + rect.width / 2;
        const centerY = rect.top + rect.height / 2;

        const distX = e.clientX - centerX;
        const distY = e.clientY - centerY;
        const distance = Math.sqrt(distX * distX + distY * distY);

        if (distance < radius) {
            const factor = 1 - distance / radius;
            gsap.to(ref.current, {
                x: distX * strength * factor,
                y: distY * strength * factor,
                duration: 0.3,
                ease: 'power2.out',
                overwrite: true,
            });
        }
    }, [strength, radius]);

    const handleMouseLeave = useCallback(() => {
        if (!ref.current) return;
        gsap.to(ref.current, {
            x: 0,
            y: 0,
            duration: 0.5,
            ease: 'elastic.out(1, 0.3)',
            overwrite: true,
        });
    }, []);

    return (
        <div
            ref={ref}
            className={className}
            onMouseMove={handleMouseMove}
            onMouseLeave={handleMouseLeave}
        >
            {children}
        </div>
    );
}
