import React, { useRef } from 'react';
import { motion, useInView } from 'framer-motion';
import { cn } from '@/lib/utils';

interface FadeInViewProps {
  children: React.ReactNode;
  className?: string;
  delay?: number;
  direction?: 'up' | 'down' | 'left' | 'right' | 'none';
  duration?: number;
}

export const FadeInView: React.FC<FadeInViewProps> = ({
  children,
  className,
  delay = 0,
  direction = 'up',
  duration = 0.5,
}) => {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: "-10%" });

  const getVariants = () => {
    const distance = 14;
    const variants: any = {
      hidden: { opacity: 0, x: 0, y: 0 },
      visible: {
        opacity: 1,
        x: 0,
        y: 0,
        transition: { duration, delay, ease: "easeOut" }
      },
    };

    if (direction === 'up') variants.hidden.y = distance;
    if (direction === 'down') variants.hidden.y = -distance;
    if (direction === 'left') variants.hidden.x = distance;
    if (direction === 'right') variants.hidden.x = -distance;

    return variants;
  };

  return (
    <motion.div
      ref={ref}
      initial="hidden"
      animate={isInView ? "visible" : "hidden"}
      variants={getVariants()}
      className={cn(className)}
    >
      {children}
    </motion.div>
  );
};
