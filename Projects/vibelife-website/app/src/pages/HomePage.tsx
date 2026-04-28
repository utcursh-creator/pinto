import { useState } from 'react';
import { NewNavbar } from '@/components/layout/NewNavbar';
import { NewHeroSection } from '@/components/sections/NewHeroSection';
import { ProofSection } from '@/components/sections/ProofSection';
import { ProblemSection } from '@/components/sections/ProblemSection';
import { SandboxSection } from '@/components/sections/SandboxSection';
import { FounderSection } from '@/components/sections/FounderSection';
import { TrustSection } from '@/components/sections/TrustSection';
import { FinalCTASection } from '@/components/sections/FinalCTASection';
import { FooterSection } from '@/components/sections/FooterSection';
import { WaitlistModal } from '@/components/ui/WaitlistModal';
import { GrainOverlay } from '@/components/effects/AtmosphericEffects';
import { CustomCursor } from '@/components/animation/CustomCursor';

export function HomePage() {
    const [isSandboxModalOpen, setIsSandboxModalOpen] = useState(false);

    const handleBookSandbox = () => {
        setIsSandboxModalOpen(true);
    };

    return (
        <div className="bg-void min-h-screen text-ink antialiased selection:bg-gold/30">
            <CustomCursor />
            <GrainOverlay />

            <WaitlistModal
                isOpen={isSandboxModalOpen}
                onClose={() => setIsSandboxModalOpen(false)}
            />

            <NewNavbar onBookSandbox={handleBookSandbox} />

            <main>
                {/* 1. Hero — proof-first headline */}
                <NewHeroSection onBookSandbox={handleBookSandbox} />

                {/* 2. Proof Bar — stats, logos, testimonial */}
                <section id="proof">
                    <ProofSection />
                </section>

                {/* 3. Problem — fulfillment bottleneck */}
                <ProblemSection />

                {/* 4. 3-Week Sandbox — the offer */}
                <section id="sandbox">
                    <SandboxSection onBookSandbox={handleBookSandbox} />
                </section>

                {/* 5. Before/After — case studies */}
                <FounderSection />

                {/* 6. Trust/Objections — address hesitations */}
                <TrustSection />

                {/* 7. Final CTA */}
                <FinalCTASection onBookSandbox={handleBookSandbox} />
            </main>

            <FooterSection />
        </div>
    );
}
