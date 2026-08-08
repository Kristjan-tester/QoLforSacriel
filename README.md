Make life better for playing Project Zomboid.

Link to steam workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3774739161

Current version: v0.8 

- Why we are doing this?
	- These mods are designed increase Quality of Life by removing unnecessary steps from player actions so they can maintain situational awareness in the game.
	- None of these mods affect difficulty of the game.

- Overall design idea: 
	- Minimal changes to keep game as close to original as possible.
	- All modules can be toggled on/off from modoptions on the fly. And fine-tuned where appropriate. 
	- Made for single-player. Not tested in multiplayer.
 
Features:
- Character Audio Rings - shows radius where the sounds travels when made. Important:
    - Zombies can hear sounds outside of that range (depending on their hearing: 0.45x ; 1x; 3x range)
    - Game does not generate sounds that one would expect - opening doors, for example - testing all of them is tricky, let me know when you see inconsistencies. 
    - Footsteps only make sound with probability for example, and crouch walking and running is same loudness (probably bug in vanilla). 
    - Currently limited to direct player sounds, so using microwave for example wouldn't generate a ring. Hitting a door with a weapon would.
  
- Audio direction visualiser (default off), Customisable categories for sounds groups to track, fps drop fixed.
- Filter skills list to hide 0xp skills
- Rest until sleepy, speeds up time until player can sleep again (ignores panic or pain limits to sleep)
- Dragging corpses exhaustion rate ramps up from 35% to vanilla over time (120 sec)
- Armour presets (1..8, default 2) with custom key-binds (default: ctrl+F1..8) and 'add all current armour/weapons' function:
    - Any item can be added manually to preset.
    - Remembers held weapons hand preference, and armour slots
    - No new visuals for hotbar - all is handled via right-click context menu at the moment
- Armour discomfort reduction (95%) when not doing complex actions (running, climbing or building stuff, etc.)
- Find deeper natural water sources in foraging mode (choose target 'water')
- Nudge furniture by 1 tile, can nudge multi-tile items and ignore tool/skill requirements:
    - Items have to be removed from containers before nudge. 
- Nearby light switch toggle with key-bind (default: ctrl+f) should help out when looking for obscured switches in the dark
    - range, default 1 tile radius, customisable
- Heavy load pain reaction means character cries out in pain when over-encumbered so that it causes loss of health.
    - Sound made only for player notification (zombies don't react).
- Detailed stats in crafting menu 
    - All weapon stats visible in crafting menu and inventory tooltip 
    - XP gain in crafting menu (depending on your skills, traits and books)
- Handcrafting menu extended with tool selection submenus
    - Populates the context menu with all available tools for that craft, respects 'don't use for crafting' flags
- "Take all rotten" and "take all stale" from container (right-click in that container)
- Extended EAT menu to have 'eat all stack' and 'eat until not hungry'
    - "Eat all stack" stops when 'stuffed'
    - "Eat until not hungry" stops when player is not hungry but that doesn't mean player can't eat more.  
- Dropping painfully heavy crafting results so player wouldn't take too much damage.
    - Sawing logs for example
    - Doesn't conflict with auto-mechanics




- Steam page does not have enough space to explain all the features, thus this page:
