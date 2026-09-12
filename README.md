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
- Z returns to the level menu. The menu has eight levels in a 4×2 grid.
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

Run the regression checks from the outer `pico` directory:

```sh
lua moon_shot/tests/gameplay_test.lua
```

The tests load the actual cartridge includes and artwork/map data, and exercise
all eight levels, collisions, ownership, timers, animation and transitions.
They mock PICO-8 input/drawing and use standard Lua numbers, so native rendering
and PICO-8 fixed-point behavior still need a check in PICO-8.
