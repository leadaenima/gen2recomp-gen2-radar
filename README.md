# Encounter Radar

A **RADAR** row in the START menu that lists every wild Pokémon the map you
are standing on can produce, with each one's share of the roll and its level
range.

Gen 2 is the generation this is worth building for. A Johto route does not
have *a* wild table — it has one for morning, one for day, one for night, one
for surfing, and one row list per fishing rod, all keyed off the same tile you
are standing on. The radar pages through every one of them and marks the page
the clock is currently on with **NOW**.

**Persona: the Tool Builder.** Read the merged encounter tables through
`mod.content.encounters`, put a screen on the stack through `mod.ui`, and
change nothing about how the game rolls.

## Try it

Copy this folder to `mods/johto_radar`, then enable **Encounter Radar** in the
in-game mod manager (F10 on desktop; the MODS row in the START menu on a
phone).

- Stand anywhere in the overworld, open START, choose **RADAR**.
- **LEFT / RIGHT** page between GRASS MORN / GRASS DAY / GRASS NITE / SURF /
  OLD ROD / GOOD ROD / SUPER ROD — only the pages the map actually has.
- **B** goes back to the START menu.

Reading a row:

```
GRASS DAY NOW              ◀▶
▶ PIDGEY               30/100
    LV 2-4
  SENTRET              30/100
    LV 3
ROUTE 29
STEP 24/256               2/5
```

`30/100` is the species' share **of an encounter**, summed over every slot it
occupies. `STEP 24/256` is the separate question of whether a step produces an
encounter at all — the raw byte the engine compares a `rand(0,255)` against,
not a rounded percentage. On a rod page that bottom line reads `BITE 64/256`
instead, which is the fishing group's own bite chance.

A Pokéball next to a name means you already own that species. Turn that off
with the **MARK OWNED** option if you would rather not see it.

## What it reads

| Seam | Used for |
|---|---|
| `mod.content.encounters:get` | the map's grass / water tables, including `byTime` |
| `mod.content.pokemon:get` | species display names |
| `mod.content.maps:get` | the map's `fishGroup` when called through the export |
| `mod.world:overworld()` | the live map and the cached time of day |
| `hooks:wrap("ui.start_menu.items")` | the RADAR row, anchored before SAVE |
| `mod.ui.ListMenu` / `mod.ui.push` | the screen and the way back to START |
| `mod.options:define` / `:get` | ENABLED and MARK OWNED |

Fishing data does not live in the encounter record. The map header carries a
`FISHGROUP_*`, `field.fishGroups` carries a bite chance and one row list per
rod, and a row with no species names an index into `field.timeFishGroups` that
resolves to a day or night pair — so the Super Rod page genuinely changes after
dark. That is the same walk `engine/events/fish.asm` does.

## Export

Other mods can read the same table the screen draws:

```lua
local radar = mod.find("johto_radar")
local pages = radar.exports.report("ROUTE_29", "NITE")
-- pages[i] = { title, tod, note, rows = { { species, min, max, weight }, ... } }
```

`weight` is out of 256, not a percentage, because that is the number the roll
actually uses; divide it yourself if you want a percentage.

## Tests

```sh
luajit mods/johto_radar/tests/radar_tests.lua
```

Forty assertions over synthetic tables, covering the bucket-difference
arithmetic, level-range merging, the rod threshold walk, TimeFishGroups
resolution, a rate of zero, and a map with no wild data at all. The suite is
listed in `.modkitignore` so it stays out of the packaged archive.

## Known limits

- Swarms, the Bug Catching Contest and roaming legendaries are not encounter
  tables and do not appear here.
- Headbutt and Rock Smash have no extracted tables on this engine, so they get
  no page.
- Odds are the vanilla slot shares. A mod that hooks `encounter.roll` or
  `encounter.species` to change what actually appears will not be reflected —
  the radar reads the tables, not the roll.

## Credits

- Gen2Recomped — the `encounters` registry, `field.fishGroups`, and the
  `ui.start_menu.items` / `mod.ui` seams.
