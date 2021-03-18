-- Configuration ----------------------
TLA_AUTOTRACKER_DEBUG = true
---------------------------------------

print("")
print("Active Auto-Tracker Configuration")
print("")
print("Enable Item Tracking:       ", AUTOTRACKER_ENABLE_ITEM_TRACKING)
print("Enable Location Tracking:   ", AUTOTRACKER_ENABLE_LOCATION_TRACKING)
if TLA_AUTOTRACKER_DEBUG then
   print("Enable Debug Logging:       ", TLA_AUTOTRACKER_DEBUG)
end
print("")

function autotracker_started()
   print("Started Tracking")
end

U8_READ_CACHE = 0
U8_READ_CACHE_ADDRESS = 0
U16_READ_CACHE = 0
U15_READ_CACHE_ADDRESS = 0

function InvalidateReadCaches()
   U8_READ_CACHE_ADDRESS = 0
   U16_READ_CACHE_ADDRESS = 0
end

function ReadU8(segment, address)
   if U8_READ_CACHE_ADDRESS ~= address then
      U8_READ_CACHE = segment:ReadUInt8(address)
      U8_READ_CACHE_ADDRESS = address
   end
   return U8_READ_CACHE
end

function ReadU16(segment, address)
   if U16_READ_CACHE_ADDRESS ~= address then
      U16_READ_CACHE = segment:ReadUInt16(address)
      U16_READ_CACHE_ADDRESS = address
   end
   return U16_READ_CACHE
end

function isInGame()
   return AutoTracker:ReadU8(0x0200042c) > 0x1
end

