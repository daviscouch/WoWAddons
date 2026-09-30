package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local T = require("check")

-- Fake WoW Forever talent tree built from the real capture. Tiers unlock every 5 points spent in that tree.
local FIXTURE = dofile("tests/forever_hunter_tree_full.lua")
local tree = { unspent = 0, nodes = {}, order = {} }
local names = {}
local function treeOf(x) return x < 4000 and "BM" or (x < 8000 and "MM" or "SV") end
local tiers = {}
for _, n in ipairs(FIXTURE) do
  local t = treeOf(n[2])
  tiers[t] = tiers[t] or {}
  tiers[t][n[3]] = true
end
local tierIndex = {}
for t, ys in pairs(tiers) do
  local sorted = {}
  for y in pairs(ys) do sorted[#sorted + 1] = y end
  table.sort(sorted)
  tierIndex[t] = {}
  for i, y in ipairs(sorted) do tierIndex[t][y] = i - 1 end
end
local function reset(ranks)   -- ranks: nil = the real capture, {} = fresh, or { name = rank }
  tree.nodes, tree.order = {}, {}
  for _, n in ipairs(FIXTURE) do
    local rank = n[4]
    if ranks then rank = ranks[n[7]] or 0 end
    tree.nodes[n[1]] = { id = n[1], x = n[2], y = n[3], rank = rank, max = n[5], name = n[7], tree = treeOf(n[2]) }
    tree.order[#tree.order + 1] = n[1]
    names[n[1]] = n[7]
  end
end
local function spentIn(t)
  local s = 0
  for _, n in pairs(tree.nodes) do if n.tree == t then s = s + n.rank end end
  return s
end
local function available(n) return spentIn(n.tree) >= 5 * tierIndex[n.tree][n.y] end

C_Spell = { GetSpellName = function(id) return names[id] end }
C_ClassTalents = { GetActiveConfigID = function() return 539272 end, CommitConfig = function() return true end }
C_Traits = {
  GetConfigInfo = function() return { ID = 539272, treeIDs = { 1091 } } end,
  GetTreeNodes = function() return tree.order end,
  GetNodeInfo = function(_, id)
    local n = tree.nodes[id]
    local open = available(n)
    return { ID = id, posX = n.x, posY = n.y, currentRank = n.rank, maxRanks = n.max, ranksPurchased = n.rank,
             isVisible = true, isAvailable = open, meetsEdgeRequirements = true,
             canPurchaseRank = open and n.rank < n.max, entryIDs = { id } }
  end,
  GetEntryInfo = function(_, entryID) return { definitionID = entryID } end,
  GetDefinitionInfo = function(defID) return { spellID = defID } end,
  GetTreeCurrencyInfo = function() return { { quantity = tree.unspent } } end,
  PurchaseRank = function(_, id)
    local n = tree.nodes[id]
    if tree.unspent <= 0 or not available(n) or n.rank >= n.max then return false end
    n.rank, tree.unspent = n.rank + 1, tree.unspent - 1
    return true
  end,
}
function GetSpellInfo() end

dofile("TalentGuide/Builds.lua")
dofile("TalentGuide/TalentGuide.lua")
local SLASH = SlashCmdList.TALENTGUIDE
local panel = _G.TalentGuidePanel
local function strip(s) return (tostring(s):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function update(event) M.fire(event or "TRAIT_CONFIG_UPDATED") M.flush() end
local function rankOf(name) for _, n in pairs(tree.nodes) do if n.name == name then return n.rank end end end

reset()
M.fire("PLAYER_LOGIN") M.flush()
T.ok("no unspent points: panel hidden", not panel:IsShown())

tree.unspent = 1
update("PLAYER_LEVEL_UP")
T.ok("level up with a point: panel shows the next talent", panel:IsShown() and strip(panel.line:GetText()) == "Next: Deadly Aspects 5/5",
     strip(panel.line:GetText()))
T.ok("...with the build name and step", strip(panel.sub:GetText()) == "Beast Mastery (leveling) - step 1 of 18", strip(panel.sub:GetText()))
T.ok("...and Learn enabled", panel.learn:IsEnabled())

M.clearPrinted()
panel.learn:Click()
M.flush()
T.ok("Learn buys the rank and commits", rankOf("Deadly Aspects") == 5 and tree.unspent == 0
     and M.printedText():find("Learned Deadly Aspects 5/5", 1, true), M.printedText())
T.ok("panel hides when no points are left", not panel:IsShown())

tree.unspent = 1
update()
T.ok("next point: skips finished steps (your 2 Focused Fire / 2 Pathfinding / 1 Endurance Training)",
     strip(panel.line:GetText()) == "Next: Unleashed Fury 2/5", strip(panel.line:GetText()))

-- Close (snooze) until another point arrives
panel.close:Click()
update()
T.ok("closing hides it while the point count is the same", not panel:IsShown())
tree.unspent = 2
update()
T.ok("...and it comes back when you get another point", panel:IsShown())
tree.unspent = 1

-- Combat
M.state.combat = true
M.clearPrinted()
SLASH("learn")
T.ok("won't learn in combat", rankOf("Unleashed Fury") == 1 and M.printedText():find("in combat", 1, true), M.printedText())
M.state.combat = false

-- Fresh character
reset({})
tree.unspent = 1
update()
T.ok("fresh tree: first talent of the build", strip(panel.line:GetText()) == "Next: Deadly Aspects 1/5", strip(panel.line:GetText()))

-- Import a build whose first step is locked: learn something from the next steps meanwhile
M.clearPrinted()
SLASH("import TG1;HUNTER;Wrath First;Frenzy:5,Deadly Aspects:5,Bestial Wrath:1")
T.ok("import a shared build", M.printedText():find('Imported "Wrath First" (3 steps)', 1, true), M.printedText())
SLASH("use 2")
update()
T.ok("locked first step: suggests the next learnable one", strip(panel.line:GetText()) == "Next: Deadly Aspects 1/5"
     and strip(panel.sub:GetText()):find("Frenzy 1/5 unlocks later", 1, true), strip(panel.line:GetText()) .. " | " .. strip(panel.sub:GetText()))

SLASH("import TG1;HUNTER;Far;Frenzy:5,Bestial Wrath:1,Intimidation:1,Ferocity:5,Unleashed Fury:5,Deadly Aspects:5")
SLASH("use 3")
update()
T.ok("doesn't jump far ahead in the build: Learn disabled", panel:IsShown() and not panel.learn:IsEnabled())

M.clearPrinted()
SLASH("import TG1;MAGE;Frost;Frostbolt:5")
T.ok("rejects another class's build", M.printedText():find("That build is for MAGE", 1, true), M.printedText())
SLASH("import TG1;HUNTER;Typo;Deadly Aspecs:5,Deadly Aspects:5")
M.clearPrinted()
SLASH("use 4")
SLASH("")
T.ok("warns about talents not in your tree", M.printedText():find("aren't in your tree: Deadly Aspecs", 1, true), M.printedText())

-- Save / export round trip
reset()
SLASH("use 1")
M.clearPrinted()
SLASH("save My Hunter")
T.ok("save a snapshot of your talents", M.printedText():find('Saved "My Hunter" (6 talents)', 1, true), M.printedText())
M.clearPrinted()
SLASH("builds")
T.ok("/tg builds lists built-in and yours", M.printedText():find("1. Beast Mastery (leveling)", 1, true)
     and M.printedText():find("My Hunter (yours)", 1, true), M.printedText())
SLASH("use 5")
SLASH("export")
local exported = _G.TalentGuideCopy and _G.TalentGuideCopy.edit:GetText()
T.ok("export: top tier first", exported and exported:find("^TG1;HUNTER;My Hunter;Deadly Aspects:4,Endurance Training:1,"), tostring(exported))
SLASH("delete 5")
SLASH("import " .. exported)
M.clearPrinted()
SLASH("builds")
T.ok("delete, then import the exported string", M.printedText():find("My Hunter (yours)", 1, true), M.printedText())

-- Other commands don't error
M.clearPrinted()
local ok = pcall(SLASH, "show") and pcall(SLASH, "debug") and pcall(SLASH, "help")
T.ok("show/debug/help run", ok and M.printedText():find("Talent tree: config 539272, 52 talents", 1, true), M.printedText())

T.done()
