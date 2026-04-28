import { useState, useEffect } from 'react';
import { cn } from '@/lib/utils';

export interface FloatingSphereProps {
  className?: string;
  size?: number;
  color?: string;
  src?: string;
  delay?: number;
  duration?: number;
  blur?: number;
  position?: {
    top?: string | number;
    bottom?: string | number;
    left?: string | number;
    right?: string | number;
  };
}

export function FloatingSphere({
  className,
  size = 200,
  color = 'bg-teal',
  src,
  delay = 0,
  duration = 4,
  blur = 40,
  position,
}: FloatingSphereProps) {
  const [isMobile, setIsMobile] = useState(false);

  useEffect(() => {
    const mql = window.matchMedia('(max-width: 767px)');
    setIsMobile(mql.matches);

    const handler = (e: MediaQueryListEvent) => setIsMobile(e.matches);
    mql.addEventListener('change', handler);
    return () => mql.removeEventListener('change', handler);
  }, []);

  const adjustedSize = isMobile ? Math.min(size * 0.5, 100) : size;
  const adjustedBlur = isMobile ? Math.min(blur * 0.5, 20) : blur;

  const style: React.CSSProperties = {
    width: adjustedSize,
    height: adjustedSize,
    animationDelay: `${delay}s`,
    animationDuration: `${duration}s`,
    contain: 'layout paint',
    ...position,
  };

  if (src) {
    return (
      <img
        src={src}
        alt=""
        loading="lazy"
        decoding="async"
        className={cn(
          "absolute animate-float pointer-events-none select-none",
          "hidden sm:block",
          className
        )}
        style={style}
      />
    );
  }

  return (
    <div
      className={cn(
        "absolute rounded-full opacity-30 animate-float pointer-events-none",
        "hidden sm:block",
        color,
        className
      )}
      style={{
        ...style,
        filter: `blur(${adjustedBlur}px)`,
      }}
    />
  );
}
