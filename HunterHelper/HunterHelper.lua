-- HunterHelper: on-screen reminders for Hunter chores.
--  * Ammo: low / out of ammo, "stock up" while in town, and a warning when you leave town short.
--  * Pet: dead, missing, or not Happy - with a Feed button that uses the best food in your bags.
--  * Aspect: no Aspect active.
HunterHelperDB = HunterHelperDB or {}

local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local MAX_BAG = (NUM_BAG_SLOTS or 4)

local DEFAULTS = { ammo = true, pet = true, nopet = true, aspect = true, sound = true,
                   lowAmmo = 200, townAmmo = 1000, locked = true }
local function Opt(name)
  if HunterHelperDB[name] == nil then return DEFAULTS[name] end
  return HunterHelperDB[name]
end

local function Say(msg) print("|cffabd473HunterHelper:|r " .. msg) end

---------------------------------------------------------------------------
-- Small API helpers (work on both Classic-style and modern clients)
---------------------------------------------------------------------------
local function SpellName(id)
  if C_Spell and C_Spell.GetSpellName then
    local ok, n = pcall(C_Spell.GetSpellName, id)
    if ok and n then return n end
  end
  if GetSpellInfo then
    local ok, n = pcall(GetSpellInfo, id)
    if ok then return n end
  end
end

local function Known(id)
  for _, fn in ipairs({ IsPlayerSpell, IsSpellKnown, C_SpellBook and C_SpellBook.IsSpellKnown }) do
    if type(fn) == "function" then
      local ok, known = pcall(fn, id)
      if ok and known then return true end
    end
  end
  return false
end

local function ItemID(link) return tonumber(link and link:match("item:(%d+)")) end

local function Secret(v) return issecretvalue and issecretvalue(v) end

-- Calls fn(name) for each buff on unit; stops early if fn returns true.
-- Returns true if fn matched, false if not, nil if buffs can't be read right now (e.g. hidden in combat).
local function FindBuff(unit, fn)
  for i = 1, 40 do
    local name
    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
      local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HELPFUL")
      if not ok then return nil end
      if not data then return false end
      name = data.name
    elseif UnitBuff then
      name = UnitBuff(unit, i)
      if not name then return false end
    else
      return nil
    end
    if Secret(name) then return nil end
    if type(name) == "string" and fn(name) then return true end
  end
  return false
end

-- Bag slot reader: itemID, count, link
local function SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if info then return info.itemID, info.stackCount, info.hyperlink end
    return
  end
  local _, count, _, _, _, _, link, _, _, itemID = GetContainerItemInfo(bag, slot)
  return itemID, count, link
end

local function EachBagItem(fn)
  for bag = 0, MAX_BAG do
    for slot = 1, (GetNumSlots(bag) or 0) do
      local itemID, count, link = SlotInfo(bag, slot)
      if itemID then fn(bag, slot, itemID, count or 1, link) end
    end
  end
end

---------------------------------------------------------------------------
-- Ammo
---------------------------------------------------------------------------
-- Ranged weapon subclass -> projectile subclass it fires (2 = arrows, 3 = bullets)
local AMMO_FOR = { [2] = 2, [18] = 2, [3] = 3 }
local AMMO_NAME = { [2] = "arrows", [3] = "bullets" }

-- Returns the projectile subclass your ranged weapon needs, or nil (thrown, wand, none)
local function AmmoType()
  for _, slot in ipairs({ 18, 16 }) do
    local link = GetInventoryItemLink("player", slot)
    if link then
      local _, _, _, _, _, classID, subID = GetInstant(link)
      if classID == 2 and AMMO_FOR[subID] then return AMMO_FOR[subID] end
    end
  end
end

local function AmmoCount(ammoType)
  local total = 0
  EachBagItem(function(_, _, itemID, count)
    local _, _, _, _, _, classID, subID = GetInstant(itemID)
    if classID == 6 and subID == ammoType then total = total + count end
  end)
  return total
end

