<p align="center">
  <img src="Media/icon.png" alt="ProfessionsForever" width="128" />
</p>

<h1 align="center">ProfessionsForever</h1>

<p align="center">
  A skinnable replacement professions window for <b>WoW: Forever</b> with bag and bank awareness,<br>
  a crafting queue, a shopping list, and optional navigation to vendors, trainers and bankers.
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
- The `x` on a primary profession's card unlearns it, through the game's own confirmation.

### Summary footer (every tab)
- Four cells along the bottom of the window show your **crafting queue**, **cooldowns**, **transfer plan** and **shopping list** (with estimated cost when Auctionator is installed) at a glance. Click one to open or close its window. Hover a cell whose text is cut off to read all of it.

### Recipe browser
- **Search** by recipe name or by reagent name.
- **Sort** by name, skill-up difficulty, craftable amount, or profit (with Auctionator). Right-click the sort button to reverse the order.
- **Filters** drop-down: show unlearned, unlearned only, has materials, orange and yellow only, hide grey recipes, favorites only, and hiding the category headers.
- **Expand** and **collapse** every category with the `+` and `-` buttons.
- **Row spacing** drop-down: compact, normal, roomy or spacious rows.
- Recipes are coloured by skill-up difficulty, with a status stripe for materials: bags, bank, partial or none.
- Hover an unlearned recipe to see where it comes from: the trainer you've seen teach it, or the vendors Questie knows.
- **Ctrl-click** a recipe, or its icon in the detail panel, to preview what it makes in the dressing room when it can be worn.

### Reagent cards
- Every reagent shows `have / need`, plus how much sits in your bank.
- Badges show what the **crafting queue** and **shopping list** already want of that reagent, with a breakdown on hover.
- A vendor badge appears when a vendor sells the reagent. Click it, or right-click the card, to navigate to the nearest vendor.
- **From bags** and **From bank** tiles show how many crafts you can make now and how many more the bank adds. Right-click the bank tile to navigate to the nearest banker.
- A **Requires** line lists tools and stations, coloured by whether you have them: in bags, in the bank, or missing.

### Crafting queue
- Queue recipes across any number of professions, each with its own quantity (`-` / `+` buttons, Shift for steps of 10).
- **Craft Queue** works through the list and opens each profession as needed. **Stop Craft** cancels the current craft and moves on. **Stop Queue** ends the run.
- One click adds every missing reagent for the whole queue to the shopping list. Shared materials are counted once.

### Shopping list
- Per-character or account-wide, with needed, owned and to-buy columns.
- Click an item to search for it at the auction house.
- With Auctionator: a unit price per item, a cost column, an estimated total, and a one-click send to an Auctionator shopping list.
- Export as plain text.

### Alt inventory and transfer planner
- With Syndicator active, it does the tracking: other characters' bags and bank are read from its data, and this addon scans and saves no inventory of its own. Characters hidden in Syndicator are skipped.
- Without Syndicator, every character's bags and bank are cached account-wide as you play. The cache is a snapshot, so it can be out of date.
- A third **From alts** tile shows how many extra crafts the enabled alts could add on top of bags and bank. It never counts as materials you have now.
- Tooltips on the tile, on a reagent's alt badge and on shopping list rows show which character holds what and how much to transfer.
- Settings choose the mode: **Never** (alts ignored), **Show only** (shown, but shopping is unchanged) or **Include in planning** (default: enabled alts supply materials, so only the remainder is bought). Each character can be enabled or disabled, or removed from the cache. In the Transfer Planner, every character holding a needed material is listed under its name: tick or untick it to take the material from that character or not, or type an amount to take exactly that many (right-click a row to let the planner decide again). Once you change any character for a material, the planner no longer fills the rest from the others; what is left shows as unavailable.
- The **Transfer Planner** window lists, per character, what to retrieve for the whole crafting queue and what nothing can supply. Nothing is mailed for you. Once items move, the plan shrinks on its own.
- **Publish** saves the plan account-wide. When you log into an alt it prints what to send to the crafter, and opening a mailbox shows the same list in the Transfer Planner. Items you mail to the crafter are counted off. Publish again after collecting your mail.

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
- **Track location** on an unlearned recipe sets a waypoint to the trainer or vendor that teaches it, using Questie and the trainers you have visited. Where no location is known, the recipe panel says so.
- Trainers, bankers and vendors you open are remembered (with the recipes and items a vendor sells), so the lookup improves as you play and works without Questie. They are saved account-wide and only used for characters of a faction that has opened them.
- `Data/Npcs.lua` ships the same tables. `tools/merge_npcs.lua` merges players' `SavedVariables/ProfessionsForever.lua` files into it: `luajit tools/merge_npcs.lua <file>...`. The files are run in an empty environment and validated, but still only merge ones you trust.
- Right-click Polestar's arrow, or use the **Clear waypoint** button, to remove it. Waypoints also clear on arrival.

### Look and feel
- Three skins: **Modern Dark**, **Classic** and **Minimal**, plus an **EllesmereUI** skin when EllesmereUI is installed. Pick them from the Skin drop-down on the settings page.
- Adjustable font, font size, scale, background opacity and accent colour.
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
| Add missing reagents to the shopping list | Click the red banner, or **Add missing to Shopping List** |
| Navigate to a vendor, trainer or banker | Right-click a reagent card, profession tab or the **From bank** tile |
| Scale the window | Ctrl + mouse wheel on the title bar |

