local M = {}

local environment = require("environment")
local doUntil = require("doUntil")
local bot = require("bot")
local tools = require("tools")

local component = require("component")
local robot = require("robot")

local inventory_controller = component.inventory_controller
local upgrade_me = component.upgrade_me
local beekeeper = component.beekeeper

M.isActive = false

--载入蜂箱数据
local apiaryList, worldAccelerator_tier = {}, 0
do
    local config = require("config")
    local biomes = require("biomes")
    for i=1,16 do
        if config.apiary[i] ~= 0 then
            local b = biomes[config.apiary[i]]
            apiaryList[i] = {
                biome = b.name,
                biomeTypes = b.biomeTypes,
                temperature = environment.getTemperatureLevel(b.temperature, b.biomeTypes),
                humidity = environment.getHumidityLevel(b.rainfall)
            }
        end
    end
    worldAccelerator_tier = config.worldAccelerator_tier or 1
end

local apiaryLocation, apiaryDamage, foundation = 0, 0, nil
local apiaryLocationList = {{1,1},{0,2},{1,3},{2,2}, {2,3},{1,4},{2,5},{3,4}, {4,2},{3,3},{4,4},{5,3}, {3,0},{2,1},{3,2},{4,1}}
local worldAcceleratorLocationList = {{1,2},{2,4},{4,3},{3,1}}

--移动蜂箱、基石
local function setupApiary(location, damage, targetFoundation)
    if location == 0 then
        damage = damage or 0
    elseif not location or not apiaryList[location] or not damage then
        error(string.format("错误的调用setupApiary(%s, %s)", tostring(location), tostring(damage)))
    end
    local moveLocation = apiaryLocation ~= location --位置是否需要移动
    local isDifferentFoundation = (not foundation and targetFoundation) or (foundation and not targetFoundation) --基石是否发生变化
    or (foundation and targetFoundation and (foundation.name ~= targetFoundation.name or foundation.damage ~= targetFoundation.damage))
    local changeFoundation = moveLocation or isDifferentFoundation --是否需要重新铺设基石
    local changeApiary = moveLocation or apiaryDamage ~= damage or changeFoundation --是否需拆除并重新放置蜂箱
    --拆除蜂箱与基石
    if changeApiary and apiaryLocation ~= 0 then
        bot.moveYTo(2)
        bot.moveXZTo(table.unpack(apiaryLocationList[apiaryLocation]))
        local previousLabel = bot.inventoryLabel
        bot.inventoryLabel = "apiary.apiculture"
        tools.swingDown()
        bot.inventoryLabel = previousLabel
        if foundation and changeFoundation then
            bot.moveYTo(1)
            tools.swingDown(foundation.tool)
        end
    end
    --拆除并放置世界加速器
    local worldAcceleratorlocation, targetWALocation = math.ceil(apiaryLocation / 4), math.ceil(location / 4)
    if worldAcceleratorlocation ~= targetWALocation then
        bot.moveYTo(2)
        if worldAcceleratorlocation ~= 0 then
            bot.moveXZTo(table.unpack(worldAcceleratorLocationList[worldAcceleratorlocation]))
            local previousLabel = bot.inventoryLabel
            bot.inventoryLabel = "apiary.apiculture"
            tools.swingDown()
            bot.inventoryLabel = previousLabel
        end
        if location ~= 0 then
            bot.moveXZTo(table.unpack(worldAcceleratorLocationList[targetWALocation]))
            doUntil(function()
                robot.select(
                    doUntil(function()
                        return bot.checkItem({name = "gregtech:gt.blockmachines", damage = 11099 + worldAccelerator_tier}, 1)
                    end, "缺少世界加速器")
                )
                return robot.placeDown()
            end, "放置世界加速器失败")
        end
    end
    --放置蜂箱与基石
    if location ~= 0 then
        if changeFoundation and targetFoundation then
            bot.moveYTo(2)
            bot.moveXZTo(table.unpack(apiaryLocationList[location]))
            bot.moveYTo(1)
            if robot.detectDown() then
                tools.swingDown()
            end
            tools.placeDown(targetFoundation)
        end
        if changeApiary then
            bot.moveYTo(2)
            bot.moveXZTo(table.unpack(apiaryLocationList[location]))
            doUntil(function()
                robot.select(
                    doUntil(function()
                        return bot.checkItem({name = "Forestry:apiculture", damage = damage}, 1)
                    end, "缺少"..(damage == 0 and "蜂箱" or "简易蜂房"))
                )
                return robot.placeDown()
            end, "放置蜂箱失败")
        end
    end
    apiaryLocation = location
    apiaryDamage = damage
    foundation = targetFoundation
