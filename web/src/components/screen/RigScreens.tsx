import { useState } from 'react';
import { useNuiEvent } from '../../hooks/useNuiEvent';
import { isEnvBrowser } from '../../utils/misc';
import { color, font, scanlines } from '../../theme/tokens';
import type { RigScreenFrameEntry, RigScreenStat } from '../../types';

// The floating live monitor drawn on each nearby rig. Driven entirely by two
// NUI messages from client/screen.lua: `rigScreenStats` (the numbers, slow) and
// `rigScreenFrame` (where/how big to draw, per frame). It renders as a passive,
// click-through layer so it never interferes with the game or the dashboard.

const SEVERITY_COLOR: Record<RigScreenStat['severity'], string> = {
  good: color.good,
  warn: color.warn,
  danger: color.bad,
  idle: color.textMuted,
};

// A little browser-preview sample so the monitor is visible during `npm start`.
const DEMO_STATS: Record<string, RigScreenStat> = {
  '1': {
    id: 1,
    label: 'Mining Rig',
    status: 'MINING',
    severity: 'good',
    online: true,
    assembled: true,
    powered: true,
    legacy: false,
    heat: 58,
    powerKw: 1.24,
    hashrate: 42.7,
    btcPerHour: 0.004821,
    gpuTemp: 64,
    cpuTemp: 52,
    usedSlots: 2,
    maxSlots: 4,
    hasCooling: true,
  },
};
const DEMO_FRAME: RigScreenFrameEntry[] = [{ id: 1, x: 0.5, y: 0.52, scale: 1 }];

function heatColor(heat: number): string {
  if (heat >= 80) return color.bad;
  if (heat >= 60) return color.warn;
  return color.good;
}

export function RigScreens() {
  const browser = isEnvBrowser();
  const [stats, setStats] = useState<Record<string, RigScreenStat>>(browser ? DEMO_STATS : {});
  const [frame, setFrame] = useState<RigScreenFrameEntry[]>(browser ? DEMO_FRAME : []);

  useNuiEvent<Record<string, RigScreenStat>>('rigScreenStats', setStats);
  useNuiEvent<RigScreenFrameEntry[]>('rigScreenFrame', (f) => setFrame(Array.isArray(f) ? f : []));

  return (
    <div style={{ position: 'fixed', inset: 0, pointerEvents: 'none', overflow: 'hidden' }}>
      {frame.map((entry) => {
        const stat = stats[String(entry.id)];
        if (!stat) return null;
        return <Monitor key={entry.id} entry={entry} stat={stat} />;
      })}
    </div>
  );
}

function Monitor({ entry, stat }: { entry: RigScreenFrameEntry; stat: RigScreenStat }) {
  const sev = SEVERITY_COLOR[stat.severity] ?? color.textMuted;

  return (
    <div
      style={{
        position: 'absolute',
        left: `${entry.x * 100}%`,
        top: `${entry.y * 100}%`,
        transform: `translate(-50%, -100%) scale(${entry.scale})`,
        transformOrigin: 'bottom center',
        pointerEvents: 'none',
      }}
    >
      {/* Bezel */}
      <div
        style={{
          width: 210,
          background: '#000',
          border: '2px solid #1b1b1b',
          borderRadius: 6,
          padding: 5,
          boxShadow: `0 0 0 1px #000, 0 10px 30px rgba(0,0,0,0.6), 0 0 22px ${sev}22`,
        }}
      >
        {/* Screen */}
        <div
          style={{
            ...scanlines,
            background: 'linear-gradient(180deg, #0b0d10 0%, #070809 100%)',
            border: `1px solid ${color.border}`,
            borderRadius: 3,
            padding: '8px 9px',
            fontFamily: font.mono,
            color: color.text,
            position: 'relative',
          }}
        >
          {/* Header */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
            <span style={{ fontFamily: font.display, fontSize: 9, letterSpacing: '0.1em', color: color.textMuted, textTransform: 'uppercase' }}>
              {stat.label}
            </span>
            <span style={{ fontFamily: font.mono, fontSize: 9, color: color.textDim }}>#{String(stat.id).padStart(3, '0')}</span>
          </div>

          {/* Status */}
          <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
            <span style={{ width: 7, height: 7, borderRadius: '50%', background: sev, boxShadow: `0 0 6px ${sev}` }} />
            <span style={{ fontFamily: font.display, fontSize: 13, fontWeight: 700, letterSpacing: '0.04em', color: sev }}>
              {stat.status}
            </span>
          </div>

          {/* Metric grid */}
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: '5px 10px', marginBottom: 8 }}>
            <Metric label="HASH" value={stat.online ? `${stat.hashrate.toFixed(1)}` : '--'} unit="MH/s" />
            <Metric label="POWER" value={stat.powerKw.toFixed(2)} unit="kW" />
            <Metric label="GPU" value={`${stat.gpuTemp}`} unit="°C" valueColor={heatColor(stat.heat)} />
            <Metric label="CPU" value={`${stat.cpuTemp}`} unit="°C" />
          </div>

          {/* Heat bar */}
          <div style={{ marginBottom: 6 }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', fontSize: 8, color: color.textDim, marginBottom: 2 }}>
              <span>TEMP LOAD</span>
              <span style={{ color: heatColor(stat.heat) }}>{stat.heat}%</span>
            </div>
            <div style={{ height: 4, background: '#15181c', borderRadius: 2, overflow: 'hidden' }}>
              <div style={{ height: '100%', width: `${Math.min(100, stat.heat)}%`, background: heatColor(stat.heat), transition: 'width 400ms ease' }} />
            </div>
          </div>

          {/* Footer */}
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', fontSize: 8, color: color.textDim }}>
            <span>
              GPU {stat.usedSlots}/{stat.maxSlots}
            </span>
            <span style={{ color: stat.hasCooling ? color.good : color.warn }}>{stat.hasCooling ? 'COOLED' : 'NO FAN'}</span>
            <span style={{ color: stat.online ? color.text : color.textDim }}>{stat.online ? `${stat.btcPerHour.toFixed(5)} BTC/h` : 'IDLE'}</span>
          </div>
        </div>
      </div>

      {/* Stand */}
      <div style={{ width: 14, height: 8, margin: '0 auto', background: '#121212', borderRadius: '0 0 3px 3px' }} />
      <div style={{ width: 40, height: 3, margin: '0 auto', background: '#1b1b1b', borderRadius: 2 }} />
    </div>
  );
}

function Metric({ label, value, unit, valueColor }: { label: string; value: string; unit: string; valueColor?: string }) {
  return (
    <div>
      <div style={{ fontSize: 8, color: color.textDim, letterSpacing: '0.08em' }}>{label}</div>
      <div style={{ fontFamily: font.mono, fontVariantNumeric: 'tabular-nums' }}>
        <span style={{ fontSize: 13, color: valueColor ?? color.text }}>{value}</span>
        <span style={{ fontSize: 8, color: color.textMuted, marginLeft: 2 }}>{unit}</span>
      </div>
    </div>
  );
}