## Optional integrations

| Addon | What it adds |
| --- | --- |
| **Auctionator** | Prices, cost totals, send-to-Auctionator |
| **Syndicator** | Live bank counts, and the inventory of your other characters for the alt features |
| **Questie** | Vendor, trainer and banker locations. Current Questie releases keep their database in the separate **QuestieDB** addon, which is read directly, so QuestieDB alone is enough; older Questie releases that bundle the database work too |
| **TomTom** or **Polestar** | Waypoints and the navigation arrow |
| **EllesmereUI** | An EllesmereUI skin for the windows |

Features that need a missing addon are hidden rather than shown disabled.

## Slash commands

| Command | Action |
| --- | --- |
| `/pf`, `/professions`, `/professionsforever` | Toggle the window |
| `/pf shop` | Toggle the shopping list |
| `/pf transfer` | Toggle the transfer planner |
| `/pf cooldowns`, `/pf cd` | Toggle the cooldowns window |
| `/pf options` | Open the settings |
| `/pf reset` | Reset window position and size |
| `/pf clearway` | Remove the active waypoint |
| `/pf help` | List the commands |

Diagnostics for bug reports: `/pf debug tools`, `/pf debug cooldowns`.

## Settings

Open them with `/pf options` or the Options button in the title bar.

- Skin, font, font size, scale, background opacity, accent colour
- Replace the default professions window (on or off)
- Shopping list scope: per character or account-wide
- Hide the minimap button
- Alt inventory mode (Never, Show only, Include in planning) and which characters may supply materials
- Reset window position and size
- Reset all options (click twice to confirm)

## Notes and limits

- **Recipe data** comes from the client, so the recipe list only exists for a profession while it is open. Queued recipes keep their own copy of their reagents.
- **Crafting automation:** Blizzard may require a fresh click to start a craft, so a queue run can pause and ask you to click again. Stop Craft uses a secure button to cancel the current cast.
- **Source information** for unlearned recipes is limited: Blizzard supplies none on this client, so it comes from Questie and from trainers you have visited.
- Navigation features depend on third-party data and have not been verified against every vendor or trainer.

## Development

Edit the files in this folder and run `./deploy.sh` to replace the installed copy. The AddOns path is read from the first argument, the `WOW_ADDONS_DIR` variable, or a `.addons-path` file next to the script. In VS Code, the default build task (Ctrl+Shift+B) runs it. Use `/reload` in game afterwards.

| File | Purpose |
| --- | --- |
| `Core/Core.lua` | Saved settings, event dispatch and startup |
| `Core/Professions.lua` | Replacing Blizzard's window, the player's professions, opening a profession, keybind |
| `Core/Commands.lua` | Slash commands and the addon compartment entry |
| `Core/Recipes.lua` | Recipe data, filtering, sorting, material evaluation |
| `Core/Inventory.lua` | Bag and bank counts |
| `Core/Craft.lua` | Craft actions and the enchant / salvage target picker |
| `Core/Prices.lua` | Auctionator price lookups and the profit estimate |
| `Core/Tools.lua` | Tool and station requirements |
| `Core/Waypoint.lua` | Navigator (Polestar / TomTom) and the Questie lookups the Waypoint files share |
| `Core/WaypointRecord.lua` | Recording the trainers, bankers and vendors you open; reading them together with the shipped `Data/Npcs.lua` |
| `Core/WaypointVendors.lua`, `Core/WaypointTrainers.lua`, `Core/WaypointBankers.lua` | Vendor, trainer and banker navigation |
| `Data/Npcs.lua` | Shipped trainers, bankers and vendors, generated by `tools/merge_npcs.lua` |
| `Alts/AltInventory.lua` | Account-wide cache of every character's bags and bank |
| `Alts/TransferPlanner.lua` | Allocates enabled alts' stock against requirements; the one source of transfer and shortage results |
| `Alts/Outgoing.lua` | Published transfers each character sees when it logs in |
| `UI/Skin.lua`, `UI/Widgets.lua` | Skins, EllesmereUI integration, fonts; buttons, steppers, dropdown menu, tooltips |
| `UI/Shared.lua`, `UI/UI.lua` | Constants and helpers the main window's files share; the window frame, refresh and title bar |
| `UI/ProfessionBar.lua` | The open profession's skill bar and the profession tabs |
| `UI/RecipeList.lua`, `UI/RecipePanel.lua` | Filtering and the recipe rows; the search box, filter bar and list frame |
| `UI/Detail.lua`, `UI/DetailPanel.lua` | Showing the selected recipe; building the detail panel, reagent cards and craft buttons |
| `UI/Profit.lua` | Cost and profit lines and their tooltips |
| `UI/Overview.lua` | Overview page and profession cards |
| `UI/Footer.lua` | Summary cells along the bottom of the window |
| `UI/SidePanel.lua`, `UI/Disenchant.lua` | Docking and pinning for the side windows; the Disenchant button |
| `UI/Options.lua`, `UI/Minimap.lua` | Settings page and minimap button |
| `Panels/Queue.lua`, `Panels/ShoppingList.lua`, `Panels/TransferPanel.lua`, `Panels/TransferRows.lua`, `Panels/Cooldowns.lua` | Crafting queue and runner; shopping list and Auctionator export; transfer planner window and its row list; cooldowns window |
| `Locales/enUS.lua` | Strings |
