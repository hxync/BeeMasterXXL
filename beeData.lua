--蜜蜂库存管理
local M = {}

local component = require("component")
local serialization = require("serialization")

local bot = require("bot")
local analyzeGenes = require("analyzeGenes")
local doUntil = require("doUntil")

local database = component.database
local upgrade_me = component.upgrade_me--[[@as table]]

local chromosomeList = {"species", "speed", "lifespan", "fertility", "flowering", "flowerProvider", "territory", "effect", "temperatureTolerance", "humidityTolerance", "nocturnal", "tolerantFlyer", "caveDwelling"}

local data
local function saveData()
    if data then
        data.initialized = M.initialized
    end
    local file = io.open("data.txt", "w")
    if file then
        file:write(serialization.serialize(data) or "{}")
        file:close()
    end
    
end
local function loadData()
    local file = io.open("data.txt", "r")
    if file then
        data = serialization.unserialize(file:read("*a"))
        file:close()
    end
    if not data then
        data = {
            initialized = false,
            assistantDroneTag = nil,
            assistantPrincessTag = nil,
            speedLevel = nil,
            usingPrincessTag = nil
        }
        saveData()
    end
    M.initialized = data.initialized
end
loadData()

function M.getSpeedAndEffect(species)
    database.set(1, "Forestry:beeDroneGE", 0, '{IsAnalyzed:1b,Genome:{Chromosomes:[0:{Slot:0b,UID0:"'..species..'",UID1:"'..species..'"}]}}')
    local effect = (database.get(1)--[[@as any]]).individual.inactive.effect:gsub("^forestry%.allele%.effect%.(%l)(%w*)", function(_1, _2) return "forestry.effect" .. _1:upper() .. _2 end)--forestry效果基因nbt与oc不一致，要加个替换
    local speed = math.floor((database.get(1) --[[@as any]]).individual.inactive.speed / 0.23)
    database.set(1, "Forestry:beeDroneGE", 0, '{IsAnalyzed:1b,Genome:{Chromosomes:[0:{Slot:0b,UID0:"'..species..'",UID1:"'..species..'"},12:{Slot:13b,UID0:"'..effect..'",UID1:"forestry.effectNone"}]}}')
    effect = (database.get(1)--[[@as any]]).individual.inactive.effect:gsub("^forestry%.allele%.effect%.(%l)(%w*)", function(_1, _2) return "forestry.effect" .. _1:upper() .. _2 end)
    return effect, speed >= (data.speedLevel or 0) and speed or data.speedLevel
end
 
function M.getTargetGenes(species)
    if M.initialized then
        local effect, speed = M.getSpeedAndEffect(species)
        return {
            species = species,
            speed = speed,
            effect = effect,
            lifespan = 1,
            flowering = 1,
            flowerProvider = "extrabees.flower.rock",
            fertility = 4,
            territory = 1,
            temperatureTolerance = "BOTH_5",
            humidityTolerance = "BOTH_5",
            nocturnal = true,
            tolerantFlyer = true,
            caveDwelling = true
        }
    else
        if species == "forestry.speciesCommon" then
            return {species = "forestry.speciesCommon",speed = 2,lifespan = 2,fertility = 4,flowering = 1,flowerProvider = "extrabees.flower.rock",territory = 1,effect = "forestry.effectNone",temperatureTolerance = "BOTH_5",humidityTolerance = "BOTH_5",nocturnal = true,tolerantFlyer = true,caveDwelling = true}
        elseif species == "forestry.speciesCultivated" then
            return {species = "forestry.speciesCultivated",speed = 5,lifespan = 1,fertility = 4,flowering = 1,flowerProvider = "extrabees.flower.rock",territory = 1,effect = "forestry.effectNone",temperatureTolerance = "BOTH_5",humidityTolerance = "BOTH_5",nocturnal = true,tolerantFlyer = true,caveDwelling = true}
        else 
            error("错误的调用beeData.getTargetGenes("..species..")，未完成初始化")
        end
    end
end

function M.updateAssistantDrone(slot, force)
    if not bot.inventory[slot] or bot.inventory[slot].name ~= "Forestry:beeDroneGE" then
        error("错误的调用beeData.updateAssistantDrone()，物品栏第"..slot.."格不是雄蜂")
    end
    for _, chromosome in pairs(chromosomeList) do
        if bot.inventory[slot][chromosome][1] ~= bot.inventory[slot][chromosome][2] then
            return false
        end
    end
    if bot.inventory[slot].species[1] == "forestry.speciesCultivated" and not M.initialized then
        M.initialized = true
        saveData()
    end
    if force or ((not data.speedLevel or bot.inventory[slot].speed[1] > data.speedLevel) and bot.inventory[slot].speed[1] == bot.inventory[slot].speed[2]) then
        data.speedLevel = bot.inventory[slot].speed[1]
        data.assistantDroneTag = bot.inventory[slot].tag
        local oldAssistantPrincessTag = data.assistantPrincessTag
        data.assistantPrincessTag = nil
        saveData()
        return true, oldAssistantPrincessTag
    end
    return false
