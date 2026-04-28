import { motion, useInView } from 'framer-motion';
import { useRef } from 'react';
import { cn } from '@/lib/utils';

interface FlowNode {
  label: string;
  sub?: string;
  icon?: React.ReactNode;
  color?: 'gold' | 'teal' | 'coral' | 'white';
}

interface FlowDiagramProps {
  nodes: FlowNode[];
  className?: string;
  direction?: 'horizontal' | 'vertical';
}

const colorStyles = {
  gold: 'border-gold/30 bg-gold/5 text-gold',
  teal: 'border-teal/30 bg-teal/5 text-teal',
  coral: 'border-coral/30 bg-coral/5 text-coral',
  white: 'border-ink-disabled/30 bg-charcoal/50 text-ink-2',
};

const pulseColors = {
  gold: 'bg-gold',
  teal: 'bg-teal',
  coral: 'bg-coral',
  white: 'bg-ink-2',
};

export function FlowDiagram({ nodes, className, direction = 'horizontal' }: FlowDiagramProps) {
  const ref = useRef(null);
  const isInView = useInView(ref, { once: true, margin: '-10%' });

  const isHorizontal = direction === 'horizontal';

  return (
    <div
      ref={ref}
      className={cn(
        'flex items-center justify-center gap-0',
        isHorizontal ? 'flex-col md:flex-row' : 'flex-col',
        className
      )}
    >
      {nodes.map((node, i) => (
        <div key={i} className={cn('flex items-center', isHorizontal ? 'flex-col md:flex-row' : 'flex-col')}>
          {/* Node */}
          <motion.div
            className={cn(
              'relative px-5 py-3 rounded-md border shadow-neu-raised',
              'text-center min-w-[120px]',
              colorStyles[node.color || 'white']
            )}
            initial={{ opacity: 0, scale: 0.8 }}
            animate={isInView ? { opacity: 1, scale: 1 } : {}}
            transition={{ delay: i * 0.15, duration: 0.4, type: 'spring', stiffness: 200 }}
          >
            {node.icon && <div className="mb-1">{node.icon}</div>}
            <p className="text-sm font-semibold">{node.label}</p>
            {node.sub && <p className="text-[10px] text-ink-3 mt-0.5">{node.sub}</p>}
          </motion.div>

          {/* Connector */}
          {i < nodes.length - 1 && (
            <div className={cn(
              'relative flex items-center justify-center',
              isHorizontal ? 'w-8 md:w-12 h-8 md:h-px my-2 md:my-0' : 'h-8 w-px mx-auto'
            )}>
              <motion.div
                className={cn(
                  isHorizontal ? 'hidden md:block w-full h-px' : 'h-full w-px',
                  'bg-gradient-to-r from-transparent via-ink-disabled/30 to-transparent'
                )}
                initial={{ scaleX: 0, scaleY: isHorizontal ? 1 : 0 }}
                animate={isInView ? { scaleX: 1, scaleY: 1 } : {}}
                transition={{ delay: i * 0.15 + 0.1, duration: 0.3 }}
              />
              {/* Pulse dot */}
              <motion.div
                className={cn('absolute w-1.5 h-1.5 rounded-full', pulseColors[nodes[i + 1]?.color || 'white'])}
                initial={{ opacity: 0 }}
                animate={isInView ? {
                  opacity: [0, 1, 0],
                  x: isHorizontal ? [0, 20, 40] : 0,
                  y: isHorizontal ? 0 : [0, 10, 20],
                } : {}}
                transition={{ delay: i * 0.15 + 0.3, duration: 1.5, repeat: Infinity }}
              />
              {/* Mobile arrow */}
              <svg className={cn('md:hidden w-3 h-3 text-ink-disabled', isHorizontal ? '' : '')} viewBox="0 0 12 12" fill="none">
                <path d="M6 2L6 10M6 10L2 6M6 10L10 6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
            </div>
          )}
        </div>
      ))}
    </div>
  );
}
