--  Load configuration options up front
ScriptHost:LoadScript("scripts/settings.lua")

Tracker:AddItems("items/common.json")
Tracker:AddItems("items/djinn.json")
Tracker:AddItems("items/progression.json")

ScriptHost:LoadScript("scripts/logic_common.lua")

Tracker:AddMaps("maps/maps.json")
Tracker:AddLocations("locations/weyard.json")
Tracker:AddLayouts("layouts/items.json")
Tracker:AddLayouts("layouts/psynergy.json")
Tracker:AddLayouts("layouts/summons_and_djinn.json")
Tracker:AddLayouts("layouts/tracker.json")
Tracker:AddLayouts("layouts/standard_broadcast.json")

if _VERSION == "Lua 5.3" then
  ScriptHost:LoadScript("scripts/autotracking.lua")
else
  print("Your tracker version does not support autotracking")
end