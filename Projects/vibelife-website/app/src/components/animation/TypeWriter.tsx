import { motion, useInView } from 'framer-motion';
import { useRef, useState, useEffect } from 'react';
import { cn } from '@/lib/utils';

interface TypeWriterProps {
  text: string;
  className?: string;
  speed?: number;
  delay?: number;
  cursor?: boolean;
}

export function TypeWriter({ text, className, speed = 40, delay = 0, cursor = true }: TypeWriterProps) {
  const ref = useRef<HTMLSpanElement>(null);
  const isInView = useInView(ref, { once: true });
  const [displayed, setDisplayed] = useState('');
  const [done, setDone] = useState(false);

  useEffect(() => {
    if (!isInView) return;

    const timeout = setTimeout(() => {
      let i = 0;
      const interval = setInterval(() => {
        setDisplayed(text.slice(0, i + 1));
        i++;
        if (i >= text.length) {
          clearInterval(interval);
          setDone(true);
        }
      }, speed);

      return () => clearInterval(interval);
    }, delay);

    return () => clearTimeout(timeout);
  }, [isInView, text, speed, delay]);

  return (
    <span ref={ref} className={cn(className)}>
      {displayed}
      {cursor && (
        <motion.span
          className="inline-block w-[2px] h-[1em] bg-gold ml-0.5 align-text-bottom"
          animate={{ opacity: done ? [1, 0] : 1 }}
          transition={done ? { duration: 0.5, repeat: Infinity, repeatType: 'reverse' } : {}}
        />
      )}
    </span>
  );
}
