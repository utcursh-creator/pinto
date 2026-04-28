import { motion, useScroll, useTransform, MotionValue } from 'framer-motion';
import { useRef } from 'react';

interface ScrollGradientTextProps {
  children: React.ReactNode;
  className?: string;
  gradient?: string;
}

export function ScrollGradientText({
  children,
  className = '',
  gradient = 'from-gold via-teal to-gold'
}: ScrollGradientTextProps) {
  const ref = useRef<HTMLSpanElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start 0.9', 'start 0.3'],
  });

  const opacity = useTransform(scrollYProgress, [0, 1], [0.3, 1]);
  const scale = useTransform(scrollYProgress, [0, 1], [0.98, 1]);

  return (
    <motion.span
      ref={ref}
      className={`bg-gradient-to-r ${gradient} bg-clip-text text-transparent inline-block ${className}`}
      style={{ opacity, scale }}
    >
      {children}
    </motion.span>
  );
}

interface ScrollRevealTextProps {
  text: string;
  className?: string;
  highlightWords?: string[];
  highlightClass?: string;
}

// Extracted Word component so useTransform is called at component top-level (not inside .map())
function ScrollRevealWord({
  word,
  index,
  totalWords,
  scrollYProgress,
  isHighlighted,
  highlightClass,
}: {
  word: string;
  index: number;
  totalWords: number;
  scrollYProgress: MotionValue<number>;
  isHighlighted: boolean;
  highlightClass: string;
}) {
  const wordOpacity = useTransform(
    scrollYProgress,
    [index / totalWords * 0.5, (index + 1) / totalWords * 0.5 + 0.3],
    [0.2, 1]
  );
  const wordY = useTransform(
    scrollYProgress,
    [index / totalWords * 0.5, (index + 1) / totalWords * 0.5 + 0.3],
    [10, 0]
  );

  return (
    <motion.span
      className={`inline-block mr-[0.25em] ${isHighlighted ? highlightClass : ''}`}
      style={{
        opacity: wordOpacity,
        y: wordY,
      }}
    >
      {word}
    </motion.span>
  );
}

export function ScrollRevealText({
  text,
  className = '',
  highlightWords = [],
  highlightClass = 'text-gold'
}: ScrollRevealTextProps) {
  const ref = useRef<HTMLDivElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start 0.8', 'start 0.2'],
  });

  const words = text.split(' ');

  return (
    <div ref={ref} className={className}>
      {words.map((word, i) => {
        const isHighlighted = highlightWords.some(hw =>
          word.toLowerCase().includes(hw.toLowerCase())
        );

        return (
          <ScrollRevealWord
            key={i}
            word={word}
            index={i}
            totalWords={words.length}
            scrollYProgress={scrollYProgress}
            isHighlighted={isHighlighted}
            highlightClass={highlightClass}
          />
        );
      })}
    </div>
  );
}

interface AnimatedHeadlineProps {
  children: React.ReactNode;
  className?: string;
  as?: 'h1' | 'h2' | 'h3' | 'h4' | 'span' | 'p';
}

export function AnimatedHeadline({
  children,
  className = '',
  as: Component = 'h2'
}: AnimatedHeadlineProps) {
  const ref = useRef<HTMLElement>(null);
  const { scrollYProgress } = useScroll({
    target: ref,
    offset: ['start 0.9', 'start 0.4'],
  });

  const opacity = useTransform(scrollYProgress, [0, 1], [0.3, 1]);
  const y = useTransform(scrollYProgress, [0, 1], [14, 0]);
  const backgroundPosition = useTransform(scrollYProgress, [0, 1], ['0% 50%', '100% 50%']);

  return (
    <Component
      ref={ref as any}
      className={`${className}`}
      style={{
        opacity: opacity as any,
        y: y as any,
      }}
    >
      <motion.span
        className="bg-gradient-to-r from-ink via-gold to-teal bg-clip-text text-transparent"
        style={{
          backgroundPosition: backgroundPosition as any,
        }}
      >
        {children}
      </motion.span>
    </Component>
  );
}

interface TypewriterTextProps {
  text: string;
  className?: string;
  delay?: number;
}

export function TypewriterText({ text, className = '', delay = 0 }: TypewriterTextProps) {
  const characters = text.split('');

  return (
    <span className={className}>
      {characters.map((char, i) => (
        <motion.span
          key={i}
          initial={{ opacity: 0 }}
          whileInView={{ opacity: 1 }}
          viewport={{ once: true }}
          transition={{
            delay: delay + i * 0.03,
            duration: 0.1,
          }}
          className={char === ' ' ? 'mr-[0.25em]' : ''}
        >
          {char}
        </motion.span>
      ))}
    </span>
  );
}
