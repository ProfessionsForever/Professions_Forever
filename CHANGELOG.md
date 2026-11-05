# Changelog

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
