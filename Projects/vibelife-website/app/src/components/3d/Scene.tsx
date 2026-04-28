import { Suspense, useRef, useEffect, useState } from 'react';
import { Canvas } from '@react-three/fiber';
import { Environment } from '@react-three/drei';

interface SceneProps {
    children: React.ReactNode;
    className?: string;
    cameraPosition?: [number, number, number];
}

export function Scene({ children, className = '', cameraPosition = [0, 0, 5] }: SceneProps) {
    const containerRef = useRef<HTMLDivElement>(null);
    const [isVisible, setIsVisible] = useState(false);

    // Only render Three.js when in viewport
    useEffect(() => {
        const observer = new IntersectionObserver(
            ([entry]) => {
                setIsVisible(entry.isIntersecting);
            },
            { rootMargin: '200px' }
        );

        if (containerRef.current) {
            observer.observe(containerRef.current);
        }

        return () => observer.disconnect();
    }, []);

    return (
        <div ref={containerRef} className={className}>
            {isVisible && (
                <Canvas
                    camera={{ position: cameraPosition, fov: 45 }}
                    dpr={Math.min(window.devicePixelRatio, 2)}
                    gl={{ antialias: true, alpha: true }}
                    style={{ background: 'transparent' }}
                >
                    <Suspense fallback={null}>
                        <ambientLight intensity={0.4} />
                        <directionalLight position={[5, 5, 5]} intensity={0.8} />
                        <pointLight position={[-5, -5, 5]} intensity={0.3} color="#d4a574" />
                        <Environment preset="city" environmentIntensity={0.5} />
                        {children}
                    </Suspense>
                </Canvas>
            )}
        </div>
    );
}
