# Changelog
## 0.10.3

### Added
- A recipe's tooltip lists every trainer of your faction known to teach it, nearest first (up to 5, then "+N more"). The recipe panel names the nearest one, with how many others, and the waypoint goes to the nearest.
- Item tooltips show "On Shopping List" with how many for every item on the shopping list, including ones you added yourself, and "Still to Buy" under it. Show Shopping List on Item Tooltips is under Options, Tooltips, Queues & Shopping (renamed from Crafting Queues).
- Enchants can be queued with a quantity, to plan and shop for their materials. Each one applied with the Enchant button comes off the queue; the queue runner skips them.
- Item tooltips and shopping list rows show "Made by Queues": how many your other characters' queued crafts make of an item the queues need, and who makes them. Shown even when nothing is left to buy.
- "Crafts Into" on item tooltips: on a raw material such as Copper Ore, what a recipe your characters know turns it into that the queues need, and how many that takes.
- Queue Needed button in the recipe panel: queues the crafts that make what the queues still need, with who needs it in its tooltip.
- The crafting queue's missing marker names the other character making a missing reagent, and turns yellow when they make all of it.
- Show Made by Queues and Show Crafts Into are under Options, Tooltips, Queues & Shopping.

### Changed
- The What's New window's header has the options banner's accent glow and a welcome with your character's name. Its background is solid in the Classic and Minimal skins, as the options window's is.

### Fixed
- Switching the skin to EllesmereUI with a window open hid the art drawn on the window itself, such as the What's New icons, until a reload.
- The options' welcome showed only your first name. It now shows your full name.
- With the shared shopping list, an item another character had queued to craft stayed on the list as well as that craft's materials. It now comes off the list, chains included (bars for ore).
- Recipes a trainer lists by what they make, such as Smelt Steel ("Steel Bar"), said "Location not currently known" even after visiting the trainer. Trainers are now matched by the item a recipe makes too.
- The recipe icon in the detail pane now shows how many items one craft makes ("2", or "2-4" for a range), as Blizzard's window does.
- Profession tabs, quick buttons and keys could cast a class spell, such as a shaman's totem, after learning a new spell.
- The disenchant verdict (item tooltips and Disenchanting Mode) picked Sell It at Auction when it only just beat the vendor or disenchant value. Auction now has to win by more than a listing's deposit, 24 hours by default (Auction Deposit, under Options, Disenchanting).
- With EllesmereUI, the What's New window's dark title strip stopped partway down its title. It now ends at the line under the title.
- The Overview's Bait and Tackle button closed Fishing when it was already open. It now works like the Fishing card, right-click included.

## 0.10.2

