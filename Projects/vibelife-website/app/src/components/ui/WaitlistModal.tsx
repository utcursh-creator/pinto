import { motion, AnimatePresence } from 'framer-motion';
import { useState } from 'react';
import { X, Check } from 'lucide-react';
import { Button } from './button';

interface WaitlistModalProps {
  isOpen: boolean;
  onClose: () => void;
}

export function WaitlistModal({ isOpen, onClose }: WaitlistModalProps) {
  const [email, setEmail] = useState('');
  const [isSubmitted, setIsSubmitted] = useState(false);
  const [isLoading, setIsLoading] = useState(false);

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    if (!email) return;

    setIsLoading(true);
    await new Promise(resolve => setTimeout(resolve, 1500));
    setIsLoading(false);
    setIsSubmitted(true);
  };

  return (
    <AnimatePresence>
      {isOpen && (
          <motion.div
            key="waitlist-modal"
            className="fixed inset-0 z-[100] flex items-center justify-center p-4 bg-void/90 backdrop-blur-xl"
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            exit={{ opacity: 0 }}
            onClick={onClose}
          >
            <motion.div
              className="relative w-full max-w-md glass shadow-neu-raised rounded-lg p-8 overflow-hidden"
              initial={{ scale: 0.9, y: 14 }}
              animate={{ scale: 1, y: 0 }}
              exit={{ scale: 0.9, y: 14 }}
              transition={{ type: 'spring', damping: 25, stiffness: 300 }}
              onClick={(e) => e.stopPropagation()}
            >
              {/* Close button */}
              <button
                onClick={onClose}
                className="absolute top-4 right-4 text-ink-3 hover:text-ink transition-colors"
              >
                <X className="w-5 h-5" />
              </button>

              {/* Decorative elements */}
              <div className="absolute -top-20 -right-20 w-40 h-40 bg-gold/10 rounded-full blur-3xl" />
              <div className="absolute -bottom-20 -left-20 w-40 h-40 bg-teal/10 rounded-full blur-3xl" />

              {/* Content */}
              {!isSubmitted ? (
                <div className="relative z-10">
                  <h2 className="text-2xl font-display text-ink mb-2">
                    Join the Waitlist
                  </h2>
                  <p className="text-ink-2 text-sm mb-6">
                    Be among the first to exit the loop. We'll be in touch when the system is ready.
                  </p>

                  <form onSubmit={handleSubmit}>
                    <div className="space-y-4">
                      <div>
                        <label className="section-label mb-1.5 block">
                          Email Address
                        </label>
                        <input
                          type="email"
                          value={email}
                          onChange={(e) => setEmail(e.target.value)}
                          placeholder="you@example.com"
                          className="w-full bg-charcoal shadow-neu-inset rounded-sm px-4 py-3 font-mono text-[0.76rem] text-ink placeholder:text-ink-3 focus:outline-none focus:ring-1 focus:ring-gold/30 transition-all"
                          required
                        />
                      </div>

                      <Button
                        type="submit"
                        disabled={isLoading}
                        variant="gold-pill"
                        className="w-full py-3"
                      >
                        {isLoading ? (
                          <span className="flex items-center justify-center gap-2">
                            <motion.span
                              animate={{ rotate: 360 }}
                              transition={{ duration: 1, repeat: Infinity, ease: 'linear' }}
                            >
                              ⟳
                            </motion.span>
                            Processing...
                          </span>
                        ) : (
                          'Enter the Latent Space'
                        )}
                      </Button>
                    </div>
                  </form>

                  <p className="text-xs text-ink-3 mt-4 text-center">
                    Reality is a controlled hallucination. Let's engineer it.
                  </p>
                </div>
              ) : (
                <motion.div
                  className="relative z-10 text-center py-8"
                  initial={{ opacity: 0, scale: 0.9 }}
                  animate={{ opacity: 1, scale: 1 }}
                >
                  <div className="w-16 h-16 rounded-full bg-gold/20 flex items-center justify-center mx-auto mb-4">
                    <Check className="w-8 h-8 text-gold" />
                  </div>
                  <h3 className="text-xl font-display text-ink mb-2">
                    You're on the list
                  </h3>
                  <p className="text-ink-2 mb-4">
                    We'll be in touch when the system is ready.
                  </p>
                  <p className="text-xs text-gold font-mono tracking-wider">
                    Status: Queued
                  </p>
                </motion.div>
              )}
            </motion.div>
          </motion.div>
      )}
    </AnimatePresence>
  );
}
