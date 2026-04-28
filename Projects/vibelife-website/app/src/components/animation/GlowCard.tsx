import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';
import { useRef, useCallback } from 'react';

interface GlowCardProps {
  children: React.ReactNode;
  className?: string;
  glowColor?: 'gold' | 'teal' | 'coral';
  delay?: number;
}

const glowMap = {
  gold: 'rgba(var(--color-gold), 0.12)',
  teal: 'rgba(var(--color-teal), 0.12)',
  coral: 'rgba(var(--color-coral), 0.12)',
};

export function GlowCard({ children, className, glowColor = 'gold', delay = 0 }: GlowCardProps) {
  const glowRef = useRef<HTMLDivElement>(null);

  const handleMouseMove = useCallback((e: React.MouseEvent<HTMLDivElement>) => {
    if (!glowRef.current) return;
    const rect = e.currentTarget.getBoundingClientRect();
    const x = e.clientX - rect.left;
    const y = e.clientY - rect.top;
    glowRef.current.style.background = `radial-gradient(300px circle at ${x}px ${y}px, ${glowMap[glowColor]}, transparent 60%)`;
    glowRef.current.style.opacity = '1';
  }, [glowColor]);

  const handleMouseLeave = useCallback(() => {
    if (!glowRef.current) return;
    glowRef.current.style.opacity = '0';
  }, []);

  return (
    <motion.div
      className={cn(
        'relative rounded-md bg-charcoal-light shadow-neu-raised overflow-hidden',
        'transition-all duration-short',
        className
      )}
      initial={{ opacity: 0, y: 14 }}
      whileInView={{ opacity: 1, y: 0 }}
      viewport={{ once: true, margin: '-10%' }}
      transition={{ delay, duration: 0.45, ease: 'easeOut' }}
      whileHover={{ y: -3 }}
      onMouseMove={handleMouseMove}
      onMouseLeave={handleMouseLeave}
    >
      <div
        ref={glowRef}
        className="absolute inset-0 pointer-events-none transition-opacity duration-300"
        style={{ opacity: 0 }}
      />
      <div className="relative z-10">{children}</div>
    </motion.div>
  );
}
