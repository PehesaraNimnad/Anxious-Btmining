import { useRef, useState } from 'react';
import { color, font } from '../../theme/tokens';
import type { CablesDifficulty } from '../../types';

// "Power Routing" (PSU) -- click a colored lead, then the socket of the same
// color. Match every lead to seat the PSU; one wrong socket shorts it and the
// attempt fails. A wiring puzzle, not a timing bar -- the PSU's own feel.
const LEAD_COLORS = ['#f87171', '#4ade80', '#60a5fa', '#fbbf24', '#c084fc', '#22d3ee'];

interface Port {
  id: number;
  colorIndex: number;
}

export function CablesGame({ difficulty, onResult }: { difficulty: CablesDifficulty; onResult: (success: boolean) => void }) {
  const pairs = Math.min(Math.max(difficulty.pairs, 2), LEAD_COLORS.length);

  // Leads keep a fixed order; sockets are a shuffled copy of the same colors.
  const leads = useRef<Port[]>(Array.from({ length: pairs }, (_, i) => ({ id: i, colorIndex: i })));
  const sockets = useRef<Port[]>(shuffle(Array.from({ length: pairs }, (_, i) => ({ id: i, colorIndex: i }))));

  const [selectedLead, setSelectedLead] = useState<number | null>(null);
  const [connected, setConnected] = useState<Set<number>>(new Set()); // lead colorIndexes done
  const [bad, setBad] = useState<number | null>(null); // socket id flashing red
  const doneRef = useRef(false);

  const finish = (success: boolean) => {
    if (doneRef.current) return;
    doneRef.current = true;
    onResult(success);
  };

  function clickLead(colorIndex: number) {
    if (doneRef.current || connected.has(colorIndex)) return;
    setSelectedLead(colorIndex);
  }

  function clickSocket(socket: Port) {
    if (doneRef.current || selectedLead === null) return;
    if (socket.colorIndex === selectedLead) {
      const next = new Set(connected);
      next.add(selectedLead);
      setConnected(next);
      setSelectedLead(null);
      if (next.size >= pairs) finish(true);
    } else {
      // Wrong socket -- short circuit, fail the attempt.
      setBad(socket.id);
      setTimeout(() => finish(false), 250);
    }
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 14 }}>
      <div style={{ fontFamily: font.mono, fontSize: 11, color: color.textMuted }}>
        {connected.size}/{pairs} leads routed
      </div>
      <div style={{ display: 'flex', gap: 60 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {leads.current.map((lead) => {
            const isDone = connected.has(lead.colorIndex);
            const isSel = selectedLead === lead.colorIndex;
            return (
              <button
                key={lead.id}
                onClick={() => clickLead(lead.colorIndex)}
                disabled={isDone}
                style={{
                  width: 90,
                  height: 34,
                  display: 'flex',
                  alignItems: 'center',
                  gap: 8,
                  padding: '0 10px',
                  background: color.panelAlt,
                  border: `1px solid ${isSel ? color.borderBright : color.border}`,
                  borderRadius: 2,
                  cursor: isDone ? 'default' : 'pointer',
                  opacity: isDone ? 0.4 : 1,
                }}
              >
                <span style={{ width: 14, height: 14, borderRadius: '50%', background: LEAD_COLORS[lead.colorIndex] }} />
                <span style={{ fontFamily: font.mono, fontSize: 10, color: color.textMuted }}>{isDone ? 'OK' : 'LEAD'}</span>
              </button>
            );
          })}
        </div>

        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          {sockets.current.map((socket) => {
            const isDone = connected.has(socket.colorIndex);
            const isBad = bad === socket.id;
            return (
              <button
                key={socket.id}
                onClick={() => clickSocket(socket)}
                disabled={isDone}
                style={{
                  width: 90,
                  height: 34,
                  display: 'flex',
                  alignItems: 'center',
                  justifyContent: 'flex-end',
                  gap: 8,
                  padding: '0 10px',
                  background: color.panelAlt,
                  border: `1px solid ${isBad ? color.bad : isDone ? color.good : color.border}`,
                  borderRadius: 2,
                  cursor: isDone ? 'default' : 'pointer',
                }}
              >
                <span style={{ fontFamily: font.mono, fontSize: 10, color: color.textMuted }}>{isDone ? 'OK' : 'PORT'}</span>
                <span
                  style={{
                    width: 14,
                    height: 14,
                    borderRadius: 3,
                    border: `2px solid ${LEAD_COLORS[socket.colorIndex]}`,
                    background: isDone ? LEAD_COLORS[socket.colorIndex] : 'transparent',
                  }}
                />
              </button>
            );
          })}
        </div>
      </div>
      <div style={{ fontFamily: font.mono, fontSize: 10, color: color.textDim }}>
        Click a lead, then its matching port. A wrong port shorts the supply.
      </div>
    </div>
  );
}

function shuffle<T>(arr: T[]): T[] {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}
