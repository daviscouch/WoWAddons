-- CraftProfit: what your recipes cost to make and what they sell for on the auction house.
--  * Prices come from auction house scans (per-recipe search, or a full scan every 15 minutes)
--    and from vendors you visit (for thread, dye, salt...). Saved per realm.
--  * The CraftProfit window lists your learned recipes sorted by profit.
--  * Item tooltips show the auction price and, for things you craft, the profit.
CraftProfitDB = CraftProfitDB or {}

local GetInfo = (C_Item and C_Item.GetItemInfo) or GetItemInfo
local GetInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
local GetCount = (C_Item and C_Item.GetItemCount) or GetItemCount

local AH_CUT = 0.05          -- the auction house keeps 5% of the sale
local FULL_SCAN_COOLDOWN = 15 * 60
local QUERY_TIMEOUT = 4      -- seconds to wait for one search before moving on

local function Say(msg) print("|cff33ff99CraftProfit:|r " .. msg) end
local function Now() return (time and time()) or 0 end

---------------------------------------------------------------------------
-- Money and time formatting
---------------------------------------------------------------------------
local function Money(copper, signed)
  if not copper then return "|cff888888?|r" end
  local neg = copper < 0
  copper = math.floor(math.abs(copper) + 0.5)
  local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
  local out = {}
  if g > 0 then out[#out + 1] = g .. "|cffffd700g|r" end
  if s > 0 then out[#out + 1] = s .. "|cffc7c7cfs|r" end
  if c > 0 or #out == 0 then out[#out + 1] = c .. "|cffeda55fc|r" end
  return (neg and "-" or (signed and "+" or "")) .. table.concat(out, " ")
end

local function Age(t)
  if not t then return "never" end
  local s = Now() - t
  if s < 90 then return "just now" end
  if s < 3600 then return math.floor(s / 60) .. "m ago" end
  if s < 86400 * 2 then return math.floor(s / 3600) .. "h ago" end
  return math.floor(s / 86400) .. "d ago"
end

---------------------------------------------------------------------------
-- Price storage (per realm)
---------------------------------------------------------------------------
local function Realm()
  CraftProfitDB.realms = CraftProfitDB.realms or {}
  local key = GetRealmName and GetRealmName() or "?"
  local r = CraftProfitDB.realms[key]
  if not r then r = { ah = {}, vendor = {} } CraftProfitDB.realms[key] = r end
  r.ah, r.vendor = r.ah or {}, r.vendor or {}
  return r
end

-- AH unit price: { p = copper or false (none listed), t = time }
local function SetAH(itemID, price) Realm().ah[itemID] = { p = price or false, t = Now() } end
local function AH(itemID)
  local e = Realm().ah[itemID]
  if e then return e.p or nil, e.t, e.p == false end
  -- Auctionator, if installed, as a backup source
  if Auctionator and Auctionator.API and Auctionator.API.v1 and Auctionator.API.v1.GetAuctionPriceByItemID then
    local ok, p = pcall(Auctionator.API.v1.GetAuctionPriceByItemID, "CraftProfit", itemID)
    if ok and type(p) == "number" then return p, nil, false, "Auctionator" end
  end
end
local function Vendor(itemID) return Realm().vendor[itemID] end

-- Cheapest way to get one of a reagent: returns price, source ("AH"/"vendor"), age time
local function ReagentPrice(itemID)
  local ah, t = AH(itemID)
  local v = Vendor(itemID)
  if v and (not ah or v <= ah) then return v, "vendor" end
  if ah then return ah, "AH", t end
end

---------------------------------------------------------------------------
-- Recipes
---------------------------------------------------------------------------
local TS = C_TradeSkillUI

-- Crafting recipes: { id, name, profession, learned, output, qty, link, icon, reagents = { {itemID, count} } }
-- recipeCache.learned = the ones you know; recipeCache.unlearned = ones you don't, in professions you have
local recipeCache
local function BuildRecipes()
  local all = {}
  if not (TS and TS.GetAllRecipeIDs and TS.GetRecipeInfo and TS.GetRecipeSchematic) then return all end
  local ok, ids = pcall(TS.GetAllRecipeIDs)
  for _, id in ipairs((ok and ids) or {}) do
    local okI, info = pcall(TS.GetRecipeInfo, id)
    if okI and type(info) == "table" and not info.isDummyRecipe and not info.isGatheringRecipe
       and not info.isSalvageRecipe and not info.isEnchantingRecipe then
      local okS, s = pcall(TS.GetRecipeSchematic, id, false)
      if okS and type(s) == "table" and s.outputItemID then
        local r = { id = id, name = info.name or s.name, output = s.outputItemID, icon = info.icon, learned = info.learned and true or false,
                    qty = ((s.quantityMin or 1) + (s.quantityMax or s.quantityMin or 1)) / 2,
                    link = info.hyperlink, reagents = {} }
        for _, slot in ipairs(s.reagentSlotSchematics or {}) do
          local reagent = slot.reagents and slot.reagents[1]
          if slot.required ~= false and reagent and reagent.itemID then
            r.reagents[#r.reagents + 1] = { itemID = reagent.itemID, count = slot.quantityRequired or 1 }
          end
        end
        if TS.GetProfessionInfoByRecipeID then
          local okP, p = pcall(TS.GetProfessionInfoByRecipeID, id)
          if okP and type(p) == "table" then r.profession = p.parentProfessionName or p.professionName end
        end
        if r.profession == "" then r.profession = nil end
        all[#all + 1] = r
      end
    end
  end
  return all
end

local function Cache()
  if recipeCache then return recipeCache end
  local all = BuildRecipes()
  local learned, unlearned, mine = {}, {}, {}
  for _, r in ipairs(all) do
    if r.learned then learned[#learned + 1] = r if r.profession then mine[r.profession] = true end end
  end
  for _, r in ipairs(all) do
    if not r.learned and r.profession and mine[r.profession] then unlearned[#unlearned + 1] = r end
  end
  recipeCache = { learned = learned, unlearned = unlearned }
  return recipeCache
end

-- Recipes you know
local function Recipes() return Cache().learned end

-- What the window lists: what you know, plus (if turned on) what you could still learn
local function ListedRecipes()
  local c = Cache()
  if not CraftProfitDB.showUnlearned then return c.learned end
  local list = {}
  for _, r in ipairs(c.learned) do list[#list + 1] = r end
  for _, r in ipairs(c.unlearned) do list[#list + 1] = r end
  return list
end

-- Where to get a recipe you don't know (trainer, drop, vendor...)
local function RecipeSource(r)
  if not (TS and TS.GetRecipeSourceText) then return end
  local ok, text = pcall(TS.GetRecipeSourceText, r.id)
  if ok and type(text) == "string" and text ~= "" then return text end
end

-- Cost, value and profit for one recipe
local function Evaluate(r)
  local cost, missing = 0, false
  for _, g in ipairs(r.reagents) do
    local p = ReagentPrice(g.itemID)
    if p then cost = cost + p * g.count else missing = true end
  end
  local unit, t, none = AH(r.output)
  local value = unit and unit * r.qty * (1 - AH_CUT)
  local profit = (value and not missing) and (value - cost) or nil
  -- How many you can make from your bags
  local canMake
  for _, g in ipairs(r.reagents) do
    local have = (GetCount and GetCount(g.itemID)) or 0
    local n = math.floor(have / g.count)
    canMake = canMake and math.min(canMake, n) or n
  end
  if not r.learned then canMake = 0 end
  return { cost = (not missing) and cost or nil, partialCost = cost, missing = missing, value = value,
           profit = profit, age = t, noneListed = none, canMake = canMake or 0 }
end

-- Items to look up at the AH: every reagent and output of the recipes in the window
local function ItemsToScan()
  local seen, list = {}, {}
  for _, r in ipairs(ListedRecipes()) do
    local function add(id) if id and not seen[id] and not Vendor(id) then seen[id] = true list[#list + 1] = id end end
    add(r.output)
    for _, g in ipairs(r.reagents) do add(g.itemID) end
  end
  return list
end

---------------------------------------------------------------------------
-- Auction house scanning
---------------------------------------------------------------------------
local A = C_AuctionHouse
local ahOpen = false
local scan = nil   -- { kind = "recipes"|"full", queue, index, total, current, started }
local UpdateUI     -- forward declaration

local function SortByPrice()
  local order = (Enum and Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price) or 0
  return { { sortOrder = order, reverseSort = false } }
end

local function IsCommodity(itemID)
  if not (A and A.GetItemCommodityStatus) then return true end
  local ok, status = pcall(A.GetItemCommodityStatus, itemID)
  local ITEM = (Enum and Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Item) or 1
  return not (ok and status == ITEM)
end

local QueryNext

local function FinishScan(msg)
  local kind = scan and scan.kind
  scan = nil
  if msg then Say(msg) end
  if kind then UpdateUI() end
end

-- Save a search result and move to the next item. skip = true: no answer, so leave the price as it was.
local function Record(itemID, price, skip)
  if not skip then SetAH(itemID, price) end
  if scan and scan.current == itemID then
    scan.current = nil
    if C_Timer and C_Timer.After then C_Timer.After(0.05, QueryNext) else QueryNext() end
  end
end

function QueryNext()
  if not scan or scan.kind ~= "recipes" then return end
  if not ahOpen then return FinishScan("Scan stopped - the auction house closed.") end
  if scan.current then return end
  if A.IsThrottledMessageSystemReady and not A.IsThrottledMessageSystemReady() then return end   -- resumes on ready event
  scan.index = scan.index + 1
  local itemID = scan.queue[scan.index]
  if not itemID then return FinishScan("Scanned " .. scan.total .. " items.") end
  scan.current = itemID
  scan.isCommodity = IsCommodity(itemID)
  local okK, key = pcall(A.MakeItemKey, itemID)
  if not okK or not key then return Record(itemID, nil, true) end
  scan.key = key
  pcall(A.SendSearchQuery, key, SortByPrice(), true)
  UpdateUI()
  local mine = scan
  if C_Timer and C_Timer.After then
    C_Timer.After(QUERY_TIMEOUT, function()
      if scan == mine and scan.current == itemID then Record(itemID, nil, true) end   -- no answer: skip it
    end)
  end
end

local function OnCommodityResults(itemID)
  if not (scan and scan.current == itemID) then return end
  local n = A.GetNumCommoditySearchResults and A.GetNumCommoditySearchResults(itemID) or 0
  local price
  if n > 0 then
    local r = A.GetCommoditySearchResultInfo(itemID, 1)
    price = r and r.unitPrice
  end
  Record(itemID, price)
end

local function OnItemResults(itemKey)
  if not (scan and scan.current) then return end
  if type(itemKey) == "table" and itemKey.itemID and itemKey.itemID ~= scan.current then return end
  local key = scan.key
  local n = A.GetNumItemSearchResults and A.GetNumItemSearchResults(key) or 0
  local best
  for i = 1, math.min(n, 50) do
    local r = A.GetItemSearchResultInfo(key, i)
    local each = r and r.buyoutAmount and r.quantity and r.quantity > 0 and (r.buyoutAmount / r.quantity)
    if each and (not best or each < best) then best = each end
  end
  Record(scan.current, best)
end

local function StartRecipeScan()
  if not ahOpen then Say("Open the auction house first.") return end
  if scan then Say("Already scanning.") return end
  local queue = ItemsToScan()
  if #queue == 0 then Say("No recipes to scan. Open your profession window once so CraftProfit can see your recipes.") return end
  scan = { kind = "recipes", queue = queue, index = 0, total = #queue }
  Say("Scanning " .. #queue .. " reagents and crafted items...")
  QueryNext()
end

-- Full scan: one request for the whole auction house, then read it in chunks so the game doesn't freeze
local function ReadReplicate()
  local n = (A.GetNumReplicateItems and A.GetNumReplicateItems()) or 0
  local best = {}
  local i = 0
  local function chunk()
    local stop = math.min(i + 2000, n)
    while i < stop do
      local info = { A.GetReplicateItemInfo(i) }
      local count, buyout, itemID = info[3], info[10], info[17]
      if itemID and buyout and buyout > 0 and count and count > 0 then
        local each = buyout / count
        if not best[itemID] or each < best[itemID] then best[itemID] = each end
      end
      i = i + 1
    end
    if i < n and C_Timer and C_Timer.After then C_Timer.After(0, chunk) return end
    local items = 0
    for itemID, p in pairs(best) do SetAH(itemID, p) items = items + 1 end
    FinishScan("Full scan done: " .. n .. " auctions, prices for " .. items .. " items.")
  end
  chunk()
end

local function StartFullScan()
  if not ahOpen then Say("Open the auction house first.") return end
  if scan then Say("Already scanning.") return end
  local last = CraftProfitDB.lastFullScan or 0
  local wait = FULL_SCAN_COOLDOWN - (Now() - last)
  if wait > 0 then Say("The game allows a full scan every 15 minutes - try again in " .. math.ceil(wait / 60) .. " min.") return end
  if not (A and A.ReplicateItems) then Say("Full scan isn't available here - use Scan recipes.") return end
  CraftProfitDB.lastFullScan = Now()
  scan = { kind = "full", started = Now() }
  Say("Full scan started - this can take a minute...")
  pcall(A.ReplicateItems)
  UpdateUI()
  local mine = scan
  if C_Timer and C_Timer.After then
    C_Timer.After(90, function() if scan == mine then FinishScan("Full scan got no answer from the server.") end end)
  end
end

---------------------------------------------------------------------------
-- Vendor prices (recorded whenever you open a vendor)
---------------------------------------------------------------------------
local function RecordVendor()
  local n = (GetMerchantNumItems and GetMerchantNumItems()) or 0
  local v = Realm().vendor
  for i = 1, n do
    local link = GetMerchantItemLink and GetMerchantItemLink(i)
    local itemID = link and tonumber(link:match("item:(%d+)"))
    local price, stack, available, extended
    if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
      local ok, info = pcall(C_MerchantFrame.GetItemInfo, i)
      if ok and type(info) == "table" then
        price, stack, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
      end
    elseif GetMerchantItemInfo then
      local _, _, p, q, avail, _, ext = GetMerchantItemInfo(i)
      price, stack, available, extended = p, q, avail, ext
    end
    -- Only unlimited items bought with gold
    if itemID and price and price > 0 and not extended and (available == nil or available < 0) then
      v[itemID] = price / math.max(1, stack or 1)
    end
  end
end

---------------------------------------------------------------------------
-- UI: the CraftProfit window
---------------------------------------------------------------------------
local ROWS, ROW_H = 14, 22
local win = CreateFrame("Frame", "CraftProfitFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
local WIDTH = 580
win:SetSize(WIDTH, 110 + ROWS * ROW_H)
win:SetFrameStrata("HIGH")
win:SetClampedToScreen(true)
win:SetMovable(true)
win:EnableMouse(true)
win:RegisterForDrag("LeftButton")
win:SetScript("OnDragStart", win.StartMoving)
win:SetScript("OnDragStop", function(self)
  self:StopMovingOrSizing()
  local point, _, rel, x, y = self:GetPoint()
  CraftProfitDB.pos = { point, rel, x, y }
end)
if win.SetBackdrop then
  win:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
                    tile = true, tileSize = 16, edgeSize = 14, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
end
win:Hide()
tinsert(UISpecialFrames or {}, "CraftProfitFrame")   -- Esc closes it

win.title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
win.title:SetPoint("TOPLEFT", 12, -10)
win.close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
win.close:SetPoint("TOPRIGHT", 0, 0)
win.status = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
win.status:SetPoint("TOPLEFT", 12, -32)
win.status:SetWidth(WIDTH - 24)
win.status:SetJustifyH("LEFT")

local function Button(text, width, onClick)
  local b = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
  b:SetSize(width, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end
win.scanRecipes = Button("Scan recipes", 110, StartRecipeScan)
win.scanRecipes:SetPoint("BOTTOMLEFT", 10, 10)
win.scanFull = Button("Full scan", 90, StartFullScan)
win.scanFull:SetPoint("LEFT", win.scanRecipes, "RIGHT", 6, 0)
win.makeable = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
win.makeable:SetSize(24, 24)
win.makeable:SetPoint("BOTTOMRIGHT", -130, 9)
win.makeable.label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
win.makeable.label:SetPoint("LEFT", win.makeable, "RIGHT", 2, 0)
win.makeable.label:SetText("Only what I can make")
win.makeable:SetScript("OnClick", function(self) CraftProfitDB.onlyMakeable = self:GetChecked() and true or false UpdateUI() end)
win.unlearned = CreateFrame("CheckButton", nil, win, "UICheckButtonTemplate")
win.unlearned:SetSize(24, 24)
win.unlearned:SetPoint("BOTTOMRIGHT", -270, 9)
win.unlearned.label = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
win.unlearned.label:SetPoint("LEFT", win.unlearned, "RIGHT", 2, 0)
win.unlearned.label:SetText("Show unlearned")
win.unlearned:SetScript("OnClick", function(self)
  CraftProfitDB.showUnlearned = self:GetChecked() and true or false
  win.offset = 0
  UpdateUI()
end)

-- Column headers
-- { header, x, width }: numbers are right-aligned under right-aligned headers
local COLS = { { "Recipe", 12, 214 }, { "Cost", 232, 76 }, { "Sells for", 314, 80 }, { "Profit", 400, 86 }, { "Craft now", 492, 72 } }
for c, col in ipairs(COLS) do
  local h = win:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  h:SetPoint("TOPLEFT", col[2] + (c == 1 and 22 or 0), -52)
  h:SetWidth(col[3] - (c == 1 and 22 or 0))
  h:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
  h:SetText(col[1])
end

win.rows = {}
for i = 1, ROWS do
  local row = CreateFrame("Button", nil, win)
  row:SetSize(WIDTH - 16, ROW_H)
  row:SetPoint("TOPLEFT", 8, -66 - (i - 1) * ROW_H)
  row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(18, 18)
  row.icon:SetPoint("LEFT", 4, 0)
  row.cells = {}
  for c, col in ipairs(COLS) do
    local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", col[2] - 8 + (c == 1 and 22 or 0), 0)
    fs:SetWidth(col[3] - (c == 1 and 22 or 0))
    fs:SetJustifyH(c == 1 and "LEFT" or "RIGHT")
    fs:SetWordWrap(false)
    row.cells[c] = fs
  end
  win.rows[i] = row
end

win.offset = 0
win:EnableMouseWheel(true)
win:SetScript("OnMouseWheel", function(self, delta)
  self.offset = math.max(0, math.min((self.total or 0) - ROWS, self.offset - delta * 3))
  UpdateUI()
end)

local function ReagentTooltip(row)
  local r, e = row.recipe, row.eval
  if not r then return end
  -- Open on whichever side of the window has more room
  local x = win:GetCenter()
  GameTooltip:SetOwner(row, (x and x > UIParent:GetWidth() / 2) and "ANCHOR_LEFT" or "ANCHOR_RIGHT")
  GameTooltip:SetText(r.name .. (r.qty ~= 1 and (" (makes " .. r.qty .. ")") or ""))
  if not r.learned then
    GameTooltip:AddLine("You haven't learned this recipe yet.", 1, 0.6, 0.2)
    local source = RecipeSource(r)
    if source then GameTooltip:AddLine(source, 0.8, 0.8, 0.8, true) end
  end
  local short = {}
  for _, g in ipairs(r.reagents) do
    local p, source, t = ReagentPrice(g.itemID)
    local name = (GetInfo(g.itemID)) or ("item " .. g.itemID)
    local have = (GetCount and GetCount(g.itemID)) or 0
    if have < g.count then short[#short + 1] = name .. " (have " .. have .. " of " .. g.count .. ")" end
    local detail = p and (Money(p * g.count) .. " |cff888888(" .. source .. (t and (", " .. Age(t)) or "") .. ")|r") or "|cffff6666no price - scan at the AH|r"
    GameTooltip:AddDoubleLine(g.count .. "x " .. name .. " |cff888888(you have " .. have .. ")|r", detail, 1, 1, 1, 1, 1, 1)
  end
  if not r.learned then
    -- nothing to say about crafting it now
  elseif e.canMake > 0 then
    GameTooltip:AddLine("You have materials to craft " .. e.canMake .. " right now.", 0.2, 1, 0.2)
  elseif #short > 0 then
    GameTooltip:AddLine("Can't craft right now - missing: " .. table.concat(short, ", "), 1, 0.4, 0.4, true)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddDoubleLine("Cost to make", Money(e.cost), 1, 0.82, 0, 1, 1, 1)
  if e.value then
    GameTooltip:AddDoubleLine("Sells for (after 5% AH cut)", Money(e.value), 1, 0.82, 0, 1, 1, 1)
    GameTooltip:AddLine("Auction price from " .. Age(e.age), 0.6, 0.6, 0.6)
  elseif e.noneListed then
    GameTooltip:AddLine("None on the auction house at the last scan.", 1, 0.4, 0.4)
  else
    GameTooltip:AddLine("No auction price yet - scan at the AH.", 1, 0.4, 0.4)
  end
  GameTooltip:Show()
end

function UpdateUI()
  if not win:IsShown() then return end
  local rows = {}
  for _, r in ipairs(ListedRecipes()) do
    local e = Evaluate(r)
    if not CraftProfitDB.onlyMakeable or e.canMake > 0 then rows[#rows + 1] = { r = r, e = e } end
  end
  -- Most profitable first; recipes with missing prices at the bottom
  table.sort(rows, function(a, b)
    local pa, pb = a.e.profit, b.e.profit
    if pa and pb then return pa > pb end
    if pa or pb then return pa ~= nil end
    return a.r.name < b.r.name
  end)
  win.total = #rows
  win.offset = math.max(0, math.min(win.offset, #rows - ROWS))
  local profession
  for _, x in ipairs(rows) do if x.r.profession then profession = x.r.profession break end end
  win.title:SetText("CraftProfit" .. (profession and (" - " .. profession) or ""))

  for i, row in ipairs(win.rows) do
    local x = rows[i + win.offset]
    if x then
      local r, e = x.r, x.e
      row.recipe, row.eval = r, e
      row.icon:SetTexture(r.icon or select(5, GetInstant(r.output)))
      row.cells[1]:SetText(r.learned and r.name or ("|cff9d9d9d" .. r.name .. "|r"))
      row.cells[2]:SetText(e.cost and Money(e.cost) or (e.missing and "|cff888888?|r"))
      row.cells[3]:SetText(e.value and Money(e.value) or (e.noneListed and "|cffff6666none|r" or "|cff888888?|r"))
      if e.profit then
        row.cells[4]:SetText((e.profit >= 0 and "|cff33ff33" or "|cffff4040") .. Money(e.profit, true) .. "|r")
      else
        row.cells[4]:SetText("|cff888888?|r")
      end
      row.cells[5]:SetText((not r.learned) and "|cff888888not learned|r" or (e.canMake > 0 and e.canMake or "|cff8888880|r"))
      row:SetScript("OnEnter", ReagentTooltip)
      row:SetScript("OnLeave", function() GameTooltip:Hide() end)
      row:Show()
    else
      row.recipe = nil
      row:Hide()
    end
  end

  -- Status line
  local status
  if scan and scan.kind == "recipes" then
    status = "Scanning " .. math.min(scan.index, scan.total) .. " of " .. scan.total .. "..."
  elseif scan and scan.kind == "full" then
    status = "Full scan in progress..."
  elseif #rows == 0 then
    status = CraftProfitDB.onlyMakeable and "Nothing you can make from your bags right now."
             or "No recipes yet - open your profession window once."
  else
    local newest
    for _, x in ipairs(rows) do if x.e.age and (not newest or x.e.age > newest) then newest = x.e.age end end
    local shown = (#rows > ROWS) and (" Showing " .. (win.offset + 1) .. "-" .. math.min(#rows, win.offset + ROWS)
                                         .. " - scroll for more.") or ""
    local unl = 0
    for _, x in ipairs(rows) do if not x.r.learned then unl = unl + 1 end end
    status = #rows .. " recipes" .. (unl > 0 and (" (" .. unl .. " not learned)") or "") .. ". Prices from " .. Age(newest) .. "." .. shown .. (ahOpen and "" or " Open the auction house to scan.")
  end
  win.status:SetText(status)
  win.scanRecipes:SetEnabled(ahOpen and not scan)
  local wait = FULL_SCAN_COOLDOWN - (Now() - (CraftProfitDB.lastFullScan or 0))
  win.scanFull:SetEnabled(ahOpen and not scan and wait <= 0)
  win.makeable:SetChecked(CraftProfitDB.onlyMakeable and true or false)
  win.unlearned:SetChecked(CraftProfitDB.showUnlearned and true or false)
end

local function PlaceWindow()
  win:ClearAllPoints()
  local p = CraftProfitDB.pos
  if p then win:SetPoint(p[1], UIParent, p[2], p[3], p[4]) else win:SetPoint("LEFT", UIParent, "CENTER", 60, 0) end
end

local function Open() PlaceWindow() win:Show() UpdateUI() end
win:SetScript("OnShow", function() UpdateUI() end)

---------------------------------------------------------------------------
-- Item tooltips
---------------------------------------------------------------------------
local craftedBy
local function CraftedBy(itemID)
  if not craftedBy then
    craftedBy = {}
    for _, r in ipairs(Recipes()) do craftedBy[r.output] = craftedBy[r.output] or r end
  end
  return craftedBy[itemID]
end

local function AddTooltipLines(tt, itemID)
  if not itemID or tt ~= GameTooltip and tt ~= ItemRefTooltip then return end
  local p, t, none, src = AH(itemID)
  local v = Vendor(itemID)
  local added = false
  if p then
    tt:AddDoubleLine("|cff33ff99CraftProfit|r AH", Money(p) .. " |cff888888" .. (src or Age(t)) .. "|r", 1, 1, 1, 1, 1, 1)
    added = true
  elseif none then
    tt:AddDoubleLine("|cff33ff99CraftProfit|r AH", "|cffff6666none listed|r |cff888888" .. Age(t) .. "|r", 1, 1, 1, 1, 1, 1)
    added = true
  end
  if v then tt:AddDoubleLine("|cff33ff99CraftProfit|r vendor", Money(v), 1, 1, 1, 1, 1, 1) added = true end
  local r = CraftedBy(itemID)
  if r then
    local e = Evaluate(r)
    tt:AddDoubleLine("|cff33ff99CraftProfit|r cost to make", Money(e.cost), 1, 1, 1, 1, 1, 1)
    if e.profit then
      tt:AddDoubleLine("|cff33ff99CraftProfit|r profit", (e.profit >= 0 and "|cff33ff33" or "|cffff4040") .. Money(e.profit, true) .. "|r", 1, 1, 1, 1, 1, 1)
    end
    added = true
  end
  if added then tt:Show() end
end

local function SetupTooltips()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tt, data)
      local id = data and data.id
      if not id and tt.GetItem then
        local _, link = tt:GetItem()
        id = link and tonumber(link:match("item:(%d+)"))
      end
      pcall(AddTooltipLines, tt, id)
    end)
  end
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_CRAFTPROFIT1 = "/cp"
SLASH_CRAFTPROFIT2 = "/craftprofit"
SlashCmdList["CRAFTPROFIT"] = function(msg)
  local cmd = ((msg or ""):match("^(%S*)") or ""):lower()
  if cmd == "scan" then StartRecipeScan()
  elseif cmd == "fullscan" then StartFullScan()
  elseif cmd == "auto" then
    CraftProfitDB.noAutoOpen = not CraftProfitDB.noAutoOpen
    Say("Open automatically with professions / the auction house: " .. (CraftProfitDB.noAutoOpen and "off" or "on") .. ".")
  elseif cmd == "reset" then
    CraftProfitDB.pos = nil
    PlaceWindow()
  elseif cmd == "help" or cmd == "?" then
    Say("/cp - show or hide the window  |  /cp scan - scan your recipes' items (at the AH)")
    Say("/cp fullscan - scan the whole auction house (every 15 min)  |  /cp auto - auto-open on/off  |  /cp reset - move the window back")
  else
    if win:IsShown() then win:Hide() else Open() end
  end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local f = CreateFrame("Frame")
local EVENTS = { "PLAYER_LOGIN", "TRADE_SKILL_SHOW", "TRADE_SKILL_CLOSE", "TRADE_SKILL_LIST_UPDATE", "NEW_RECIPE_LEARNED",
                 "AUCTION_HOUSE_SHOW", "AUCTION_HOUSE_CLOSED", "COMMODITY_SEARCH_RESULTS_UPDATED", "ITEM_SEARCH_RESULTS_UPDATED",
                 "AUCTION_HOUSE_THROTTLED_SYSTEM_READY", "REPLICATE_ITEM_LIST_UPDATE", "MERCHANT_SHOW", "BAG_UPDATE_DELAYED" }
for _, ev in ipairs(EVENTS) do pcall(f.RegisterEvent, f, ev) end

local professionOpen = false
f:SetScript("OnEvent", function(_, event, arg)
  if event == "PLAYER_LOGIN" then
    CraftProfitDB = CraftProfitDB or {}
    CraftProfitDB.probe = nil   -- left over from the 0.0.1 probe build
    SetupTooltips()
  elseif event == "TRADE_SKILL_SHOW" then
    professionOpen = true
    recipeCache, craftedBy = nil, nil
    if not CraftProfitDB.noAutoOpen then Open() end
  elseif event == "TRADE_SKILL_CLOSE" then
    professionOpen = false
    if not ahOpen then win:Hide() end
  elseif event == "TRADE_SKILL_LIST_UPDATE" or event == "NEW_RECIPE_LEARNED" then
    recipeCache, craftedBy = nil, nil
    UpdateUI()
  elseif event == "AUCTION_HOUSE_SHOW" then
    ahOpen = true
    if not CraftProfitDB.noAutoOpen then Open() else UpdateUI() end
  elseif event == "AUCTION_HOUSE_CLOSED" then
    ahOpen = false
    if scan and scan.kind == "recipes" then FinishScan("Scan stopped - the auction house closed.") end
    if not professionOpen then win:Hide() end
  elseif event == "COMMODITY_SEARCH_RESULTS_UPDATED" then
    pcall(OnCommodityResults, arg)
  elseif event == "ITEM_SEARCH_RESULTS_UPDATED" then
    pcall(OnItemResults, arg)
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    QueryNext()
  elseif event == "REPLICATE_ITEM_LIST_UPDATE" then
    if scan and scan.kind == "full" then pcall(ReadReplicate) end
  elseif event == "MERCHANT_SHOW" then
    pcall(RecordVendor)
  elseif event == "BAG_UPDATE_DELAYED" then
    UpdateUI()
  end
end)
