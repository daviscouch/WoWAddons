package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local T = require("check")

-- Items
M.items = {
  [783] = { name = "Light Hide", quality = 1, classID = 7, subID = 6 },
  [2318] = { name = "Light Leather", quality = 1, classID = 7, subID = 6 },
  [2320] = { name = "Coarse Thread", quality = 1, classID = 7, subID = 5 },
  [4289] = { name = "Salt", quality = 1, classID = 7, subID = 11 },
  [4231] = { name = "Cured Light Hide", quality = 1, classID = 7, subID = 6 },
  [2304] = { name = "Light Armor Kit", quality = 1, classID = 0, subID = 6 },
  [2302] = { name = "Handstitched Leather Boots", quality = 1, classID = 4, subID = 2, equipLoc = "INVTYPE_FEET" },
  [2568] = { name = "Brown Linen Vest", quality = 1, classID = 4, subID = 1 },
  [2996] = { name = "Bolt of Linen Cloth", quality = 1, classID = 7, subID = 5 },
  [5957] = { name = "Handstitched Leather Vest", quality = 1, classID = 4, subID = 2, equipLoc = "INVTYPE_CHEST" },
}
function C_Item.GetItemCount(id)
  local n = 0
  for _, bag in pairs(M.bags) do for _, s in pairs(bag) do if s.id == id then n = n + (s.count or 1) end end end
  return n
end
time = function() return M.state.now or 100000 end
Enum = { TooltipDataType = { Item = 0 }, ItemCommodityStatus = { Unknown = 0, Item = 1, Commodity = 2 },
         AuctionHouseSortOrder = { Price = 0 } }
local tooltipHook
TooltipDataProcessor = { AddTooltipPostCall = function(_, fn) tooltipHook = fn end }
UISpecialFrames = {}
function tinsert(t, v) table.insert(t, v) end

-- Recipes (Leatherworking)
local RECIPES = {
  [2152] = { name = "Light Armor Kit", learned = true, out = 2304, qty = 1, reagents = { { 2318, 1 } } },
  [2149] = { name = "Handstitched Leather Boots", learned = true, out = 2302, qty = 1, reagents = { { 2318, 2 }, { 2320, 1 } } },
  [3816] = { name = "Cured Light Hide", learned = true, out = 4231, qty = 1, reagents = { { 783, 1 }, { 4289, 1 } } },
  [7126] = { name = "Handstitched Leather Vest", learned = false, out = 5957, qty = 1, reagents = { { 2318, 3 } } },
  [2385] = { name = "Brown Linen Vest", learned = false, out = 2568, qty = 1, reagents = { { 2996, 1 } }, prof = "Tailoring" },
}
C_TradeSkillUI = {
  GetAllRecipeIDs = function() return { 2152, 2149, 3816, 7126, 2385 } end,
  GetRecipeInfo = function(id) local r = RECIPES[id] return { name = r.name, learned = r.learned, icon = 1, hyperlink = "recipe:" .. id } end,
  GetRecipeSchematic = function(id)
    local r = RECIPES[id]
    local slots = {}
    for i, g in ipairs(r.reagents) do slots[i] = { required = true, quantityRequired = g[2], reagents = { { itemID = g[1] } } } end
    return { outputItemID = r.out, quantityMin = r.qty, quantityMax = r.qty, reagentSlotSchematics = slots, name = r.name }
  end,
  GetProfessionInfoByRecipeID = function(id) return { professionName = RECIPES[id].prof or "Leatherworking" } end,
  GetRecipeSourceText = function(id) return id == 7126 and "Trainer: Leatherworking Trainer" or nil end,
}

