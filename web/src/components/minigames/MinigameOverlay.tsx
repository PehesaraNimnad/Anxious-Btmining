import { useEffect, useRef, useState } from 'react';
import { color, font, scanlines } from '../../theme/tokens';
import type {
  CablesDifficulty,
  LatchDifficulty,
  MinigameRequest,
  PinsDifficulty,
  SequenceDifficulty,
  SweepDifficulty,
} from '../../types';
import { SweepGame } from './SweepGame';
import { SequenceGame } from './SequenceGame';
import { PinsGame } from './PinsGame';
import { LatchGame } from './LatchGame';
import { CablesGame } from './CablesGame';

const TITLES: Record<MinigameRequest['kind'], string> = {
  extinguish: 'Coolant Purge',
  install: 'Socket Alignment',
  hack: 'Firewall Breach',
  sequence: 'Standoff Map',
  pins: 'Pin Align',
  latch: 'DIMM Latch',
  cables: 'Power Routing',
};

const INSTRUCTIONS: Record<MinigameRequest['kind'], string> = {
  extinguish: 'Strike the marker inside the zone to vent pressure before time runs out.',
  install: 'Strike the marker inside the zone to seat the card without cracking a pin.',
  hack: 'Watch the sequence, then repeat it exactly. One wrong node ends the attempt.',
  sequence: 'Memorise the standoff pattern, then repeat it to seat the board.',
  pins: 'Lock the pointer while it is inside the socket arc to seat the chip.',
  latch: 'Clip the left then right latch as the marker passes through each zone.',
  cables: 'Route each colored lead to its matching port. A wrong port shorts out.',
};

export function MinigameOverlay({
  request,
  onResult,
}: {
  request: MinigameRequest;
  onResult: (success: boolean, input?: number[]) => void;
}) {
  const [result, setResult] = useState<'success' | 'failure' | null>(null);
  const reportedRef = useRef(false);

  // `input` is only supplied by the hack (SequenceGame) -- it's the player's
  // actual clicks, passed up so the server can validate them. Sweep games
  // (install/extinguish) leave it undefined.
  function handleResult(success: boolean, input?: number[]) {
    if (reportedRef.current) return;
    reportedRef.current = true;
    setResult(success ? 'success' : 'failure');
    setTimeout(() => onResult(success, input), 700);
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') handleResult(false);
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div
      style={{
        position: 'fixed',
        inset: 0,
        background: 'rgba(0,0,0,0.72)',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'center',
        zIndex: 50,
      }}
    >
      <div
        style={{
          ...scanlines,
          width: 440,
          maxWidth: '90vw',
          border: `1px solid ${result === 'success' ? color.good : result === 'failure' ? color.bad : color.borderBright}`,
          borderRadius: 4,
          background: color.bg,
          boxShadow: '0 24px 64px rgba(0,0,0,0.7)',
          padding: 24,
          display: 'flex',
          flexDirection: 'column',
          alignItems: 'center',
          gap: 16,
        }}
      >
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontFamily: font.display, fontSize: 16, fontWeight: 700, letterSpacing: '0.06em', textTransform: 'uppercase' }}>
            {TITLES[request.kind]}
          </div>
          <div style={{ fontFamily: font.mono, fontSize: 11, color: color.textMuted, marginTop: 6, maxWidth: 340 }}>
            {INSTRUCTIONS[request.kind]}
          </div>
        </div>

        {result ? (
          <div
            style={{
              fontFamily: font.display,
              fontSize: 20,
              fontWeight: 700,
              letterSpacing: '0.08em',
              color: result === 'success' ? color.good : color.bad,
              padding: '24px 0',
            }}
          >
            {result === 'success' ? 'SUCCESS' : 'FAILURE'}
          </div>
        ) : request.kind === 'hack' || request.kind === 'sequence' ? (
          <SequenceGame difficulty={request.difficulty as SequenceDifficulty} onResult={handleResult} />
        ) : request.kind === 'pins' ? (
          <PinsGame difficulty={request.difficulty as PinsDifficulty} onResult={handleResult} />
        ) : request.kind === 'latch' ? (
          <LatchGame difficulty={request.difficulty as LatchDifficulty} onResult={handleResult} />
        ) : request.kind === 'cables' ? (
          <CablesGame difficulty={request.difficulty as CablesDifficulty} onResult={handleResult} />
        ) : (
          <SweepGame difficulty={request.difficulty as SweepDifficulty} onResult={handleResult} />
        )}
      </div>
    </div>
  );
}
