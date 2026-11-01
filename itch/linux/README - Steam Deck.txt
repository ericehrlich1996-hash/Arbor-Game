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

STEP 1 - Download the itch app

   a. In Desktop Mode, open a web browser. Firefox or Chrome both work.
      If you don't have one, open "Discover" (the blue shopping-bag
      icon in the taskbar), search "Firefox" and install it.
   b. Go to  itch.io/app  and click the download button. Make sure it
      says Linux. The file you get is called "itch-setup" (no ending).

STEP 2 - Install the itch app

   a. Open Dolphin, the file manager (the blue folder icon in the
      taskbar). Click "Downloads" in the left-hand list.
   b. Right-click "itch-setup" > Properties > the "Permissions" tab >
      tick "Is executable" > OK.
      (Linux won't run a downloaded program until you tick this box.)
   c. Double-click "itch-setup". A small window downloads and installs
      the app, then the itch app opens on its own.
   d. Log in with your itch.io account, or make a free one.

   Next time, you'll find the itch app in the Application Launcher
   (the Steam Deck logo at the bottom-left). Just search "itch".

STEP 3 - Install Arbor Simulator

   a. In the itch app, click the search bar at the top and type
      arborsim  (or go to  fizzehbuboleh.itch.io/arborsim ).
   b. Open the game's page and click "Install".
   c. If it asks which file you want, pick the Linux one
      (it has a penguin icon or says "linux").
   d. If it asks where to install, keep the default. The game goes to
        /home/deck/.config/itch/apps/
      (".config" is a hidden folder. You'll need that in step 4.)
   e. Wait for it to finish. The button changes to "Launch".
      You can press Launch to test it right there in Desktop Mode.

STEP 4 - Add it to Steam

   Follow "ADDING THE GAME TO STEAM" below. The game's folder is inside
   /home/deck/.config/itch/apps/


Updates: the itch app only updates games while it's open. Every so
often, switch to Desktop Mode and open the itch app. It downloads the
newest build on its own (you'll see a progress bar). The Steam shortcut
keeps working after an update, so you don't need to add the game again.


-------------------------------------------------------------
OPTION B - Download it directly
-------------------------------------------------------------

STEP 1 - Download the game

   a. In Desktop Mode, open a web browser and go to
        fizzehbuboleh.itch.io/arborsim
   b. Scroll down to the downloads and click "Download" on the Linux
      one (penguin icon). You get a .zip file in your Downloads folder.

STEP 2 - Unzip it and give it a home

   a. Open Dolphin (the blue folder icon) > "Downloads".
   b. Right-click the .zip > Extract > "Extract archive here,
      autodetect subfolder". You get a new folder next to the zip.
   c. Make a permanent spot for it: click "Home" in the left-hand list,
      right-click an empty area > Create New > Folder, and name it Games.
   d. Go back to Downloads. Drag the new game folder onto "Games", or
      right-click it > Cut, open Games, right-click > Paste.
      It ends up at  /home/deck/Games/<the game folder>
      (Don't leave it in Downloads. It's easy to delete by accident.)

STEP 3 - Make it runnable

   a. Open the game folder. You'll see:
        ArborSimulator.x86_64     <- the game itself
        ArborSimulator.pck        <- the game's data (must stay here)
        README - Steam Deck.txt   <- this file
   b. Right-click  ArborSimulator.x86_64  > Properties > the
      "Permissions" tab > tick "Is executable" > OK.
      (Zip files lose this setting, so the game won't start without it.)
   c. To test it, double-click ArborSimulator.x86_64. The game should
      open. Quit it before going on.

STEP 4 - Add it to Steam

   Follow "ADDING THE GAME TO STEAM" below. The game's folder is
   /home/deck/Games/<the game folder>

To update: download the new zip, extract it, and copy its files over the
old ones in the same folder (say yes to "Overwrite"). Then tick
"Is executable" again. The Steam shortcut keeps working.


-------------------------------------------------------------
ADDING THE GAME TO STEAM (both options)
-------------------------------------------------------------

Do this once, so the game shows up in Gaming Mode like any other game.

The easy way:

   a. In Dolphin, go to the game's folder.
      For the itch app: click "Home", then press Ctrl+H (or the menu
      button at the top-right > "Show Hidden Files") so the hidden
      ".config" folder appears. Open .config > itch > apps > the
      Arbor Simulator folder.
   b. Right-click  ArborSimulator.x86_64  > "Add to Steam".
      That's it. Skip to "Finishing up".

If "Add to Steam" isn't in the right-click menu:

   a. Open Steam (in Desktop Mode it's on the taskbar or the desktop).
   b. Click the "Games" menu at the very top > "Add a Non-Steam Game to
      My Library...". A list of programs appears.
   c. Click "Browse..." at the bottom.
   d. Change the "File type" box at the bottom to "All Files". If you
      skip this, the game file won't show up in the list.
   e. Go to the game's folder. For the itch app's hidden folder, type
        /home/deck/.config/itch/apps/
      straight into the path box at the top and press Enter.
   f. Select  ArborSimulator.x86_64  > "Open". Back in the list, make
      sure its box is ticked > "Add Selected Programs".

Finishing up (recommended):

   a. In Steam, find "ArborSimulator.x86_64" in your Library.
      Right-click it > Properties.
   b. Change the name at the top to  Arbor Simulator
   c. Click "Compatibility" on the left. Make sure "Force the use of a
      specific Steam Play compatibility tool" is OFF. This is a native
      Linux game, and Proton would stop it from running.
   d. Close the window. Double-click "Return to Gaming Mode" on the
      desktop.

Playing it:

   In Gaming Mode, press the Steam button > Library. Press R1 to move
   across the tabs to "Non-Steam". Arbor Simulator is there. Press Play.
   (It doesn't have cover art. That's normal for non-Steam games.)


-------------------------------------------------------------
CONTROLS
-------------------------------------------------------------

The game reads the Deck as an Xbox-style controller. If the buttons act
like a keyboard and mouse instead:
   Start the game > press the Steam button > Controller Settings >
   click the current layout's name > Templates > "Gamepad" > Apply.

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