end

--选择最近的可用蜂箱
local function selectNearestApiary(availableApiaryList)
    local selectedWorldAccelerator = math.ceil(apiaryLocation / 4)
    local apaiaryWithSameWorldAccelerator = {}
    for _, num in ipairs(availableApiaryList) do
        if math.ceil(num / 4) == selectedWorldAccelerator then--优先选择不用移动世界加速器的蜂箱位置
            table.insert(apaiaryWithSameWorldAccelerator, num)
        end
        if num == apiaryLocation then--如果为当前蜂箱位置，直接返回
            return num
        end
    end
    return apaiaryWithSameWorldAccelerator[1] or availableApiaryList[1]
end

--根据公主蜂基因、突变条件检查是否有可用的蜂箱
function M.checkNextGeneration(princessSlot, mutation)
    if not bot.inventory[princessSlot] or bot.inventory[princessSlot].type ~= "beePrincess" then
        error(string.format("错误的调用apiary.checkNextGeneration(%d)",princessSlot))
    end
    local availableApiaryList = {}
    local Tmin, Tmax = environment.getTemperatureRange(bot.inventory[princessSlot].temperature[1], bot.inventory[princessSlot].temperatureTolerance[1])
    local Hmin, Hmax = environment.getHumidityRange(bot.inventory[princessSlot].humidity[1], bot.inventory[princessSlot].humidityTolerance[1])
    for location, apiary in pairs(apiaryList) do
        if apiary.temperature == bot.inventory[princessSlot].temperature[1] and apiary.humidity == bot.inventory[princessSlot].humidity[1] then
            table.insert(availableApiaryList, 1, location)--若需要更换世界加速器位置，优先选择最适环境的蜂箱位置
        elseif apiary.temperature >= Tmin and apiary.temperature <= Tmax and apiary.humidity >= Hmin and apiary.humidity <= Hmax then
            table.insert(availableApiaryList, location)
        end
    end
    if type(mutation) == "table" then
        if mutation.dimension then
            return nil
        end
        if mutation.foundation and not (foundation and foundation.name == mutation.foundation.name and foundation.damage == mutation.foundation.damage or bot.checkItem({name = mutation.foundation.name, damage = mutation.foundation.damage})) then
            return nil
        end
        for _, key in pairs({"temperature", "humidity", "biome", "biomeType"}) do
            if mutation[key] then
                for i = #availableApiaryList, 1, -1 do
                    local location = availableApiaryList[i]
                    if type(mutation[key]) == "table" then
                        if apiaryList[location][key] < mutation[key][1] or apiaryList[location][key] > mutation[key][2] then
                            table.remove(availableApiaryList, i)
                        end
                    elseif key == "biomeType" then
                        local hasType = false
                        for _, bt in ipairs(apiaryList[location].biomeTypes or {}) do
                            if bt == mutation[key] then hasType = true; break end
                        end
                        if not hasType then
                            table.remove(availableApiaryList, i)
                        end
                    else
                        if apiaryList[location][key] ~= mutation[key] then
                            table.remove(availableApiaryList, i)
                        end
                    end
                end
            end
        end
        --date, time, lunar_phase交由外部调用时判断
    end
    return selectNearestApiary(availableApiaryList)
end

