<p align="center">
  <img src="Media/icon.png" alt="ProfessionsForever" width="128" />
</p>

<h1 align="center">ProfessionsForever</h1>

<p align="center">
  A replacement professions window for <b>WoW: Forever</b> that knows your bags, bank, mail and alts,<br>
  with a crafting queue, a shopping list that follows it, Disenchanting Mode,<br>
  and optional navigation to vendors, trainers and bankers.
</p>

---

## Contents

- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Optional integrations](#optional-integrations)
- [Slash commands](#slash-commands)
- [Settings](#settings)
- [Notes and limits](#notes-and-limits)
- [Development](#development)

## Features

### Overview page (the starting tab)
- A card for every profession you know, including cooking, first aid and fishing, with tier, skill bar and `rank / max`.
- Click a card to open that profession. Right-click to navigate to the nearest trainer of the tier you need.
- Drag a card onto an action bar for direct access to the profession.
- A Blacksmithing, Leatherworking or Engineering card shows your specialization under the profession, with its icon and name.
- The `x` on a primary profession's card unlearns it, through the game's own confirmation.
- The Fishing card has **Bait and Tackle** and **Find Fish** buttons; right-click Bait and Tackle for a waypoint to the nearest Fishing trainer, as on the card.
- The **Character** drop-down shows another of your characters' professions. Click a card to browse its recipes read-only, with materials counted from that character's bags and bank, and queue crafts for it: the characters holding the materials are told what to mail.

### Summary footer (every tab)
- Cells along the bottom of the window show your **crafting queue**, **cooldowns**, **transfer plan**, **shopping list** (with estimated cost when Auctionator is installed), **camp** items and **crates and writs** at a glance (each of those two can be switched off under Options, General, Main Window), plus the **Skill Up Route** with SkillUp Forever and **Disenchanting Mode** where you have an enchanter. Click one to open or close its window. Hover a cell whose text is cut off to read all of it.
- Each cell has its quick button's icon. With six or more cells the footer takes two rows, and the window grows by a row so nothing above it gets smaller.

### Recipe browser
- **Search** by recipe name or by reagent name.
- **Sort** by name, skill up difficulty, skill up chance, craftable amount, or profit (with Auctionator). The arrow next to Sort reverses the order.
- **Filters** drop-down: show unlearned, unlearned only, has materials, orange and yellow only, hide grey recipes, favorites only, and hiding the category headers.
- **Expand** and **collapse** every category with the `+` and `-` buttons.
- **Row spacing** drop-down: compact, normal, roomy or spacious rows.
- Recipes are coloured by skill up difficulty, with a status stripe for materials: bags, bank, partial or none. Learned recipes show their skill up chance (such as 75%). A glowing infinity marks recipes that are new in Forever (gold) or changed in Forever (blue).
- The recipe you last clicked in each profession is selected again when you come back to it.
- Hover a recipe to see where it comes from: every trainer of your faction known to teach it, nearest first (up to 5, then "+N more"), the vendors that sell it, the quest that rewards it and who gives it, or the creatures, chests and dungeons it drops in. The recipe panel names the nearest trainer, with how many others. Trainers are matched by the recipe's name or by the item it makes (Smelt Steel is listed as "Steel Bar").
- Unlearned recipes show the skill they need ("Requires skill 150"). The recipe icon in the panel shows how many items one craft makes ("2", or "2-4").
- **Ctrl-click** a recipe, or its icon in the detail panel, to preview what it makes in the dressing room when it can be worn.
- **Shift-click** a recipe to link it in chat, or with no chat box open to track it in the objective tracker, learned or not, as Blizzard's window does. At the auction house it searches Auctionator's Shopping tab. Everywhere in the addon's windows, Shift-click only links or searches.

### Reagent cards
- Every reagent shows `have / need`, plus how much sits in your bank.
- Badges show what the **crafting queue** and **shopping list** already want of that reagent, with a breakdown on hover.
- A vendor badge appears when a vendor sells the reagent. Click it, or right-click the card, to navigate to the nearest vendor.
- **From bags** and **From bank** tiles show how many crafts you can make now and how many more the bank adds. Right-click the bank tile to navigate to the nearest banker.
- A **Requires** line lists tools and stations, coloured by whether you have them: in bags, in the bank, or missing.
- With Auctionator, **Cost to Craft** and **Profit** lines. Each reagent is priced at the cheapest of the vendor, the auction house or crafting it from its own reagents (a Bolt of Silk Cloth against four Silk Cloth), counting your alts' recipes too if you like. Hover for the breakdown.

### Crafting queue
- Queue recipes across any number of professions, each with its own quantity (`-` / `+` buttons, Shift for steps of 10).
- **Craft Queue** works through the list and opens each profession as needed; between recipes, a click on the game world crafts the next one. **Stop Craft** cancels the current craft and moves on. **Stop Queue** ends the run.
- Click a recipe in the queue to open it in the main window; the profession switches when needed.
- Queueing a recipe whose reagents you can craft yourself queues those first, sized to what you're short of. With only part of the materials, the queue holds back the early steps so the final crafts aren't left short.
- Rows are marked when something is missing: red when no one has it, blue when it's in the bank, pink when it's waiting in the mailbox. A missing reagent another character has queued to craft is named in the tooltip, and the mark turns yellow when their crafts cover all of it.
- **Queue Needed (N)** in the recipe panel queues exactly the crafts your queues still need of what that recipe makes (441 Bronze Bar needs 221 Smelt Bronze). Its tooltip says who needs it. On another character's profession it queues for that character.
- **Enchants** can be queued with a quantity to plan and shop for their materials. The queue runner skips them; each one you apply with the Enchant button comes off the queue.
- What the queue is short of goes on the shopping list by itself and follows the queue as it changes (with the shared list, the queues of all your characters of the same faction). Shared materials are counted once. With the shared list, an item one character has queued to craft comes off the list, and its materials go on instead. Quantities you change or add yourself are kept; **Reset to Queue** in the shopping list undoes your changes to the queue's items.
- The **character picker** in the title bar shows and edits another of your characters' queue (it crafts only on that character); the Transfer Planner follows it and shows who should send that character what.

### Shopping list
- Shared by all your characters of the same faction (the default), or one list per character, with needed, owned, alts and to-buy columns.
- Click an item to search for it at the auction house.
- With Auctionator: a unit price per item, a cost column, an estimated total, and an Auctionator shopping list named ProfessionsForever that always holds what is still to buy.
- Export as plain text.
- Items on your shopping list say so on their tooltip in your bags, bank and loot window: **On Shopping List**, **Needed by Crafting Queues** when your queues need them, and **Still to Buy**. Hold Shift for each character's queued recipes that use it. **Made by Queues** says how many another character's queued crafts cover, and **Crafts Into** on a raw material such as ore says what it is smelted or crafted into that your queues need.

### Alt inventory and transfer planner
- With Syndicator active, it does the tracking: other characters' bags and bank are read from its data, and this addon scans and saves no inventory of its own. Characters hidden in Syndicator are skipped.
- Without Syndicator, every character's bags and bank are cached account-wide as you play. The cache is a snapshot, so it can be out of date.
- A third **From alts** tile shows how many extra crafts the enabled alts could add on top of bags and bank. It never counts as materials you have now.
- Tooltips on the tile, on a reagent's alt badge and on shopping list rows show which character holds what and how much to transfer.
- Settings choose the mode: **Never** (alts ignored), **Show only** (shown, but shopping is unchanged) or **Include in planning** (default: enabled alts supply materials, so only the remainder is bought). Each character can be enabled or disabled, or removed from the cache. In the Transfer Planner, every character holding a needed material is listed under its name: tick or untick it to take the material from that character or not, or type an amount to take exactly that many (right-click a row to let the planner decide again). Once you change any character for a material, the planner no longer fills the rest from the others; what is left shows as unavailable.
- The **Transfer Planner** window lists, per character, what to retrieve for the whole crafting queue and what nothing can supply. Nothing is mailed for you. Once items move, the plan shrinks on its own.
- **Sending between characters** follows the queues on its own: when you log into an alt it prints what to send to each character whose queue needs its materials, and opening a mailbox shows the same list in the Transfer Planner, with a **Mail** button that attaches it. Change or clear a queue and the list follows.
- **Mail** puts short stacks together in your bags first, attaches the fewest stacks it can and fills in an empty subject (Crafting Materials, Gear to Disenchant or Manual Transfer).
- **Mail counts as a third place your items can be.** What waits in a character's mailbox is that character's, so it isn't asked for again or bought, including auction purchases you haven't collected. At the mailbox, **Collect from Mailbox** takes what your queue needs (never cash-on-delivery mail). Viewing another character's plan shows what waits in its mailbox.
- The Transfer Planner opens by itself at a mailbox or bank when there is something to send, collect or withdraw, and closes again with it.
- **Manual Transfers** (the letter button in the Transfer Planner's title bar) send items or gold between your characters, apart from any queue: pick a character, an item (type it, or drop a stack from your bags on the window) and an amount, and/or gold, then **Send** or **Ask**. They show on the sender's list, login reminder and mailbox prompt, and the Mail button attaches them. Click one to change it; click its X or right-click it to remove it. Soulbound items are refused.

### Disenchanting Mode
- On the Enchanting tab, the dust icon swaps the recipes for the gear in your bags and bank that can be disenchanted, plus the unbound gear on your other characters (to mail over). The list has the recipe list's search, sort, groups, row spacing and filters (quality, bank items, other characters, equipment set pieces, only what's worth disenchanting).
- Pick an item to see what it may give, with chances and amounts, and whether it's worth more sold to a vendor, disenchanted or sold at auction (with Auctionator, after the auction house cut). The best choice is highlighted, and the Disenchant button casts Disenchant on it. Items in an equipment set are marked and ask for confirmation first.
- Auction is only the best choice when it wins by more than a listing's deposit: 24 hours by default, or 2 or 8 hours, or not counted (Options, Disenchanting, Auction Deposit).
- Gear on another character has **Add to Transfer Plan**, which asks that character to mail it to you.
- The Disenchanting Mode footer cell (with a count of what you could disenchant) and quick button open Enchanting straight into the mode. On a character without Enchanting, they and `/pf de` list the gear you could send your enchanter. Pick your main enchanter under Options, Disenchanting, or at the bottom of the right-click enchanter menu.

### Tooltips
- Everything the addon adds to tooltips can be set under **Options, Tooltips**: each line on or off, the detail key (Shift, Ctrl or Alt), a "Hold Shift for details" hint, spacing and indent, and the order of the blocks (drag them). A preview beside the options shows the result as you change it.
- The recipe list's tooltip normally opens over the recipe panel. **Options, Tooltips, Recipes** can dock it beside the main window instead (on its left or right; level with the recipe you point at, or always with the top of the list), so the reagents stay readable, or show it only while the detail key is held.

### Disenchant advice and your own results
- Weapons and armour that can be disenchanted say what to do with them on their tooltip: Disenchant, Vendor or Auction, with the best lit and what it earns. Hold Shift for every result with its chance and value. Options, Tooltips, Disenchant Results sets when and how much it shows.
- Every disenchant your characters do is recorded, by item level. Under each expected chance, Disenchanting Mode and the tooltip show how often you've really seen that result, your average amount, and what your disenchants were really worth, greyed until 100 disenchants of that kind are recorded.

### Recipe Search
- Find any recipe in the game, in any profession, learned or not, by name or by reagent. Hover a recipe for what it makes, its reagents and which of your characters know it; click one of your recipes to open it.

### Quick buttons and Skill Up Route
- A movable bar of icons opens the Overview, settings, crafting queue, shopping list, transfer planner, cooldowns, Skill Up Route, Camp, Crates and Writs and Disenchanting Mode without the main window, each with a count of what is waiting. It can also have a button for each profession with a crafting window, which opens it like its tab. Lay it out in fixed columns or rows, growing from any corner (Options, Quick Buttons, Buttons).
- Every quick button can have a key, even with the bar hidden: under Options, Quick Buttons, Key Bindings, or the game's Key Bindings, AddOns, ProfessionsForever. Profession 1 to 5 are your professions with a crafting window, in tab order. Or type `/pf bind` (or click Mouseover Keybinding on that page), hover a quick button and press a key; right-click a button to unbind it, Escape to finish. Each button shows its key in its top left corner.
- With SkillUp Forever installed, the Skill Up Route window shows its levelling route for each profession; click a step to go to its trainer, vendor or recipe.

### Side windows
- The crafting queue, transfer planner and shopping list share a row of buttons to open and close each other.
- Side windows dock beside the main window, or beside the open mailbox or bank while the main window is closed, and always stay on screen: at a large UI scale they get shorter, and with no room beside the main window one docks over it. Pin a window to keep it in place.

### What's New
- After an update, the first login shows a short list of what's new. `/pf whatsnew` or the What's New button under Options, About shows it again. Older and Newer step through the notes of earlier versions.
- The version is shown at login, with a note when another player has a newer version (Options, General, Notifications).

### Camp
- The **Camp** window (footer cell, quick button or `/pf camp`) lists Forever's camp features: the tent, chair, campfire kits and every profession's camp feature (anvil, loom, mana well, fishing hut and the rest), each used up when placed. Below **Essentials** they are grouped as **Camp Features (In Bags)** (with a Place button; in the bank, the count), **(Craftable)** (Craft opens the recipe), **(On Alts)** (who holds it or can craft it) and **(Not Learned)** (the skill it needs; collapsed at first). Click a group's header to fold it.
- Placing an item needs its profession (not the recipe): a character holding one without the profession sees "Needs Leatherworking" instead of Place. Camp features share one cooldown and campfire kits another; both show at the top, and Place waits while its cooldown runs. Hover an item for who has it, who can craft it and the skill it needs. The Camp quick button shows the camp features' cooldown while it runs; the footer cell shows both cooldowns.
- The Cozy Sleeping Bag and the Pouch of Violet Dust toy, which are never used up, are in their own **Essentials** group at the top on a character that has them, with a Use button that shows their cooldown while it runs.
- The camp items come from `Data/Camp.lua`, generated from the game's data by `tools/gen_camp.py`.

### Crates and Writs
- The **Crates and Writs** window (footer cell, quick button or `/pf crates`) helps you pick which Waylaid Crates and Craftsman's Writs to do. Crates pay Merchant's Favor and writs pay reputation with your faction's camp. Your standing, Favor and Performance Bonus are along the top.
- **Held** lists the crates and writs your characters hold. Each crate shows its cheapest fill and how you would come by it: from what you have in hand, then what your alts can send, then crafting it or buying it. The right column is the cost per Favor (per reputation for a writ). What you already hold counts at its full price, since you could sell it instead, and so does the crate or writ itself, at its auction price less the cut; the cost is green when it is all in hand. The column before it is what the hand-in pays. Holding several of one crate, pick how many to fill in the number box beside the row's button: the fill, the Favor and the button follow it. A writ handed in today reads **Delivered (Resets in 5h)**, in Buy Writs too.
- The row's button does the next step: **Queue** queues the crafts (with the crafts of their reagents first), **Shop** puts what is missing on the shopping list, **Fill** fills a crate once its fill is in your bags, and **Waypoint** points to the customer or the camp. Right-click a row for the waypoint; hover it for every fill and its cost.
- **Buy Crates** ranks every crate by what buying it at the auction house and filling it costs per Favor. **Buy Writs** rates writs with an auction price per reputation, and sealed writs as an average over the orders they can open into. **Shop** on a row puts that crate or writ on the shopping list; Ctrl-click any row to search the auction house for it.
- A crate has a Forged Delivery Receipt's icon before its name when a receipt is the cheaper reputation: only between Friendly and Exalted, and only when it beats your cheapest writ. Its tooltip shows the numbers.
- What Artisan, Elite and blue crates pay isn't known yet: hand one in and the addon remembers it. A Performance Bonus double is not mistaken for the base pay.
- Crate and writ tooltips in your bags show the same pay and fills (Options, Tooltips, Crates and Writs).
- The crates and writs come from `Data/Orders.lua`, generated from the game's data and forever-db by `tools/gen_orders.py`. 29 writs have no customer on record; yours is remembered when you hand one in.

### Recipe Scout
- Entering a zone opens the **Recipe Scout** window, once per zone each session, listing the recipes you have not learned that you can get there: sold by a vendor (marked Limited Supply when the vendor's stock runs out), taught by a trainer once your skill is high enough, rewarded by a quest you can take, or dropped by a creature or held by a chest or other object. Inside a dungeon or raid it lists what its creatures and chests drop. `/pf scout` opens it again.
- Each recipe shows the skill it needs and where it comes from. Click one to open it, right-click for a waypoint to its vendor, trainer, quest giver or drop. Shift-click ignores a recipe in that zone for this character; **Show Ignored** lists them again.
- A recipe you already bought and have not learned says whether it is in your bags, bank or mailbox, and does not open the window on its own. Recipes of a specialization you do not have (Goblin Engineer, Weaponsmith and the like) and creatures friendly to your side are left out. Darkmoon Faire merchants are listed only while the faire is in that zone, and Winter Veil vendors only during the Feast of Winter Veil.
- The **Drops** dropdown lists all drops, only the recipes that drop nowhere but in this zone, or none. The window reopens where you dragged it, and its pin keeps it open and lists each zone you enter.
- Opening a vendor records which recipes it sells in a limited supply, and the window follows that over the built-in data.
- Options, General, Recipe Scout turns off opening on its own and chooses what it lists: vendors, limited supply, trainers, quests, drops, and recipes you already have.

### One-Click Fishing
- Bind a key under Options, One-Click Fishing (or the game's Key Bindings). Press it to cast, and again to catch when the fish bites. It only catches your bobber, never a nearby NPC.
- A press gets you ready first: it puts on your fishing gear set (picked per character), your best pole and your best lure, then casts. Each step can be turned off, and chat says what was equipped.
- **Skip the Lure While Holding** (Shift, Ctrl or Alt): that key held with the Fishing Key casts without putting a lure on. With Automatically Apply Your Best Lure off it becomes **Add a Lure While Holding**, putting your best lure on just for that press. It works when the Fishing Key with that modifier is bound to nothing else.
- Your normal gear goes back on when you mount, after a while without fishing (2 minutes by default) or when combat ends, each an option; or press the Swap Back key or type `/pf swapback`.
- **Louder Fishing Sounds** turns sound effects up while your line is out and puts your settings back after. It can also mute music and ambience, and keep sound on in the background.

### Recipe cooldowns
- A recipe with a cooldown (transmutes, Mooncloth and the like) shows the cooldown's length above the description in the recipe panel, then either "ready" or the time left. A recipe on cooldown also shows its time next to its name in the list, and its craft buttons are off until it is ready.
- Which recipes have a cooldown, and how long it is, comes from `Data/Cooldowns.lua`, generated from the game's data by `tools/gen_cooldowns.py`. A character's cooldown recipes are tracked once they are known, so the **Cooldowns** window lists every character's, ready ones first, with recipes that share a cooldown counted once as ready. Click a row of the current character to open that recipe, switching profession if needed. Right-click a row to ignore that cooldown for that character for good; tick **Show ignored** to list the ignored ones and right-click again to turn one back on.
- At login, one chat line per character names its ready cooldowns (recipes sharing a cooldown are grouped, like "Transmute (9)"); an option turns it off. The minimap tooltip shows how many are ready.
- The crafting queue crafts a tracked recipe once at a time and skips it while it is on cooldown.

### Bank awareness
- The bank is scanned whenever you open it and remembered per character.
- With Syndicator installed, live bank counts are used instead.

### Navigation (optional)
- Waypoints go through **Polestar** (when its integration setting is on) or **TomTom**.
- Targets: vendors for a recipe or reagent, the nearest trainer for a profession tier, the nearest banker.
- Darkmoon Faire vendors are offered at both faire sites, Mulgore and Elwynn Forest, to either faction.
- **Track location** on an unlearned recipe sets a waypoint to the nearest trainer or vendor that teaches it, from the shipped NPC data, Questie and the trainers you have visited. Where no location is known, the recipe panel says so.
- Trainers, bankers and vendors you open are remembered (with the recipes and items a vendor sells), so the lookup improves as you play. They are saved account-wide and only used for characters of a faction that has opened them, or that the built-in data lists them for (a neutral vendor opened on one faction serves the other too).
- `Data/ClassicNpcs.lua` ships the profession trainers, bankers and vendors of reagents and recipes from [cmangos/classic-db](https://github.com/cmangos/classic-db), so navigation works without Questie, with the trainers Forever added from ForeverTDB and the recipe vendors it added from forever-db. `Data/RecipeSources.lua` ships who or what each recipe is learned from: trainers, vendors, drops, objects and quest rewards, from QuestieDB, forever-db, ForeverTDB and classic-db, each under the best source that has it. `tools/gen_npcs.py` generates both (task **Update NPC data**; run `tools/gen_recipes.py` first), with `tools/recipe_sources.py` gathering the recipe sources. Each source is pinned to one commit or release, next to the newest Forever build on wago.tools; recorded NPCs win over them.
- `Data/Npcs.lua` ships NPCs players recorded in game, including ones classic-db lacks. `tools/merge_npcs.lua` merges players' `SavedVariables/ProfessionsForever.lua` files into it: `luajit tools/merge_npcs.lua <file>...`. The files are run in an empty environment and validated, but still only merge ones you trust.
- Right-click Polestar's arrow, or use the **Clear waypoint** button, to remove it. Waypoints also clear on arrival.

### Look and feel
- Four skins: **Modern Dark**, **Blackout**, **Classic** and **Minimal**, plus an **EllesmereUI** skin when EllesmereUI is installed. Pick them from the Skin drop-down on the Appearance page.
- Adjustable font (by default Game Default, the game's own font for your client's language, so Korean, Chinese and Russian text shows), font size, scale, background opacity and accent colour.
- Blizzard's own sounds for opening and closing the window, the crafting queue, the shopping list and the settings, and for switching tabs.
- The default professions keybind and the micro-menu Professions button open this window.

## Installation

1. Copy the `ProfessionsForever` folder to your AddOns directory:
   `World of Warcraft/<client>/Interface/AddOns/`
   This addon targets WoW: Forever only.
2. Start the game, or run `/reload` if it is already running.

The addon declares only **optional** dependencies, so it loads fine without any of them.

## Usage

| Action | How |
| --- | --- |
| Open or close the window | Professions keybind, `/pf`, the minimap button, or the micro-menu Professions button |
| Open a profession | Click its tab or Overview card |
| Add a recipe to the queue | **Add to Queue** in the recipe panel |
| Put missing reagents on the shopping list | Queue the recipe; the list follows the queue (click the red banner to open it) |
| Navigate to a vendor, trainer or banker | Right-click a reagent card, profession tab or the **From bank** tile |
| Scale the window | Ctrl + mouse wheel on the title bar |

## Optional integrations

| Addon | What it adds |
| --- | --- |
| **Auctionator** | Prices, crafting costs and profit, cost totals, an Auctionator shopping list kept in sync, disenchant values; prices update as soon as a scan or search finishes. "Auction Scan: 2h Ago" in the shopping list, Crates and Writs, Disenchanting Mode and the cost and profit tooltips, red once older than Prices Are Old After (24 hours by default), and "(3 Days Old)" on a single price last seen too long ago. While the auction house is open, a **Search** button in the recipe panel searches the Shopping tab for what the recipe makes and its reagents |
| **Syndicator** | Live bank counts, and the inventory of your other characters for the alt features |
| **Questie** | Vendor, trainer and banker locations. Current Questie releases keep their database in the separate **QuestieDB** addon, which is read directly, so QuestieDB alone is enough; older Questie releases that bundle the database work too |
| **TomTom** or **Polestar** | Waypoints and the navigation arrow; with Polestar, multi-step routes are printed to chat |
| **SkillUp Forever** | The Skill Up Route window, footer cell and quick button |
| **EllesmereUI** | An EllesmereUI skin for the windows; side windows dock beside its bank window |

Features that need a missing addon are hidden rather than shown disabled. Each has its own page under **Integrations** in the options.

## Slash commands

| Command | Action |
| --- | --- |
| `/pf`, `/professions`, `/professionsforever` | Toggle the window |
| `/pf queue` | Toggle the crafting queue |
| `/pf shop` | Toggle the shopping list |
| `/pf transfer` | Toggle the transfer planner |
| `/pf cooldowns`, `/pf cd` | Toggle the cooldowns window |
| `/pf camp` | Toggle the Camp window |
| `/pf crates`, `/pf writs` | Toggle the Crates and Writs window |
| `/pf scout` | Show the Recipe Scout window for this zone |
| `/pf recipe` | Toggle Recipe Search, searching by recipe name |
| `/pf reagent` | Toggle Recipe Search, searching by reagent |
| `/pf de`, `/pf disenchant` | Toggle Disenchanting Mode: on your own Enchanting, or without Enchanting, the gear you could send your main enchanter. It can't open Enchanting itself; use a macro with `/cast Enchanting` and then `/pf de` |
| `/pf track shop` | Turn the shopping list's Track on Screen on or off |
| `/pf bind` | Mouseover Keybinding: hover a quick button and press a key to bind it; Escape to finish |
| `/pf swapback` | Put your normal gear back on after One-Click Fishing |
| `/pf route` | Toggle the Skill Up Route window (needs SkillUp Forever) |
| `/pf whatsnew` | Show what's new in this version |
| `/pf options` | Open the settings |
| `/pf reset` | Reset window position and size |
| `/pf clearway` | Remove the active waypoint |
| `/pf help` | List the commands |

Diagnostics for bug reports: `/pf debug tools`, `/pf debug cooldowns`.

## Settings

Open them with `/pf options` or the Options button in the title bar. Each category page links to its pages.

- **General:** **Main Window** (replace the default professions window, skill up chance in the recipe list, the mark on recipes new or changed in Forever, minimap button), **Shopping List** (shared by your characters of the same faction, or per character), **Alt Inventory** (Never, Show only, Include in planning, and which characters may supply materials) and **Notifications** (the version at login, the newer-version note, ready cooldowns at login, opening the Transfer Planner at your bank or a mailbox) and **Recipe Scout** (open when you enter a zone, pin the window, and which kinds of recipes it lists)
- **Appearance:** **Theme** (skin, font, accent colour) and **Size and Window** (scale, font size, background opacity, locking and resetting the window's position and size)
- **Quick Buttons:** **Buttons** (show, lock, which buttons, fixed columns or fixed rows and how many, the corner they grow from, keys shown on the buttons) and **Key Bindings** (a key for each quick button and profession, and Mouseover Keybinding)
- **Disenchanting:** record your results, show seen rates, main enchanter, Auction Deposit
- **Tooltips:** a page for each part of what the addon adds to tooltips (**General**, **Queues & Shopping**, **Alts and Transfers**, **Prices and Hints**, **Recipes**, **Disenchant Results**), with a live preview beside them
- **One-Click Fishing:** the Fishing key, getting ready (best pole, best lure, a key to skip or add the lure, a gear set for this character), swapping back (Swap Back key, when you mount, when you stop fishing, after combat) and Louder Fishing Sounds
- **Integrations:** an overview of the supported addons; under it, a page for each: Auctionator, Polestar & TomTom, Questie, Syndicator, SkillUp Forever and EllesmereUI
- **About:** version, What's New, links and credits
- Each page and category has its own reset, and Reset all options resets everything (click twice to confirm)

## Notes and limits

- **Recipe data** comes from the client, so the recipe list only exists for a profession while it is open. Queued recipes keep their own copy of their reagents.
- **Crafting automation:** the game only lets an addon start a craft from a click. Between recipes the queue waits, then crafts the next one when you click the game world; switching to another profession needs a click on Craft Queue. Stop Craft uses a secure button to cancel the current cast.
- **Source information** for unlearned recipes is limited: Blizzard supplies none on this client, so it comes from the shipped recipe sources (trainers, vendors, quests, drops and objects), Questie and the trainers and vendors you have visited.
- Navigation features depend on third-party data and have not been verified against every vendor or trainer.

## Development

Edit the files in this folder and run `./deploy.sh` to replace the installed copy. The AddOns path is read from the first argument, the `WOW_ADDONS_DIR` variable, or a `.addons-path` file next to the script. In VS Code, the default build task (Ctrl+Shift+B) runs it. Use `/reload` in game afterwards.

Before deploying, `tools/check.py` (the "Check addon code" task) checks the code without the game: syntax, globals that don't resolve or are set by accident (against `tools/known-globals.txt`), unused locals, and the `.toc` against the files on disk. Edit only `README.md` and the CurseForge page's `CURSEFORGE.md`: `tools/gen_readmes.py` (the "Build readmes" task) builds the packaged `README.txt` and `CURSEFORGE.html` from them. After tagging a release, `tools/package.py` (the "Package release" task) builds `dist/ProfessionsForever-<tag>.zip` from the tag the way CurseForge packages it, to attach to the GitHub release. The "Update all data" task regenerates every generated `Data/` file from the newest Forever build; the generators share their wago.tools download helpers in `tools/wago.py`.

| File | Purpose |
| --- | --- |
| **Core/** | **Logic and data; no windows** |
| `Core/Core.lua` | Saved settings, event dispatch and startup |
| `Core/Professions.lua` | Replacing Blizzard's window, the player's professions, opening a profession, keybind |
| `Core/Commands.lua` | Slash commands and the addon compartment entry |
| `Core/Recipes.lua` | Recipe data, categories, filtering, sorting, material evaluation |
| `Core/Chain.lua`, `Core/ReagentUses.lua` | Crafting a short reagent first; which recipes use a reagent |
| `Core/KnownRecipes.lua` | Which of your characters know each recipe |
| `Core/Disenchant.lua`, `Core/DisenchantRecord.lua` | Disenchant loot tables, values, the gear that can be disenchanted and your enchanters; recording your disenchants and your seen rates |
| `Core/Inventory.lua` | Bag and bank counts, withdrawing from the bank |
| `Core/Prices.lua` | Auctionator prices, craft cost and profit |
| `Core/Tools.lua` | Tool and station requirements |
| `Core/Cooldowns.lua` | Recipe cooldowns on every character |
| `Core/Camp.lua` | Camp items: what you hold, can craft or an alt has; the shared camp cooldowns |
| `Core/Queue.lua`, `Core/QueueRunner.lua` | The crafting queue and what it needs; the runner that crafts it |
| `Core/Shopping.lua` | The shopping list and what is still to buy |
| `Core/Fishing.lua` | One-Click Fishing: the cast and catch key, getting ready, swapping back, louder sounds |
| `Core/VersionCheck.lua` | The version line at login and the newer-version note |
| `Core/Debug.lua` | `/pf debug` diagnostics; never packaged |
| **Alts/** | **Other characters** |
| `Alts/AltInventory.lua` | Account-wide cache of every character's bags, bank, mail and unbound gear |
| `Alts/AltProfessions.lua` | Every character's professions, and browsing another character's profession |
| `Alts/TransferPlanner.lua` | Allocates enabled alts' stock against requirements; the one source of transfer and shortage results; what to fetch from your own bank and mailbox |
| `Alts/Outgoing.lua` | What each character should mail the others, worked out from their queues |
| **Waypoints/** | **Trainer, vendor and banker locations** |
| `Waypoints/Waypoint.lua` | Navigator (Polestar / TomTom) and the Questie lookups the Waypoint files share |
| `Waypoints/WaypointRecord.lua` | Recording the trainers, bankers and vendors you open; reading them together with the shipped NPC data |
| `Waypoints/WaypointVendors.lua`, `WaypointTrainers.lua`, `WaypointBankers.lua` | Vendor, trainer and banker navigation |
| **UI/Common/** | **Building blocks every window uses** |
| `UI/Common/Skin.lua`, `UI/Common/Widgets.lua` | Skins, EllesmereUI integration, fonts; buttons, steppers, dropdown menu, tooltips |
| `UI/Common/KeyBinding.lua` | Binding and unbinding keys, for the options' key rows and the quick buttons' bind mode |
| `UI/Common/Scrollbar.lua`, `UI/Common/Completion.lua`, `UI/Common/ItemAutocomplete.lua` | The thin scroll bar every list uses; type-ahead suggestions for edit boxes; item name suggestions |
| `UI/Common/ListHeader.lua` | The search, sort, category, row spacing and filter rows above the recipe list and Disenchanting Mode's list |
| `UI/Common/SidePanel.lua`, `UI/Common/CombatClose.lua` | Building, docking and pinning the side windows, their window buttons; closing windows as combat starts |
| **UI/** | **The main window** |
| `UI/UI.lua`, `UI/Shared.lua`, `UI/Redraw.lua` | The window frame, refresh and title bar; shared constants; redrawing windows once when data changes |
| `UI/ProfessionBar.lua`, `UI/ProfessionOpener.lua`, `UI/ExtraSpell.lua` | The skill bar and profession tabs; opening a profession; Disenchant and tracking spell buttons |
| `UI/RecipeList.lua`, `UI/RecipePanel.lua` | The recipe rows; the search box, filter bar and list frame |
| `UI/RecipeInfo.lua` | Where a recipe comes from, and its preview, track and link actions (shared by the list and the recipe panel) |
| `UI/Detail.lua`, `UI/DetailPanel.lua`, `UI/ReagentCards.lua` | Showing the selected recipe; building the detail panel; the reagent cards |
| `UI/Profit.lua`, `UI/Craft.lua` | Cost and profit lines; craft actions and the enchant / salvage target picker |
| `UI/Overview.lua`, `UI/Footer.lua` | Overview page and profession cards; summary cells along the bottom |
| `UI/DisenchantMode.lua` | Disenchanting Mode |
| `UI/WhatsNew.lua` | The What's New window |
| `UI/Minimap.lua`, `UI/Launcher.lua` | Minimap button and quick buttons |
| `UI/Options/` | The options window and its pages |
| **Tooltips/** | **Lines added to item tooltips** |
| `Tooltips/Tooltips.lua` | The one item tooltip hook, running each block in the chosen order; the detail key, spacing, indent and key hint |
| `Tooltips/QueueNeeds.lua` | On Shopping List, Needed by Crafting Queues, Still to Buy, Made by Queues and Crafts Into, the shopping list's numbers |
| `Tooltips/Disenchant.lua` | Disenchant results and the best choice (disenchant, vendor or auction) |
| `Tooltips/Preview.lua` | The tooltip preview docked beside the options while a Tooltips page is open |
| **Panels/** | **Side windows** |
| `Panels/Queue.lua`, `Panels/QueueDrag.lua` | Crafting queue window; drag to reorder |
| `Panels/Shopping/` | Shopping list window, export, on-screen tracker, item search, merchant Buy List button |
| `Panels/TransferPanel.lua`, `Panels/TransferRows.lua`, `Panels/TransferForm.lua` | Transfer planner window; its row lists; the Manual Transfers form |
| `Panels/Cooldowns.lua`, `Panels/SkillUp.lua`, `Panels/ReagentSearch.lua` | Cooldowns window; SkillUp Forever route; Recipe Search (by name or reagent) |
| `Panels/Camp.lua` | Camp window |
| **Data/**, **Locales/** | |
| `Data/ClassicNpcs.lua` | Shipped trainers, bankers and vendors from classic-db, ForeverTDB and forever-db, generated by `tools/gen_npcs.py` |
| `Data/RecipeSources.lua` | Where each recipe is learned (trainer, vendor, drop, object, quest reward) from QuestieDB, forever-db, ForeverTDB and classic-db, generated by `tools/gen_npcs.py` with `tools/recipe_sources.py` |
| `Data/Npcs.lua` | Trainers, bankers and vendors recorded by players, generated by `tools/merge_npcs.lua` |
| `Data/Recipes.lua`, `Data/Items.lua`, `Data/Cooldowns.lua`, `Data/Camp.lua` | Recipe, item, cooldown and camp item data generated from wago.tools |
| `Data/Orders.lua` | Waylaid Crates and Craftsman's Writs, generated from wago.tools and forever-db by `tools/gen_orders.py` |
| `Data/Disenchant.lua` | Disenchant results with odds, level brackets and items that can't be disenchanted, generated by `tools/gen_disenchant.py` from classic-db and wago.tools |
| `Locales/enUS.lua` | Strings |

## License and credits

ProfessionsForever is free software under the GNU General Public License, version 3 (see `LICENSE`).

- `Data/ClassicNpcs.lua` and `Data/RecipeSources.lua` are derived from [cmangos/classic-db](https://github.com/cmangos/classic-db) (GPL-3.0): NPC spawns, trainer spell lists, vendor stock and limited supplies. World of Warcraft content and materials are trademarks and copyrights of Blizzard Entertainment; classic-db is not affiliated with Blizzard.
- The trainers added in Forever, and the skill and cost to learn a recipe seen on a Forever build, come from ForeverTDB ([advocaite/TrinityCore](https://github.com/advocaite/TrinityCore), GPL-2.0 or later), which itself builds on VMaNGOS, cmangos classic-db and Questie data.
- Recipe vendors, drops, objects and quest rewards come from [foreverfraddons/forever-db](https://github.com/foreverfraddons/forever-db) (GPL-3.0) and [QuestieDB](https://github.com/Questie/QuestieDB), whose team allows copying under the GPLv3 terms. QuestieDB's data will be removed on request.
- `Data/Recipes.lua`, `Data/Items.lua`, `Data/Cooldowns.lua` and `Data/Camp.lua` are generated from the wago.tools DB2 tables for WoW: Forever.
- `Data/Disenchant.lua` takes its loot tables and odds from cmangos/classic-db (GPL-3.0) and its level brackets from the wago.tools tables for WoW: Forever.
