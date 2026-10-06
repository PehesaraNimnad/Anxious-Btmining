# Project 7H — Roadmap & Spec Mapping

This document maps the **Project 7H Advanced Crypto Infrastructure** spec onto the
current `anxious_btcmining` codebase: what already exists, what this security pass
added, and what remains — in the spec's own recommended phase order (spec §66).

The full spec describes a premium-scale data-centre simulation (DUI world screens,
facilities, racks, generators/UPS, network sim, full admin NUI, multi-framework
bridges). It is a multi-phase build. This repo is **server-authoritative today** and
the work below extends that spine rather than replacing it.

---

## Legend

- ✅ **Done** — implemented and working in this repo
- 🟡 **Partial** — a working subset exists; spec asks for more
- ⬜ **Planned** — not yet built

---

## What this pass added (security + police + logging)

The user's three explicit priorities — *server-side validation / no client trust*,
*security*, and *police raid* — were implemented end to end:

| Area | Files | Notes |
|---|---|---|
| ✅ Anti-exploit guards | `server/security.lua` | Distance + rate-limit + input-type validation on **every** sensitive callback; structural violations are flagged, logged, optionally auto-kicked. |
| ✅ Police / dispatch raid | `server/dispatch.lua`, `client/dispatch.lua` | Framework-agnostic bridge: `ps-dispatch`, `cd_dispatch`, `qs-dispatch`, `core_dispatch`, `linden_outlawalert`, `standalone`, `custom`. Alerts on hack start/fail/success, GPU theft, unauthorised access. Min-cops-online gate; hardened rigs raise alerts more often. |
| ✅ Discord logging | `server/logs.lua` | Per-category webhook logs (mining/hardware/theft/access/admin/exploit), input sanitised against mention/markdown injection. |
| ✅ Buy-GPU money safety | `server/skill.lua` | Charge-then-grant with refund on inventory-full, closing a "force inventory full to keep an unpaid GPU" edge. |
| ✅ Config | `config.lua` | New `Config.Security`, `Config.Dispatch`, `Config.Logs` blocks, fully commented. |

All validation is **server-side**. The client only ever *requests* an action; the
server derives position, rate, ownership, price and result from its own state.

---

## Spec section coverage

### Already server-authoritative (spec §25, §29, §34, §57, §62–65)
- ✅ Mining reward calculated server-side per tick — `server/rig_state.lua`
- ✅ BTC market is server-controlled via `GlobalState` — `server/btc_market.lua`
- ✅ Ownership + shared access, server-checked — `server/access.lua`, `HasRigAccess`
- ✅ "Is player near device / owns item / slot free" checks — `server/security.lua` + callbacks
- ✅ Persistence across restart — `mining_rigs` table, dirty-flag flush (`server/rig_state.lua`)
- ✅ Anti-exploit model: *client requests → server validates → server computes → DB → broadcast*

### Physical device & world (spec §6–10, §33–37, §59–61)
- 🟡 Placeable rig props, distance stream in/out, ox_target interaction — `client/placement.lua`, `client/rig_props.lua`, `client/target.lua`
- 🟡 Real-time shared device state (heat/fire/power broadcast to nearby players) — `BroadcastRigSummaries`
- 🟡 Configurable machine **classes** — four chassis classes (Desktop PC / Mining Rig / Server Rack / Data Center Node) in `Config.RigModels`, each with its own slot count, cooling capacity, and a **min/max GPU-rank window** enforced server-side (`GpuFitsChassis`). ASIC class still ⬜ (needs a separate ASIC-item path, not GPU slots).
- ⬜ Facilities / racks / multi-device grouping (§32, §33, §59)
- ⬜ Device status LEDs, physical cable connections (§35, §36)

### DUI world-screen (spec §2–5, §38, §46–49, §67)
- ⬜ DUI runtime-texture monitor screens — **today the UI is fullscreen NUI** (`web/`)
- ⬜ `/devicecalibrate` screen calibration (§8)
- ⬜ Shared screen state on the physical prop (§4, §37)
- The existing React UI (`web/src/`) is a strong base to render *into* a DUI texture.

### Mining & economy (spec §25–31, §50–52)
- ✅ Hashrate/difficulty-style tiers, server rewards, wallet-as-item, sell at live price
- 🟡 Wallet (item-based BTC + per-rig accrual buffer) — spec wants a richer wallet ledger
- ⬜ Player-to-player BTC transfers (§31)
- ⬜ Profitability engine / analytics dashboard (§51, §52)

### Infrastructure (spec §11–24)
- 🟡 Power: billing mode + auto-shutdown + generator capacity — `Config.PowerMode`, `server/rig_state.lua`
- 🟡 Heat/cooling simulation + fire — `server/rig_state.lua`, `server/fire.lua`
- 🟡 Hardware health/degradation (GPU durability from heat) — `server/rig_state.lua`
- ⬜ Electricity **meter + bills + grace period + disconnection** (§13–16)
- ⬜ Generator fuel/health, UPS (§17, §18)
- ⬜ Cooling **upgrade tiers** + maintenance items/time (§20, §22)
- ⬜ Network contract / bandwidth / network bills (§23, §24)

### Security & gameplay (spec §38–43)
- ✅ Theft: "Firewall Breach" hacking minigame, cooldowns, daily caps — `server/theft.lua`, `web/src/components/minigames/`
- ✅ **Police dispatch on break-ins** (this pass) — `server/dispatch.lua`
- ✅ **Discord logs** (this pass) — `server/logs.lua`
- 🟡 Permissions: Owner + shared access — spec wants Owner/Admin/Technician/Viewer roles (§38)
- ⬜ Terminal security: PIN / keycard / password (§39)  *(config hook `unauthorizedAccess` alert is ready for it)*
- ⬜ Full robbery actions (steal server/ASIC, destroy hardware, disable power/network) (§41)
- 🟡 Admin commands (`/btcgive`, `/btcfire`, `/btcrigs`, ACE-gated, now logged) — spec wants a full admin NUI panel (§42)

### Framework & integration (spec §53–56)
- 🟡 Hard dependency on qbx_core / ox_* today
- ⬜ Bridge layer for QBCore / ESX / Standalone, inventory/target/notify/dispatch (§55)
- ✅ Dispatch bridge is already provider-abstracted (this pass) — a template for the others

---

## Suggested next phases

Following spec §66, and building on what's now in place:

1. **Electricity billing** (§13–16) — new `crypto_electricity_bills` table, a billing
   tick on top of the existing power loop, grace period, and a disconnection state that
   reuses the existing `power_state` + `status` broadcast. Pay via bank/cash/crypto.
2. **Machine classes & facilities** (§6, §32, §33) — generalise `Config.RigModels` into
   typed classes; add a facility grouping so racks/devices roll up to one dashboard.
3. **DUI world screens** (§2–8) — render the existing React UI into a runtime texture on
   the prop; add `/devicecalibrate`. Biggest visual lift.
4. **Framework bridges** (§55) — extract qbx/ox calls behind `bridge/` modules mirroring
   the dispatch bridge pattern already shipped.
5. **Robbery + terminal security + role permissions** (§38–41) — extend the theft and
   access systems already in place.
6. **Admin NUI + economy controls** (§42) — graduate the `/btc*` commands into a panel.

Each phase is additive and keeps the server-authoritative contract intact.
