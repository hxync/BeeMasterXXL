--解析NBT数据
local zzlib = require("zzlib")
local nbt = require("nbt")
local database = require("component").database

local function decode(tag)
    local temp = { pcall(zzlib.gunzip,tag) }
    if not temp[1] then
        return nil, temp[2]
    end
    temp = { pcall(nbt.decode,temp[2]) }
    if not temp[1] or not temp[3] then
        return nil, temp[2]
    end
    return temp[3].value
end

--寿命：1-早夭，2-较短寿，3-短寿，4-不足寿，5-一般，6-足寿，7-长寿，8-较长寿，9-最长寿，10-永生
local lifespanLevel = { ["forestry.lifespanShortest"]=1, ["forestry.lifespanShorter"]=2, ["forestry.lifespanShort"]=3, ["forestry.lifespanShortened"]=4, ["forestry.lifespanNormal"]=5, ["forestry.lifespanElongated"]=6, ["forestry.lifespanLong"]=7, ["forestry.lifespanLonger"]=8, ["forestry.lifespanLongest"]=9, ["gregtech.lifeEon"]=10 }
--工作速度：1-最慢，2-较慢，3-慢速，4-一般，5-快速，6-较快，7-最快，8-急速
local speedLevel = { ["forestry.speedSlowest"]=1, ["forestry.speedSlower"]=2, ["forestry.speedSlow"]=3, ["forestry.speedNormal"]=4, ["forestry.speedFast"]=5, ["forestry.speedFaster"]=6, ["forestry.speedFastest"]=7, ["magicbees.speedBlinding"]=8 }
--授粉速度：1-最慢，2-较慢，3-慢速，4-平均，5-快速，6-较快，7-最快，8-最大速度
local floweringLevel = { ["forestry.floweringSlowest"]=1, ["forestry.floweringSlower"]=2, ["forestry.floweringSlow"]=3, ["forestry.floweringNormal"]=4, ["forestry.floweringFast"]=5, ["forestry.floweringFaster"]=6, ["forestry.floweringFastest"]=7, ["forestry.floweringMaximum"]=8 }
--生育能力：1x，2x，3x，4x
local fertilityLevel = { ["forestry.fertilityLow"]=1, ["forestry.fertilityNormal"]=2, ["forestry.fertilityHigh"]=3, ["forestry.fertilityMaximum"]=4 }
local fertilityDominance = { ["forestry.fertilityLow"]=true, ["forestry.fertilityNormal"]=true }
--活动范围：1-平均(9x6x9)，2-大(11x8x11)，3-较大(13x12x13)，4-最大(15x13x15)
local territoryLevel = { ["forestry.territoryAverage"]=1, ["forestry.territoryLarge"]=2, ["forestry.territoryLarger"]=3, ["forestry.territoryLargest"]=4 }
--温度：1-严寒，2-寒冷，3-一般，4-温暖，5-炙热，6-地狱
local temperatureLevel = { ["Icy"]=-2, ["Cold"]=-1, ["Normal"]=0, ["Warm"]=1, ["Hot"]=2, ["Hellish"]=3 }
--湿度：1-干旱，2-一般，3-潮湿
local humidityLevel = { ["Arid"]=-1, ["Normal"]=0, ["Damp"]=1 }
--适应性
local toleranceLevel = { ["forestry.toleranceUp1"]="UP_1", ["forestry.toleranceUp2"]="UP_2", ["forestry.toleranceUp3"]="UP_3", ["forestry.toleranceUp4"]="UP_4", ["forestry.toleranceUp5"]="UP_5", ["forestry.toleranceNone"]="NONE",
                           ["forestry.toleranceDown1"]="DOWN_1", ["forestry.toleranceDown2"]="DOWN_2", ["forestry.toleranceDown3"]="DOWN_3", ["forestry.toleranceDown"]="DOWN_4", ["forestry.toleranceDown5"]="DOWN_5",
                           ["forestry.toleranceBoth1"]="BOTH_1", ["forestry.toleranceBoth2"]="BOTH_2", ["forestry.toleranceBoth3"]="BOTH_3", ["forestry.toleranceBoth4"]="BOTH_4", ["forestry.toleranceBoth5"]="BOTH_5" }
local toleranceDominance = { ["forestry.toleranceUp1"]=true, ["forestry.toleranceDown1"]=true, ["forestry.toleranceBoth1"]=true }
--种族对应的最适温度与最适湿度
local original_genes = {}

