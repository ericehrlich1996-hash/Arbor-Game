# Arbor Simulator

A physics-based tree work game. You start with a chainsaw, a wood chipper and an old square-body truck, and work your way up to bigger jobs, a crew and better equipment.

## Play

Open `index.html` in a browser (Chrome, Edge or Firefox). No install or build step.

| Key | Action |
| --- | --- |
| WASD | walk (Shift to run, Space to jump) |
| Mouse | look (click the view to capture the mouse) |
| E | talk, pick up (several pieces at once), start or feed the chipper, unhitch / walk / rehitch the chipper at its tongue |
| 1 / 2 | hands / chainsaw |
| R | pull-start or stop the saw |
| Right mouse | rev and cut |
| Mouse wheel | roll the saw (turns the cut plane) |
| C | crouch |
| 3 | ear muffs on/off (muffles the saw and chipper) |
| Q | drop one piece (E drops everything) |
| F | kick: shove a log, or snap apart a piece that's nearly cut through |
| G | throw a log off your shoulder (lands in the truck bed when you're near it) |
| T | drag a log that's too heavy to lift but under 200 lb (T or E to let go) |
| E at the tailgate | hop up into the truck bed (E again to hop down) |
| E at the driver door | drive the truck (W/S drive, A/D steer, Space brake, V camera, E get out) |
| H | help |

## Level 1: Earl's dead ash

You pull up the driveway, finish your energy drink and meet Earl, the client. His white ash was killed by emerald ash borer.

1. **Drop it.** Cuts are free-form: wherever the bar enters the wood, at whatever angle you hold the saw, is the cut. How you cut decides where it falls, or whether it barber-chairs.
2. **Limb it** and feed the brush to the chipper. Branches go in butt first, flat along the infeed.
3. **Buck it** into rounds light enough to lift (132 lb max), and pile them up behind the shed. Rounds ride on your shoulder (G throws them, into the truck bed when you are near it); heavier pieces under 200 lb can be dragged with T; wood dropped in the truck bed rides along when you drive.
4. **Get paid.** Clean felling and quick work earn a bonus. A barber chair costs you.

## Code layout

| File | What it does |
| --- | --- |
| `js/engine.js` | math, WebGL2 renderer, mesh builder |
| `js/world.js` | random property: terrain, road, driveway, house, shed, woods, tree placement |
| `js/models.js` | truck (with cab interior), chipper, Earl, chainsaw, hands |
| `js/physics.js` | rigid-body physics for logs and limbs (terrain and body contacts, sleeping, ray casts) |
| `js/tree.js` | the tree: shape, limbs, mass and contact points for every piece |
| `js/drive.js` | driving the truck with the chipper in tow; limbs snapping under a felled stem |
| `js/haul.js` | hitching the chipper, truck bed and chipper as solid shapes, carrying several pieces, sawdust piles |
| `js/saw.js` | the chainsaw: bar in the world, free-form cut planes, open faces, hinge analysis, stump and butt faces, chipper feeding |
| `js/audio.js` | all sounds, synthesized with Web Audio |
| `js/game.js` | the level: intro, player, Earl and dialogue, felling, cutting, chipper, objectives, HUD |

`./build.sh` bundles everything into `dist/arbor-simulator.html`, a single file you can share or upload.

## Deploying

The repo root is a static site. Point Netlify (or GitHub Pages) at this repo with no build command and `/` as the publish directory.
