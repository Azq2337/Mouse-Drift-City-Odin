# Mouse Drift City

A small portrait-window arcade street-racing prototype built with **Odin + raylib + Box3D**. Everything is procedural and the repository contains no external art assets.

## Toolchain

Test target used during development:

- Odin `dev-2026-07a` / commit `819fdc7`
- `vendor:raylib` 6.0
- `vendor:box3d`

## Run

Windows:

```bat
script\run.bat
```

Linux development run:

```bash
./script/run.sh
```

Release builds:

```bash
./script/build.sh
```

On Windows, `script\build.bat` builds a GUI-subsystem `.exe`, so double-clicking the game does not open a console window. On Linux, the build script also creates `build/mouse-drift-city.desktop` with `Terminal=false`; launch that entry (or the ELF directly) for a terminal-free start.

Directly with Odin:

```bash
odin run src/main -debug
```

## Controls

Driving is intentionally mouse-only:

- automatic throttle
- **LMB**: nitro
- **RMB**: brake / initiate drift; keep holding after stopping to reverse
- move mouse left/right: steer
- **MMB**: pause / resume
- pause menu **RECOVER**: return the car to the last passed gate (or the start before gate 1) without resetting race progress/time

The main menu lets you regenerate the procedural map, choose the car body and color, enable any combination of 20 visual parts, tune race gate count / route length, and cycle the window between **1.0x / 1.5x / 2.0x** UI scale for high-DPI displays.

## Current prototype features

- procedural 11 x 13 road network
- non-repeating race road segments with random valid starts
- two curved coastal edges with bays, broad drivable sand, sand-colored beach route segments, and a resort-building band behind the beach; only the waterline is physically blocked
- winding river topology with normal and jump bridges, low masonry embankments, and uncluttered bridge openings
- Tokyo-style downtown plus Chinatown district
- residential, industrial, resort and park districts
- Mt. Fuji-inspired landmark, shrine-road torii and cherry trees
- destructible Box3D trees and streetlights activated near the player
- rotating panoramic night sky, distant skyline and illuminated buildings
- live minimap progression: passed gates disappear, the next gate is strongly highlighted, and the player is a heading arrow
- 20 car body styles, 20 colors and 20 mix-and-match cosmetic parts

Default race setup is **10 turn gates / about 600 m**. Route-length buttons change distance in 96 m increments (four 24 m city blocks), while changing the gate count scales the current route distance proportionally.

## Source layout

- `src/main/main.odin` - application state, menus and game loop
- `src/main/car.odin` - arcade car handling and procedural car rendering
- `src/main/city.odin` - procedural city, coast, river, buildings, roads and route generation
- `src/main/props.odin` - destructible streetlights and vegetation
- `src/main/race.odin` - checkpoint/race state
- `src/main/hud.odin` - HUD, minimap and menu UI
- `src/main/config.odin` - main constants and tuning values
- `src/main/math_helpers.odin` - shared math helpers

## Status

This is a compact gameplay prototype rather than a finished racing game. The physics are deliberately arcade-oriented: Box3D handles collision, gravity, props and airborne motion, while the car controller prioritizes predictable mouse steering over a full suspension/tire simulation.


### Water and park roads

- River and sea water are not touch-death surfaces. The car is recovered only after its full footprint has fallen into water and settled low enough to count as submerged.
- `RECOVER` and automatic water recovery return to the most recently passed gate (or the start before gate 1).
- The mountain-side river entrance gets a guaranteed normal bridge. On the beach side, the true outer road gets a bridge whenever the generated shoreline leaves that road intact; deep bays fall back to the nearest valid inland crossing.
- Roads enclosed by park blocks use a park-road surface instead of normal city asphalt, including junctions surrounded by four park blocks.
