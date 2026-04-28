import { motion, type Variants } from 'framer-motion';

const pageVariants: Variants = {
    initial: {
        opacity: 0,
        y: 14,
    },
    enter: {
        opacity: 1,
        y: 0,
        transition: {
            duration: 0.45,
            ease: [0.25, 0.1, 0.25, 1] as [number, number, number, number],
        },
    },
    exit: {
        opacity: 0,
        y: -10,
        transition: {
            duration: 0.3,
            ease: [0.4, 0, 1, 1] as [number, number, number, number],
        },
    },
};

export function PageTransition({ children }: { children: React.ReactNode }) {
    return (
        <motion.div
            variants={pageVariants}
            initial="initial"
            animate="enter"
            exit="exit"
        >
            {children}
        </motion.div>
    );
}
