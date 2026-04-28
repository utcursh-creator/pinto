import { useEffect, useRef, useCallback, useState } from 'react';
import gsap from 'gsap';

export function CustomCursor() {
    const cursorRef = useRef<HTMLDivElement>(null);
    const cursorDotRef = useRef<HTMLDivElement>(null);
    const isVisibleRef = useRef(false);
    const isHoveringRef = useRef(false);
    const [isFullscreen, setIsFullscreen] = useState(false);

    const updateCursorStyle = useCallback(() => {
        const cursor = cursorRef.current;
        if (!cursor) return;
        const hovering = isHoveringRef.current;
        cursor.style.width = hovering ? '60px' : '32px';
        cursor.style.height = hovering ? '60px' : '32px';
        const ring = cursor.firstElementChild as HTMLElement;
        if (ring) {
            ring.style.borderColor = hovering ? 'rgba(var(--color-gold), 0.6)' : 'rgba(var(--color-ink), 0.3)';
            ring.style.borderWidth = hovering ? '2px' : '1px';
        }
        const dot = cursorDotRef.current;
        if (dot) {
            dot.style.width = hovering ? '6px' : '4px';
            dot.style.height = hovering ? '6px' : '4px';
        }
    }, []);

    useEffect(() => {
        // Don't show on touch devices
        if ('ontouchstart' in window) return;

        const cursor = cursorRef.current;
        const dot = cursorDotRef.current;
        if (!cursor || !dot) return;

        // Use GSAP for smooth cursor following — no React state, no re-renders
        const moveCursor = (e: MouseEvent) => {
            if (!isVisibleRef.current) {
                isVisibleRef.current = true;
                cursor.style.opacity = '1';
                dot.style.opacity = '1';
            }
            gsap.to(cursor, { x: e.clientX, y: e.clientY, duration: 0.25, ease: 'power2.out', overwrite: true });
            gsap.to(dot, { x: e.clientX, y: e.clientY, duration: 0.08, ease: 'none', overwrite: true });
        };

        const handleMouseLeave = () => {
            isVisibleRef.current = false;
            cursor.style.opacity = '0';
            dot.style.opacity = '0';
        };

        // Single delegated event listener — no per-element listeners needed
        const handleOver = (e: MouseEvent) => {
            const target = e.target as HTMLElement;
            if (target.closest('a, button, [role="button"], input, textarea, select, .cursor-hover')) {
                if (!isHoveringRef.current) {
                    isHoveringRef.current = true;
                    updateCursorStyle();
                }
            }
        };

        const handleOut = (e: MouseEvent) => {
            const target = e.target as HTMLElement;
            if (target.closest('a, button, [role="button"], input, textarea, select, .cursor-hover')) {
                if (isHoveringRef.current) {
                    isHoveringRef.current = false;
                    updateCursorStyle();
                }
            }
        };

        const handleFullscreenChange = () => {
            setIsFullscreen(!!document.fullscreenElement);
        };

        window.addEventListener('mousemove', moveCursor, { passive: true });
        document.addEventListener('mouseleave', handleMouseLeave);
        document.addEventListener('mouseover', handleOver, { passive: true });
        document.addEventListener('mouseout', handleOut, { passive: true });
        document.addEventListener('fullscreenchange', handleFullscreenChange);

        return () => {
            window.removeEventListener('mousemove', moveCursor);
            document.removeEventListener('mouseleave', handleMouseLeave);
            document.removeEventListener('mouseover', handleOver);
            document.removeEventListener('mouseout', handleOut);
            document.removeEventListener('fullscreenchange', handleFullscreenChange);
        };
    }, [updateCursorStyle]);

    // Don't render on touch devices
    if (typeof window !== 'undefined' && 'ontouchstart' in window) return null;

    return (
        <>
            <div
                ref={cursorRef}
                className="fixed top-0 left-0 pointer-events-none z-[9999] -translate-x-1/2 -translate-y-1/2 transition-[width,height] duration-300"
                style={{ width: 32, height: 32, opacity: 0 }}
            >
                <div
                    className="w-full h-full rounded-full border transition-all duration-300"
                    style={{ borderColor: 'rgba(var(--color-ink), 0.3)', borderWidth: 1 }}
                />
            </div>
            <div
                ref={cursorDotRef}
                className="fixed top-0 left-0 pointer-events-none z-[9999] -translate-x-1/2 -translate-y-1/2 transition-[width,height] duration-200"
                style={{ width: 4, height: 4, opacity: 0 }}
            >
                <div className="w-full h-full rounded-full bg-ink" />
            </div>
            <style>{`
                @media (pointer: fine) {
                    ${isFullscreen ? '' : '* { cursor: none !important; }'}
                }
            `}</style>
        </>
    );
}