end

function M.updateAssistantPrincess(slot, exchangeTag)
    if not bot.inventory[slot] or bot.inventory[slot].name ~= "Forestry:beePrincessGE" then
        error("错误的调用beeData.updateAssistantPrincess()，物品栏第"..slot.."格不是公主蜂")
    end
    if not data.assistantDroneTag then
        error("错误的调用beeData.updateAssistantPrincess()，尚未设置辅助雄蜂")
    end
    local droneGenes = analyzeGenes({name="Forestry:beeDroneGE", tag=data.assistantDroneTag, individual={}})
    for _, chromosome in pairs(chromosomeList) do
        if bot.inventory[slot][chromosome][1] ~= droneGenes[chromosome][1] or bot.inventory[slot][chromosome][2] ~= droneGenes[chromosome][2] then
            return false
        end
    end
    if exchangeTag then
        data.usingPrincessTag = exchangeTag
    end
    data.assistantPrincessTag = bot.inventory[slot].tag
    saveData()
    return true
end

function M.updateUsingPrincess(slot)
    if not bot.inventory[slot] or bot.inventory[slot].name ~= "Forestry:beePrincessGE" then
        error("错误的调用beeData.updateUsingPrincess()，物品栏第"..slot.."格不是公主蜂")
    end
    if bot.inventory[slot].isNatural then
        data.usingPrincessTag = bot.inventory[slot].tag
        saveData()
    end
    return true
end

function M.getDroneTag(species)
    database.set(1, "Forestry:beeDroneGE", 0, '{IsAnalyzed:1b,Genome:{Chromosomes:[0:{Slot:0b,UID0:"'..species..'",UID1:"'..species..'"}]}}')
    local droneList = upgrade_me.getItemsInNetwork({label = database.get(1).label})
    for slot, stack in pairs(bot.inventory) do
        if stack and stack.name == "Forestry:beeDroneGE" and stack.species[1] == species and stack.species[2] == species then
            table.insert(droneList, component.inventory_controller.getStackInInternalSlot(slot))
        end
    end
    if #droneList < 2 then
        return droneList[1] and droneList[1].tag
    end
    local scoreList = {}
    for i, drone in pairs(droneList) do
        local score = 0
        local droneGenes = analyzeGenes(drone)
        local templateGenes = {
            speed = data.speedLevel,
            lifespan = 1,
            flowering = 1,
            flowerProvider = "extrabees.flower.rock",
            fertility = 4,
            territory = 1,
            temperatureTolerance = "BOTH_5",
            humidityTolerance = "BOTH_5",
            nocturnal = true,
            tolerantFlyer = true,
            caveDwelling = true
        }
        for chromosome, gene in pairs(templateGenes) do
            if droneGenes[chromosome][1] == gene then
                score = score + 1
            end
            if droneGenes[chromosome][2] == gene then
                score = score + 1
            end
            if droneGenes[chromosome][1] == droneGenes[chromosome][2] then
                score = score + 3
            end
        end
        if droneGenes.species[2] ~= species then
            score = score - 100
        end
        scoreList[i] = score
    end
    local bestIndex = 1
    for i, score in pairs(scoreList) do
        if score > scoreList[bestIndex] then
            bestIndex = i
        end
    end 
    return droneList[bestIndex] and droneList[bestIndex].tag
end

local function isPrincessAvailable(tag)
    if tag == data.assistantPrincessTag then
        return false
    end
    return true
end

function M.getPrincessTag(isNatural)
    if isNatural and data.usingPrincessTag and bot.checkItem({tag=data.usingPrincessTag}) then
        return data.usingPrincessTag
    end
    local princess = doUntil(function()
        local princessList = upgrade_me.getItemsInNetwork({name = "Forestry:beePrincessGE"})
        for _, p in pairs(princessList) do
            if p.individual.isNatural == isNatural and isPrincessAvailable(p.tag) then
                return p
            end
        end
        for _, item in pairs(bot.inventory) do
            if item and item.name == "Forestry:beePrincessGE" and item.isNatural == isNatural and isPrincessAvailable(item.tag) then
                return item
            end
        end
    end, "缺少"..(isNatural and "始祖" or "卑贱").."种公主蜂")
    local tag = princess.tag
    if isNatural then
        data.usingPrincessTag = tag
        saveData()
    end
    return tag
end

function M.getAssistantBeesTag()
    if not data.assistantDroneTag or not bot.checkItem({tag = data.assistantDroneTag}) then
        error("尚未设置辅助雄蜂")
    end
    if not data.assistantPrincessTag or not bot.checkItem({tag = data.assistantPrincessTag}) then
        return data.assistantDroneTag
    end
    return data.assistantDroneTag, data.assistantPrincessTag
end

return M

--[[
data = {
    initialized = true,
    assistantDroneTag = component.getStackInInternalSlot(1).tag,
    speedLevel = 5,
}
robot.select(1)
component.upgrade_me.sendItems()
local file = io.open("data.txt", "w")
file:write(require("serialization").serialize(data))
file:close()
]]