# Gear Audit Forever

Party and raid gear overview for **WoW Forever** — the same addon as
[Gear Audit](https://github.com/tyler3497/wow-gear-audit) (retail), built
for the Forever client.

## Install

Copy the `GearAudit` folder into your Forever client's AddOns folder:

```
World of Warcraft\_forever_\Interface\AddOns\GearAudit
```

Then tick **Gear Audit Forever** in the AddOns list at character select.
(The Forever beta used `_classic_beta_`; the live client uses `_forever_`.)

## What it does

- `/ga` (also `/gear`, `/gearaudit`) opens the overview, sorted by average
  item level, with click-through detail per player.
- **Refresh** inspects party/raid members one at a time and audits every
  slot: item level, missing enchants, and empty gem sockets.
- **Auto-scan**: joining a party (or a new player joining) queues that
  player for a scan automatically; combat joins wait until combat ends.
- Overview and detail show Class / Spec / Role and, where the game
  provides it, the item upgrade track.

## Forever differences from the retail version

- TOC Interface is **16001** (Forever), not retail's 120105. A retail
  or Classic TOC will not load correctly in Forever, and vice versa.
- The addon folder is still named `GearAudit`, but the saved-variables
  file is `GearAuditForeverDB`, so Forever settings never collide with
  retail's.
- All item, inspect, spec, and tooltip calls are guarded: a Forever API
  that differs from retail degrades to "unknown" or an empty slot
  instead of a Lua error. The code is otherwise identical to retail
  Gear Audit v1.5.0.

## Status

**Untested in-game.** The Forever client launches November 4, 2026, and
no Forever client is available in this environment, so this release is
built from the proven retail code plus the Forever TOC. Enchant, gem,
and upgrade-track columns are best-effort until confirmed in-game:
Forever's exact enchanting, socket, and upgrade systems may differ
from retail's, and any column that proves wrong should be reported
with a screenshot and any Lua error text.

## Version

1.0.0 — first Forever release, ported from retail Gear Audit v1.5.0.