### Added
- A Camp window (Camp footer cell, quick button or `/pf camp`) for Forever's camp features: the tent, chair, campfire kits and every profession's camp feature. Essentials holds the Cozy Sleeping Bag and the Pouch of Violet Dust, with a Use button. Then Camp Features (In Bags) with a Place button, (Craftable) with Craft, (On Alts) and (Not Learned) with the skill each needs. The camp feature and campfire cooldowns show at the top, on the Place buttons, on the footer cell and on the quick button.
- Key bindings for the quick buttons: a key for each window, Disenchanting Mode, and Profession 1 to 5, under Options, Quick Buttons, Key Bindings or the game's Key Bindings, AddOns, ProfessionsForever. They work with the quick buttons hidden. Mouseover Keybinding (`/pf bind`): hover a quick button and press a key; right-click to unbind, Escape to finish. Each quick button shows its key (Show Keys on Buttons).
- Two more quick buttons: Overview (on by default) and Settings (off by default), under Options, Quick Buttons, Buttons. Overview's key is the game's professions key (K).
- Show Camp Button and Show Disenchanting Mode Button, under Options, Quick Buttons, Buttons.
- One-Click Fishing: bind a key under Options, One-Click Fishing or Key Bindings. Press it to cast, and again to catch when the fish bites. It only catches the bobber, never a nearby NPC.
- One-Click Fishing gets you ready first: a press puts on your fishing gear set (picked per character), your best pole and your best lure, then casts. Each step can be turned off. Chat says what was equipped.
- One-Click Fishing swaps your normal gear back when you mount, when you stop fishing for a while (2 minutes by default) or when combat ends, each an option. Or use the Swap Back key or `/pf swapback`.
- Louder Fishing Sounds: sound effects turned up while your line is out, and your settings put back after. It can also mute music and ambience, and keep sound on in the background.
- The version is now shown at login, with a note when a newer version is out. Turn either off under Options, General, Notifications.
- Manual Transfers: send items or gold between your characters, apart from any queue. Click the letter button in the Transfer Planner's title bar, pick a character, an item (type it, or drop a stack on the window) and an amount, and/or gold, then Send or Ask. It shows on the sender's list, login reminder and mailbox prompt, and their Mail button attaches it. Click a manual transfer to change it; click its X or right-click it to remove it. Soulbound items are refused.
- Disenchanting Mode: Add to Transfer Plan asks another character to send you their piece of gear.
- Crafted reagents are priced at what they cost to craft when that's cheaper (a Bolt of Silk Cloth or four Silk Cloth). Used by Cost to Craft, Profit and the Profit sort; the Cost to Craft tooltip lists what each is made from. Include Recipes Your Other Characters Know is under Options, Integrations, Auctionator.
- `/pf track shop` turns the shopping list's Track on Screen on and off.
- Item tooltips show "Needed by Crafting Queues" and "Still to Buy" for items your queues need. Hold Shift for who needs it and for which recipes. Shopping list rows show the recipes with Shift too.
- A Tooltips category in the options, with a page for each part of what the addon adds to tooltips: General (detail key, hint, spacing, indent, block order), Crafting Queues, Alts and Transfers, Prices and Hints, Disenchant Results and Recipes. A live preview sits beside them.
- Show Where Learned Recipes Came From, under Options, Tooltips, Recipes (off by default): keeps showing a recipe's source after you learn it.

### Changed
- Recipe and item data updated to the latest Forever build.
- The options are sorted into categories: General, Appearance, Quick Buttons, Disenchanting, Tooltips, One-Click Fishing, Integrations and About. Each category page links to its pages and has a Reset This Category button. Alt Inventory moved to General.
- Quick button layout: Fixed Columns or Fixed Rows with a slider, and Grow From any corner, under Options, Quick Buttons, Buttons.
- The quick buttons and footer cells are in a new order: Overview and Settings, Crafting Queue, Shopping List, Transfer Planner, Cooldowns, Skill Up Route, Camp, Disenchanting Mode, then your professions.
- With six or more footer cells, the footer takes two rows.
- Disenchanting Mode has a footer cell, replacing the icon next to the Overview's character picker.
- A reagent sold by a vendor and on the auction house is priced at whichever is cheaper.
- Shorter tooltips on shopping list rows, Transfer Planner rows and reagent cards.
- The click hints are one line, and the auction price line is left off when Auctionator shows its own. Both can go back under Options, Tooltips, Prices and Hints.
- New addon icon.

### Fixed
- The Transfer Planner's Mail button attached the whole stack instead of splitting it.
- Disenchanting Mode: clicking Disenchant during another cast or the global cooldown put the gear on instead.
- The profession quick buttons opened the profession and closed it again at once.
- On a character without Enchanting, a second click on Disenchanting Mode opened your enchanter's recipes. It now takes you back to where you were.
- Windows opened before the main window opened in the middle of the screen, on top of each other. They now dock where the main window will be.
- A queued recipe the character hadn't learned kept its item and materials on the shopping list.
- Items the game hadn't loaded yet showed as "item:2840" until the window was reopened.
- Turning Use Auctionator's Prices on or off scrolled the recipe list to the top.

## 0.10.1

### Fixed
- Enchanting gear in the trade window, for another player, wasn't possible: the Enchant button stayed grey until you chose an item, and the item in the trade window's "Will not be traded" slot can't be chosen. As in Blizzard's window, Enchant now works with no item chosen: click it, then click the item in the trade window (or any item) with the glowing cursor.
- Updating past a version (say from 0.9.4 straight to 0.10.1) skipped the What's New window, since only the newest version's notes were looked for. It now shows the newest notes you haven't seen, so 0.10.0's notes still show after updating to 0.10.1, and `/pf whatsnew` still opens them.