local function analyzeBee(stack)--返回值只有部分基因能正确表示显隐性关系
    local tag = decode(stack.tag)
    local genes = {}
    if not tag or not tag.Genome or not tag.Genome.value or not tag.Genome.value.Chromosomes or not tag.Genome.value.Chromosomes.value then
        error("基因数据缺失或格式错误")
    end
    for _,t in pairs(tag.Genome.value.Chromosomes.value) do
        genes[t.value.Slot.value] = { t.value.UID0.value, t.value.UID1.value }
    end
    --如果original_genes无种族对应的温度与湿度信息，则在数据库中创建一个分析过的雄蜂，并记录其信息
    if not original_genes[genes[0][1]] then
        database.set(1, "Forestry:beeDroneGE", 0, '{IsAnalyzed:1b,Genome:{Chromosomes:[0:{Slot:0b,UID0:"'..genes[0][1]..'",UID1:"'..genes[0][1]..'"}]}}')
        original_genes[genes[0][1]] = (database.get(1)--[[@as any]]).individual.active.species
    end
    if not original_genes[genes[0][2]] then
        database.set(1, "Forestry:beeDroneGE", 0, '{IsAnalyzed:1b,Genome:{Chromosomes:[0:{Slot:0b,UID0:"'..genes[0][2]..'",UID1:"'..genes[0][2]..'"}]}}')
        original_genes[genes[0][2]] = (database.get(1)--[[@as any]]).individual.active.species
    end
    --检查显性种族基因与适应性基因
    if stack.individual.ident and genes[0][1] ~= stack.individual.ident then
        genes[0] = { genes[0][2], genes[0][1] }
    end
    if not toleranceDominance[genes[4][1]] and toleranceDominance[genes[4][2]] then
        genes[4] = { genes[4][2], genes[4][1] }
    end
    if not toleranceDominance[genes[7][1]] and toleranceDominance[genes[7][2]] then
        genes[7] = { genes[7][2], genes[7][1] }
    end
    if not fertilityDominance[genes[3][1]] and fertilityDominance[genes[3][2]] then
        genes[3] = { genes[3][2], genes[3][1] }
    end
    return {
        name = stack.name,
        damage = stack.damage,
        tag = stack.tag,
        label = stack.label,
        size = stack.size,--数量
        maxSize = stack.maxSize,--最大堆叠数
        isNatural = stack.individual.isNatural,--是否为始祖种
        generation = stack.individual.generation or 0,--第几代
        species = genes[0],--种族
        lifespan = { lifespanLevel[genes[2][1]], lifespanLevel[genes[2][2]] },--寿命
        speed = { speedLevel[genes[1][1]], speedLevel[genes[1][2]] },--工作速度
        flowering = { floweringLevel[genes[11][1]], floweringLevel[genes[11][2]] },--授粉速度
        flowerProvider = genes[10],--采蜜对象
        fertility = { fertilityLevel[genes[3][1]], fertilityLevel[genes[3][2]] },--生育能力
        territory = { territoryLevel[genes[12][1]], territoryLevel[genes[12][2]] },--活动范围
        effect = genes[13],--特殊效果
        temperature = { temperatureLevel[original_genes[genes[0][1]].temperature], temperatureLevel[original_genes[genes[0][2]].temperature] },--温度
        temperatureTolerance = { toleranceLevel[genes[4][1]], toleranceLevel[genes[4][2]] },--温度适应性
        humidity = { humidityLevel[original_genes[genes[0][1]].humidity], humidityLevel[original_genes[genes[0][2]].humidity] },--湿度
        humidityTolerance = { toleranceLevel[genes[7][1]], toleranceLevel[genes[7][2]] },--湿度适应性
        nocturnal = { genes[5][1] == "forestry.boolTrue", genes[5][2] == "forestry.boolTrue" },--夜行性
        tolerantFlyer = { genes[8][1] == "forestry.boolTrue", genes[8][2] == "forestry.boolTrue" },--耐雨飞行性
        caveDwelling = { genes[9][1] == "forestry.boolTrue", genes[9][2] == "forestry.boolTrue" },--穴居性
        type = stack.name == "Forestry:beePrincessGE" and "beePrincess" or "beeDrone",--公主蜂/雄蜂
    }
end

local analyzeGenes = function(stack)
    if stack.name == "Forestry:beePrincessGE" or stack.name == "Forestry:beeDroneGE" then
        return analyzeBee(stack)
    else
        error("错误的调用analyzeGenes()")
    end
end

return analyzeGenes
--[[
database.set(1, "Forestry:beePrincessGE", 0, '{MaxH:10,IsAnalyzed:1b,Genome:{Chromosomes:['..
'0:{Slot:0b,UID0:"gregtech.bee.speciesStardust",UID1:"gregtech.bee.speciesStardust"},'..
'1:{Slot:1b,UID0:"magicbees.speedBlinding",UID1:"magicbees.speedBlinding"},'..
'2:{Slot:2b,UID0:"forestry.lifespanShortest",UID1:"forestry.lifespanShortest"},'..
'3:{Slot:3b,UID0:"forestry.fertilityNormal",UID1:"forestry.fertilityNormal"},'..
'4:{Slot:4b,UID0:"forestry.toleranceBoth2",UID1:"forestry.toleranceBoth2"},'..
'5:{Slot:5b,UID0:"forestry.boolTrue",UID1:"forestry.boolTrue"},'..
'6:{Slot:7b,UID0:"forestry.toleranceBoth2",UID1:"forestry.toleranceBoth2"},'..
'7:{Slot:8b,UID0:"forestry.boolFalse",UID1:"forestry.boolFalse"},'..
'8:{Slot:9b,UID0:"forestry.boolFalse",UID1:"forestry.boolFalse"},'..
'9:{Slot:10b,UID0:"extrabees.flower.book",UID1:"extrabees.flower.book"},'..
'10:{Slot:11b,UID0:"forestry.floweringSlower",UID1:"forestry.floweringSlower"},'..
'11:{Slot:12b,UID0:"forestry.territoryLarger",UID1:"forestry.territoryLarger"},'..
'12:{Slot:13b,UID0:"forestry.effectNone",UID1:"forestry.effectNone"}]},Health:10}')
]]