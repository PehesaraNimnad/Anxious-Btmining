import { useState } from 'react';
import { fetchNui } from '../../utils/fetchNui';
import { button, buttonPrimary, color, font, panel, panelHeader } from '../../theme/tokens';
import type { ComponentCategoryDef, MinigameDifficulty, MinigameKind, RigData } from '../../types';
import { MinigameOverlay } from '../minigames/MinigameOverlay';

// Build the right difficulty payload for whichever minigame a part uses. These
// are cosmetic skill-gates (the server validates ownership/slots/deps, not the
// minigame), so the numbers only need to feel fair.
function difficultyFor(kind: ComponentCategoryDef['minigame']): { kind: MinigameKind; difficulty: MinigameDifficulty } {
  switch (kind) {
    case 'sequence':
      return { kind: 'sequence', difficulty: { gridSize: 9, length: 4, showDelayMs: 520, inputTimeoutMs: 6500 } };
    case 'pins':
      return { kind: 'pins', difficulty: { arcDeg: 72, speedMs: 1500 } };
    case 'latch':
      return { kind: 'latch', difficulty: { zoneWidthPct: 22, speedMs: 950 } };
    case 'cables':
      return { kind: 'cables', difficulty: { pairs: 4 } };
    case 'sweep':
    default:
      return { kind: 'install', difficulty: { variant: 'linear', zoneWidthPct: 22, speedMs: 900, requiredHits: 2, maxMisses: 1, timeLimitMs: 9000 } };
  }
}

function statLine(def: ComponentCategoryDef, key: string): string | null {
  const tier = def.tiers[key];
  if (!tier) return null;
  if (tier.hashrateBonus) return `+${tier.hashrateBonus} H/s`;
  if (tier.efficiency && tier.efficiency !== 1) return `+${Math.round((tier.efficiency - 1) * 100)}% efficiency`;
  if (tier.wattage) return `${tier.wattage}W delivery`;
  if (tier.coolingBonus) return `+${tier.coolingBonus} cooling`;
  return null;
}

export function AssemblyTab({ data }: { data: RigData; onUpdate: (patch: Partial<RigData>) => void }) {
  const { rig, componentDefs, componentOrder, myComponents } = data;
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState<string | null>(null);
  const [pickerCategory, setPickerCategory] = useState<string | null>(null);
  const [attempt, setAttempt] = useState<{ category: string; tierKey: string; kind: MinigameKind; difficulty: MinigameDifficulty } | null>(null);

  // Legacy rigs (placed before the assembly system) have no component data and
  // just run as-is -- there's nothing to assemble.
  if (!rig.components) {
    return (
      <div style={panel}>
        <div style={panelHeader}>
          <span>Assembly</span>
        </div>
        <div style={{ padding: 16, fontFamily: font.mono, fontSize: 12, color: color.textMuted, lineHeight: 1.6 }}>
          This rig predates the assembly system and runs as a complete unit. Newly placed rigs are built from parts.
        </div>
      </div>
    );
  }

  function beginInstall(category: string, tierKey: string) {
    const def = componentDefs[category];
    const { kind, difficulty } = difficultyFor(def.minigame);
    setMessage(null);
    setPickerCategory(null);
    setAttempt({ category, tierKey, kind, difficulty });
  }

  async function onMinigameResult(success: boolean) {
    const a = attempt;
    setAttempt(null);
    if (!a) return;
    if (!success) {
      setMessage('Install failed -- the part didn\'t seat. Try again.');
      return;
    }
    setBusy(true);
    const res = await fetchNui<{ ok: boolean; message?: string }>('installComponent', { category: a.category, tierKey: a.tierKey });
    if (!res.ok) setMessage(res.message ?? 'Install failed');
    setBusy(false);
  }

  async function remove(category: string) {
    setBusy(true);
    setMessage(null);
    const res = await fetchNui<{ ok: boolean; message?: string }>('removeComponent', { category });
    if (!res.ok) setMessage(res.message ?? 'Remove failed');
    setBusy(false);
  }

  const missing = rig.missingComponents ?? [];

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      <div style={panel}>
        <div style={panelHeader}>
          <span>Build Status</span>
          <span style={{ fontFamily: font.mono, fontSize: 11, color: rig.assembled ? color.good : color.warn }}>
            {rig.assembled ? 'READY TO RUN' : 'INCOMPLETE'}
          </span>
        </div>
        <div style={{ padding: 12, fontFamily: font.mono, fontSize: 12, color: color.textMuted }}>
          {rig.assembled
            ? 'All core components installed. This rig can be powered on and will mine.'
            : `Missing: ${missing.map((c) => componentDefs[c]?.label ?? c).join(', ')} -- the rig can't power on until these are installed.`}
        </div>
      </div>

      <div style={panel}>
        <div style={panelHeader}>
          <span>Components</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column' }}>
          {componentOrder.map((category) => {
            const def = componentDefs[category];
            if (!def) return null;
            const slot = rig.components?.[category];
            const installed = slot && slot.key ? slot : null;
            const owned = myComponents.filter((c) => c.category === category);
            const stat = installed ? statLine(def, installed.key) : null;

            return (
              <div key={category} style={{ borderTop: `1px solid ${color.border}`, padding: 12 }}>
                <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', gap: 10 }}>
                  <div>
                    <div style={{ fontFamily: font.display, fontSize: 13, fontWeight: 600 }}>
                      {def.label}
                      {def.required ? '' : <span style={{ color: color.textDim, fontSize: 11 }}> (optional)</span>}
                    </div>
                    <div style={{ fontFamily: font.mono, fontSize: 11, color: installed ? color.good : color.textDim }}>
                      {installed ? `${def.tiers[installed.key]?.label ?? installed.key}${stat ? ` -- ${stat}` : ''}` : 'Empty slot'}
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 8 }}>
                    {installed ? (
                      <button style={button} disabled={busy} onClick={() => remove(category)}>
                        Remove
                      </button>
                    ) : owned.length === 0 ? (
                      <span style={{ fontFamily: font.mono, fontSize: 10, color: color.textDim }}>No part in inventory</span>
                    ) : (
                      <button style={buttonPrimary} disabled={busy} onClick={() => setPickerCategory(pickerCategory === category ? null : category)}>
                        Install
                      </button>
                    )}
                  </div>
                </div>

                {pickerCategory === category && !installed && (
                  <div style={{ marginTop: 10, display: 'flex', flexDirection: 'column', gap: 6 }}>
                    {owned.map((c) => (
                      <button key={c.key} style={button} disabled={busy} onClick={() => beginInstall(category, c.key)}>
                        {c.label} ×{c.count} — start install
                      </button>
                    ))}
                  </div>
                )}
              </div>
            );
          })}
        </div>
        {message && (
          <div style={{ padding: '0 12px 12px', fontFamily: font.mono, fontSize: 11, color: color.textMuted }}>{message}</div>
        )}
      </div>

      {attempt && (
        <MinigameOverlay request={{ requestId: 0, kind: attempt.kind, difficulty: attempt.difficulty }} onResult={onMinigameResult} />
      )}
    </div>
  );
}
