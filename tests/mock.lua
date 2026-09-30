-- Minimal fake WoW client for running addons outside the game.
-- Usage (from the WoWAddons folder):  lua tests/test_<addon>.lua
local M = {}

M.printed = {}
function print(...)
  local parts = {}
  for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
  M.printed[#M.printed + 1] = table.concat(parts, " ")
end
function M.clearPrinted() M.printed = {} end
function M.printedText() return table.concat(M.printed, "\n") end

-- Timers run when the test calls M.flush()
M.timers = {}
C_Timer = {
  After = function(_, fn) M.timers[#M.timers + 1] = fn end,
  NewTicker = function(_, fn) M.ticker = fn return {} end,
}
function M.flush(max)
  for _ = 1, (max or 200) do
    local fn = table.remove(M.timers, 1)
    if not fn then return end
    fn()
  end
end

M.state = { combat = false, shift = false, resting = false, level = 20, class = "HUNTER", money = 100000 }
function InCombatLockdown() return M.state.combat end
function IsShiftKeyDown() return M.state.shift end
function IsResting() return M.state.resting end
function UnitLevel() return M.state.level end
function UnitClass() return M.state.class:sub(1, 1) .. M.state.class:sub(2):lower(), M.state.class, 3 end
function UnitName() return "Tester" end
function GetRealmName() return "Realm" end
function GetBuildInfo() return "1.60.1", "70058", "Sep 2026", 16001 end
function GetTime() return M.state.time or 1000 end
function GetMoney() return M.state.money end
function UnitIsDeadOrGhost() return false end
function IsMounted() return false end
function UnitOnTaxi() return false end
function PlaySound() M.sounds = (M.sounds or 0) + 1 end
SOUNDKIT = { RAID_WARNING = 8959 }
function hooksecurefunc() end

-- Generic frame: remembers text/shown/attributes/scripts, every other method is a no-op
local FrameMT = {}
-- Fields the mock itself stores, and fields addons attach to frames: these are data, not methods
local DATA = { scripts = true, attrs = true, shown = true, text = true, enabled = true, texture = true, checked = true,
               name = true, kind = true, template = true }
FrameMT.__index = function(t, k)
  local v = rawget(FrameMT, k)
  if v then return v end
  if DATA[k] or type(k) ~= "string" or k:find("^%l") then return nil end   -- lowercase = addon data
  return function() end
end
function FrameMT:Show() self.shown = true end
function FrameMT:Hide() self.shown = false end
function FrameMT:IsShown() return self.shown == true end
function FrameMT:IsVisible() return self.shown == true end
function FrameMT:SetShown(v) self.shown = v and true or false end
function FrameMT:SetText(t) self.text = t end
function FrameMT:GetText() return self.text end
function FrameMT:SetAttribute(k, v) self.attrs = self.attrs or {} self.attrs[k] = v end
function FrameMT:GetAttribute(k) return self.attrs and self.attrs[k] end
function FrameMT:SetScript(k, fn) self.scripts = self.scripts or {} self.scripts[k] = fn end
function FrameMT:GetScript(k) return self.scripts and self.scripts[k] end
function FrameMT:RegisterEvent(ev) M.events = M.events or {} M.events[ev] = true end
function FrameMT:SetEnabled(v) self.enabled = v and true or false end
function FrameMT:IsEnabled() return self.enabled ~= false end
function FrameMT:SetTexture(t) self.texture = t end
function FrameMT:SetChecked(v) self.checked = v and true or false end
function FrameMT:GetChecked() return self.checked == true end
function FrameMT:GetWidth() return 1920 end
function FrameMT:GetTop() return 1080 end
function FrameMT:GetCenter() return 960, 540 end
function FrameMT:GetName() return self.name end
function FrameMT:GetPoint() return "TOP", nil, "TOP", 0, 0 end
function FrameMT:CreateFontString() return setmetatable({}, FrameMT) end
function FrameMT:CreateTexture() return setmetatable({}, FrameMT) end
function FrameMT:Click() local fn = self:GetScript("OnClick") if fn then fn(self) end end

M.frames = {}
function CreateFrame(kind, name, parent, template)
  local f = setmetatable({ kind = kind, name = name, template = template }, FrameMT)
  if name then _G[name] = f end
  M.frames[#M.frames + 1] = f
  return f
end
UIParent = setmetatable({ name = "UIParent" }, FrameMT)
GameTooltip = setmetatable({ name = "GameTooltip" }, FrameMT)
SlashCmdList = {}

-- Fire an event at every frame that has an OnEvent script
function M.fire(event, ...)
  for _, f in ipairs(M.frames) do
    local fn = f.scripts and f.scripts.OnEvent
    if fn then fn(f, event, ...) end
  end
end

---------------------------------------------------------------------------
-- Items and bags
---------------------------------------------------------------------------
-- M.items[id] = { name, quality, classID, subID, sellPrice, level, equipLoc, icon }
M.items = {}
function M.link(id) return "|cffffffff|Hitem:" .. id .. "::::::::|h[" .. M.items[id].name .. "]|h|r" end
local function idOf(x) if type(x) == "number" then return x end return tonumber(tostring(x):match("item:(%d+)")) end
C_Item = {
  GetItemInfoInstant = function(x)
    local id = idOf(x) local i = id and M.items[id]
    if not i then return end
    return id, "", "", i.equipLoc or "", i.icon or 134400, i.classID, i.subID
  end,
  GetItemInfo = function(x)
    local id = idOf(x) local i = id and M.items[id]
    if not i then return end
    return i.name, M.link(id), i.quality, i.level or 1, 1, "", "", 20, i.equipLoc or "", 134400, i.sellPrice or 0, i.classID, i.subID
  end,
}

-- M.bags[bag][slot] = { id, count, noValue, locked }
M.bags = {}
C_Container = {
  GetContainerNumSlots = function(bag) return (bag == 0) and 16 or ((M.bags[bag] and 16) or 0) end,
  GetContainerItemInfo = function(bag, slot)
    local s = M.bags[bag] and M.bags[bag][slot]
    if not s then return end
    local i = M.items[s.id]
    return { itemID = s.id, stackCount = s.count or 1, hyperlink = M.link(s.id), quality = i.quality,
             hasNoValue = s.noValue, isLocked = s.locked }
  end,
  UseContainerItem = function(bag, slot)
    M.used = M.used or {}
    M.used[#M.used + 1] = bag .. ":" .. slot
    if M.bags[bag] then M.bags[bag][slot] = nil end
  end,
}
function M.setBags(t) M.bags = t end

-- Equipment: M.equipped[slot] = itemID
M.equipped = {}
function GetInventoryItemLink(_, slot) return M.equipped[slot] and M.link(M.equipped[slot]) end

return M
