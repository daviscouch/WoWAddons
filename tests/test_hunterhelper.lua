package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local T = require("check")

M.items = {
  [2504] = { name = "Worn Shortbow", quality = 1, classID = 2, subID = 2, equipLoc = "INVTYPE_RANGED" },
  [2508] = { name = "Old Blunderbuss", quality = 1, classID = 2, subID = 3, equipLoc = "INVTYPE_RANGEDRIGHT" },
  [2512] = { name = "Rough Arrow", quality = 1, classID = 6, subID = 2 },
  [2516] = { name = "Light Shot", quality = 1, classID = 6, subID = 3 },
  [117] = { name = "Tough Jerky", quality = 1, classID = 0, subID = 5, level = 5 },
  [2287] = { name = "Haunch of Meat", quality = 1, classID = 0, subID = 5, level = 15 },
  [4540] = { name = "Tough Hunk of Bread", quality = 1, classID = 0, subID = 5, level = 5 },
  [99001] = { name = "Skyborne Venison Strip", quality = 1, classID = 0, subID = 5, level = 20 },  -- not in table: keyword
  [99002] = { name = "Refreshing Spring Water", quality = 1, classID = 0, subID = 5, level = 5 },
}

-- Spells and auras
local SPELLS = { [6991] = "Feed Pet", [883] = "Call Pet", [13165] = "Aspect of the Hawk", [13163] = "Aspect of the Monkey" }
local known = { [6991] = true, [883] = true, [13165] = true, [13163] = true }
C_Spell = { GetSpellName = function(id) return SPELLS[id] end }
function IsPlayerSpell(id) return known[id] == true end
local buffs = { player = {}, pet = {} }
C_UnitAuras = { GetAuraDataByIndex = function(unit, i) local n = buffs[unit] and buffs[unit][i] return n and { name = n } end }

-- Pet
local pet = { exists = true, dead = false, happiness = 3, diet = { "Meat", "Fish" } }
function UnitExists(u) return u == "pet" and pet.exists end
function UnitIsDead(u) return u == "pet" and pet.dead end
function GetPetHappiness() return pet.happiness end
function GetPetFoodTypes() return table.unpack(pet.diet) end

-- Merchant
local merchant = {}
function GetMerchantNumItems() return #merchant end
function GetMerchantItemLink(i) return merchant[i] and M.link(merchant[i]) end

dofile("HunterHelper/Foods.lua")
dofile("HunterHelper/HunterHelper.lua")
local SLASH = SlashCmdList.HUNTERHELPER
local box, feed = _G.HunterHelperAlerts, _G.HunterHelperFeedButton

