import React from 'react';
import { cn } from '@/lib/utils';

interface GradientBorderProps {
  children: React.ReactNode;
  className?: string;
  containerClassName?: string;
}

export const GradientBorder: React.FC<GradientBorderProps> = ({
  children,
  className,
  containerClassName,
}) => {
  return (
    <div className={cn("relative group p-[1px] rounded-xl overflow-hidden", containerClassName)}>
      <div className="absolute inset-0 bg-gradient-to-r from-transparent via-gold/40 to-transparent translate-x-[-100%] animate-gradient-border opacity-0 group-hover:opacity-100 transition-opacity duration-500" />
      <div className={cn("relative rounded-xl bg-void-deep border border-ink-disabled/20", className)}>
        {children}
      </div>
    </div>
  );
};
