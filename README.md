# Arbor Simulator

A physics arborist game, built with **Godot 4.7**. You start with a chainsaw, a wood chipper and an '80s square-body truck, and work your way up to bigger jobs.

**Level 1 · Earl's dead ash.** Drive up a randomly generated property, finish your energy drink, and meet Earl. Drop his dead ash without hitting the house, limb it, chip the brush, buck the stem into rounds he can lift, and pile them behind his shed. Then get paid (mostly in twenties).

**Home.** A beat-down log cabin in the woods is the main menu. Pick jobs and buy upgrades on the old computer in the corner.

**Level 2 · Widow Hale's leaning maple.** Unlocks after your first job. Walter's dead sugar maple leans hard at Mrs. Hale's garage, and it has to go the other way, out across the lawn. A heavy leaner sits back on its hinge, so you have to tip it toward your notch:
- **Felling wedges + sledge** ($60): tap wedges into the back cut behind the bar. Each tight wedge lifts the tree a little.
- **Bull rope** ($120): tie it high on the trunk, hook it on the truck's hitch, and ease the truck away until it's bar-tight. Pull too hard and it snaps.

Drop it on the garage and the roof caves in, and the damage comes out of your pay. You need to buy the wedges before Mrs. Hale's job opens up.

**Level 3 · Gus's dock logs.** Unlocks after two jobs (bring the bull rope). Old log-drive timber is floating in the waist-deep shallows where Gus wants his dock. Wade out, tie the rope round a log, hook it to the truck, and drive up the lawn to drag it onto the beach. Then buck the logs and load the rounds in your trailer. Gus pays in cash and his old spinning rod.

**Walter's trailer.** The rounds go in Mrs. Hale's long utility trailer, tarped over the top. Back the truck up to its tongue and press E to hitch it (the load comes along), and walk the chipper's tongue to the ball on the trailer's back bumper to tow both: truck, trailer, chipper.

## Play it

- **In the browser:** the web build lives at the root of this repo (`index.html`, `index.wasm`, …), so the Netlify site serves it as-is. There is no build step, and the publish directory is the repo root.
- **In Godot:**
  1. Install Godot 4.7 (the standard build, not .NET).
  2. Choose **Import** and pick `godot/project.godot`.
  3. Press **F5** to play.

## Controls

| Key | Action |
| --- | --- |
| WASD | walk (Shift runs, Space jumps, C crouches) |
| Mouse | look (click the game to capture the mouse, Esc to release it) |
| E | talk, pick up (several pieces at once), use, drive, hitch/unhitch, hop in the truck bed |
| 1 / 2 / 3 | hands / chainsaw / ear muffs |
| 4 / 5 | felling wedges / pull rope (once bought); left click to set or drive a wedge, tie or hook the rope |
| U | unstick the truck: lifts it onto its wheels at the nearest clear spot (whatever's hitched comes along) |
| R | pull-start or stop the saw |
| Right mouse | rev and cut |
| Mouse wheel | roll the saw (turns the cut plane) |
| Q | drop one piece (E drops everything) |
| G | throw a piece (it lands in the truck bed when you're near the bed) |
| T | drag a piece that's too heavy to lift but under 200 lb |
| F | kick: shove a piece, or snap one that's nearly cut through |
| In the truck | W/S drive, A/D steer, Space brakes, V switches the camera, E gets out |
| H | help |

## How it works

- **Cutting is real geometry.** Each piece of wood is a solid (Godot CSG).
  - A cut in progress subtracts a saw-kerf-thin slab from it.
  - A finished cut splits the piece into two solids, with faces at whatever angle you held the bar.
  - Notches are real wedges, and the wedge pops out.
- **Felling.** The standing tree tracks which fibre columns are still holding. From that it decides between:
  - a hinge (open-face notch plus back cut),
  - a straight drop,
  - a barber chair (no notch, a heavy lean, and a deep cut from one side).

  The stem pivots on the hinge, then falls under the physics engine, which is Jolt. Limbs that get driven into the ground snap off.
- **Vehicles.**
  - The truck is a `VehicleBody3D`. The cab and bed are solid, so wood rides in the bed and you can stand in it.
  - The chipper hangs off the hitch ball with a pin joint.
  - The rear-view mirror is a second camera rendered into the glass.

## Project layout

| Path | What it is |
| --- | --- |
| `godot/project.godot` | the Godot project |
| `godot/scripts/game.gd` | the level: intro, input, interaction, dialogue, objectives, payday |
| `godot/scripts/world_gen.gd` | random property: terrain, road, driveway, house, shed, woodpile spot, woods |
| `godot/scripts/models.gd`, `mesh_builder.gd` | every model, built in code (truck, chipper, Earl, saw, hands) |
| `godot/scripts/truck.gd`, `chipper.gd` | the truck and the towed chipper |
| `godot/scripts/wood.gd`, `wood_piece.gd`, `lumber.gd` | tree shape, solid wood pieces and their cuts, splitting |
| `godot/scripts/ash_tree.gd` | the standing tree, felling analysis, the fall, the stump |
| `godot/scripts/saw.gd` | the chainsaw: pose, bar contact, cutting, hands, sawdust |
| `godot/scripts/haul.gd` | carrying, throwing, dragging, kicking, feeding the chipper |
| `godot/scripts/sfx.gd` | all sounds, synthesized at startup; ear muffs |
| `godot/scripts/tests.gd` | scripted playthroughs: `godot --path godot -- --test=job` |
| `godot/export_web.sh` | exports the web build and copies it to the repo root |
| `legacy/` | the earlier hand-written WebGL version |
