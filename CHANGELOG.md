# Changelog

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
- Fixed an "action blocked" error when pressing Escape in combat. The main window, Queue panel and unpinned side panels now close when combat starts.

## 0.9.3

### Added
- Fishing card buttons for Bait and Tackle and Find Fish.

### Fixed
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
- Overview cards with a spell button caused an "action blocked" error when the overview refreshed during combat.
