import { forwardRef } from 'react';

interface SplitTextProps {
    text: string;
    type?: 'words' | 'chars' | 'lines';
    className?: string;
    wordClassName?: string;
    charClassName?: string;
}

export const SplitText = forwardRef<HTMLDivElement, SplitTextProps>(
    ({ text, type = 'words', className = '', wordClassName = '', charClassName = '' }, ref) => {
        const words = text.split(' ');

        if (type === 'chars') {
            return (
                <div ref={ref} className={className} aria-label={text}>
                    {words.map((word, wi) => (
                        <span key={wi} className={`inline-block ${wordClassName}`}>
                            {word.split('').map((char, ci) => (
                                <span
                                    key={ci}
                                    className={`inline-block split-char ${charClassName}`}
                                    style={{ willChange: 'transform, opacity' }}
                                >
                                    {char}
                                </span>
                            ))}
                            {wi < words.length - 1 && (
                                <span className="inline-block split-char">&nbsp;</span>
                            )}
                        </span>
                    ))}
                </div>
            );
        }

        return (
            <div ref={ref} className={className} aria-label={text}>
                {words.map((word, i) => (
                    <span
                        key={i}
                        className={`inline-block split-word ${wordClassName}`}
                        style={{ willChange: 'transform, opacity' }}
                    >
                        {word}
                        {i < words.length - 1 && '\u00A0'}
                    </span>
                ))}
            </div>
        );
    }
);

SplitText.displayName = 'SplitText';