--培育下一代
function M.nextGeneration(princessSlot, droneSlot, mutation)
    --校验突变条件
    local availableApiary, requiredApiaryDamage = M.checkNextGeneration(princessSlot, mutation), mutation == true and 2 or 0
    if not availableApiary then
        error("apiary.nextGeneration()缺少合适的蜂箱")
    end
    if apiaryDamage ~= requiredApiaryDamage and not bot.checkItem({name = "Forestry:apiculture", damage = requiredApiaryDamage}) then
        doUntil(function()
            return bot.checkItem({name = "Forestry:apiculture", damage = requiredApiaryDamage})
        end, "缺少"..(requiredApiaryDamage == 0 and "蜂箱" or "简易蜂房"))
    end
    --修改成合适的蜂箱配置
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "apiary.nextGeneration()"
    setupApiary(availableApiary, requiredApiaryDamage, type(mutation) == "table" and mutation.foundation)
    local previousFertility = bot.inventory[princessSlot].fertility[1]
    bot.moveYTo(2)
    bot.moveXZTo(table.unpack(apiaryLocationList[availableApiary]))
    --培育蜂后
    robot.select(princessSlot)
    if not inventory_controller.dropIntoSlot(0, 1, 1) then
        error("apiary.nextGeneration()转移公主蜂失败")
    end
    robot.select(droneSlot)
    bot.inventory[droneSlot].size = bot.inventory[droneSlot].size - 1
    if not inventory_controller.dropIntoSlot(0, 2, 1) then
        error("apiary.nextGeneration()转移工蜂失败")
    end
    bot.selectUsedSlot()--不用robot.select(1)是为了确保相同物品能够堆叠
    while true do
        local info = inventory_controller.getStackInSlot(0, 1)
        if not info or info.name == "Forestry:beeQueenGE" then
            break
        end
        os.sleep(1)
    end
    --等待子代并收集输出
    local function collectOutput()
        for i=3,9 do
            if not inventory_controller.suckFromSlot(0, i) then
                break
            end
            os.sleep(0)
        end
        for _,slot in ipairs(bot.getItemsWithLabel("apiary.nextGeneration()")) do
            if bot.inventory[slot] and bot.inventory[slot].type == "beePrincess" then
                return true
            end
        end
        return false
    end
    while true do
        doUntil(function()
            return beekeeper.canWork(0) or collectOutput()
        end, "蜜蜂无法生长，请补全缺失的生长条件")
        if collectOutput() then
            collectOutput()
            break
        end
        os.sleep(1)
    end
    --处理子代蜜蜂与产物
    local newDronesCount = 0
    for _,slot in ipairs(bot.getItemsWithLabel("apiary.nextGeneration()")) do
        if bot.inventory[slot] and bot.inventory[slot].type == "beeDrone" then
            newDronesCount = newDronesCount + bot.inventory[slot].size
        end
        if bot.inventory[slot] and (bot.inventory[slot].type == "beePrincess" or bot.inventory[slot].type == "beeDrone") then
            bot.inventory[slot].inventoryLabel = previousLabel
        else
            robot.select(slot)
            doUntil(function()
                upgrade_me.sendItems()
                return robot.count(slot) == 0
            end, "ME网络存储空间不足")
        end
    end
    if newDronesCount < previousFertility then
        for _,slot in pairs(bot.getItemsWithLabel(previousLabel)) do--size变化不会触发inventory_changed事件，需要手动更新数量
            local count = bot.inventory[slot].size or 0
            bot.inventory[slot].size = robot.count(slot)
            newDronesCount = newDronesCount + bot.inventory[slot].size - count
            if newDronesCount >= previousFertility then
                break
            end
        end
    end
    bot.inventoryLabel = previousLabel
end

--检查突变环境可行性
function M.checkMutationEnvironment(mutation)
    local result = {}
    if mutation.temperature then
        local hasSuitableApiary = false
        if type(mutation.temperature) == "table" then
            for _, apiary in pairs(apiaryList) do
                if apiary.temperature >= mutation.temperature[1] and apiary.temperature <= mutation.temperature[2] then
                    hasSuitableApiary = true
                    break
                end
            end
        else
            for _, apiary in pairs(apiaryList) do
                if apiary.temperature == mutation.temperature then
                    hasSuitableApiary = true
                    break
                end
            end
        end
        if not hasSuitableApiary then
            table.insert(result, "temperature")
        end
    end
    if mutation.humidity then
        local hasSuitableApiary = false
        for _, apiary in pairs(apiaryList) do
            if apiary.humidity == mutation.humidity then
                hasSuitableApiary = true
                break
            end
        end
        if not hasSuitableApiary then
            table.insert(result, "humidity")
        end
    end
    if mutation.biome then
        local hasSuitableApiary = false
        for _, apiary in pairs(apiaryList) do
            if apiary.biome == mutation.biome then
                hasSuitableApiary = true
                break
            end
        end
        if not hasSuitableApiary then
            table.insert(result, "biome")
        end
    end
    if mutation.biomeType then
        local hasSuitableApiary = false
        for _, apiary in pairs(apiaryList) do
            for _, bt in ipairs(apiary.biomeTypes or {}) do
                if bt == mutation.biomeType then
                    hasSuitableApiary = true
                    break
                end
            end
            if hasSuitableApiary then
                break
            end
        end
        if not hasSuitableApiary then
            table.insert(result, "biomeType")
        end
    end
    if result[1] then
        return false, result
    else
        return true
    end
end

function M.destruct()
    setupApiary(0)
    for _,slot in ipairs(bot.getItemsWithLabel("apiary.apiculture")) do
        robot.select(slot)
        upgrade_me.sendItems()
    end
end

return M