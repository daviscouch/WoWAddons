# Davis's WoW Forever addons

| Addon | What it does | Command |
|---|---|---|
| **NeedIt** | NEED / GREED / PASS on gear tooltips, bag and vendor markers, roll hints | `/needit` |
| **HunterHelper** | Ammo, pet happiness and food (Feed button), and Aspect reminders | `/hh` |
| **TalentGuide** | Next talent in your build, with a Learn button | `/tg` |
| **TidyVendor** | Sells grey items and repairs at vendors (hold Shift to skip) | `/tv` |
| **CraftProfit** | Recipe cost vs auction house price and profit | `/cp` |

NeedIt has its own repo: https://github.com/daviscouch/NeedIt. To include it, clone it into this folder:

```
git clone https://github.com/daviscouch/NeedIt
```

## Install

Easiest: run `Update-Addons.ps1` (below). It installs everything in this folder into the game.

By hand: copy each addon folder (`HunterHelper`, `TalentGuide`, `TidyVendor`, `CraftProfit`) into
`World of Warcraft\_classic_beta_\Interface\AddOns\` (you don't need the `tests` folder), then restart the game.

## After a game patch ("Out of date" in the AddOns list)

Run the update script from this folder:

```
powershell -ExecutionPolicy Bypass -File .\Update-Addons.ps1
```

It reads the game version from `WowB.exe`, updates every addon's `## Interface:` number, runs the tests, and
installs all five into the game. Then restart the game.

- Different game folder (e.g. after Forever's full launch): `.\Update-Addons.ps1 -Game "_forever_"`
- Skip the tests: `-SkipTests`

If a patch changes how the game works (something breaks, not just "out of date"), ask Claude Code to
"update my WoW addons". Every addon has a `debug` command (`/needit debug`, `/hh debug`, `/tg debug`),
which is usually the first thing to check.

## Layout

- `<Addon>\` - the files the game loads (`.toc`, `.lua`)
- `tests\` - offline tests that fake the WoW API. From this folder: `lua tests\test_craftprofit.lua` etc.
  NeedIt's tests are in `NeedIt\tests\` (`lua tests\test_needit.lua NeedIt.lua` from the NeedIt folder).
- `tests\forever_hunter_tree_full.lua` - a real capture of WoW Forever's Hunter talent tree
- `Update-Addons.ps1` - version bump + test + install

## WoW Forever API notes (beta 1.60.1, interface 16001)

Forever runs Classic content on the modern (retail, Midnight 12.x "Camelot") addon API:

- Talents: no Classic talent-tab functions. One class-wide spec (e.g. "Hunter"). All three Classic trees are in
  one `C_Traits` tree side by side, and each talent's most common group ID says which tree it belongs to.
- Pets: `C_PetInfo.GetPetHappiness`, `C_PetInfo.GetPetFoodTypes` (returns a table), `C_PetInfo.CanPetEatItem(itemID)`.
- Professions: modern `C_TradeSkillUI` (`GetAllRecipeIDs`, `GetRecipeInfo`, `GetRecipeSchematic`).
- Auction house: modern `C_AuctionHouse` (`SendSearchQuery`, `ReplicateItems` full scan every 15 min).
- Vendors: `C_MerchantFrame.GetItemInfo` (no `GetMerchantItemInfo`).
- Ranged slot 18 and ammo still exist. Tooltips: `TooltipDataProcessor` and `C_TooltipInfo`.
