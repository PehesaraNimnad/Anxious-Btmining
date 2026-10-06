export interface RigSlotGpu {
  tier: string;
  durability: number;
}

export type RigSlotValue = RigSlotGpu | false;

export interface RigStatus {
  damaged?: boolean;
  onFire?: boolean;
  seized?: boolean;
}

export interface Rig {
  id: number;
  rig_model: string;
  maxSlots: number;
  chassisLabel?: string; // e.g. "Desktop PC" -- shown in the dashboard header
  minGpuRank?: number; // GPU-rank window this chassis accepts (1-20)
  maxGpuRank?: number;
  coords: { x: number; y: number; z: number };
  heading: number;
  slots: RigSlotValue[];
  heat: number;
  power_state: boolean;
  banked_micro_btc: number;
  uptime_seconds: number;
  status: RigStatus;
  xp: number;
  level: number;
  isOwner: boolean; // false for a shared-access viewer -- gates the Access tab
  // Assembly state. `components` is undefined for a legacy (grandfathered) rig
  // placed before the assembly system; otherwise a map of category -> slot.
  components?: Record<string, ComponentSlotValue>;
  assembled: boolean; // all required components present (true for legacy rigs)
  missingComponents: string[]; // required categories still empty
}

export interface AccessEntry {
  citizenid: string;
  name: string;
}

export interface SkillProgress {
  level: number;
  xp: number;
  maxLevel: number;
  currentLevelXp: number;
  nextLevelXp: number;
}

export interface ShopEntry {
  key: string;
  label: string;
  rank: number; // position on the GPU line (1-20)
  price: number;
  requiredLevel: number;
  hashrate: number;
  powerDraw: number;
  heatPerSecond: number;
  unlocked: boolean; // rig level >= requiredLevel
  fitsChassis: boolean; // rank is inside this chassis's accepted window
}

export interface OwnedGpu {
  inventorySlot: number;
  tier: string;
  label: string;
  durability: number;
}

// --- Build components / assembly ------------------------------------------

export interface ComponentTierDef {
  item: string;
  label: string;
  hashrateBonus?: number;
  efficiency?: number;
  wattage?: number;
  coolingBonus?: number;
}

export interface ComponentCategoryDef {
  label: string;
  required: boolean;
  minigame: 'sequence' | 'pins' | 'latch' | 'cables' | 'sweep';
  tiers: Record<string, ComponentTierDef>;
}

export interface InstalledComponent {
  key: string;
}

export type ComponentSlotValue = InstalledComponent | false;

export interface OwnedComponent {
  category: string;
  key: string;
  label: string;
  item: string;
  count: number;
}

export interface GpuTierConfig {
  item: string;
  label: string;
  rank: number;
  hashrate: number;
  powerDraw: number;
  heatPerSecond: number;
  price: number;
  maxCondition: number;
  requiredLevel: number;
}

export interface RigData {
  rig: Rig;
  skill: SkillProgress;
  shop: ShopEntry[];
  myGpus: OwnedGpu[];
  myComponents: OwnedComponent[];
  access: AccessEntry[]; // [] for a shared-access (non-owner) viewer
  btcPrice: number;
  gpuTiers: Record<string, GpuTierConfig>;
  componentDefs: Record<string, ComponentCategoryDef>;
  componentOrder: string[];
}

export type MinigameKind = 'extinguish' | 'install' | 'hack' | 'sequence' | 'pins' | 'latch' | 'cables';

// "Coolant Purge" (fire) and "Socket Alignment" (GPU install) -- a marker
// sweeps a track, the player strikes when it's inside the target zone.
export interface SweepDifficulty {
  variant: 'linear' | 'radial';
  zoneWidthPct: number; // target zone width, as a % of the full track/circle
  speedMs: number; // time for the marker to sweep the full track one-way
  requiredHits: number;
  maxMisses: number;
  timeLimitMs: number;
}

// "Firewall Breach" (hack) -- a Simon-says sequence-recall grid.
export interface SequenceDifficulty {
  gridSize: number; // perfect square: 9 = 3x3, 16 = 4x4
  length: number;
  showDelayMs: number;
  inputTimeoutMs: number;
  // The sequence is generated SERVER-SIDE and sent down only to be displayed;
  // the player's clicks are echoed back for the server to validate. Optional
  // so the browser-preview path can still self-generate one locally.
  sequence?: number[];
}

// "Pin Align" (CPU) -- a pointer sweeps a ring; lock it while it's inside the
// socket arc.
export interface PinsDifficulty {
  arcDeg: number; // width of the target arc, in degrees
  speedMs: number; // time for the pointer to travel the full ring once
}

// "DIMM Latch" (RAM) -- clip the left then right latch, each as the slider
// passes through its zone.
export interface LatchDifficulty {
  zoneWidthPct: number;
  speedMs: number;
}

// "Power Routing" (PSU) -- match each colored lead to its socket.
export interface CablesDifficulty {
  pairs: number;
}

export type MinigameDifficulty =
  | SweepDifficulty
  | SequenceDifficulty
  | PinsDifficulty
  | LatchDifficulty
  | CablesDifficulty;

export interface MinigameRequest {
  requestId: number;
  kind: MinigameKind;
  difficulty: MinigameDifficulty;
}
