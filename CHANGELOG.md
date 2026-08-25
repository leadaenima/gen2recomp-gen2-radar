# Changelog

All notable changes to this mod are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the version
numbers match `manifest.version`.

## [1.0.0]

### Added

- A **RADAR** row in the START menu, anchored before SAVE, opening a paged
  read-out of the current map's wild encounter tables.
- Separate pages for morning, day and night grass, read from the Gen 2
  `byTime` slot sets; the page matching the clock opens first and is titled
  **NOW**.
- A **SURF** page from the map's water table.
- One page per fishing rod, walked out of `field.fishGroups` with
  `field.timeFishGroups` rows resolved against the current time of day.
- Per-species odds summed across slots, level ranges collapsed to a span, and
  an owned marker read from the Pokédex.
- Options: **ENABLED** and **MARK OWNED**.
- `mod.exports.report(mapId, tod, mapDef)` publishing the same page table the
  screen draws.
