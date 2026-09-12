# Moon Shot

From PICO-8's root configured to the outer `pico` directory:

```text
load moon_shot/moon_shot.p8
run
```

Alternatively, enter `cd moon_shot` first, then `load moon_shot`. Keep all six
`.lua` files beside the cartridge: PICO-8 resolves its includes relative to the
cartridge. See the [PICO-8 manual](https://www.lexaloffle.com/dl/docs/pico-8_manual.html#_INCLUDE).

- Left/right adjusts aim; up/down adjusts throwing power.
- X throws the next moon. Once the inventory is empty, X launches the ship.
- Tap Z to restart the current level (on release). Hold Z for one second to
  return to the main menu, which has eight levels in a 4×2 grid. Release Z
  before pressing it again in the menu to return to the title screen.
- Moons destroy obstacles on impact. Destroying the ship or goal, or sending
  the ship offscreen, restarts the current level after the explosion.
- Landing on the green goal advances to the next level. Level 8 returns to the
  menu; completing all eight displays the completion message. Progress lasts
  for the current run.

Level names, inventories, default aim and map regions live in `levels.lua`.
Each level uses a separate 16×16 region at map row 16. Place sprite 16 for the
ship, 17 for the goal and 18 for an obstacle. The map scanner dispatches by
sprite ID and its gameplay adapters convert map tiles to centered pixel positions.

Starter sprites: ship 16, goal 17, moon 18, gravity 5 and 9 (32×32 frames), explosion 32–35,
inventory/menu frames 48–49, background/wipe tiles 50–52, and level numbers 64–71.

New placeholder objects use these map markers:

| Object | Sprite / animation frames | Behavior |
| --- | --- | --- |
| Black hole | 80 | Fixed attraction field; destroys incoming ships/moons and survives impacts. |
| Repulsor planet | 81 | Fixed repulsion field; its solid core can be destroyed. |
| Red nebula | 128–129 (place 128; row reserved through 143) | Destroys ships; moons pass through. |
| Blue nebula | 144–145 (place 144; row reserved through 159) | Destroys ordinary/repulsor planets; ships and the goal pass through. |
| Purple nebula | 160–161 (place 160; row reserved through 175) | Destroys ships, planets and the goal. |

Nebulae persist after contact. Their collider `filter` receives the other
entity's tag; both colliders must accept a contact. Repulsors use orange
32×32 ring frames at 72 and 76. Nebula animations have their own rows in the
lower half of the sprite sheet, with room for 16 frames per color. Draw extra
8×8 frames to the right and increase the corresponding `Id_red_nebula_frames`,
`Id_blue_nebula_frames` or `Id_purple_nebula_frames` field in `game_systems.lua`.
Keep map markers on the first frame. The lower sprite-sheet half shares memory
with map rows 32–63; leave those map rows unused. All eight levels use map rows
16–31, so their data does not overlap these animation rows.

Levels 2–4 introduce red, blue and purple nebulae. Level 5 introduces repulsion,
level 6 introduces black holes, level 7 mixes nebulae, and level 8 combines the
objects. Each has an on-screen hint. In levels 2 and 4, throw the moon right,
then aim the ship toward the raised goal; blue clouds let the ship pass in
levels 3, 7 and 8. The paired fields in levels 5, 6 and 8 leave a route between
them. Default ship aim is set per level, and starting power respects the
configured minimum and maximum.

Run the regression checks from the outer `pico` directory:

```sh
lua moon_shot/tests/gameplay_test.lua
```

The tests load the actual cartridge includes and artwork/map data, and exercise
all eight levels, collisions, ownership, timers, animation and transitions.
They mock PICO-8 input/drawing and use standard Lua numbers, so native rendering
and PICO-8 fixed-point behavior still need a check in PICO-8.
