local M = {}

local apiary = require("apiary")
--local alveary = require("alveary")
--local industrialApiary = require("industrialApiary")

local bot = require("bot")
local mutations = require("mutations")
local function checkMutation(princessSlot, droneSlot)
    local speciesGeneList = { bot.inventory[princessSlot].species[1], bot.inventory[princessSlot].species[2], bot.inventory[droneSlot].species[1], bot.inventory[droneSlot].species[2] }
    for i=4,2,-1 do
        for j=1,i-1 do
            if speciesGeneList[i] == speciesGeneList[j] then
                table.remove(speciesGeneList, i)
                break
            end
        end
    end
    local function check(allele1, allele2)
        for _,mutation in pairs(mutations) do
            if mutation[1] then
                for i=1,#mutation do
                    if not mutation[i].foundation and (mutation[i].parents[1] == allele1 and mutation[i].parents[2] == allele2 or mutation[i].parents[1] == allele2 and mutation[i].parents[2] == allele1) then
                        return true
                    end
                end
            else
                if not mutation.foundation and (mutation.parents[1] == allele1 and mutation.parents[2] == allele2 or mutation.parents[1] == allele2 and mutation.parents[2] == allele1) then
                    return true
                end
            end
        end
        return false
    end
    for i=1,#speciesGeneList-1 do
        for j=i,#speciesGeneList do
            if check(speciesGeneList[i], speciesGeneList[j]) then
                return true
            end
        end
    end
    return false
end

local function chooseMethod(strategy)
    --暂时只写了单方块蜂箱
    return apiary
end

function M.nextGeneration(princessSlot, droneSlot, mutation)
    if not bot.inventory[princessSlot] or bot.inventory[princessSlot].type ~= "beePrincess" or not bot.inventory[droneSlot] or bot.inventory[droneSlot].type ~= "beeDrone" then
        error(string.format("错误的调用nextGeneration(%d, %d)",princessSlot, droneSlot))
    end
    local strategy = mutation or checkMutation(princessSlot, droneSlot)
    --[[策略为false，忽略突变率，使寿命尽可能短
    策略为true，在突变率为0的前提下使寿命尽可能短
    策略type为table，尽可能将突变率提高到100]]
    if not apiary.checkNextGeneration(princessSlot, strategy) then
        error("没有满足条件的蜂箱可供培育下一代")
    end
    return chooseMethod(strategy).nextGeneration(princessSlot, droneSlot, strategy)
end

function M.checkMutationEnvironment(mutation)
    return apiary.checkMutationEnvironment(mutation)
end

function M.destruct()
    apiary.destruct()
end

return M