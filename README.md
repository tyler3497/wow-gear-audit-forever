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
- **Gear stats overview (top of the detail window):** each player's
  detail window opens with the stats their equipped gear provides,
  summed across all slots — Strength, Stamina, Attack Power, Spell
  Power, Healing Power, Crit, Haste, and anything else on the gear.
  One honest limit, stated in the window itself: the totals are the
  items' **base stats** (from GetItemStats), because no API exposes
  the gemmed and enchanted totals, so enchant and gem bonuses are
  not included in these numbers.
- **Active set bonuses (top of the detail window, under the stats):**
  each worn set shows its name and piece count (e.g. "Dreadmist
  Raiment (2/8)"), followed by the bonuses whose piece threshold is
  actually met. Sets with no bonus met yet still show their count,
  so progress toward the next bonus is visible. Detection reads the
  set header and "(N) Set:" lines from item tooltips and compares
  the threshold to the worn count, so it never guesses from colors
  or names.

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

1.1.0 — gear-stats overview and active set bonuses at the top of the
detail window, plus the 1.0.0 Forever port of retail Gear Audit v1.5.0.
