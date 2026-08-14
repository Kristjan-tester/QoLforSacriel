Make life better for playing Project Zomboid.

Link to steam workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3774739161

Current version: v0.15

- Why we are doing this?
	- These mods are designed increase Quality of Life by removing unnecessary steps from player actions so they can maintain situational awareness in the game.
	- None of these mods affect difficulty of the game.

- Overall design idea: 
	- Minimal changes to keep game as close to original as possible.
	- All modules can be toggled on/off from modoptions on the fly. And fine-tuned where appropriate. 
	- Made for single-player. Not tested in multiplayer.
 
Features:
- (NEW) - 'Add bait' now extends to nearby containers
- (NEW) - 'Wash all' sorts by bloodiest
- (NEW) - 'Put in container' extended for handheld items for all nearby containers 
- Towels take linear amount of water - 1 towel is enough now to dry yourself.
- Improve entering car, character will reorient themselves when close to door
- Fitness tab in Info panel - indicate weight gain in detail, strength training xp, etc.
- Switch off nearby device with keybind (CTRL+G) or context menu option - alarms, TV/Radio:
	- searches nearby 3 radius cells for active items to turn off, walks to them and turns off
 	- priority highest to lowest:
  		- Inventory item alarms
    	- Inventory devices
     	- World alarms
      	- World devices
	- Known limitation : doesn't work for parcels or garbage bags (any container-in-container basically)      	  
- Character Audio Rings - shows radius where the sounds travels when made. Important:
    - Zombies can hear sounds outside of that range (depending on their hearing: 0.45x ; 1x; 3x range)
    - Game does not generate sounds that one would expect - opening doors, using microwave, for example - testing all of them is tricky, let me know when you see inconsistencies. 
    - Footsteps only make sound with probability for example, and crouch walking and running is same loudness (probably bug in vanilla). 
    - UPDATED to include world objects (excluding zombies), though not 100% sure if all animals will make rings.
    - Audio rings with higher radius from same source have priority now, concurrent ring radius labels offset for visibility
	- Ring radius label text size can be set to Small, Medium, or Large in ModOptions.
- Car horn can be honked from outside when door is open or window open/broken. Both radial menu and key-bind
- Audio direction visualiser (default off), Customisable categories for sounds groups to track, fps drop fixed (let me know if you experience it).
	- Loudness scales the size of the arrow 
 	- Distance changes the colour: green is far away, Red is close 
- Filter skills panel, on the fly:
	- highlights recently improved skills with 'green' texts, within last 60 in-game minutes (by default)
	- hover a green skill name to see the observed recent XP gains and their in-game ages
	- filter to hide 0xp skills
	- filter to hide all below 2 levels of skill (by default) - still shows recent skills even if below that limit
- Rest until sleepy, speeds up time until player can sleep:
	- respects going to sleep again limit even if player is tired enough to sleep
	- does not take panic or pain limits into account
- Dragging corpses exhaustion rate ramps up from 35% to vanilla over time (120 sec)
- Armour presets (1..8, default 2) with custom key-binds (default: ctrl+F1..8) and 'add all current armour/weapons' function:
    - Any item can be added manually to preset.
    - Remembers held weapons hand preference, and armour slots
	- Restores saved worn backpacks to their original armour slot when toggled
    - No new visuals for hotbar - all is handled via right-click context menu at the moment
    - can be renamed in modoptions (up to 24 characters shows in context menu)
    - can interact with mannequins
- Armour discomfort reduction (95%) when not doing complex actions (running, climbing, building stuff) or sleeping/resting
	- Respects vanilla discomfort cap (sum of all worn items)
- Find deeper natural water sources in foraging mode (choose target 'water')
- Nudge furniture by 1 tile, can nudge multi-tile items and ignore tool/skill requirements:
    - Items have to be removed from containers before nudge. 
- Nearby light switch toggle with key-bind (default: ctrl+f) should help out when looking for obscured switches in the dark
    - range, default 1 tile radius, customisable
- Heavy load pain reaction means character cries out in pain when over-encumbered so that it causes loss of health.
    - Sound made only for player notification (zombies don't react).
- Detailed stats in tooltips & crafting menu 
    - All weapon stats (and footwear stomping power) visible in crafting menu and inventory tooltip (can be disabled by modoption)
    - All items known stats are shown as numbers (bars are still visible) 
	- XP gain in crafting menu (depending on your skills, traits and books)
 	- Summary added to "protection" panel
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