## 0.10.0

### Added
- A What's New window: after updating, the first login shows a short list of the main changes. Open it again any time with `/pf whatsnew` or the What's New button under Options, About.
- First Aid, Cooking and Fishing at their Journeyman cap: the profession card and tab now say the Expert rank needs a skill book bought from a vendor (Expert First Aid, Expert Cookbook, Expert Fishing), and the right-click waypoint goes to the nearest vendor that sells it instead of a trainer.
- Artisan First Aid, Cooking and Fishing at Expert cap and 225 skill: the card says it is a quest, and the right-click waypoint goes to the NPC that finishes it (Doctor Gustaf VanHowzen or Doctor Gregory Victor, Dirge Quikcleave, Nat Pagle).
- Trainer, banker and vendor locations now ship with the addon (from the cmangos classic-db project), so waypoints to profession trainers, bankers and reagent or recipe vendors work without Questie. NPCs you open in game still take priority.
- Skill Up chance on each learned recipe in the list (such as 75%), in the recipe's difficulty colour and gone once it turns grey. It is worked out from the same skill thresholds the game uses for the colours. Turn it off under Options, General. The recipe panel also shows it under the recipe name, and the list can be sorted by it (Sort: Skill Up Chance, highest first).
- New Blackout skin: the EllesmereUI look (black windows, thin grey borders) without needing EllesmereUI.
- New scrollbars in every skin.
- Another player's profession, opened from a chat link, now opens in this window. It is read-only: crafting, queueing, tracking and favorites are off, and your own materials are still counted.
- Skill Up Route: with SkillUp Forever installed, a footer window (and `/pf route`) shows its levelling route for each profession: the next train, buy, gather and craft steps and the reagents they need. Click a step to set a waypoint to its trainer or vendor, or to open the recipe to craft.
- Quick buttons: a small bar of icons that opens the cooldowns, transfer planner, shopping list and crafting queue without the main window, each with a count of what is waiting (ready cooldowns, alts to visit, items to buy, queued recipes). It also has a button for each profession with a crafting window, which opens it like its tab, including Forever's camp crafting in Herbalism and Fishing; turn those off under Options, Quick Buttons. With SkillUp Forever installed it also has a Skill Up Route button, whose tooltip shows the next step; it can be turned off under Integrations. On a character that knows Disenchant, a Disenchanting Mode button opens Enchanting straight into Disenchanting Mode, or turns the mode on and off while Enchanting is open (not in combat). On a character without Enchanting it lists the gear you could send your best enchanter (same faction first, then highest skill) instead; right-click it to pick another enchanter. If you have more than one enchanter, pick your main one under Options, General, Disenchanting, or at the bottom of that right-click menu, and it comes first everywhere. `/pf de` does the same; on an enchanter it can't open Enchanting itself, so a macro of `/cast Enchanting` then `/pf de` opens it straight into the mode. On a character without Enchanting, the Overview also has a Disenchanting Mode icon next to the character picker that does the same. Under Options, Quick Buttons, set how many buttons go in a row and which way they grow (left or right, up or down); while unlocked, a handle marks the corner they grow from and drags the bar.
- Recipe Search: find any recipe in the game, in any profession, learned or not, even on a character without that profession. Search by name, or by reagent to see every recipe that uses an item. Open it with the magnifier button (title bar, under the recipe list, or next to Add in the shopping list), `/pf recipe` or `/pf reagent`, or Alt-click a reagent in the recipe panel or an item in the shopping list. Hover a recipe to see what it makes, its reagents with how many you have, and which of your characters know it (each character is counted from its first login with this version). Click a recipe of one of your professions to open it.
- Disenchanting Mode: on the Enchanting tab (the dust icon next to the Disenchant button, or the same icon on the Overview's Enchanting card) swaps the recipes for the gear in your bags and bank that can be disenchanted (the bank as it was on your last visit). Pick an item to see what it may give, with chances, and whether it is worth more sold to a vendor, disenchanted or sold at auction (with Auctionator, after the auction house cut). The Disenchant button casts Disenchant on it. Items in an equipment set are marked with a warning, and disenchanting one asks you to confirm first. "Back to Recipes" at the top of the list leaves the mode. The search, sort, category, row spacing and filter controls work as in the recipe list: search suggests item names as you type; sort by name, item level, quality or best value, either way round; pick a group (your bags, your bank or one of your other characters) or collapse and expand them; and a Filters menu shows or hides other characters' gear, bank items, each quality (uncommon, rare, epic) and equipment set pieces, or only the items worth more disenchanted (needs Auctionator). Your other characters' unbound gear is listed too, grouped by character, with which of their bags or bank it is in, so you can see what they could mail you to disenchant; each character's gear is saved when it logs in and visits its bank (with Syndicator, characters not logged in since this version show what Syndicator recorded). Characters turned off on the Alt Inventory page and of the other faction are left out.
- Disenchant results on item tooltips: weapons and armour that can be disenchanted say what to do with them, the same verdict as Disenchanting Mode: a "Disenchant / Vendor / Auction" line with the best choice lit in its colour and the others grey, and what it earns after the 5% auction house cut (needs Auctionator; without prices the line shows the likeliest disenchant result, such as Strange Dust x1-2). Hold Shift to see each choice's value, and every disenchant result with its chance, amount and value. A new Tooltips options page turns it off and picks when it shows (always or only with Shift), how much it shows (one line, every result, or one line with every result on Shift), whether it leads with the best choice or just the disenchant value, and whether a character needs Enchanting: any of yours (the default), this one, or none, so a main without Enchanting can see what to vendor and what to send to an enchanter. Soulbound gear only shows it on a character that knows Enchanting, since it can't be mailed to one (can be turned off). While Auctionator's own disenchant tooltips are on, ProfessionsForever leaves its lines out; that can be turned off under Integrations.
- Disenchant results are now recorded: each time one of your characters disenchants an item, what it gave is saved account-wide, by item quality, type and level, along with the WoW build. This is the groundwork for checking the disenchant chances against what Forever really drops. Turn it off under Options, General. How often you've really seen each result, and how many of it you got on average, show under its chance and amount in Disenchanting Mode ("seen 75%", "seen 1.7") and on item tooltips with every result shown, added up across your characters for each kind of item, with how many disenchants that is and any results the table doesn't list. Under the Disenchant value, "seen" shows what your disenchants of that kind were really worth on average, at today's auction prices (it doesn't change which choice is best). It is greyed and marked unreliable until 100 disenchants of that kind are recorded. Turn it off under Options, General, Show Seen Rates.
- Browse your other characters' professions: a character dropdown on the Overview swaps the cards for another character's professions, and clicking one opens its recipes in this window, read-only: what that character knows, in the game's categories, with skill-up colours and chances at their skill. Materials, craftable counts and required tools are counted from that character's bags and bank, and what your other characters could add includes the one you're on. A learned recipe can be queued for that character with "Queue for \<name>": it goes straight into their queue (they're told at their next login), and the materials they're short of go on the transfer list, so the characters holding them (you first) are told what to mail. In Recipe Search, clicking a recipe that only another of your characters knows opens it on that character. On another character's Enchanting, Disenchanting Mode lists the unbound gear in your bags and bank that you could mail them to disenchant, with what each may give and whether it's worth more sold or disenchanted. At an open mailbox, "Mail to \<name>" attaches the item to a mail to them and fills in their name. Each character's professions are saved at login, and a profession's categories the first time any of your characters opens it. The Overview title now names whose professions it shows, in class colour.
- Another player's or character's profession no longer shows craft, queue and track buttons that can't be used; a line says why instead.
- Transfer Planner: each "Send to" character has a Mail button. At an open mailbox it switches to Send Mail, fills in their name and attaches exactly what to send them from your bags, splitting stacks where needed. If it doesn't all fit in one mail, send it and click Mail again for the rest.
- Other characters' queues: a character picker in the title bar of the crafting queue and the Transfer Planner shows another of your characters' queue and plan, in both windows at once. Its queue can be edited (quantities, removing, reordering, clearing) but only crafted on that character, and the Transfer Planner shows who should send it what, so you know which characters to log into. Your own row there has the Mail button for your share, and the amounts you set per character are saved with that character's queue. Both windows go back to you when you open them again. Queueing for another character now also prints the whole plan in chat: what each character should send it and what no one has. With nothing queued on the character you're on, the Crafting Queue footer cell says how many other characters have crafts queued.
- Integrations options: an overview of the addons ProfessionsForever works with (whether each is installed and what it adds), and a page of its own for each, listed under Integrations: Auctionator, Polestar & TomTom, Questie, Syndicator, SkillUp Forever and EllesmereUI. A setting is greyed out when its addon isn't installed.
  - Waypoints: says whether waypoints go to Polestar or TomTom, and which Polestar setting decides it.
  - Polestar: when a waypoint's route has more than one step (a flight, a boat, the Hearthstone), the steps are printed to chat. Can be turned off.
  - Switches to stop using Auctionator's prices, Questie's NPC database or Syndicator's inventory data (needs a UI reload) while keeping those addons installed, and to hide the Skill Up Route cell from the footer.
