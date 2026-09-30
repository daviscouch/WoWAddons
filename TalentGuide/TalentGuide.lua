-- TalentGuide: follow a talent build. When you have a point to spend it shows the next talent in your
-- build, with a Learn button. Works with WoW Forever's single talent tree (C_ClassTalents / C_Traits).
TalentGuideDB = TalentGuideDB or {}

local function Say(msg) print("|cffffcc00TalentGuide:|r " .. msg) end
local function PlayerClass() return select(2, UnitClass("player")) end
local function CharKey() return (UnitName("player") or "?") .. "-" .. (GetRealmName() or "?") end
local function CharData()
  TalentGuideDB.chars = TalentGuideDB.chars or {}
  local key = CharKey()
  TalentGuideDB.chars[key] = TalentGuideDB.chars[key] or {}
  return TalentGuideDB.chars[key]
end

---------------------------------------------------------------------------
-- Reading the talent tree
---------------------------------------------------------------------------
local nameCache = {}   -- nodeID -> talent name (names never change)

local function call(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b = pcall(fn, ...)
  if ok then return a, b end
end

local function NodeName(configID, node)
  if nameCache[node.ID] then return nameCache[node.ID] end
  local TR = C_Traits
  local entryID = (node.activeEntry and node.activeEntry.entryID) or (node.entryIDs and node.entryIDs[1])
  local entry = entryID and call(TR.GetEntryInfo, configID, entryID)
  local def = type(entry) == "table" and entry.definitionID and call(TR.GetDefinitionInfo, entry.definitionID)
  local name
  if type(def) == "table" then
    name = def.overrideName
    if (not name or name == "") and def.spellID then
      name = (C_Spell and C_Spell.GetSpellName and call(C_Spell.GetSpellName, def.spellID))
          or (GetSpellInfo and call(GetSpellInfo, def.spellID))
    end
  end
  if type(name) == "string" and name ~= "" then nameCache[node.ID] = name end
  return name
end

-- Returns tree = { configID, treeID, unspent, nodes = { [lowercase name] = node info + name } } or nil
local function ReadTree()
  local CT, TR = C_ClassTalents, C_Traits
  if not (CT and TR and CT.GetActiveConfigID and TR.GetConfigInfo and TR.GetTreeNodes and TR.GetNodeInfo) then return end
  local configID = call(CT.GetActiveConfigID)
  if not configID then return end
  local cfg = call(TR.GetConfigInfo, configID)
  if type(cfg) ~= "table" or type(cfg.treeIDs) ~= "table" or not cfg.treeIDs[1] then return end
  local tree = { configID = configID, treeID = cfg.treeIDs[1], nodes = {}, unspent = 0, count = 0 }
  for _, treeID in ipairs(cfg.treeIDs) do
    for _, nodeID in ipairs(call(TR.GetTreeNodes, treeID) or {}) do
      local n = call(TR.GetNodeInfo, configID, nodeID)
      if type(n) == "table" and n.isVisible ~= false then
        local name = NodeName(configID, n)
        if name then
          n.name = name
          tree.count = tree.count + 1
          -- Some trees have two talents with the same name: keep the one with points in it, else the first
          local key, existing = name:lower(), tree.nodes[name:lower()]
          if not existing or ((n.currentRank or 0) > 0 and (existing.currentRank or 0) == 0) then tree.nodes[key] = n end
        end
      end
    end
    local currency = call(TR.GetTreeCurrencyInfo, configID, treeID, false)
    if type(currency) == "table" then
      for _, c in ipairs(currency) do tree.unspent = tree.unspent + (tonumber(c.quantity) or 0) end
    end
  end
  return tree
end

---------------------------------------------------------------------------
-- Builds
---------------------------------------------------------------------------
-- All builds for your class: built-in ones first, then yours. Each { name, steps, notes, custom }
local function Builds()
  local list = {}
  for _, b in ipairs((TalentGuideBuiltins or {})[PlayerClass()] or {}) do list[#list + 1] = b end
  for _, b in ipairs((TalentGuideDB.builds or {})) do
    if b.class == PlayerClass() then list[#list + 1] = { name = b.name, steps = b.steps, custom = true } end
  end
  return list
end

local function ActiveBuild()
  local list = Builds()
  local want = CharData().build
  for _, b in ipairs(list) do if b.name == want then return b end end
  return list[1]
end

local LOOKAHEAD = 4

-- Works out where the next point goes.
-- Returns next = { step, node, index } (first unfinished step), ready = the first unfinished step you can
-- learn right now (may be the same), missing = names in the build that aren't in your talent tree.
local function Plan(build, tree)
  local nextStep, ready, missing = nil, nil, {}
  for i, step in ipairs(build.steps) do
    local node = tree.nodes[step[1]:lower()]
    if not node then
      missing[#missing + 1] = step[1]
    elseif (node.currentRank or 0) < math.min(step[2], node.maxRanks or step[2]) then
      local s = { step = step, node = node, index = i }
      nextStep = nextStep or s
      -- If the next step is still locked, only look a few steps ahead for something to learn meanwhile,
      -- so the guide doesn't jump to the end of the build (e.g. into another tree)
      if i - nextStep.index > LOOKAHEAD then break end
      if not ready and node.canPurchaseRank and node.isAvailable ~= false and node.meetsEdgeRequirements ~= false then
        ready = s
      end
      if ready then break end
    end
  end
  return nextStep, ready, missing
end

local function StepText(s)
  local n = s.node
  return n.name .. " " .. ((n.currentRank or 0) + 1) .. "/" .. math.min(s.step[2], n.maxRanks or s.step[2])
end

---------------------------------------------------------------------------
-- Learning a point
---------------------------------------------------------------------------
local function Learn(s, tree)
  if InCombatLockdown and InCombatLockdown() then Say("Can't learn talents in combat.") return false end
  if not s or not tree then return false end
  if tree.unspent <= 0 then Say("You have no talent points to spend.") return false end
  local TR, CT = C_Traits, C_ClassTalents
  local ok, bought = pcall(TR.PurchaseRank, tree.configID, s.node.ID)
  if not ok or bought == false then
    Say("Couldn't learn " .. s.node.name .. " automatically - open your talents (N) and click it.")
    return false
  end
  local commit = (CT and CT.CommitConfig) or TR.CommitConfig
  local okC, committed = pcall(commit, tree.configID)
  if not okC or committed == false then
    Say("Couldn't save the talent change - open your talents (N) and click Apply.")
    return false
  end
  Say("Learned " .. StepText(s) .. ".")
  return true
end

---------------------------------------------------------------------------
-- UI: a small "next talent" panel that shows while you have points to spend
---------------------------------------------------------------------------
local panel = CreateFrame("Frame", "TalentGuidePanel", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
panel:SetSize(260, 74)
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:EnableMouse(true)
panel:RegisterForDrag("LeftButton")
panel:SetScript("OnDragStart", panel.StartMoving)
panel:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  TalentGuideDB.pos = { point, rel, x, y }
end)
if panel.SetBackdrop then
  panel:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                      tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  panel:SetBackdropColor(0, 0, 0, 0.8)
end
panel.title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
panel.title:SetPoint("TOPLEFT", 10, -9)
panel.line = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
panel.line:SetPoint("TOPLEFT", panel.title, "BOTTOMLEFT", 0, -5)
panel.line:SetWidth(170)
panel.line:SetJustifyH("LEFT")
panel.sub = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
panel.sub:SetPoint("TOPLEFT", panel.line, "BOTTOMLEFT", 0, -3)
panel.sub:SetWidth(240)
panel.sub:SetJustifyH("LEFT")
panel.learn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
panel.learn:SetSize(64, 22)
panel.learn:SetPoint("TOPRIGHT", -10, -24)
panel.learn:SetText("Learn")
panel.close = CreateFrame("Button", nil, panel, "UIPanelCloseButton")
panel.close:SetPoint("TOPRIGHT", 2, 2)
panel.close:SetScale(0.8)
panel:Hide()

local snoozedAt   -- unspent count when you closed the panel; reopens when you gain another point
panel.close:SetScript("OnClick", function()
  local tree = ReadTree()
  snoozedAt = tree and tree.unspent or 0
  panel:Hide()
end)
panel.learn:SetScript("OnEnter", function(self)
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Learn this talent")
  GameTooltip:AddLine("Talent points can only be taken back by resetting talents at a trainer.", 1, 1, 1, true)
  GameTooltip:Show()
end)
panel.learn:SetScript("OnLeave", function() GameTooltip:Hide() end)

local function PlacePanel()
  panel:ClearAllPoints()
  local p = TalentGuideDB.pos
  if p then panel:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else panel:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -240, -200) end
end

local function Refresh()
  local tree = ReadTree()
  local build = ActiveBuild()
  if not tree or not build or tree.unspent <= 0 then panel:Hide() snoozedAt = nil return end
  if snoozedAt and tree.unspent <= snoozedAt then return end
  snoozedAt = nil
  local nextStep, ready = Plan(build, tree)
  if not nextStep then panel:Hide() return end
  panel.title:SetText(tree.unspent .. " talent point" .. (tree.unspent == 1 and "" or "s") .. " to spend")
  local target = ready or nextStep
  panel.line:SetText("Next: |cffffffff" .. StepText(target) .. "|r")
  if ready and ready ~= nextStep then
    panel.sub:SetText(StepText(nextStep) .. " unlocks later - " .. build.name)
  else
    panel.sub:SetText(build.name .. " - step " .. target.index .. " of " .. #build.steps)
  end
  panel.learn:SetEnabled(ready ~= nil)
  panel.learn:SetScript("OnClick", function()
    if Learn(ready, tree) and C_Timer and C_Timer.After then C_Timer.After(0.5, Refresh) end
  end)
  panel:Show()
end

---------------------------------------------------------------------------
-- Saving, sharing and importing builds
---------------------------------------------------------------------------
local function SaveBuild(name, steps)
  TalentGuideDB.builds = TalentGuideDB.builds or {}
  for i, b in ipairs(TalentGuideDB.builds) do
    if b.class == PlayerClass() and b.name:lower() == name:lower() then table.remove(TalentGuideDB.builds, i) break end
  end
  table.insert(TalentGuideDB.builds, { class = PlayerClass(), name = name, steps = steps })
end

-- Snapshot of what you have now, ordered top of the tree to bottom (so earlier tiers come first)
local function Snapshot(tree)
  local nodes = {}
  for _, n in pairs(tree.nodes) do if (n.currentRank or 0) > 0 then nodes[#nodes + 1] = n end end
  table.sort(nodes, function(a, b)
    if (a.posY or 0) ~= (b.posY or 0) then return (a.posY or 0) < (b.posY or 0) end
    return (a.posX or 0) < (b.posX or 0)
  end)
  local steps = {}
  for _, n in ipairs(nodes) do steps[#steps + 1] = { n.name, n.currentRank } end
  return steps
end

-- "TG1;HUNTER;Build name;Deadly Aspects:5,Focused Fire:2,..."
local function Export(build)
  local parts = {}
  for _, s in ipairs(build.steps) do parts[#parts + 1] = s[1] .. ":" .. s[2] end
  return "TG1;" .. PlayerClass() .. ";" .. build.name .. ";" .. table.concat(parts, ",")
end

local function Import(text)
  local class, name, body = text:match("^%s*TG1;(%u+);([^;]+);(.+)$")
  if not class then return nil, "That doesn't look like a TalentGuide build (it should start with TG1;)." end
  if class ~= PlayerClass() then return nil, "That build is for " .. class .. "." end
  local steps = {}
  for talent, rank in body:gmatch("([^:,]+):(%d+)") do steps[#steps + 1] = { talent:match("^%s*(.-)%s*$"), tonumber(rank) } end
  if #steps == 0 then return nil, "No talents found in that build." end
  return name, steps
end

-- A copy box so exports can be copied with Ctrl+C
local copy
local function ShowCopy(text)
  if not copy then
    copy = CreateFrame("Frame", "TalentGuideCopy", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    copy:SetSize(420, 60)
    copy:SetPoint("CENTER")
    copy:SetFrameStrata("DIALOG")
    if copy.SetBackdrop then
      copy:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                         tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
      copy:SetBackdropColor(0, 0, 0, 0.9)
    end
    local label = copy:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 10, -8)
    label:SetText("Ctrl+C to copy, Esc to close")
    copy.edit = CreateFrame("EditBox", nil, copy, "InputBoxTemplate")
    copy.edit:SetSize(390, 20)
    copy.edit:SetPoint("BOTTOM", 0, 10)
    copy.edit:SetAutoFocus(true)
    copy.edit:SetScript("OnEscapePressed", function() copy:Hide() end)
  end
  copy.edit:SetText(text)
  copy.edit:HighlightText()
  copy:Show()
  copy.edit:SetFocus()
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function ShowBuild(build, tree)
  Say(build.name .. (build.custom and " (yours)" or "") .. ":")
  if build.notes then Say("|cffaaaaaa" .. build.notes .. "|r") end
  local nextStep = tree and Plan(build, tree)
  local lines, line = {}, {}
  for i, s in ipairs(build.steps) do
    local node = tree and tree.nodes[s[1]:lower()]
    local done = node and (node.currentRank or 0) >= math.min(s[2], node.maxRanks or s[2])
    local mark = (nextStep and nextStep.index == i) and "|cff33ff33> " or (done and "|cff777777" or "|cffffffff")
    line[#line + 1] = mark .. i .. ". " .. s[1] .. " " .. s[2] .. "|r"
    if #line == 3 then lines[#lines + 1] = table.concat(line, "   ") line = {} end
  end
  if #line > 0 then lines[#lines + 1] = table.concat(line, "   ") end
  for _, l in ipairs(lines) do Say(l) end
end

local function Help()
  Say("/tg - what's next  |  /tg show - the whole build  |  /tg builds - list builds")
  Say("/tg use <number> - pick a build  |  /tg learn - learn the next talent now")
  Say("/tg save <name> - save your current talents as a build (for alts or after a reset)")
  Say("/tg export - copy the build to share  |  /tg import <text> - add a shared build")
  Say("/tg delete <number> - delete one of your builds  |  /tg debug")
end

SLASH_TALENTGUIDE1 = "/tg"
SLASH_TALENTGUIDE2 = "/talentguide"
SlashCmdList["TALENTGUIDE"] = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.*)$")
  cmd = cmd:lower()
  local tree, build = ReadTree(), ActiveBuild()
  if cmd == "builds" then
    local list = Builds()
    if #list == 0 then Say("No builds for your class yet. Spend some points, then /tg save <name>, or /tg import.") return end
    for i, b in ipairs(list) do
      Say(i .. ". " .. b.name .. (b.custom and " (yours)" or "") .. (b == build and "  |cff33ff33<- using|r" or ""))
    end
  elseif cmd == "use" then
    local b = Builds()[tonumber(rest) or 0]
    if not b then Say("Pick a number from /tg builds.") return end
    CharData().build = b.name
    Say("Now following " .. b.name .. ".")
    snoozedAt = nil
    Refresh()
  elseif cmd == "show" then
    if not build then Say("No build selected. /tg builds") return end
    ShowBuild(build, tree)
  elseif cmd == "learn" then
    if not (tree and build) then Say("No talent tree or build found.") return end
    local _, ready = Plan(build, tree)
    if not ready then Say("Nothing in your build can be learned right now.") return end
    Learn(ready, tree)
  elseif cmd == "save" then
    if rest == "" then Say("Give it a name: /tg save My Build") return end
    if not tree then Say("Couldn't read your talents.") return end
    local steps = Snapshot(tree)
    if #steps == 0 then Say("You haven't spent any points yet.") return end
    SaveBuild(rest, steps)
    Say("Saved \"" .. rest .. "\" (" .. #steps .. " talents). /tg builds to pick it.")
  elseif cmd == "export" then
    if not build then Say("No build selected.") return end
    ShowCopy(Export(build))
  elseif cmd == "import" then
    local name, steps = Import(rest)
    if not name then Say(steps) return end
    SaveBuild(name, steps)
    Say("Imported \"" .. name .. "\" (" .. #steps .. " steps). /tg builds to pick it.")
  elseif cmd == "delete" then
    local b = Builds()[tonumber(rest) or 0]
    if not (b and b.custom) then Say("Pick one of your own builds from /tg builds.") return end
    for i, saved in ipairs(TalentGuideDB.builds or {}) do
      if saved.class == PlayerClass() and saved.name == b.name then table.remove(TalentGuideDB.builds, i) break end
    end
    Say("Deleted " .. b.name .. ".")
  elseif cmd == "debug" then
    Say("Talent tree: " .. (tree and ("config " .. tostring(tree.configID) .. ", " .. tree.count .. " talents, " .. tree.unspent .. " unspent") or "not found"))
    Say("Build: " .. tostring(build and build.name))
    if tree and build then
      local nextStep, ready, missing = Plan(build, tree)
      Say("Next: " .. tostring(nextStep and StepText(nextStep)) .. ", can learn now: " .. tostring(ready and StepText(ready)))
      if #missing > 0 then Say("Not found in your tree: " .. table.concat(missing, ", ")) end
    end
  elseif cmd == "help" or cmd == "?" then
    Help()
  else
    if not tree then Say("Couldn't read your talent tree.") return end
    if not build then Say("No build for your class. /tg help") return end
    local nextStep, ready, missing = Plan(build, tree)
    if not nextStep then Say("You've finished " .. build.name .. "!") return end
    Say(tree.unspent .. " point" .. (tree.unspent == 1 and "" or "s") .. " to spend. Next in " .. build.name .. ": "
        .. StepText(ready or nextStep) .. ((ready and ready ~= nextStep) and (" (" .. StepText(nextStep) .. " unlocks later)") or ""))
    if #missing > 0 then Say("|cffff9933These talents in the build aren't in your tree: " .. table.concat(missing, ", ") .. "|r") end
    snoozedAt = nil
    Refresh()
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
for _, ev in ipairs({ "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "TRAIT_CONFIG_UPDATED",
                      "TRAIT_TREE_CURRENCY_INFO_UPDATED", "TRAIT_NODE_CHANGED", "PLAYER_REGEN_ENABLED" }) do
  pcall(f.RegisterEvent, f, ev)
end
local pending = false
f:SetScript("OnEvent", function(_, event)
  if event == "PLAYER_LOGIN" then
    TalentGuideDB = TalentGuideDB or {}
    PlacePanel()
  end
  if pending then return end
  pending = true
  -- Talent data can lag a moment behind the event
  local function run() pending = false pcall(Refresh) end
  if C_Timer and C_Timer.After then C_Timer.After(1, run) else run() end
end)
