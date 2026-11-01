ARBOR SIMULATOR on STEAM DECK
=============================

This is the native Linux version. It runs directly on the Steam Deck,
no Proton needed. It works on any other Linux PC too.

There are two ways to install it. Option A updates itself, so pick that
one if you want to keep up with new test builds.

All of the setup happens in Desktop Mode. To get there: hold the Power
button > Switch to Desktop. To get back afterward, double-click
"Return to Gaming Mode" on the desktop.

Tip: in Desktop Mode, press STEAM + X to bring up the on-screen keyboard.


-------------------------------------------------------------
OPTION A - The itch app (updates automatically)
-------------------------------------------------------------

1. In Desktop Mode, open a web browser and go to  itch.io/app
   Download the Linux version. You get a file called "itch-setup".

2. Open Dolphin (the file manager) > Downloads. Right-click "itch-setup"
   > Properties > Permissions, tick "Is executable", then OK.
   Double-click it to install the itch app.

3. Log in to the itch app, open Arbor Simulator
   (fizzehbuboleh.itch.io/arborsim) and press Install.
   If it asks which download you want, pick the Linux one.

4. Now add the game to Steam so it shows up in Gaming Mode:
   a. Open Steam (in Desktop Mode).
   b. Games menu > "Add a Non-Steam Game to My Library..." > Browse...
   c. Press Ctrl+H to show hidden folders, then go to
        /home/deck/.config/itch/apps/
      open the Arbor Simulator folder and pick  ArborSimulator.x86_64
   d. Click "Add Selected Programs".

5. Go back to Gaming Mode. The game is in your Library under
   "Non-Steam". Press Play.

Updates: the itch app only runs in Desktop Mode. Every so often, open it
there and it downloads the newest build. The Steam shortcut keeps working
after an update.


-------------------------------------------------------------
OPTION B - Download it directly
-------------------------------------------------------------

1. In Desktop Mode, open fizzehbuboleh.itch.io/arborsim in a browser
   and download the Linux version (a .zip).

2. In Dolphin > Downloads, right-click the zip > Extract > Extract
   archive here. Move the folder somewhere permanent, for example
   /home/deck/Games/ArborSimulator

3. Inside that folder, right-click  ArborSimulator.x86_64  > Properties
   > Permissions, tick "Is executable", then OK.
   (Keep ArborSimulator.pck in the same folder. The game needs it.)

4. Add it to Steam, same as step 4 in Option A: Steam > Games >
   "Add a Non-Steam Game to My Library..." > Browse > pick
   ArborSimulator.x86_64 > "Add Selected Programs".

5. Back to Gaming Mode > Library > Non-Steam > Play.

To update: download the new zip and replace the files in the same folder.
The Steam shortcut keeps working.


-------------------------------------------------------------
CONTROLS
-------------------------------------------------------------

The game reads the Deck as an Xbox-style controller. If the buttons act
like a keyboard and mouse instead, press the Steam button, open the
game's controller settings, and pick the "Gamepad" layout.

  Left stick     walk (click it to run) / steer the truck
  Right stick    look
  RT             main action: grab, swing, throw, saw throttle / gas
  LT             second action: rev the saw, set down / reverse
  A              jump (in the truck: brake)
  X              talk, pick up, use, drive
  B              kick (hold: flip past a limb when climbing)
  Y              throw (hold in a tree: let the lowering rope run)
  LB (hold)      tool wheel: point the right stick at a tool, let go
  RB             swap back to your last tool
  D-pad left/right   angle the cut
  D-pad up       ear muffs        D-pad down   drag
  R3             crouch
  View button    stop the saw, hold it for help
  Menu button    pause

In menus: the D-pad or left stick moves, A selects, B goes back.


-------------------------------------------------------------
IF SOMETHING GOES WRONG
-------------------------------------------------------------

- The game won't start (Play flashes and stops):
  * Make sure "Is executable" is ticked (step 2 or 3 above).
  * Make sure Steam is NOT running it through Proton. In your Library:
    the game > gear icon > Properties > Compatibility. "Force the use of
    a specific Steam Play compatibility tool" must be OFF. This is a
    native Linux game.
  * Make sure ArborSimulator.pck is next to ArborSimulator.x86_64.

- The controls act like a mouse: see CONTROLS above (pick "Gamepad").

- Crew play (co-op): works on the Deck like on a PC. On the same Wi-Fi,
  just call the host's number on the cabin phone.

This is a test build. If something breaks, tell the developer what you
were doing and which build it is (it shows on the pause menu).