- Mail now counts as a third place your items can be, beside bags and bank. What waits in a character's mailbox is counted as that character's: it is read whenever you open a mailbox, and anything you mail to another of your characters is added to theirs straight away. Items in the mail are not asked for again in the Transfer Planner and do not go on the shopping list, including auction house purchases you have not collected yet. They can't be crafted with until collected, so the crafting queue marks recipes waiting on them (pink "!"), reagent cards show "N in mail", the recipe panel says when the missing materials are waiting in the mailbox, and the Transfer Planner has a "Collect from Your Mailbox" section, opens at a mailbox when there is something to collect, and has a Collect from Mailbox button that takes what the queue needs from the open mailbox (whole stacks, never cash-on-delivery mail). Viewing another character's plan, it shows what waits in their mailbox, so you can see why nothing more needs sending. With Syndicator, every character's mailbox comes from its data, and so does the bank of the character you are on, so both are known before this addon has seen them. Cash-on-delivery mail is not counted.

### Changed
- The transfer planner, when it opened by itself at a mailbox or bank, now closes again when you close the mailbox or bank. If you had it open already, or pin it while it's open, it stays.
- With the main window closed, the transfer planner (and any other docked window) now docks beside the open mailbox or bank (EllesmereUI's bank window too) instead of sitting where the main window would be. Opening the main window there moves them back beside it.
- The shopping list is now shared by all your characters of the same faction by default (the Account-Wide option; your Horde and Alliance characters each have their own list, since items can't be mailed across). Existing lists move over by themselves: each character's own list is added into the shared one the next time you log in to that character (items you lowered below what a queue needs aren't carried over). You can still switch back to one list per character under Options, General, Shopping List Scope, and that choice is kept.
- The crafting queue, transfer planner and shopping list each have the same row of three buttons, Crafting Queue, Transfer Planner and Shopping List, in place of the single "Open ..." button. A button is lit while its window is open, and clicking it opens or closes that window. In the shopping list the row sits between the item search and Reset to Queue, and the list shows one row fewer to make room. The crafting queue, transfer planner, shopping list, cooldowns, Skill Up Route and Recipe Search windows are now all the same width (the shopping list is a little narrower, its queue and planner neighbours a little wider).
- Unlearned recipes in the crafting queue are now marked: grey with a star and a greyed icon, a "Not Learned" tooltip, and a status line saying how many are not learned yet. Crafting the queue skips them at once and says so, instead of waiting and stopping with "Crafting did not start". They can still be queued to plan and shop for their materials, and the Queue button says so on an unlearned recipe.
- New option under General: Open the Transfer Planner at a Mailbox (on by default, as before). Turn it off to stop the planner opening by itself when you have something to send.
- Only profession trainers are remembered now; other trainer windows are ignored.
- The nearest-trainer waypoint no longer guesses a trainer's ranks from its title (a "Superior Cook" is a title, not a rank, and some trainers have none). It now uses which ranks each trainer actually teaches: the list that ships with the addon, corrected by what trainers offer you in game. Each time you open a profession trainer, the addon notes whether it offers your next rank, and a trainer seen not to offer it is no longer suggested for it. Trainers nothing is known about are only suggested when no known one teaches the rank.
- The Overview's rank names are limited to Forever's four ranks: Apprentice, Journeyman, Expert and Artisan.
- The remove-character tooltip under Options now says everything it removes (inventory, queue, cooldowns and professions), and the waypoint hint on unlearned recipes no longer names TomTom when Polestar is the navigator.
- Shorter, more consistent wording in several tooltips and messages: "other characters" instead of "alts" in sentences, one way of saying "log in on", "withdraw from bank" throughout, "recipes skipped" instead of "entries skipped" when the queue skips crafts, and tighter Mail, Queue All and price tooltips.
- The footer cells and quick buttons now show everything in their window when you hover them: the crafting queue's recipes with their icons (red when short, blue when in the bank), what it is missing, and each other character's queued crafts; every character's cooldowns with ready or time left; who sends you what, what you send, what is in the mail to you and what no one has; each item to buy with its cost and the total; and the next step of each profession on the Skill Up Route.
- The Transfer Planner's buttons now follow the crafting queue's layout: a status line, the window buttons across the width, and Refresh and Withdraw from Bank below them. The crafting queue's Plan Materials button is gone; its Transfer Planner window button does the same.
- The shopping list now follows the crafting queues by itself: what a queue is short of is added, and shrinks or goes away as the queue changes or other characters cover it. With the Account-Wide list it covers the queues of all your characters of the same faction, so another character's shortage shows wherever you are. Quantities you change are kept as your own change on top (a row's tooltip shows both), and an item you remove or lower stays that way until a queue needs more of it. The Add Missing to Shopping List buttons are gone (crafting queue, Transfer Planner and recipe panel): queue a recipe to shop for it, and the red missing-materials banner now opens the shopping list; Recalculate in the shopping list is now Reset to Queue, which undoes your changes to the queues' items. Items you added yourself are never touched.
- The profession spell buttons (Disenchant, Find Minerals, Find Herbs, Find Fish, Bait and Tackle) now have the same skinned border as the other icon buttons.
- Waypoints to trainers, vendors, bankers and Artisan quest givers now say which zone the NPC is in, in the chat message and the waypoint title ("Betty Quin in Stormwind City"). NPCs you open are saved with the zone the game shows where they stand, so Vanessa Sellers reads "City of Dalaran" instead of Questie's "Alterac Mountains" once you've opened her.
- Trainers, vendors and bankers you've opened, and the ones shipped with the addon, now take priority over Questie's position for the same NPC, so each NPC is offered once.
- Recorded trainers, vendors and bankers now note the addon version and WoW build that recorded them.
- Trainers, vendors and bankers you open are now saved where you stand, and updated on every visit, so an NPC that moved or that Questie places wrong is corrected. A vendor's saved stock keeps items seen on earlier visits, so limited-supply items that were sold out are not forgotten.
- The Alt Inventory options moved to the new Integrations page.
- ProfessionsForever is now licensed under the GNU General Public License, version 3. Credits for the data it uses are in the options About page and README.
- Unlearned recipes now show the profession skill you need to learn them ("Requires skill 150", green once you have it, red until then) in the recipe panel and the recipe list tooltip. This includes recipes taught by a pattern, plan or schematic, such as Green Firework (Engineering 150).
- The craftable counter tiles now show their text in their colour, so they work as a legend.
- The Font option also lists the fonts that other addons have registered with LibSharedMedia.
- Scroll bars are now thin and smooth with or without EllesmereUI.
- Removed leftover Retail-only code.
- The crafting queue goes on to the next recipe of the open profession when you click the game world, instead of needing the Craft Queue button. A banner in the Queue panel (or a chat message if the panel is closed) says when it is waiting. Switching to another profession still needs a click on Craft Queue.
- Crafting queue rows now highlight under the mouse, like the rows in the other windows.
- The Clear Waypoint button in the title bar now has a tooltip saying what it does.
- What each character should mail the others now always follows the crafting queues: change or clear a queue and the "Send to" lists on your other characters follow straight away, so a cleared queue no longer leaves old requests behind. The Publish button in the Transfer Planner is gone, as there is nothing to publish any more. Items you mail are counted as on their way, so they aren't asked for again, until the recipient visits its mailbox. Old saved requests are cleared once and worked out again from the queues.
- The amounts you choose per character in the Transfer Planner are now saved with that character's queue, so planning its queue from another character uses the same choices.

### Fixed
- An Enchanting recipe that needs a Runed Copper Rod said the rod was missing, and its Enchant button stayed off, when you carry a better rod such as the Runed Silver Rod, which the game accepts instead. Requirements the game says are met now count as met, whichever item meets them.
- With only part of the materials, running the crafting queue could spend a shared material on the early steps and leave the final recipe short (all your Copper Bars made into bolts, none left for the Copper Modulators that also need a bar). The queue now makes only the intermediate crafts the later recipes can use with what you have, and says when it holds one back.
- The recipe you last clicked in a profession wasn't always selected again: after logging in or reloading, the first recipe in the list could be selected instead. The remembered recipe now comes back once the profession has finished loading.
- Stopping the crafting queue mid-craft (Stop Queue or Stop Craft) could say "Crafting interrupted.", then start the queue again, and the craft that finished afterwards wasn't counted off the queue, so it looked like one more was needed. Stop Queue now stops, Stop Craft moves on to the next recipe, and a craft that still completes is counted.
- Docked windows (crafting queue, transfer planner, shopping list, cooldowns, Skill Up Route, Recipe Search) could run off the bottom or right of the screen at a larger UI scale or on a smaller screen. They now always stay on screen: when two stacked windows don't fit below the main window, both get shorter and their lists show fewer rows, and when there is no room left beside the main window, a window docks over its right side instead, and stays on top of the main window. Moving or resizing the main window, or changing the UI scale, rearranges them. A window you drag away or pin keeps its full height.
- Prices didn't update after an Auctionator scan until something else redrew the window. Recipe profit, the queue, the shopping list and Disenchanting Mode's values, best choice, Best Value sort and Worth Disenchanting Only filter now update as soon as a scan or search finishes.
- With the EllesmereUI skin, the recipe list's search box started a few pixels right of the boxes under it. It now lines up in every skin.
- The blinking cursor in an empty search box sat on top of the first letter of the grey hint text ("Search...", Reagent Search, and the shopping list's "Item ID / link / name"). The hint now starts just after the cursor.
- The recipe list's Filters button lost its highlight (shown while a filter is on) as soon as the mouse moved over it and away. It now stays lit, with a faint fill, until the filters are back to their defaults.
- A recipe from a profession you dropped and learned again could still be offered as a way to craft a missing reagent. Only recipes you know now are used.
- Removing a character under Options while the main window showed that character's professions or Overview caused an error on every refresh. The window now goes back to your own Overview.
- A character you removed and later logged in on again stayed empty with Syndicator installed. Logging in on it now brings it back.
- The shopping list window did not update as you bought or looted items while the main window was closed (opened from the quick buttons, `/pf shop` or pinned). It now follows your bags and bank on its own.
- With Syndicator: a character whose inventory you hid in Syndicator was still counted, from an old snapshot taken before Syndicator was in use. Hidden characters now count as holding nothing.
- A queued recipe was marked as missing a material you had in your bags when a recipe further down the queue makes that same material.
- Opening a profession for the first time in a session while in combat (from an action bar) no longer gives an "action blocked" message.
- Opening a profession could raise a Lua error ("attempt to compare a secret number value") while reading recipe cooldowns.
- Fixed the trainer waypoint for a profession you haven't learned yet going to a far-off trainer (such as Vanessa Sellers in Hillsbrad Foothills from Stormwind) instead of the nearest one. It now looks for an Apprentice trainer, so you get the nearest Journeyman trainer (such as Betty Quin) or "\<Profession> Trainer". Trainers are now only picked when they can teach the rank you need: Journeyman trainers also teach Apprentice, "\<Profession> Trainer" titles teach up to Expert, and Artisan needs an Artisan trainer. When none is known it says so instead of sending you to one who can't teach you.
- Fixed every character appearing twice in the alt lists on WoW: Forever when Syndicator is installed, once with its surname and once without. ProfessionsForever now names characters the way Syndicator does (first name, surname and ruleset), so the two records are one. Each character's old record is merged into it the next time that character logs in. This also fixes alts never seeing the "Send to" list the crafter published for them.
- Fixed crafting queue rows showing no warning when a tool or other requirement (such as Flint and Tinder) is missing. The row now gets the red "!" and its tooltip lists what is missing. The game only gives the requirements of the open profession, so rows for other professions show it once that profession is opened.
- Fixed profession links in chat opening the default professions window.
- Fixed dragging the Fishing card to an action bar picking up nothing, again. Cards now pick up spells the way Blizzard's profession book does.
- Fixed dropdown lists being see-through in the Minimal skin, which made them hard to read. They now have a solid background in every skin.
- Fixed the Transfer Planner footer cell and quick button saying "No transfers needed" when this character has items to mail to another one, such as after queueing a recipe for an alt that needs your materials. They now show "Send N item types to N character(s)", and update as soon as you queue or mail.

## 0.9.4

### Added
- Recipe chaining. When a recipe is short only of reagents you can craft, the recipe panel says it is craftable after crafting them, and Add to Queue queues those crafts first, in order, in whichever profession makes them. Needs each profession to have been opened once so its recipes are known.
- Queue materials that earlier queue entries make no longer count as missing.
- Queue rows with materials that are only in the bank are marked, and their tooltip lists what to fetch.
- The Transfer Planner has a "Withdraw from Your Bank" section for what the queue needs from your own bank, and a Withdraw from Bank button that moves it into your bags while the bank is open. An option (on by default) opens the planner when you open your bank and the queue needs something from it.

### Changed
- The X in the search box now clears only the search. A new X beside the Filters dropdown resets the category and filters.
- The shopping list's item box has an X to clear the text.
- Profession tabs in the recipe window show a tooltip sooner, with your skill level.
- The crafting queue skips a recipe whose tool or station (an anvil, a forge) is missing and moves on to the next one.
- Switching away from the EllesmereUI skin now asks if you want to reload the UI.
- The shopping list's item search now covers every tradeable item in the game, not just recipe reagents.

### Fixed
- Opening a profession for the first time in a session while in combat (from an action bar) no longer gives an "action blocked" message.
- Fixed an "action blocked" error when pressing Escape in combat. The main window, Queue panel and unpinned side panels now close when combat starts.

## 0.9.3

### Added
- Fishing card buttons for Bait and Tackle and Find Fish.

### Fixed
- Opening a profession for the first time in a session while in combat (from an action bar) no longer gives an "action blocked" message.
- Fixed an issue where the Fishing card cast the pole instead of opening the Fishing crafting window.
- Dragging the Fishing card to an action bar picks up the Fishing spell.

## 0.9.2

### Added
- Queue All button: queues as many crafts of the selected recipe as your bags allow.

### Changed
- The Qty box counts down while crafting and resets when the batch ends, the window closes, or you switch tab or profession.
- First Aid skill bar is now red.
- Overview profession icons highlight on hover.

### Fixed
- Opening a profession for the first time in a session while in combat (from an action bar) no longer gives an "action blocked" message.
- Fixed an issue where the incorrect profession was opening.
- Dragging spell buttons and profession cards to an action bar no longer casts the spell.

### Notes
- The window can't be opened, closed or switched between overview and recipes in combat.

## 0.9.1

### Added
- Tracking spell buttons for Mining (Find Minerals), Herbalism (Find Herbs) and Fishing (Find Fish), like the Disenchant button. They appear on the profession's card in the overview and in the recipe window header, and can be dragged to an action bar.

### Changed
- Questie-based vendor lookups no longer build an index of every NPC; they search for the one vendor needed. Recipe and trainer indexes keep only the names they can match, which uses far less memory.
- New addon icon.

### Fixed
- Opening a profession for the first time in a session while in combat (from an action bar) no longer gives an "action blocked" message.
- Overview cards with a spell button caused an "action blocked" error when the overview refreshed during combat.