function getAddress(bitFlag)
   return 0x02000040 + (bitFlag // 8)
end

function getFlag(bitFlag)
   return 1 << (bitFlag % 8)
end

function checkFlag(bitFlag)
   local address = getAddress(bitFlag)
   local flag = getFlag(bitFlag)
   local value = AutoTracker:ReadU8(address)
   return (value & flag) > 0
end

function checkFlagWithSegment(segment, bitFlag)
   local address = getAddress(bitFlag)
   local flag = getFlag(bitFlag)
   local value = ReadU8(segment, address)
   return (value & flag) > 0
end

function updateStateWithSegment(segment, callback)
   -- loop over locations
   for location, bfTable in pairs(bitFlags) do
      -- loop over sets at the location
      for i, bitFlagSet in pairs(bfTable) do
	 for j, flag in pairs(bitFlagSet) do
	    if callback(flag) then
	       currentState[flag] = checkFlagWithSegment(segment, flag)
	    end
	 end                
      end
   end
end

function updateChestCounts()
   -- loop over places
   for location, trackerTable in pairs(locationTrackers) do
      -- loop over chest sets
      for i, tracker in pairs(trackerTable) do
	 flags = bitFlags[location][i]
	 chestCount = 0
	 for j, flag in pairs(flags) do
	    chestCount = chestCount + (currentState[flag] and 0 or 1)
	 end
	 tracker.AvailableChestCount = chestCount
      end 
   end
end

-- maps vanilla flag to index of rando djinn table
djinnTable = {}
local index = 0
for element=0,3 do
   for id=0,0x11 do
      flag = element*0x14 + id + 0x30
      djinnTable[flag] = index
      index = index + 1
   end
end

-- maps vanilla flag to rando flag
function convertDjinnFlag(flag)
   local i = djinnTable[flag]
   local newId = AutoTracker:ReadU8(0x08fa0000 + 2*i)
   local newElem = AutoTracker:ReadU8(0x08fa0000 + 2*i+1)
   return newElem*0x14 + newId + 0x30
end

function updateHosts(segment, callback)
   for location, trackerTable in pairs(hostTrackers) do
      for i, tracker in pairs(trackerTable) do
	 flag = hostFlags[location][i]
	 if callback(flag) then
	    if tracker.Name == 'Djinni' then
	       -- remap flag
	       flag = convertDjinnFlag(flag)
	    end
	    tracker.HostedItem.Active = checkFlagWithSegment(segment, flag)
	 end
      end
   end
end

function isChestFlag(bitFlag)
   return bitFlag >= 0x800
end

function isTabletFlag(bitFlag)
   return bitFlag < 0x20
end

function isDjinnFlag(bitFlag)
   return (bitFlag >= 0x30) and (bitFlag < 0x80)
end 

-- BitFlags in range [0x800, 0xFFF] (NONTABLETS)
function updateChests(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   print('updating chests')
   updateStateWithSegment(segment, isChestFlag)
   updateChestCounts()
end

-- BitFlags in range [0x10,0x1F]  (SUMMON TABLETS IN VANILLA)
function updateTablets(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   print('updating tablets')
   updateStateWithSegment(segment, isTabletFlag)
   updateChestCounts()
end


function updateItemHosts(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   print('updating item hosts')
   updateHosts(segment, isChestFlag)
   -- Overwrite Large Bread (0x902) if Jailbreak (0x97F) is on
   -- NOTE: currentStates aren't set so this line will not work!
   tracker = Tracker:FindObjectForCode("@Alhafra/Large Bread")
   tracker.HostedItem.Active = checkFlag(0x902) or checkFlag(0x97F)
end

function updateDjinnHosts(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   print('updating djinn hosts')
   updateHosts(segment, isDjinnFlag)
end



-------------------
-- global tables --
-------------------
-- Data read from location file weyard.json.
-- File must be overwritten when using the door shuffler.
currentState = {}
locationTrackers = {}
bitFlags = {}
hostTrackers = {}
hostFlags = {}
function loadData(code)
   local data = Tracker:FindObjectForCode(code)
   if (data == nil) then 
      return nil
   end
   
   local size = tonumber(data.Sections.Count)

   -- Get location
   location = string.sub(code, 2) -- remove "@"
   locationTrackers[location] = {}
   bitFlags[location] = {}
   hostTrackers[location] = {}
   hostFlags[location] = {}
   
   -- Loop over and store trackers and flag sets
   local i = 0
   while (i < size) do
      tracker = data.Sections[i]
      if tracker.HostedItem ~= nil then
	 table.insert(hostTrackers[location], tracker)
	 -- WILL NEVER BE MORE THAN 1 FLAG IN HOSTED SET
	 flag = tonumber(data.Children[i].Name)
	 table.insert(hostFlags[location], flag)
      else
	 locationTrackers[location][i] = tracker
	 flags = data.Children[i].Name
	 bitFlags[location][i] = {}
	 for flag in string.gmatch(flags, '([^,]+)') do
	    f = tonumber(flag)
	    table.insert(bitFlags[location][i], f)
	    currentState[f] = false
	 end
      end
      i = i + 1
   end
end

loadData("@Airs Rock")
loadData("@Alhafra")
loadData("@Alhafra Cave")
loadData("@Anemos Inner Sanctum")
loadData("@Angara Cavern")
loadData("@Ankohl Ruins")
loadData("@Apojii Islands")
loadData("@Aqua Rock")
loadData("@Atteka Cavern")
loadData("@Atteka Inlet")
loadData("@Champa")
loadData("@Contigo")
loadData("@Daila")
loadData("@Dekhan Plateau")
loadData("@E Tundaria Islet")
loadData("@Gabomba Catacombs")
loadData("@Gabomba Statue")
loadData("@Gaia Rock")
loadData("@Garoh")
loadData("@Gondowan Cliffs")
loadData("@Gondowan Settlement")
loadData("@Hesperia Settlement")
loadData("@Idejima")
loadData("@Indra Cavern")
loadData("@Islet Cave")
loadData("@Izumo")
loadData("@Jupiter Lighthouse")
loadData("@Kalt Island")
loadData("@Kandorean Temple")
loadData("@Kibombo")
loadData("@Kibombo Mountains")
loadData("@Lemuria")
loadData("@Lemurian Ship")
loadData("@Loho")
loadData("@Madra")
loadData("@Madra Catacombs")
loadData("@Magma Rock")
loadData("@Mars Lighthouse")
loadData("@Mikasalla")
loadData("@N Osenia Islet")
loadData("@Naribwe")
loadData("@Northern Reaches")
loadData("@Osenia Cavern")
loadData("@Osenia Cliffs")
loadData("@Prox")
loadData("@SE Angara Islet")
loadData("@SW Atteka Islet")
loadData("@Sea of Time Islet")
loadData("@Shaman Village")
loadData("@Shaman Village Cave")
loadData("@Shrine of the Sea God")
loadData("@Taopo Swamp")
loadData("@Treasure Isle")
loadData("@Tundaria Tower")
loadData("@W Indra Islet")
loadData("@Yallam")
loadData("@Yampi Desert")
loadData("@Yampi Desert Cave")
-- In ocean
loadData("@Overworld 1")
loadData("@Overworld 2")
loadData("@Overworld 3")
loadData("@Overworld 4")
loadData("@Overworld 5")
-- Overworld Djinn
loadData("@Indra (North)")
loadData("@Indra (South)")
loadData("@Osenia")
loadData("@Gondowan")
loadData("@Atteka")
loadData("@Hesperia")
loadData("@Tundaria")



-- updates djinn counts
function updateDjinn(segment)
   if not isInGame() then
      return false
   end

   InvalidateReadCaches()

   local address = 0x02000046
   local elements = {[0] = 0, [1] = 0, [2] = 0, [3] = 0}

   local i = 0
   while (i < 80) do
      value = ReadU8(segment, address)
      j = 0
      while (value > 0) do
	 idx = (i+j) // 20
	 elements[idx] = elements[idx] + (value & 1)
	 value = value >> 1
	 j = j + 1
      end
      i = i + 8
      address = address + 1
   end

   Tracker:FindObjectForCode("venus").AcquiredCount = elements[0]
   Tracker:FindObjectForCode("mercury").AcquiredCount = elements[1]
   Tracker:FindObjectForCode("mars").AcquiredCount = elements[2]
   Tracker:FindObjectForCode("jupiter").AcquiredCount = elements[3]
end


psynergyTable = {}
psynergyTable[0xc]  = 'growth'
psynergyTable[0x18] = 'frost_jewel'
psynergyTable[0x21] = 'douse_drop'
psynergyTable[0x4e] = 'whirlwind'
psynergyTable[0x8d] = 'mind_read'
psynergyTable[0x85] = 'lash_pebble'
psynergyTable[0x86] = 'pound_cube'
psynergyTable[0x87] = 'tremor_bit'
psynergyTable[0x88] = 'scoop_gem'
psynergyTable[0x89] = 'cyclone_chip'
psynergyTable[0x8a] = 'parch'
psynergyTable[0x8b] = 'sand'
psynergyTable[0x8e] = 'orb_of_force'
psynergyTable[0x8f] = 'lifting_gem'
psynergyTable[0x90] = 'reveal'
psynergyTable[0x93] = 'carry_stone'
psynergyTable[0x94] = 'catch_beads'
psynergyTable[0x97] = 'burst_brooch'
psynergyTable[0x98] = 'grindstone'
psynergyTable[0x99] = 'hover_jade'
psynergyTable[0x9a] = 'blaze'
psynergyTable[0x9c] = 'teleport_lapis'

function updatePsynergy(segment, pc)
   local address = 0x02000578 + 0x14c*pc
   local i = 0
   while (i < 32)
   do
      value = 0xfff & ReadU16(segment, address+i*4)
      code = psynergyTable[value]
      if code ~= nil
      then
	 obj = Tracker:FindObjectForCode(code)
	 obj.Active = true
      end
      i = i+1
   end
end

function checkIsaacPsynergy(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updatePsynergy(segment, 0)
end

function checkGaretPsynergy(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updatePsynergy(segment, 1)
end

function checkIvanPsynergy(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updatePsynergy(segment, 2)
end

function checkMiaPsynergy(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updatePsynergy(segment, 3)
end

function checkFelixPsynergy(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updatePsynergy(segment, 4)
end

function checkJennaPsynergy(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updatePsynergy(segment, 5)
end

function checkShebaPsynergy(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updatePsynergy(segment, 6)
end

function checkPiersPsynergy(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updatePsynergy(segment, 7)
end



itemTable = {}
itemTable[0x41]  = "shaman's_rod"
itemTable[0xde]  = 'mars_star'            -- mythril bag with mars star
itemTable[0xe5]  = 'lucky_medal'          -- should check for (vanilla) eclipse flag too; add to chest checker/updater
itemTable[0xf2]  = 'black_crystal'
itemTable[0xf3]  = 'red_key'
itemTable[0xf4]  = 'blue_key'
itemTable[0x146] = 'trident'
itemTable[0x1b7] = 'right_prong'
itemTable[0x1b8] = 'left_prong'
itemTable[0x1b9] = 'center_prong'
itemTable[0x1bb] = 'mysterious_card'
itemTable[0x1bc] = "trainer's_whip"
itemTable[0x1bd] = 'tomegathericon'
itemTable[0x1c0] = 'healing_fungus'
itemTable[0x1c1] = 'laughing_fungus'
itemTable[0x1c3] = 'dancing_idol'
itemTable[0x1c8] = 'aquarius_stone'
itemTable[0x1ca] = "sea_god's_tear"
itemTable[0x1cb] = 'ruin_key'
itemTable[0x1cc] = 'magma_ball'
itemTable[0x1c4] = 'pretty_stone'
itemTable[0x1c5] = 'red_cloth'
itemTable[0x1c6] = 'milk'
itemTable[0x1c7] = "li'l_turtle"

function checkIfUsed(code, bitFlag)
   item = Tracker:FindObjectForCode(code)
   used = checkFlag(bitFlag)
   item.Active = item.Active or used
end

function checkIfSold(code, address)
   item = Tracker:FindObjectForCode(code)
   sold = AutoTracker:ReadU8(address) > 0
   item.Active = item.Active or sold
end

function updateInventory(segment, pc)
   local address = 0x020005f8 + 0x14c*pc
   local i = 0
   while (i < 15) do
      value = 0x1ff & ReadU16(segment, address+i*2)
      if itemTable[value] ~= nil then
	 code = itemTable[value]
	 obj = Tracker:FindObjectForCode(code)
	 obj.Active = true
      end
      i = i+1
   end

   -- Update items if used and no longer in the inventory
   -- Flags won't always be in currentState table.
   checkIfUsed("milk", 0xAA1)
   checkIfUsed("red_cloth", 0xAA3)
   checkIfUsed("pretty_stone", 0xAA4)
   checkIfUsed("li'l_turtle", 0xAA5)
   checkIfUsed("lucky_medal", 0x90B)
   checkIfUsed("magma_ball", 0xA5F)
   checkIfUsed("dancing_idol", 0x9EE)
   checkIfUsed("aquarius_stone", 0x95D)
   checkIfUsed("right_prong", 0x975)
   checkIfUsed("left_prong", 0x976)
   checkIfUsed("center_prong", 0x977)
   checkIfUsed("ruin_key", 0x8C9)
   checkIfUsed("red_key", 0xA07)
   checkIfUsed("blue_key", 0xA08)
   checkIfUsed("healing_fungus", 0x98A)
   checkIfUsed("shaman's_rod", 0x94D)
   checkIfUsed("black_crystal", 0x8DE)

   -- Updated artifacts if sold
   checkIfSold("mysterious_card", 0x02002183)
   checkIfSold("trainer's_whip", 0x02002184)
   checkIfSold("tomegathericon", 0x02002185)
   checkIfSold("healing_fungus", 0x02002186)
   checkIfSold("dancing_idol", 0x02002187)
   checkIfSold("pretty_stone", 0x02002188)
   checkIfSold("red_cloth", 0x02002189)
   checkIfSold("milk", 0x0200218a)
   checkIfSold("li'l_turtle", 0x0200218b)
   checkIfSold("sea_god's_tear", 0x0200218c)
   checkIfSold("ruin_key", 0x0200218d)
   checkIfSold("magma_ball", 0x0200218e)
   
end

function checkIsaacInventory(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updateInventory(segment, 0)
end

function checkGaretInventory(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updateInventory(segment, 1)
end

function checkIvanInventory(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updateInventory(segment, 2)
end

function checkMiaInventory(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updateInventory(segment, 3)
end

function checkFelixInventory(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updateInventory(segment, 4)
end

function checkJennaInventory(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updateInventory(segment, 5)
end

function checkShebaInventory(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updateInventory(segment, 6)
end

function checkPiersInventory(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()
   updateInventory(segment, 7)
end


-- table of summon codes
summons = {
   "zagan","megaera","flora","moloch","ulysses","haures","eclipse","coatlicue",
   "daedalus","azul","catastrophe","charon","iris"
}

function updateSummons(segment)
   if not isInGame() then
      return false
   end
   InvalidateReadCaches()

   local address = 0x0200024e
   local value = ReadU16(segment, address)
   local idx = 1
   while (value > 0) do
      summon = Tracker:FindObjectForCode(summons[idx])
      summon.Active = value & 1 > 0
      value = value >> 1
      idx = idx + 1
   end
end

function isEnemyFlag(bitFlag)
	return bitFlag >= 0x600 and bitFlag < 0x800
end

function updateEnemyKills(segment)
	if not isInGame() then
		return false
	end
	InvalidateReadCaches()
	
	print('updating enemy kill data')
	updateStateWithSegment(segment, isEnemyFlag)
	updateChestCounts()
end


-- SOME PINS MOVE AROUND WHEN COLLECTING ITEMS. TRY NOT OVERWRITING ANYTHING UNLESS CHANGED?
ScriptHost:AddMemoryWatch("Djinn", 0x02000046, 10, updateDjinn, 3000)
ScriptHost:AddMemoryWatch("Hosts", 0x02000140, 0x100, updateItemHosts, 3000)
ScriptHost:AddMemoryWatch("Djinn Hosts", 0x02000046, 10, updateDjinnHosts, 3000)
ScriptHost:AddMemoryWatch("Chests", 0x02000140, 0x100, updateChests, 3000)
ScriptHost:AddMemoryWatch("Chests (Tablets)", 0x02000042, 0x2, updateTablets, 3000)
ScriptHost:AddMemoryWatch("Summons", 0x0200024e, 2, updateSummons, 3000)
ScriptHost:AddMemoryWatch("Enemy Kills", 0x02000100, 0x40, updateEnemyKills, 3000)

ScriptHost:AddMemoryWatch("Isaac's Psynergy", 0x02000578+0*0x14c, 0x80, checkIsaacPsynergy, 3000)
ScriptHost:AddMemoryWatch("Garet's Psynergy", 0x02000578+1*0x14c, 0x80, checkGaretPsynergy, 3000)
ScriptHost:AddMemoryWatch("Ivan's Psynergy",  0x02000578+2*0x14c, 0x80, checkIvanPsynergy, 3000)
ScriptHost:AddMemoryWatch("Mia's Psynergy",   0x02000578+3*0x14c, 0x80, checkMiaPsynergy, 3000)
ScriptHost:AddMemoryWatch("Felix's Psynergy", 0x02000578+4*0x14c, 0x80, checkFelixPsynergy, 3000)
ScriptHost:AddMemoryWatch("Jenna's Psynergy", 0x02000578+5*0x14c, 0x80, checkJennaPsynergy, 3000)
ScriptHost:AddMemoryWatch("Sheba's Psynergy", 0x02000578+6*0x14c, 0x80, checkShebaPsynergy, 3000)
ScriptHost:AddMemoryWatch("Piers's Psynergy", 0x02000578+7*0x14c, 0x80, checkPiersPsynergy, 3000)

ScriptHost:AddMemoryWatch("Isaac's Inventory", 0x020005f8+0*0x14c, 0x1e, checkIsaacInventory, 3000)
ScriptHost:AddMemoryWatch("Garet's Inventory", 0x020005f8+1*0x14c, 0x1e, checkGaretInventory, 3000)
ScriptHost:AddMemoryWatch("Ivan's Inventory",  0x020005f8+2*0x14c, 0x1e, checkIvanInventory, 3000)
ScriptHost:AddMemoryWatch("Mia's Inventory",   0x020005f8+3*0x14c, 0x1e, checkMiaInventory, 3000)
ScriptHost:AddMemoryWatch("Felix's Inventory", 0x020005f8+4*0x14c, 0x1e, checkFelixInventory, 3000)
ScriptHost:AddMemoryWatch("Jenna's Inventory", 0x020005f8+5*0x14c, 0x1e, checkJennaInventory, 3000)
ScriptHost:AddMemoryWatch("Sheba's Inventory", 0x020005f8+6*0x14c, 0x1e, checkShebaInventory, 3000)
ScriptHost:AddMemoryWatch("Piers's Inventory", 0x020005f8+7*0x14c, 0x1e, checkPiersInventory, 3000)
