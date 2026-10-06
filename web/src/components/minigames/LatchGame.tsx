import { useEffect, useRef, useState } from 'react';
import { color, font } from '../../theme/tokens';
import type { LatchDifficulty } from '../../types';

// "DIMM Latch" (RAM) -- two latches, left then right. A marker sweeps each
// latch's slot; clip it (Space) while the marker is in the green zone. Clip
// both to seat the stick; a miss on either snaps it back out. Two-stage
// timing, distinct from the single-target Sweep.
const TIME_LIMIT_MS = 8000;

type Stage = 0 | 1 | 2; // 0 = left latch, 1 = right latch, 2 = done

export function LatchGame({ difficulty, onResult }: { difficulty: LatchDifficulty; onResult: (success: boolean) => void }) {
  const { zoneWidthPct, speedMs } = difficulty;

  const startRef = useRef(performance.now());
  const [stage, setStage] = useState<Stage>(0);
  const [pos, setPos] = useState(0);
  const [msLeft, setMsLeft] = useState(TIME_LIMIT_MS);
  const [flash, setFlash] = useState<'hit' | 'miss' | null>(null);
  const zones = useRef<[number, number]>([randomZone(zoneWidthPct), randomZone(zoneWidthPct)]);
  const stageRef = useRef<Stage>(0);
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
      const cycle = speedMs * 2;
      const phase = elapsed % cycle;
      setPos(phase <= speedMs ? (phase / speedMs) * 100 : (1 - (phase - speedMs) / speedMs) * 100);
      raf = requestAnimationFrame(tick);
    };
    raf = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(raf);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  function clip() {
    if (doneRef.current) return;
    const s = stageRef.current;
    if (s !== 0 && s !== 1) return;

    const elapsed = performance.now() - startRef.current;
    const cycle = speedMs * 2;
    const phase = elapsed % cycle;
    const current = phase <= speedMs ? (phase / speedMs) * 100 : (1 - (phase - speedMs) / speedMs) * 100;

    const zoneStart = zones.current[s];
    const hit = current >= zoneStart && current <= zoneStart + zoneWidthPct;
    setFlash(hit ? 'hit' : 'miss');
    setTimeout(() => setFlash(null), 140);

    if (!hit) {
      finish(false);
      return;
    }
    const next = (s + 1) as Stage;
    stageRef.current = next;
    setStage(next);
    if (next >= 2) finish(true);
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.code === 'Space') {
        e.preventDefault();
        clip();
      }
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 18 }}>
      <div style={{ display: 'flex', gap: 28 }}>
        {[0, 1].map((i) => (
          <Latch key={i} active={stage === i} done={stage > i} pos={pos} zoneStart={zones.current[i]} zoneWidthPct={zoneWidthPct} flash={stage === i ? flash : null} />
        ))}
      </div>

      <div style={{ fontFamily: font.mono, fontSize: 12, color: color.textMuted }}>
        LATCH {Math.min(stage + 1, 2)}/2 &nbsp; TIME {(msLeft / 1000).toFixed(1)}s
      </div>

      <button
        onClick={clip}
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
        Clip Latch [Space]
      </button>
    </div>
  );
}

function randomZone(zoneWidthPct: number): number {
  return Math.random() * (100 - zoneWidthPct);
}

function Latch({
  active,
  done,
  pos,
  zoneStart,
  zoneWidthPct,
  flash,
}: {
  active: boolean;
  done: boolean;
  pos: number;
  zoneStart: number;
  zoneWidthPct: number;
  flash: 'hit' | 'miss' | null;
}) {
  const border = flash === 'hit' || done ? color.good : flash === 'miss' ? color.bad : active ? color.borderBright : color.border;
  return (
    <div
      style={{
        position: 'relative',
        width: 36,
        height: 180,
        background: color.panelAlt,
        border: `1px solid ${border}`,
        borderRadius: 2,
        opacity: active || done ? 1 : 0.4,
      }}
    >
      <div
        style={{
          position: 'absolute',
          left: 0,
          right: 0,
          top: `${zoneStart}%`,
          height: `${zoneWidthPct}%`,
          background: 'rgba(74,222,128,0.18)',
          borderTop: `1px solid ${color.good}`,
          borderBottom: `1px solid ${color.good}`,
        }}
      />
      {active && (
        <div
          style={{
            position: 'absolute',
            left: -3,
            right: -3,
            top: `${pos}%`,
            height: 2,
            background: color.borderBright,
            transform: 'translateY(-1px)',
          }}
        />
      )}
      {done && (
        <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', color: color.good, fontFamily: font.mono, fontSize: 18 }}>
          ✓
        </div>
      )}
    </div>
  );
}
