import { motion } from 'framer-motion';
import { cn } from '@/lib/utils';

interface PulseBeaconProps {
  color?: 'gold' | 'teal' | 'coral' | 'green';
  size?: 'sm' | 'md' | 'lg';
  className?: string;
}

const colorMap = {
  gold: 'bg-gold',
  teal: 'bg-teal',
  coral: 'bg-coral',
  green: 'bg-emerald-400',
};

const sizeMap = {
  sm: 'w-2 h-2',
  md: 'w-3 h-3',
  lg: 'w-4 h-4',
};

const ringSizeMap = {
  sm: 'w-6 h-6',
  md: 'w-8 h-8',
  lg: 'w-10 h-10',
};

export function PulseBeacon({ color = 'teal', size = 'md', className }: PulseBeaconProps) {
  return (
    <div className={cn('relative flex items-center justify-center', ringSizeMap[size], className)}>
      {/* Pulse ring */}
      <motion.div
        className={cn('absolute rounded-full', ringSizeMap[size], colorMap[color], 'opacity-20')}
        animate={{ scale: [1, 2, 1], opacity: [0.2, 0, 0.2] }}
        transition={{ duration: 2, repeat: Infinity, ease: 'easeOut' }}
      />
      {/* Core dot */}
      <div className={cn('rounded-full', sizeMap[size], colorMap[color])} />
    </div>
  );
}