---------------------------------------------------------------------------
-- Pet food
---------------------------------------------------------------------------
local KEYWORDS = {
  Meat = { "meat", "jerky", "chop", "shank", "steak", "ham", "haunch", "flank", "rib", "sausage", "liver",
           "snout", "venison", "bacon", "kabob", "drumstick" },
  Fish = { "fish", "mackerel", "snapper", "catfish", "cod", "yellowtail", "halibut", "salmon", "albacore",
           "filet", "eel", "trout", "grouper", "mightfish", "sagefish" },
  Bread = { "bread", "cornbread", "pie", "muffin", "biscuit", "bun" },
  Cheese = { "cheese", "cheddar", "brie", "swiss", "bleu", "dalaran sharp", "dwarven mild", "gouda" },
  Fruit = { "apple", "banana", "melon", "pumpkin", "plantain", "grape", "berry", "berries", "fruit", "peach" },
  Fungus = { "mushroom", "morel", "truffle", "mold", "bolete", "fungus" },
}

-- Diet type of an item: from the food table, else from its name. Only consumables and trade goods count.
local function FoodType(itemID, link)
  local _, _, _, _, _, classID = GetInstant(itemID)
  if classID ~= 0 and classID ~= 7 then return end
  if HunterHelperFoods and HunterHelperFoods[itemID] then return HunterHelperFoods[itemID] end
  local name = GetInfo(link or itemID)
  if type(name) ~= "string" then return end
  name = name:lower()
  for kind, words in pairs(KEYWORDS) do
    for _, w in ipairs(words) do
      if name:find(w, 1, true) then return kind end
    end
  end
end

-- Pet functions are globals on Classic and live in C_PetInfo on WoW Forever
local unpack = unpack or table.unpack
local function PI() return C_PetInfo or {} end

-- Calls a pet function with no arguments, then with "pet". Returns ok, results...
local function PetCall(fn)
  if type(fn) ~= "function" then return false end
  local r = { pcall(fn) }
  if not r[1] then r = { pcall(fn, "pet") } end
  if not r[1] then return false end
  return true, unpack(r, 2)
end

