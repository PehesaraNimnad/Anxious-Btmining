import { useEffect, useRef, useState } from 'react';
import { color, font } from '../../theme/tokens';
import type { PinsDifficulty } from '../../types';

// "Pin Align" (CPU) -- a pointer sweeps around the socket ring; lock it while
// it's inside the keyed arc to seat the chip. A single precise press, the way
// a CPU drops in one correct orientation -- distinct from the repeated-strike
// Sweep and the memory Sequence games.
const TIME_LIMIT_MS = 8000;

export function PinsGame({ difficulty, onResult }: { difficulty: PinsDifficulty; onResult: (success: boolean) => void }) {
  const { arcDeg, speedMs } = difficulty;

  const startRef = useRef(performance.now());
  const arcStart = useRef(Math.random() * (360 - arcDeg));
  const [angle, setAngle] = useState(0);
  const [msLeft, setMsLeft] = useState(TIME_LIMIT_MS);
  const [flash, setFlash] = useState<'hit' | 'miss' | null>(null);
  const doneRef = useRef(false);

  const finish = (success: boolean) => {
    if (doneRef.current) return;
    doneRef.current = true;
    setFlash(success ? 'hit' : 'miss');
    onResult(success);
  };

  useEffect(() => {
    let raf: number;
    const tick = () => {
      const elapsed = performance.now() - startRef.current;
      const remaining = TIME_LIMIT_MS - elapsed;
      if (remaining <= 0) {
        setMsLeft(0);
        finish(false);
        return;
      }
      setMsLeft(remaining);
      setAngle(((elapsed / speedMs) * 360) % 360);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function lock() {
    if (doneRef.current) return;
    const a = ((performance.now() - startRef.current) / speedMs) * 360 % 360;
    const rel = (a - arcStart.current + 360) % 360;
    finish(rel <= arcDeg);
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.code === 'Space') {
        e.preventDefault();
        lock();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const size = 220;
  const r = 90;
  const cx = size / 2;
  const cy = size / 2;
  const toXY = (deg: number) => {
    const rad = ((deg - 90) * Math.PI) / 180;
    return { x: cx + r * Math.cos(rad), y: cy + r * Math.sin(rad) };
  };
  const arcEnd = arcStart.current + arcDeg;
  const s = toXY(arcStart.current);
  const e = toXY(arcEnd);
  const largeArc = arcDeg > 180 ? 1 : 0;
  const marker = toXY(angle);
  const ring = flash === 'hit' ? color.good : flash === 'miss' ? color.bad : color.border;

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
      <svg width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
        <circle cx={cx} cy={cy} r={r} fill="none" stroke={ring} strokeWidth={2} />
        <path
          d={`M ${s.x} ${s.y} A ${r} ${r} 0 ${largeArc} 1 ${e.x} ${e.y}`}
          fill="none"
          stroke={color.good}
          strokeWidth={7}
          strokeLinecap="round"
        />
        <line x1={cx} y1={cy} x2={marker.x} y2={marker.y} stroke={color.borderBright} strokeWidth={2} />
        <circle cx={marker.x} cy={marker.y} r={5} fill={color.borderBright} />
        <circle cx={cx} cy={cy} r={4} fill={color.textDim} />
      </svg>

      <div style={{ fontFamily: font.mono, fontSize: 12, color: color.textMuted }}>TIME {(msLeft / 1000).toFixed(1)}s</div>

      <button
        onClick={lock}
        style={{
          fontFamily: font.display,
          fontSize: 13,
          fontWeight: 700,
          letterSpacing: '0.08em',
          textTransform: 'uppercase',
          background: flash === 'hit' ? color.good : flash === 'miss' ? color.bad : color.text,
          color: color.bg,
          border: 'none',
          borderRadius: 2,
          padding: '12px 40px',
          cursor: 'pointer',
        }}
      >
        Seat Chip [Space]
      </button>
    </div>
  );
}