-- Auction house: commodity prices by itemID, boots are a non-commodity item. 783 never answers.
local AHPRICES = { [2318] = 50, [783] = 30, [2304] = 150 }
local ITEMPRICES = { [2302] = { { buyoutAmount = 800, quantity = 2 }, { buyoutAmount = 500, quantity = 1 } } }
local NOANSWER = { [783] = true }
local queries, throttleOnce = {}, true
C_AuctionHouse = {
  MakeItemKey = function(id) return { itemID = id } end,
  GetItemCommodityStatus = function(id) return ITEMPRICES[id] and 1 or 2 end,
  IsThrottledMessageSystemReady = function()
    if throttleOnce and #queries == 2 then throttleOnce = false C_Timer.After(0, function() M.fire("AUCTION_HOUSE_THROTTLED_SYSTEM_READY") end) return false end
    return true
  end,
  SendSearchQuery = function(key)
    local id = key.itemID
    queries[#queries + 1] = id
    if NOANSWER[id] then return end
    C_Timer.After(0, function()
      if ITEMPRICES[id] then M.fire("ITEM_SEARCH_RESULTS_UPDATED", key) else M.fire("COMMODITY_SEARCH_RESULTS_UPDATED", id) end
    end)
  end,
  GetNumCommoditySearchResults = function(id) return AHPRICES[id] and 1 or 0 end,
  GetCommoditySearchResultInfo = function(id) return { unitPrice = AHPRICES[id] } end,
  GetNumItemSearchResults = function(key) return #(ITEMPRICES[key.itemID] or {}) end,
  GetItemSearchResultInfo = function(key, i) return ITEMPRICES[key.itemID][i] end,
  -- Full scan
  ReplicateItems = function() C_Timer.After(0, function() M.fire("REPLICATE_ITEM_LIST_UPDATE") end) end,
  GetNumReplicateItems = function() return 3 end,
  GetReplicateItemInfo = function(i)
    local rows = { [0] = { 20, 400, 2318 }, [1] = { 5, 150, 2318 }, [2] = { 1, 300, 5957 } }   -- count, buyout, itemID
    local r = rows[i]
    return "x", 1, r[1], 1, true, 1, 0, 0, 0, r[2], 0, false, nil, "seller", nil, 0, r[3], true
  end,
}

-- Vendor with thread and salt
local vendor = { { 2320, 10, 1 }, { 4289, 50, 1 } }   -- itemID, price, stack
function GetMerchantNumItems() return #vendor end
function GetMerchantItemLink(i) return M.link(vendor[i][1]) end
C_MerchantFrame = { GetItemInfo = function(i) return { price = vendor[i][2], stackCount = vendor[i][3], numAvailable = -1 } end }

dofile("CraftProfit/CraftProfit.lua")
local SLASH = SlashCmdList.CRAFTPROFIT
local win = _G.CraftProfitFrame
local function strip(s) return (tostring(s or ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
local function rowText(i)
  local row = win.rows[i]
  if not row:IsShown() then return "" end
  local out = {}
  for _, c in ipairs(row.cells) do out[#out + 1] = strip(c:GetText()) end
  return table.concat(out, " | ")
end

M.fire("PLAYER_LOGIN")
M.setBags({ [0] = { [1] = { id = 2318, count = 5 }, [2] = { id = 2320, count = 1 } } })

-- Profession window opens: recipes listed, no prices yet
M.fire("TRADE_SKILL_SHOW")
M.flush()
T.ok("opens with the profession window, titled with the profession", win:IsShown() and strip(win.title:GetText()) == "CraftProfit - Leatherworking",
     strip(win.title:GetText()))
T.ok("lists only learned recipes (3)", win.total == 3, tostring(win.total))
T.ok("no prices yet: question marks", rowText(1):find("?", 1, true) ~= nil, rowText(1))
T.ok("scan buttons disabled away from the AH", not win.scanRecipes:IsEnabled())

-- Vendor visit records thread and salt
M.fire("MERCHANT_SHOW")

-- Auction house: scan recipes
M.fire("AUCTION_HOUSE_SHOW")
M.clearPrinted()
win.scanRecipes:GetScript("OnClick")()
M.flush()
table.sort(queries)
T.ok("scan looks up each reagent and output once, skipping vendor items", table.concat(queries, ",") == "783,2302,2304,2318,4231",
     table.concat(queries, ","))
T.ok("scan finishes (throttle pause + an item that never answers)", M.printedText():find("Scanned 5 items", 1, true), M.printedText())

-- Results, most profitable first
-- Boots: 2x50 + 10 = 110 cost; best unit price min(800/2, 500/1) = 400 -> 380 after cut -> +270
-- Armor kit: 50 cost; 150 -> 142.5 -> +92.5
-- Cured Light Hide: Light Hide never answered -> no price -> bottom
T.ok("row 1: boots, +270c", rowText(1) == "Handstitched Leather Boots | 1s 10c | 3s 80c | +2s 70c | 1", rowText(1))
T.ok("row 2: armor kit, +93c", rowText(2) == "Light Armor Kit | 50c | 1s 43c | +93c | 5", rowText(2))
T.ok("row 3: missing price goes last", rowText(3):find("^Cured Light Hide | %?"), rowText(3))

-- Only what I can make
win.makeable:SetChecked(true)
win.makeable:GetScript("OnClick")(win.makeable)
T.ok("'only what I can make' hides recipes you lack reagents for", win.total == 2, tostring(win.total))
win.makeable:SetChecked(false)
win.makeable:GetScript("OnClick")(win.makeable)

-- Count my mats as free (bags: 5 Light Leather, 1 Coarse Thread)
win.ownMats:SetChecked(true)
win.ownMats:GetScript("OnClick")(win.ownMats)
T.ok("own mats: boots cost nothing (you have the leather and thread)", rowText(1) == "Handstitched Leather Boots | 0c | 3s 80c | +3s 80c | 1", rowText(1))
T.ok("own mats: armor kit too", rowText(2) == "Light Armor Kit | 0c | 1s 43c | +1s 43c | 5", rowText(2))
local tipOwn = {}
GameTooltip.AddDoubleLine = function(_, l, r) tipOwn[#tipOwn + 1] = strip(l) .. " = " .. strip(r) end
GameTooltip.AddLine = function(_, l) tipOwn[#tipOwn + 1] = strip(l) end
GameTooltip.SetText = function(_, l) tipOwn[#tipOwn + 1] = strip(l) end
win.rows[2]:GetScript("OnEnter")(win.rows[2])
local ownText = table.concat(tipOwn, "\n")
T.ok("tooltip shows both profits", ownText:find("Profit if you buy everything = +93c", 1, true)
     and ownText:find("Profit using your mats = +1s 43c", 1, true), ownText)
-- Light Leather would sell for 50c - 5% = 47.5c; crafting the kit with it: 142.5 - 47.5 = 95c more
T.ok("...and crafting vs selling the mats raw", ownText:find("Your mats would sell for 48c on the AH. Crafting earns 95c more than selling them raw.", 1, true), ownText)
-- Only some of the mats: 1 Light Leather in bags, boots need 2 -> buy 1 (50c), thread is yours
M.setBags({ [0] = { [1] = { id = 2318, count = 1 }, [2] = { id = 2320, count = 1 } } })
M.fire("BAG_UPDATE_DELAYED")
local bootsRow
for i = 1, 3 do if rowText(i):find("^Handstitched Leather Boots") then bootsRow = i end end
T.ok("own mats: only pays for what you're missing", bootsRow and rowText(bootsRow) == "Handstitched Leather Boots | 50c | 3s 80c | +3s 30c | 0",
     bootsRow and rowText(bootsRow))
M.setBags({ [0] = { [1] = { id = 2318, count = 5 }, [2] = { id = 2320, count = 1 } } })
win.ownMats:SetChecked(false)
win.ownMats:GetScript("OnClick")(win.ownMats)
T.ok("turning it off goes back to buying everything", rowText(1) == "Handstitched Leather Boots | 1s 10c | 3s 80c | +2s 70c | 1", rowText(1))

-- Recipe tooltip breaks down the reagents
local tip = {}
GameTooltip.AddDoubleLine = function(_, l, r) tip[#tip + 1] = strip(l) .. " = " .. strip(r) end
GameTooltip.AddLine = function(_, l) tip[#tip + 1] = strip(l) end
GameTooltip.SetText = function(_, l) tip[#tip + 1] = strip(l) end
win.rows[1]:GetScript("OnEnter")(win.rows[1])
local tipText = table.concat(tip, "\n")
T.ok("recipe tooltip lists each reagent with its source and how many you have",
     tipText:find("2x Light Leather (you have 5) = 1s (AH, just now)", 1, true)
     and tipText:find("1x Coarse Thread (you have 1) = 10c (vendor)", 1, true), tipText)
T.ok("...and says how many you can craft now", tipText:find("You have materials to craft 1 right now.", 1, true), tipText)
tip = {}
win.rows[3]:GetScript("OnEnter")(win.rows[3])
tipText = table.concat(tip, "\n")
T.ok("...or what you're missing", tipText:find("missing: Light Hide (have 0 of 1), Salt (have 0 of 1)", 1, true), tipText)

-- Item tooltips
tip = {}
tooltipHook(GameTooltip, { id = 2302 })
tipText = table.concat(tip, "\n")
T.ok("item tooltip: AH price, cost to make, profit", tipText:find("CraftProfit AH = 4s just now", 1, true)
     and tipText:find("cost to make = 1s 10c", 1, true) and tipText:find("profit = +2s 70c", 1, true), tipText)
tip = {}
tooltipHook(GameTooltip, { id = 783 })
T.ok("an item with no price: no tooltip lines", #tip == 0, table.concat(tip, "\n"))

-- Full scan (and its 15-minute cooldown)
M.clearPrinted()
SLASH("fullscan")
M.flush()
T.ok("full scan reads every auction, cheapest per unit", M.printedText():find("Full scan done: 3 auctions, prices for 2 items", 1, true),
     M.printedText())
T.ok("...Light Leather now 20c each (400 for 20)", rowText(2) == "Light Armor Kit | 20c | 1s 43c | +1s 23c | 5", rowText(2))
M.clearPrinted()
SLASH("fullscan")
T.ok("full scan again right away: explains the 15 minute limit", M.printedText():find("try again in 15 min", 1, true), M.printedText())

-- Shift-click a row: search the auction house for the crafted item
local searched, started, linked, mode = nil, false, nil, nil
AuctionHouseFrameDisplayMode = { Buy = "buy" }
AuctionHouseFrame = setmetatable({ shown = true, SearchBar = {
  SearchBox = { SetText = function(_, t) searched = t end },
  StartSearch = function() started = true end,
} }, getmetatable(win))
AuctionHouseFrame.SetDisplayMode = function(_, m) mode = m end
function HandleModifiedItemClick(link) linked = link end
win.rows[1]:GetScript("OnClick")(win.rows[1])
T.ok("plain click does nothing", searched == nil and linked == nil)
M.state.shift = true
win.rows[1]:GetScript("OnClick")(win.rows[1])
T.ok("shift-click with the AH open: searches for the crafted item on the Buy tab",
     searched == "Handstitched Leather Boots" and started and mode == "buy", tostring(searched))
AuctionHouseFrame.shown = false
searched = nil
win.rows[2]:GetScript("OnClick")(win.rows[2])
T.ok("shift-click with the AH closed: links it in chat instead", searched == nil and linked and linked:find("Light Armor Kit", 1, true),
     tostring(linked))
AuctionHouseFrame.shown = true
-- Shift-right-click: step through reagents. Boots = 2 Light Leather (AH) + 1 Coarse Thread (vendor, skipped)
M.clearPrinted()
win.rows[1]:GetScript("OnClick")(win.rows[1], "RightButton")
T.ok("shift-right-click searches a reagent", searched == "Light Leather"
     and M.printedText():find("Reagent 1 of 1 for Handstitched Leather Boots: Light Leather (need 2).", 1, true), M.printedText())
searched = nil
win.rows[1]:GetScript("OnClick")(win.rows[1], "RightButton")
T.ok("...vendor reagents are skipped, so it stays on Light Leather", searched == "Light Leather", tostring(searched))
-- Cured Light Hide: Light Hide + Salt (vendor) -> only Light Hide to search
M.clearPrinted()
local cured
for i = 1, 3 do if rowText(i):find("^Cured Light Hide") then cured = win.rows[i] end end
cured:GetScript("OnClick")(cured, "RightButton")
local first = searched
cured:GetScript("OnClick")(cured, "RightButton")
T.ok("stepping repeats when there's only one AH reagent", first == "Light Hide" and searched == "Light Hide", tostring(first) .. "," .. tostring(searched))
M.state.shift = false

-- Show unlearned recipes (only for professions you have)
win.unlearned:SetChecked(true)
win.unlearned:GetScript("OnClick")(win.unlearned)
local names = {}
for i = 1, 6 do local t = rowText(i) if t ~= "" then names[#names + 1] = t:match("^[^|]+") end end
local listed = table.concat(names, ",")
T.ok("'Show unlearned' adds unlearned recipes from your professions", win.total == 4 and listed:find("Handstitched Leather Vest", 1, true), listed)
T.ok("...but not other professions' recipes (Tailoring)", not listed:find("Brown Linen Vest", 1, true), listed)
local vestRow
for i = 1, 4 do if rowText(i):find("^Handstitched Leather Vest") then vestRow = i end end
T.ok("unlearned row says 'not learned' in the Craft now column", vestRow and rowText(vestRow):find("not learned$"), vestRow and rowText(vestRow))
T.ok("status counts them", strip(win.status:GetText()):find("4 recipes (1 not learned)", 1, true), strip(win.status:GetText()))
tip = {}
win.rows[vestRow]:GetScript("OnEnter")(win.rows[vestRow])
tipText = table.concat(tip, "\n")
T.ok("unlearned tooltip says where to learn it", tipText:find("You haven't learned this recipe yet.", 1, true)
     and tipText:find("Trainer: Leatherworking Trainer", 1, true) and not tipText:find("craft", 1, true), tipText)
win.makeable:SetChecked(true)
win.makeable:GetScript("OnClick")(win.makeable)
T.ok("'Only what I can make' still hides unlearned ones", win.total == 2, tostring(win.total))
win.makeable:SetChecked(false)
win.makeable:GetScript("OnClick")(win.makeable)
tip = {}
tooltipHook(GameTooltip, { id = 5957 })
T.ok("item tooltips only show crafting profit for recipes you know", not table.concat(tip, "\n"):find("cost to make", 1, true),
     table.concat(tip, "\n"))
win.unlearned:SetChecked(false)
win.unlearned:GetScript("OnClick")(win.unlearned)
T.ok("turning it off goes back to known recipes only", win.total == 3, tostring(win.total))

-- Closing
M.fire("AUCTION_HOUSE_CLOSED")
T.ok("stays open while the profession window is open", win:IsShown())
M.fire("TRADE_SKILL_CLOSE")
T.ok("closes when both are closed", not win:IsShown())
M.state.now = 100000 + 3 * 3600
SLASH("")
T.ok("/cp opens it any time, with price ages", win:IsShown() and strip(win.status:GetText()):find("Prices from 3h ago", 1, true),
     strip(win.status:GetText()))
SLASH("scan")
T.ok("scanning away from the AH says to open it", M.printedText():find("Open the auction house first", 1, true))

T.done()