-- 1 = Unhappy, 2 = Content, 3 = Happy (nil if the client can't tell us)
local function PetHappiness()
  local ok, a = PetCall(GetPetHappiness or PI().GetPetHappiness)
  if not ok then return end
  if type(a) == "table" then a = a.happiness or a.happinessLevel or a[1] end
  return tonumber(a)
end

-- The pet's diet as a set, e.g. { Meat = true, Fish = true } (returned as values or as a list)
local function PetDiet()
  local r = { PetCall(GetPetFoodTypes or PI().GetPetFoodTypes) }
  if not r[1] then return nil end
  local diet = {}
  local function take(v)
    if type(v) == "string" then diet[v] = true
    elseif type(v) == "table" then
      if type(v.name) == "string" then diet[v.name] = true end
      for _, x in pairs(v) do if type(x) == "string" then diet[x] = true end end
    end
  end
  for i = 2, #r do take(r[i]) end
  return next(diet) and diet or nil
end

-- Ask the game whether the pet eats this item (WoW Forever). true/false, or nil if we can't ask.
local function CanEat(itemID, bag, slot)
  local fn = PI().CanPetEatItem
  if type(fn) ~= "function" then return nil end
  local ok, r = pcall(fn, itemID)
  if ok and type(r) == "boolean" then return r end
  if bag and ItemLocation and ItemLocation.CreateFromBagAndSlot then
    local okL, loc = pcall(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
    if okL and loc then
      ok, r = pcall(fn, loc)
      if ok and type(r) == "boolean" then return r end
    end
  end
  return nil
end

-- Does the pet eat this? The game's answer if it has one, else our food table / name keywords.
local function Eats(itemID, link, diet, bag, slot)
  local answer = CanEat(itemID, bag, slot)
  if answer ~= nil then return answer end
  local kind = FoodType(itemID, link)
  return (kind and diet and diet[kind]) and true or false
end

local function DietText(diet)
  local out = {}
  for t in pairs(diet or {}) do out[#out + 1] = t end
  table.sort(out)
  return table.concat(out, ", ")
end

-- Best food in your bags that the pet eats: highest item level, then biggest stack.
-- Returns { bag, slot, itemID, link, count, level } or nil
local function BestFood(diet)
  if not diet and not PI().CanPetEatItem then return end
  local best
  EachBagItem(function(bag, slot, itemID, count, link)
    if Eats(itemID, link, diet, bag, slot) then
      local level = select(4, GetInfo(link or itemID)) or 0
      if not best or level > best.level or (level == best.level and count > best.count) then
        best = { bag = bag, slot = slot, itemID = itemID, link = link, count = count, level = level }
      end
    end
  end)
  return best
end

---------------------------------------------------------------------------
-- Spells
---------------------------------------------------------------------------
local FEED_PET, CALL_PET, REVIVE_PET = 6991, 883, 982
-- Aspect of the Monkey, Hawk (all ranks), Cheetah, Pack, Beast, Wild
local ASPECT_IDS = { 13163, 13165, 14318, 14319, 14320, 14321, 14322, 25296, 5118, 13159, 13161, 20043, 20190 }
local aspectNames

local function AspectNames()
  if aspectNames then return aspectNames end
  aspectNames = {}
  for _, id in ipairs(ASPECT_IDS) do
    local n = SpellName(id)
    if n then aspectNames[n] = true end
  end
  return aspectNames
end

local function KnowsAnAspect()
  for _, id in ipairs(ASPECT_IDS) do if Known(id) then return true end end
  return false
end

local function IsAspect(name)
  return AspectNames()[name] or name:find("^Aspect of") ~= nil
end

---------------------------------------------------------------------------
-- What to show. Each alert: { key, text, level = "red"|"orange"|"yellow"|"gray" }
---------------------------------------------------------------------------
local COLOR = { red = "|cffff4040", orange = "|cffff9933", yellow = "|cffffd100", gray = "|cffaaaaaa" }
local flash   -- { text, level, expires } for one-off warnings like "leaving town"

local function Busy()
  return (IsMounted and IsMounted()) or (UnitOnTaxi and UnitOnTaxi("player")) or UnitIsDeadOrGhost("player")
      or (UnitInVehicle and UnitInVehicle("player"))
end

local function Checks()
  local alerts, food = {}, nil
  local function add(key, text, level) alerts[#alerts + 1] = { key = key, text = text, level = level } end
  local resting = IsResting and IsResting()

  if Opt("ammo") then
    local ammoType = AmmoType()
    if ammoType then
      local n, name = AmmoCount(ammoType), AMMO_NAME[ammoType]
      if n == 0 then add("ammo", "Out of " .. name .. "!", "red")
      elseif n < Opt("lowAmmo") then add("ammo", "Low ammo: " .. n .. " " .. name, "orange")
      elseif resting and n < Opt("townAmmo") then
        add("ammo", "Stock up: " .. n .. " " .. name .. " (aim for " .. Opt("townAmmo") .. ")", "yellow")
      end
    end
  end

  if Opt("pet") and (UnitLevel("player") or 0) >= 10 and not Busy() then
    if UnitExists("pet") then
      if UnitIsDead("pet") then
        add("pet", "Your pet is dead - Revive Pet", "red")
      else
        local happiness = PetHappiness()
        if happiness and happiness < 3 then
          local eating = FindBuff("pet", function(n) return n:find("Feed Pet", 1, true) ~= nil end)
          if eating then
            add("pet", "Your pet is eating...", "gray")
          else
            local diet = PetDiet()
            food = BestFood(diet)
            local mood = happiness == 1 and "Unhappy" or "Content"
            local level = happiness == 1 and "red" or "yellow"
            if food then
              add("pet", "Your pet is " .. mood .. " - feed it", level)
            else
              add("pet", "Your pet is " .. mood .. " - no food it eats in your bags"
                  .. (diet and (" (" .. DietText(diet) .. ")") or ""), level)
            end
          end
        end
      end
    elseif Opt("nopet") and not resting and Known(CALL_PET) then
      add("pet", "No pet out", "gray")
    end
  end

  if Opt("aspect") and not resting and not Busy() and KnowsAnAspect() then
    local has = FindBuff("player", IsAspect)
    if has == false then add("aspect", "No Aspect active", "orange") end
  end

  if flash then
    if GetTime() < flash.expires then add("flash", flash.text, flash.level) else flash = nil end
  end
  return alerts, food
end

---------------------------------------------------------------------------
-- UI: an alert box plus a secure Feed button (secure frames can't be changed in combat)
---------------------------------------------------------------------------
local box = CreateFrame("Frame", "HunterHelperAlerts", UIParent)
box:SetSize(280, 20)
box:SetFrameStrata("MEDIUM")
box:SetClampedToScreen(true)
box.lines = {}
for i = 1, 5 do
  local fs = box:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  fs:SetPoint("TOP", box, "TOP", 0, -(i - 1) * 22)
  fs:SetJustifyH("CENTER")
  box.lines[i] = fs
end
box.bg = box:CreateTexture(nil, "BACKGROUND")
box.bg:SetAllPoints()
if box.bg.SetColorTexture then box.bg:SetColorTexture(0, 0, 0, 0.4) end
box.bg:Hide()
box:Hide()

local feed = CreateFrame("Button", "HunterHelperFeedButton", UIParent, "SecureActionButtonTemplate")
feed:SetSize(36, 36)
feed:RegisterForClicks("AnyUp", "AnyDown")
feed:SetAttribute("type", "macro")
feed.icon = feed:CreateTexture(nil, "ARTWORK")
feed.icon:SetAllPoints()
feed:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
feed.count = feed:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
feed.count:SetPoint("BOTTOMRIGHT", -2, 2)
feed:SetScript("OnEnter", function(self)
  if not self.link then return end
  GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
  GameTooltip:SetText("Feed your pet")
  GameTooltip:AddLine(self.link, 1, 1, 1)
  GameTooltip:Show()
end)
feed:SetScript("OnLeave", function() GameTooltip:Hide() end)
feed:Hide()

local function Position()
  local p = HunterHelperDB.pos or { x = 0, y = -140 }
  box:ClearAllPoints()
  box:SetPoint("TOP", UIParent, "TOP", p.x, p.y)
  if not (InCombatLockdown and InCombatLockdown()) then
    feed:ClearAllPoints()
    feed:SetPoint("TOPRIGHT", UIParent, "TOP", p.x - 145, p.y + 4)
  end
end

box:SetMovable(true)
box:RegisterForDrag("LeftButton")
box:SetScript("OnDragStart", function(self) if not Opt("locked") then self:StartMoving() end end)
box:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local cx = self:GetCenter()
  HunterHelperDB.pos = { x = math.floor(cx - UIParent:GetWidth() / 2 + 0.5), y = math.floor(self:GetTop() - UIParent:GetTop() + 0.5) }
  Position()
end)

local shownKeys = {}
local sample   -- /hh test: show example alerts

local function SetFeed(food)
  if InCombatLockdown and InCombatLockdown() then return end   -- try again after combat
  local feedName = Known(FEED_PET) and SpellName(FEED_PET)
  if food and feedName then
    feed:SetAttribute("macrotext", "/cast " .. feedName .. "\n/use " .. food.bag .. " " .. food.slot)
    feed.icon:SetTexture(select(5, GetInstant(food.itemID)))
    feed.count:SetText(food.count > 1 and food.count or "")
    feed.link = food.link
    feed:Show()
  else
    feed.link = nil
    feed:Hide()
  end
end

-- Leaving town (resting -> not resting) with less ammo than the stock-up target
local wasResting
local function RestingChanged()
  local resting = IsResting and IsResting()
  if wasResting and not resting and Opt("ammo") then
    local ammoType = AmmoType()
    if ammoType then
      local n = AmmoCount(ammoType)
      if n < Opt("townAmmo") then
        local text = "Leaving town with only " .. n .. " " .. AMMO_NAME[ammoType] .. "!"
        flash = { text = text, level = "red", expires = GetTime() + 10 }
        Say(text)
      end
    end
  end
  wasResting = resting
end
local function Refresh()
  pcall(RestingChanged)
  local alerts, food
  if sample then alerts, food = sample, nil else alerts, food = Checks() end
  local newRed = false
  local keys = {}
  for i, fs in ipairs(box.lines) do
    local a = alerts[i]
    if a then
      fs:SetText(COLOR[a.level] .. a.text .. "|r")
      fs:Show()
      keys[a.key .. a.level] = true
      if a.level == "red" and not shownKeys[a.key .. a.level] then newRed = true end
    else
      fs:SetText("")
      fs:Hide()
    end
  end
  shownKeys = keys
  box:SetHeight(math.max(20, #alerts * 22))
  box.bg:SetShown(not Opt("locked"))
  if #alerts > 0 or not Opt("locked") then box:Show() else box:Hide() end
  if newRed and Opt("sound") and PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
    pcall(PlaySound, SOUNDKIT.RAID_WARNING)
  end
  SetFeed(food)
end

---------------------------------------------------------------------------
-- Vendor and leaving-town tips
---------------------------------------------------------------------------
local function MerchantItems()
  local items = {}
  local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
  for i = 1, n do
    local link = GetMerchantItemLink and GetMerchantItemLink(i)
    if link then items[#items + 1] = link end
  end
  return items
end

local function VendorTips()
  local ammoType = Opt("ammo") and AmmoType()
  local petOut = Opt("pet") and UnitExists("pet")
  local diet = petOut and PetDiet()
  local items = MerchantItems()
  if ammoType then
    local have = AmmoCount(ammoType)
    if have < Opt("townAmmo") then
      for _, link in ipairs(items) do
        local _, _, _, _, _, classID, subID = GetInstant(link)
        if classID == 6 and subID == ammoType then
          Say("This vendor sells " .. link .. ". You have " .. have .. " " .. AMMO_NAME[ammoType]
              .. " - buy " .. (Opt("townAmmo") - have) .. " more to reach " .. Opt("townAmmo") .. ".")
          break
        end
      end
    end
  end
  if petOut and (diet or PI().CanPetEatItem) then
    local have = 0
    EachBagItem(function(bag, slot, itemID, count, link)
      if Eats(itemID, link, diet, bag, slot) then have = have + count end
    end)
    if have < 20 then
      for _, link in ipairs(items) do
        if Eats(ItemID(link), link, diet) then
          Say("This vendor sells " .. link .. ", which your pet eats. You have " .. have .. " pet food.")
          break
        end
      end
    end
  end
end


---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Toggle(name, label)
  HunterHelperDB[name] = not Opt(name)
  Say(label .. " " .. (HunterHelperDB[name] and "on" or "off") .. ".")
  Refresh()
end

local function Debug()
  local _, _, _, toc = GetBuildInfo()
  Say("Interface " .. tostring(toc) .. ", level " .. tostring(UnitLevel("player")) .. ", class " .. tostring(select(2, UnitClass("player"))))
  local ammoType = AmmoType()
  Say("Ranged slot 18: " .. tostring(GetInventoryItemLink("player", 18)) .. ", ammo type: "
      .. tostring(ammoType and AMMO_NAME[ammoType]) .. ", count: " .. tostring(ammoType and AmmoCount(ammoType)))
  local function raw(fn)
    local r = { PetCall(fn) }
    if not r[1] then return fn and "error" or "missing" end
    local out = {}
    for i = 2, #r do
      local v = r[i]
      if type(v) == "table" then
        local kv = {}
        for k, x in pairs(v) do kv[#kv + 1] = tostring(k) .. "=" .. tostring(x) end
        v = "{" .. table.concat(kv, ", ") .. "}"
      end
      out[#out + 1] = tostring(v)
    end
    return #out > 0 and table.concat(out, ", ") or "nothing"
  end
  Say("Pet: exists " .. tostring(UnitExists("pet")) .. ", happiness: " .. raw(GetPetHappiness or PI().GetPetHappiness)
      .. " -> " .. tostring(PetHappiness()) .. ", diet: " .. raw(GetPetFoodTypes or PI().GetPetFoodTypes)
      .. " -> " .. tostring(DietText(PetDiet())))
  local tried = {}
  EachBagItem(function(bag, slot, itemID, _, link)
    if #tried < 4 and FoodType(itemID, link) then
      tried[#tried + 1] = tostring(link) .. " = " .. tostring(CanEat(itemID, bag, slot))
    end
  end)
  Say("CanPetEatItem: " .. (PI().CanPetEatItem and (#tried > 0 and table.concat(tried, ", ") or "no food in bags to try") or "missing"))
  local food = BestFood(PetDiet())
  Say("Best food: " .. tostring(food and food.link) .. ", Feed Pet known: " .. tostring(Known(FEED_PET))
      .. " (" .. tostring(SpellName(FEED_PET)) .. ")")
  Say("Knows an Aspect: " .. tostring(KnowsAnAspect()) .. ", Aspect active: "
      .. tostring(FindBuff("player", IsAspect)) .. ", resting: " .. tostring(IsResting and IsResting()))
end

local function Help()
  Say("/hh - status  |  /hh unlock, /hh lock - move the alert box")
  Say("/hh ammo, /hh pet, /hh nopet, /hh aspect, /hh sound - turn each reminder on/off")
  Say("/hh low <n> - low-ammo warning (now " .. Opt("lowAmmo") .. ")  |  /hh town <n> - stock-up target (now " .. Opt("townAmmo") .. ")")
  Say("/hh test - show sample alerts for 10 seconds  |  /hh debug - what HunterHelper detects")
end

SLASH_HUNTERHELPER1 = "/hh"
SLASH_HUNTERHELPER2 = "/hunterhelper"
SlashCmdList["HUNTERHELPER"] = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.*)$")
  cmd = cmd:lower()
  if cmd == "ammo" then Toggle("ammo", "Ammo reminders")
  elseif cmd == "pet" then Toggle("pet", "Pet reminders")
  elseif cmd == "nopet" then Toggle("nopet", "'No pet out' reminder")
  elseif cmd == "aspect" then Toggle("aspect", "Aspect reminder")
  elseif cmd == "sound" then Toggle("sound", "Warning sound")
  elseif cmd == "low" or cmd == "town" then
    local n = tonumber(rest)
    if not n or n < 0 then Say("Give a number, e.g. /hh " .. cmd .. " 400") return end
    HunterHelperDB[cmd == "low" and "lowAmmo" or "townAmmo"] = math.floor(n)
    Say((cmd == "low" and "Low-ammo warning" or "Stock-up target") .. " set to " .. math.floor(n) .. ".")
    Refresh()
  elseif cmd == "unlock" then
    HunterHelperDB.locked = false
    Say("Unlocked - drag the box to move it, then /hh lock.")
    Refresh()
  elseif cmd == "lock" then
    HunterHelperDB.locked = true
    Say("Locked.")
    Refresh()
  elseif cmd == "test" then
    sample = { { key = "t1", text = "Low ammo: 83 arrows", level = "orange" },
               { key = "t2", text = "Your pet is Unhappy - feed it", level = "red" },
               { key = "t3", text = "No Aspect active", level = "orange" } }
    Refresh()
    if C_Timer and C_Timer.After then C_Timer.After(10, function() sample = nil Refresh() end) end
  elseif cmd == "debug" then
    Debug()
  elseif cmd == "help" or cmd == "?" then
    Help()
  else
    Say("Ammo " .. (Opt("ammo") and "on" or "off") .. ", pet " .. (Opt("pet") and "on" or "off")
        .. ", aspect " .. (Opt("aspect") and "on" or "off") .. ". Low ammo at " .. Opt("lowAmmo")
        .. ", stock up to " .. Opt("townAmmo") .. ". /hh help for commands.")
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
-- Coalesce bursts (UNIT_AURA, BAG_UPDATE) into one refresh a moment later
local pending = false
local function RequestRefresh()
  if pending then return end
  pending = true
  local function run() pending = false pcall(Refresh) end
  if C_Timer and C_Timer.After then C_Timer.After(0.2, run) else run() end
end
local f = CreateFrame("Frame")
local EVENTS = { "PLAYER_LOGIN", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED", "UNIT_PET", "UNIT_HAPPINESS",
                 "PET_UI_UPDATE", "UNIT_AURA", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "MERCHANT_SHOW",
                 "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SPELLS_CHANGED", "PLAYER_MOUNT_DISPLAY_CHANGED" }
for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end

local active = false
f:SetScript("OnEvent", function(_, event, unit)
  if event == "PLAYER_LOGIN" then
    HunterHelperDB = HunterHelperDB or {}
    active = select(2, UnitClass("player")) == "HUNTER"
    if not active then return end
    Position()
    wasResting = IsResting and IsResting()
    Say("loaded. /hh help for commands.")
    -- Slow heartbeat: pet happiness changes without always firing an event
    if C_Timer and C_Timer.NewTicker then C_Timer.NewTicker(2, function() pcall(Refresh) end) end
  end
  if not active then return end
  if event == "UNIT_AURA" and unit ~= "player" and unit ~= "pet" then return end
  if event == "SPELLS_CHANGED" then aspectNames = nil end
  if event == "MERCHANT_SHOW" then pcall(VendorTips) end
  if event == "PLAYER_REGEN_ENABLED" then Position() end
  RequestRefresh()
end)
