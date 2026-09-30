-- TidyVendor: sells grey (junk) items and repairs your gear when you open a vendor.
-- Hold Shift while opening the vendor to skip it for that visit.
TidyVendorDB = TidyVendorDB or {}

local GetNumSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
local UseItem = (C_Container and C_Container.UseContainerItem) or UseContainerItem
local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo

local SELL_INTERVAL = 0.15   -- seconds between sales, so the server keeps up
local MAX_BAG = (NUM_BAG_SLOTS or 4)

local function Say(msg) print("|cff33ccffTidyVendor:|r " .. msg) end

local DEFAULTS = { sell = true, repair = true, guild = true }
local function Opt(name)
  if TidyVendorDB[name] == nil then return DEFAULTS[name] end
  return TidyVendorDB[name]
end
local function Lists()
  TidyVendorDB.always = TidyVendorDB.always or {}   -- itemID -> true: sell even if not grey
  TidyVendorDB.never = TidyVendorDB.never or {}     -- itemID -> true: never sell
  return TidyVendorDB.always, TidyVendorDB.never
end

local function Money(copper)
  copper = math.floor(copper or 0)
  if GetCoinTextureString then
    local ok, s = pcall(GetCoinTextureString, copper)
    if ok and s then return s end
  end
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "g" end
  if s > 0 or g > 0 then out[#out + 1] = s .. "s" end
  if c > 0 or #out == 0 then out[#out + 1] = c .. "c" end
  return table.concat(out, " ")
end

-- Unified bag slot reader: returns itemID, count, link, quality, noValue, locked
local function SlotInfo(bag, slot)
  if C_Container and C_Container.GetContainerItemInfo then
    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then return end
    return info.itemID, info.stackCount, info.hyperlink, info.quality, info.hasNoValue, info.isLocked
  end
  local _, count, locked, quality, _, _, link, _, noValue, itemID = GetContainerItemInfo(bag, slot)
  return itemID, count, link, quality, noValue, locked
end

local function ItemID(link) return tonumber(link and link:match("item:(%d+)")) end

-- Everything in your bags that should be sold: { {bag, slot, link, value}, ... }
local function FindJunk()
  local always, never = Lists()
  local junk = {}
  for bag = 0, MAX_BAG do
    for slot = 1, (GetNumSlots(bag) or 0) do
      local itemID, count, link, quality, noValue, locked = SlotInfo(bag, slot)
      if itemID and not locked and not noValue and not never[itemID] and (quality == 0 or always[itemID]) then
        local price = select(11, GetInfo(link or itemID))
        if price and price > 0 then
          junk[#junk + 1] = { bag = bag, slot = slot, link = link, itemID = itemID, value = price * (count or 1) }
        end
      end
    end
  end
  return junk
end

---------------------------------------------------------------------------
-- Selling (one item per tick; stops if the vendor closes)
---------------------------------------------------------------------------
local selling, queue, sold, earned = false, {}, 0, 0
local merchantOpen = false

local function FinishSelling()
  selling = false
  if sold > 0 then Say("Sold " .. sold .. " junk item" .. (sold == 1 and "" or "s") .. " for " .. Money(earned) .. ".") end
  queue, sold, earned = {}, 0, 0
end

local function SellNext()
  if not merchantOpen then return FinishSelling() end
  local item = table.remove(queue, 1)
  if not item then return FinishSelling() end
  -- Make sure the slot still holds the same item before selling it
  local itemID = SlotInfo(item.bag, item.slot)
  if itemID == item.itemID then
    UseItem(item.bag, item.slot)
    sold, earned = sold + 1, earned + item.value
  end
  if C_Timer and C_Timer.After then C_Timer.After(SELL_INTERVAL, SellNext) else SellNext() end
end

local function StartSelling()
  if selling then return end
  queue = FindJunk()
  if #queue == 0 then return end
  selling, sold, earned = true, 0, 0
  SellNext()
end

---------------------------------------------------------------------------
-- Repairing
---------------------------------------------------------------------------
local function Repair()
  if not (CanMerchantRepair and CanMerchantRepair()) then return end
  local cost, canRepair = GetRepairAllCost()
  if not canRepair or not cost or cost <= 0 then return end
  if Opt("guild") and CanGuildBankRepair and CanGuildBankRepair() and IsInGuild and IsInGuild() then
    local ok = pcall(RepairAllItems, true)
    if ok then Say("Repaired for " .. Money(cost) .. " (guild bank).") return end
  end
  if GetMoney() < cost then
    Say("Repairs cost " .. Money(cost) .. " but you only have " .. Money(GetMoney()) .. ".")
    return
  end
  RepairAllItems()
  Say("Repaired for " .. Money(cost) .. ".")
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
local function Toggle(name, label)
  TidyVendorDB[name] = not Opt(name)
  Say(label .. " " .. (TidyVendorDB[name] and "on" or "off") .. ".")
end

local function EditList(which, add, rest)
  local id = ItemID(rest)
  if not id then Say("Shift-click an item after the command to add its link.") return end
  local always, never = Lists()
  local list, other = (which == "always") and always or never, (which == "always") and never or always
  list[id] = add or nil
  if add then other[id] = nil end
  Say(rest .. (add and (which == "always" and " will always be sold." or " will never be sold.")
                    or (" removed from the " .. which .. "-sell list.")))
end

local function ShowList()
  local always, never = Lists()
  local function names(t)
    local out = {}
    for id in pairs(t) do out[#out + 1] = (select(2, GetInfo(id))) or ("item " .. id) end
    return #out > 0 and table.concat(out, ", ") or "none"
  end
  Say("Always sell: " .. names(always))
  Say("Never sell: " .. names(never))
end

local function Status()
  Say("Sell junk " .. (Opt("sell") and "on" or "off") .. ", repair " .. (Opt("repair") and "on" or "off")
      .. ", guild repairs " .. (Opt("guild") and "on" or "off") .. ". Hold Shift at a vendor to skip. /tv help")
  local junk, value = FindJunk(), 0
  for _, j in ipairs(junk) do value = value + j.value end
  if #junk > 0 then Say(#junk .. " item" .. (#junk == 1 and "" or "s") .. " to sell right now, worth " .. Money(value) .. ".") end
end

SLASH_TIDYVENDOR1 = "/tv"
SLASH_TIDYVENDOR2 = "/tidyvendor"
SlashCmdList["TIDYVENDOR"] = function(msg)
  local cmd, rest = (msg or ""):match("^(%S*)%s*(.*)$")
  cmd = cmd:lower()
  if cmd == "sell" then Toggle("sell", "Selling junk")
  elseif cmd == "repair" then Toggle("repair", "Auto-repair")
  elseif cmd == "guild" then Toggle("guild", "Guild bank repairs")
  elseif cmd == "add" then EditList("always", true, rest)
  elseif cmd == "remove" then EditList("always", false, rest)
  elseif cmd == "keep" then EditList("never", true, rest)
  elseif cmd == "unkeep" then EditList("never", false, rest)
  elseif cmd == "list" then ShowList()
  elseif cmd == "help" or cmd == "?" then
    Say("/tv - status  |  /tv sell, /tv repair, /tv guild - turn each on/off")
    Say("/tv add [item] - always sell it  |  /tv remove [item]")
    Say("/tv keep [item] - never sell it (even if grey)  |  /tv unkeep [item]")
    Say("/tv list - show both lists. Hold Shift when opening a vendor to skip TidyVendor once.")
  else
    Status()
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
f:RegisterEvent("MERCHANT_SHOW")
f:RegisterEvent("MERCHANT_CLOSED")
f:SetScript("OnEvent", function(_, event)
  if event == "MERCHANT_SHOW" then
    merchantOpen = true
    if IsShiftKeyDown and IsShiftKeyDown() then Say("Skipped (Shift held).") return end
    -- Repair first so the sale total isn't mixed up with repair costs
    if Opt("repair") then pcall(Repair) end
    if Opt("sell") then pcall(StartSelling) end
  else
    merchantOpen = false
  end
end)
