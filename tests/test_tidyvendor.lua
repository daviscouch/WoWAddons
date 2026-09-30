package.path = "tests/?.lua;" .. package.path
local M = require("mock")
local T = require("check")

-- Items: greys, a white, a grey with no value, a grey on the never-sell list
M.items = {
  [100] = { name = "Broken Fang", quality = 0, classID = 15, subID = 0, sellPrice = 12 },
  [101] = { name = "Torn Cloth", quality = 0, classID = 15, subID = 0, sellPrice = 5 },
  [102] = { name = "Linen Cloth", quality = 1, classID = 7, subID = 5, sellPrice = 13 },
  [103] = { name = "Worthless Pebble", quality = 0, classID = 15, subID = 0, sellPrice = 0 },
  [104] = { name = "Lucky Grey Charm", quality = 0, classID = 15, subID = 0, sellPrice = 40 },
  [105] = { name = "Surplus Potion", quality = 1, classID = 0, subID = 1, sellPrice = 25 },
}
local function fillBags()
  M.setBags({
    [0] = { [1] = { id = 100, count = 3 }, [2] = { id = 102, count = 20 }, [3] = { id = 103 },
            [4] = { id = 101, count = 2 }, [5] = { id = 104 }, [6] = { id = 105, count = 2 } },
  })
  M.used = {}
end

-- Repair mocks
local repairs = {}
function CanMerchantRepair() return M.state.canRepair end
function GetRepairAllCost() return M.state.repairCost or 0, (M.state.repairCost or 0) > 0 end
function RepairAllItems(guild) repairs[#repairs + 1] = guild and "guild" or "self" end
function CanGuildBankRepair() return M.state.guildRepair end
function IsInGuild() return M.state.guildRepair end

dofile("TidyVendor/TidyVendor.lua")
local SLASH = SlashCmdList.TIDYVENDOR

-- 1. Sells greys only, one at a time, and reports the total
fillBags()
M.state.canRepair, M.state.repairCost = true, 1234
M.clearPrinted()
M.fire("MERCHANT_SHOW")
M.flush()
local used = table.concat(M.used, ",")
T.ok("sells only grey items with a sell price", used == "0:1,0:4,0:5", used)
T.ok("reports what it earned (3x12 + 2x5 + 40 = 86c)", M.printedText():find("Sold 3 junk items for 86c", 1, true), M.printedText())
T.ok("repairs and reports the cost", repairs[1] == "self" and M.printedText():find("Repaired for 12s 34c", 1, true), M.printedText())

-- 2. Never-sell list and always-sell list
fillBags()
SLASH("keep " .. M.link(104))
SLASH("add " .. M.link(105))
M.clearPrinted()
M.fire("MERCHANT_SHOW")
M.flush()
used = table.concat(M.used, ",")
T.ok("never-sell keeps a grey; always-sell sells a white", used == "0:1,0:4,0:6", used)

-- 3. Shift skips everything
fillBags()
repairs = {}
M.state.shift = true
M.clearPrinted()
M.fire("MERCHANT_SHOW")
M.flush()
M.state.shift = false
T.ok("holding Shift skips selling and repairing", #M.used == 0 and #repairs == 0 and M.printedText():find("Skipped", 1, true))

-- 4. Vendor closed mid-sale: stops
fillBags()
M.fire("MERCHANT_SHOW")      -- sells the first item immediately, queues the rest
M.fire("MERCHANT_CLOSED")
M.flush()
T.ok("stops selling when the vendor closes", #M.used == 1, table.concat(M.used, ","))

-- 5. Guild repairs preferred when allowed; not enough money
repairs = {}
M.state.guildRepair = true
M.fire("MERCHANT_SHOW") M.fire("MERCHANT_CLOSED") M.flush()
T.ok("uses guild bank repairs when available", repairs[1] == "guild", tostring(repairs[1]))
repairs = {}
M.state.guildRepair, M.state.money, M.state.repairCost = false, 500, 1234
M.clearPrinted()
M.fire("MERCHANT_SHOW") M.fire("MERCHANT_CLOSED") M.flush()
T.ok("doesn't repair without enough money, and says so", #repairs == 0 and M.printedText():find("only have", 1, true), M.printedText())

-- 6. Toggles and status
fillBags()
M.clearPrinted()
SLASH("sell")
SLASH("")
T.ok("/tv sell toggles off and status shows it", M.printedText():find("Sell junk off", 1, true), M.printedText())
M.used = {}
M.fire("MERCHANT_SHOW") M.flush()
T.ok("selling off: nothing sold", #M.used == 0)
SLASH("sell")
SLASH("list")
T.ok("/tv list shows both lists", M.printedText():find("Never sell: [^\n]*Lucky Grey Charm")
  and M.printedText():find("Always sell: [^\n]*Surplus Potion"), M.printedText())

T.done()