M.fire("PLAYER_LOGIN")
local function refresh() M.fire("BAG_UPDATE_DELAYED") M.flush() end
local function alerts()
  local out = {}
  if not box:IsShown() then return "" end
  for _, fs in ipairs(box.lines) do
    if fs:IsShown() then out[#out + 1] = (fs:GetText():gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
  end
  return table.concat(out, " / ")
end

-- Baseline: bow, plenty of arrows, happy pet, Aspect on -> nothing shown
M.equipped = { [18] = 2504 }
buffs.player = { "Aspect of the Hawk" }
M.setBags({ [0] = { [1] = { id = 2512, count = 200 }, [2] = { id = 2512, count = 200 } } })
refresh()
T.ok("all good: no alerts", alerts() == "", alerts())
T.ok("loaded message only for Hunters", M.printedText():find("HunterHelper:|r loaded", 1, true))

-- Ammo
M.setBags({ [0] = { [1] = { id = 2512, count = 83 } } })
refresh()
T.ok("low ammo warning", alerts() == "Low ammo: 83 arrows", alerts())
M.setBags({ [0] = {} })
local sounds = M.sounds or 0
refresh()
T.ok("out of ammo warning", alerts() == "Out of arrows!", alerts())
T.ok("out of ammo plays a warning sound once", (M.sounds or 0) == sounds + 1)
refresh()
T.ok("...and not again while it stays the same", (M.sounds or 0) == sounds + 1)
M.equipped = { [18] = 2508 }
M.setBags({ [0] = { [1] = { id = 2512, count = 500 }, [2] = { id = 2516, count = 40 } } })
refresh()
T.ok("gun counts bullets, not arrows", alerts() == "Low ammo: 40 bullets", alerts())
M.equipped = { [18] = 2504 }
M.setBags({ [0] = { [1] = { id = 2512, count = 500 } } })
M.state.resting = true
refresh()
T.ok("in town: stock-up reminder below the target", alerts():find("Stock up: 500 arrows (aim for 1000)", 1, true), alerts())
M.clearPrinted()
M.state.resting = false
M.fire("PLAYER_UPDATE_RESTING")
M.flush()
T.ok("leaving town short on ammo: warning", alerts():find("Leaving town with only 500 arrows!", 1, true)
     and M.printedText():find("Leaving town with only 500 arrows", 1, true), alerts())
M.state.time = 2000
refresh()
T.ok("...which fades after 10 seconds", alerts() == "", alerts())

-- Vendor tip
M.state.resting = true
merchant = { 4540, 2512 }
M.clearPrinted()
M.fire("MERCHANT_SHOW")
M.flush()
T.ok("vendor that sells your ammo: tells you how many to buy",
     M.printedText():find("sells [^\n]*Rough Arrow[^\n]*You have 500 arrows %- buy 500 more"), M.printedText())
M.state.resting = false
M.setBags({ [0] = { [1] = { id = 2512, count = 1000 } } })

-- Pet
pet.happiness = 2
M.setBags({ [0] = { [1] = { id = 2512, count = 1000 }, [2] = { id = 117, count = 5 }, [3] = { id = 2287, count = 2 },
                    [4] = { id = 4540, count = 10 }, [5] = { id = 99002, count = 5 } } })
refresh()
T.ok("content pet: feed reminder", alerts() == "Your pet is Content - feed it", alerts())
T.ok("Feed button shown with the best food (highest level it eats)",
     feed:IsShown() and feed:GetAttribute("macrotext") == "/cast Feed Pet\n/use 0 3", tostring(feed:GetAttribute("macrotext")))
M.setBags({ [0] = { [1] = { id = 2512, count = 1000 }, [2] = { id = 99001, count = 3 } } })
refresh()
T.ok("food not in the table is recognised by name (Venison -> Meat)", feed:GetAttribute("macrotext") == "/cast Feed Pet\n/use 0 2",
     tostring(feed:GetAttribute("macrotext")))
pet.happiness = 1
M.setBags({ [0] = { [1] = { id = 2512, count = 1000 }, [2] = { id = 4540, count = 10 } } })
refresh()
T.ok("unhappy pet, no food it eats: says so with its diet",
     alerts() == "Your pet is Unhappy - no food it eats in your bags (Fish, Meat)", alerts())
T.ok("no Feed button when there's no food", not feed:IsShown())
M.setBags({ [0] = { [1] = { id = 2512, count = 1000 }, [2] = { id = 117, count = 5 } } })
M.state.combat = true
refresh()
T.ok("in combat the (secure) Feed button isn't changed", not feed:IsShown())
M.state.combat = false
refresh()
T.ok("after combat it updates", feed:IsShown())
buffs.pet = { "Feed Pet Effect" }
refresh()
T.ok("while eating: 'eating' instead of a reminder", alerts() == "Your pet is eating...", alerts())
buffs.pet = {}
pet.happiness = 3
pet.dead = true
refresh()
T.ok("dead pet", alerts() == "Your pet is dead - Revive Pet", alerts())
pet.dead, pet.exists = false, false
refresh()
T.ok("no pet out", alerts() == "No pet out", alerts())
SLASH("nopet")
refresh()
T.ok("/hh nopet turns that off", alerts() == "", alerts())
pet.exists = true

-- Aspect
buffs.player = {}
refresh()
T.ok("no Aspect active", alerts() == "No Aspect active", alerts())
M.state.resting = true
refresh()
T.ok("...but not while resting in town", alerts() == "", alerts())
M.state.resting = false
C_UnitAuras.GetAuraDataByIndex = function() error("secret in combat") end
refresh()
T.ok("buffs unreadable (combat restrictions): no false alarm", alerts() == "", alerts())
C_UnitAuras.GetAuraDataByIndex = function(unit, i) local n = buffs[unit] and buffs[unit][i] return n and { name = n } end
buffs.player = { "Aspect of the Monkey" }
refresh()
T.ok("Aspect of the Monkey counts", alerts() == "", alerts())

-- WoW Forever: pet functions live in C_PetInfo (no globals), may return tables, and the game says what the pet eats
GetPetHappiness, GetPetFoodTypes = nil, nil
local forever = { happiness = { happiness = 1 } }
C_PetInfo = {
  GetPetHappiness = function() return forever.happiness end,
  GetPetFoodTypes = function() return { "Meat", "Fish" } end,
  CanPetEatItem = function(itemID) return itemID == 4540 end,   -- the game says: only the bread
}
buffs.player = { "Aspect of the Hawk" }
M.setBags({ [0] = { [1] = { id = 2512, count = 1000 }, [2] = { id = 2287, count = 2 }, [3] = { id = 4540, count = 4 } } })
refresh()
T.ok("Forever: C_PetInfo happiness (as a table) is read", alerts() == "Your pet is Unhappy - feed it", alerts())
T.ok("Forever: the game's CanPetEatItem wins over the food table", feed:IsShown() and feed:GetAttribute("macrotext") == "/cast Feed Pet\n/use 0 3",
     tostring(feed:GetAttribute("macrotext")))
forever.happiness = 3
refresh()
T.ok("Forever: happy pet, no reminder", alerts() == "", alerts())
C_PetInfo.CanPetEatItem = function() error("wants an ItemLocation") end
forever.happiness = 2
refresh()
T.ok("Forever: if CanPetEatItem errors, falls back to the food table (Haunch of Meat)",
     feed:GetAttribute("macrotext") == "/cast Feed Pet\n/use 0 2", tostring(feed:GetAttribute("macrotext")))
forever.happiness = 3

-- Commands
M.clearPrinted()
SLASH("low 300")
M.setBags({ [0] = { [1] = { id = 2512, count = 250 } } })
refresh()
T.ok("/hh low changes the threshold", alerts() == "Low ammo: 250 arrows", alerts())
SLASH("test")
T.ok("/hh test shows samples", alerts():find("Your pet is Unhappy - feed it", 1, true), alerts())
M.flush()
M.clearPrinted()
local ok = pcall(SLASH, "debug") and pcall(SLASH, "help") and pcall(SLASH, "") and pcall(SLASH, "unlock") and pcall(SLASH, "lock")
T.ok("debug/help/status/lock commands run", ok and M.printedText():find("ammo type: arrows, count: 250", 1, true), M.printedText())

T.done()
