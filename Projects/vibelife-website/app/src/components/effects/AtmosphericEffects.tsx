/**
 * Global grain texture overlay for premium, editorial feel
 * Uses SVG fractalNoise — opacity swaps per theme via CSS variable
 */
export function GrainOverlay() {
    return (
        <div
            className="grain-overlay"
            aria-hidden="true"
        />
    );
}

/**
 * Animated gradient mesh background
 * Uses CSS animations instead of JS-driven Framer Motion for GPU efficiency.
 * Colors reference CSS variables so they adapt to theme.
 */
export function GradientMesh() {
    return (
        <div className="absolute inset-0 -z-10 overflow-hidden pointer-events-none">
            {/* Primary gold mesh */}
            <div
                className="absolute w-[600px] h-[600px] rounded-full animate-[mesh-drift-1_20s_ease-in-out_infinite]"
                style={{
                    background: 'radial-gradient(circle, rgba(var(--color-gold), 0.12) 0%, transparent 70%)',
                    filter: 'blur(80px)',
                    top: '-20%',
                    right: '-10%',
                    willChange: 'transform',
                }}
            />

            {/* Secondary teal mesh */}
            <div
                className="absolute w-[500px] h-[500px] rounded-full animate-[mesh-drift-2_25s_ease-in-out_infinite]"
                style={{
                    background: 'radial-gradient(circle, rgba(var(--color-teal), 0.10) 0%, transparent 70%)',
                    filter: 'blur(80px)',
                    bottom: '10%',
                    left: '-5%',
                    willChange: 'transform',
                }}
            />
        </div>
    );
}
