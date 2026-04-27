local serialization = require("serialization")
local component = require("component")


--[[do--初始化以用于测试
    local data = {
        initialized = true,
        assistantDroneTag = component.inventory_controller.getStackInInternalSlot(1).tag,
        speedLevel = 5,
    }
    require("robot").select(1)
    component.upgrade_me.sendItems()
    local file = io.open("data.txt", "w")
    file:write(require("serialization").serialize(data))
    file:close()
end]]

print("加载中...")
local mutations = require("mutations")
local strategy = require("strategy")


if component.inventory_controller.getInventoryName(0) ~= "tile.oc.charger" then
    error("机器人初始位置应位于OC充电器上方")
end

local function main()
    io.write("请输入需要突变的蜜蜂:")
    local species = io.read()
    if mutations[species] then
        local suc,err = pcall(strategy.task,species)
        if not suc then
            error("错误: " .. err)
        end
    else
        error("未发现突变路径")
    end
end
main()

--[[
local function test()
    strategy.task("gregtech.bee.speciesClay")
    --strategy.newSpecies("forestry.speciesNoble", {name="高尚",parents={"forestry.speciesCommon","forestry.speciesCultivated"},baseChance=10.0})
end

test()
]]

--strategy.purify(1,2,{},2)

-- a,b=pcall(require,"bee") if a then print(a) else print(b:sub(1,300)) end

        --species = genes[0],--种族
        --lifespan = { lifespanLevel[genes[2][1]], lifespanLevel[genes[2][2]] },--寿命
        --speed = { speedLevel[genes[1][1]], speedLevel[genes[1][2]] },--工作速度
        --flowering = { floweringLevel[genes[11][1]], floweringLevel[genes[11][2]] },--授粉速度
        --flowerProvider = genes[10],--采蜜对象
        --fertility = { fertilityLevel[genes[3][1]], fertilityLevel[genes[3][2]] },--生育能力
        --territory = { territoryLevel[genes[12][1]], territoryLevel[genes[12][2]] },--活动范围
        --effect = genes[13],--特殊效果
        --temperature = { temperatureLevel[original_genes[genes[0][1]].temperature], temperatureLevel[original_genes[genes[0][2]].temperature] },--温度
        --temperatureTolerance = { toleranceLevel[genes[4][1]], toleranceLevel[genes[4][2]] },--温度适应性
        --humidity = { humidityLevel[original_genes[genes[0][1]].humidity], humidityLevel[original_genes[genes[0][2]].humidity] },--湿度
        --humidityTolerance = { toleranceLevel[genes[7][1]], toleranceLevel[genes[7][2]] },--湿度适应性
        --nocturnal = { genes[5][1] == "forestry.boolTrue", genes[5][2] == "forestry.boolTrue" },--夜行性
        --tolerantFlyer = { genes[8][1] == "forestry.boolTrue", genes[8][2] == "forestry.boolTrue" },--耐雨飞行性
        --caveDwelling = { genes[9][1] == "forestry.boolTrue", genes[9][2] == "forestry.boolTrue" }--穴居性