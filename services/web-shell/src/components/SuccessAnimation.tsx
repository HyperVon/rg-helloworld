import { useEffect } from 'react';
import type { RunStatus } from '../types';

interface SuccessAnimationProps {
  status: RunStatus;
  prefersReducedMotion: boolean;
}

export function SuccessAnimation({ status, prefersReducedMotion }: SuccessAnimationProps) {
  if (status !== 'SUCCEEDED') {
    return null;
  }

  useEffect(() => {
    if (prefersReducedMotion) return;
    const canvas = document.getElementById('success-canvas') as HTMLCanvasElement | null;
    if (!canvas) return;

    const ctx = canvas.getContext('2d');
    if (!ctx) return;

    const particles: { x: number; y: number; vx: number; vy: number; alpha: number }[] = [];
    const count = 50;
    const rect = canvas.getBoundingClientRect();

    for (let i = 0; i < count; i++) {
      particles.push({
        x: Math.random() * rect.width,
        y: Math.random() * rect.height,
        vx: (Math.random() - 0.5) * 2,
        vy: (Math.random() - 0.5) * 2,
        alpha: Math.random() * 0.5 + 0.3,
      });
    }

    let frame = 0;
    const animate = () => {
      ctx.clearRect(0, 0, rect.width, rect.height);
      ctx.fillStyle = '#10b981';
      for (const p of particles) {
        p.x += p.vx;
        p.y += p.vy;
        if (p.x < 0 || p.x > rect.width) p.vx *= -1;
        if (p.y < 0 || p.y > rect.height) p.vy *= -1;
        ctx.globalAlpha = p.alpha;
        ctx.beginPath();
        ctx.arc(p.x, p.y, 3, 0, Math.PI * 2);
        ctx.fill();
      }
      frame++;
      if (frame < 60) {
        requestAnimationFrame(animate);
      }
    };
    animate();
  }, [prefersReducedMotion]);

  return (
    <div className="success-animation">
      <canvas id="success-canvas" width={400} height={200} />
      <style>{`
        .success-animation {
          display: flex;
          flex-direction: column;
          align-items: center;
          gap: 1rem;
        }
        #success-canvas {
          background: transparent;
        }
      `}</style>
    </div>
  );
}
