import { useRef } from 'react';
import { useFrame } from '@react-three/fiber';
import { Float, MeshDistortMaterial } from '@react-three/drei';
import * as THREE from 'three';

interface HeroSphereProps {
    color?: string;
    metalness?: number;
    roughness?: number;
    distort?: number;
    speed?: number;
    scale?: number;
}

export function HeroSphere({
    color = '#d4a574',
    metalness = 0.9,
    roughness = 0.1,
    distort = 0.3,
    speed = 2,
    scale = 1.8,
}: HeroSphereProps) {
    const meshRef = useRef<THREE.Mesh>(null);

    useFrame(({ clock, pointer }) => {
        if (!meshRef.current) return;

        // Gentle auto-rotation
        meshRef.current.rotation.y = clock.getElapsedTime() * 0.15;
        meshRef.current.rotation.x = Math.sin(clock.getElapsedTime() * 0.1) * 0.1;

        // React to mouse position (subtle tilt)
        meshRef.current.rotation.z = THREE.MathUtils.lerp(
            meshRef.current.rotation.z,
            pointer.x * 0.1,
            0.05
        );
    });

    return (
        <Float
            speed={1.5}
            rotationIntensity={0.3}
            floatIntensity={0.5}
        >
            <mesh ref={meshRef} scale={scale}>
                <sphereGeometry args={[1, 64, 64]} />
                <MeshDistortMaterial
                    color={color}
                    metalness={metalness}
                    roughness={roughness}
                    distort={distort}
                    speed={speed}
                    envMapIntensity={1.2}
                />
            </mesh>

            {/* Inner glow sphere */}
            <mesh scale={scale * 1.05}>
                <sphereGeometry args={[1, 32, 32]} />
                <meshBasicMaterial
                    color={color}
                    transparent
                    opacity={0.05}
                />
            </mesh>
        </Float>
    );
}
