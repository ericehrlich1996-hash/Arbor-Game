# Arbor Simulator

A physics-based tree work game. You start with a chainsaw, a wood chipper and an old square-body truck, and work your way up to bigger jobs, a crew and better equipment.

## Play

Open `index.html` in a browser (Chrome, Edge or Firefox). No install or build step.

| Key | Action |
| --- | --- |
| WASD | walk (Shift to run, Space to jump) |
| Mouse | look (click the view to capture the mouse) |
| E | talk, pick up, start the chipper, feed the chipper |
| 1 / 2 | hands / chainsaw |
| R | pull-start or stop the saw |
| Left mouse | rev and cut |
| Q | drop what you carry |
| H | help |

## Level 1: Earl's dead ash

You pull up the driveway, finish your energy drink and meet Earl, the client. His white ash was killed by emerald ash borer.

1. **Fell it.** Cut the notch on the side you want it to fall, about a third of the way through. Then back-cut from the other side, slightly higher, until about 10% of the diameter is left as the hinge. Get clear.
2. **Limb it.** Cut the branches off where they meet the stem, and feed them to the chipper.
3. **Buck it.** Cut the stem into rounds light enough to lift (60 kg max), and stack them on the pallet by the shed.
4. **Get paid.** You earn bonuses for a textbook notch and hinge and for quick work. A barber chair costs you.

## Code layout

| File | What it does |
| --- | --- |
| `js/engine.js` | math, WebGL2 renderer, mesh builder |
| `js/world.js` | random property: terrain, road, driveway, house, shed, woods, tree placement |
| `js/models.js` | truck (with cab interior), chipper, Earl, chainsaw, hands |
| `js/physics.js` | rigid-body physics for logs and limbs (terrain and body contacts, sleeping, ray casts) |
| `js/tree.js` | the tree: shape, limbs, cut geometry, mass and contact points for every piece |
| `js/audio.js` | all sounds, synthesized with Web Audio |
| `js/game.js` | the level: intro, player, Earl and dialogue, felling, cutting, chipper, objectives, HUD |

`./build.sh` bundles everything into `dist/arbor-simulator.html`, a single file you can share or upload.

## Deploying

The repo root is a static site. Point Netlify (or GitHub Pages) at this repo with no build command and `/` as the publish directory.
