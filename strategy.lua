--制定公主蜂和雄蜂的选择策略
local M = {}

local component = require("component")
local robot = require("robot")
local mutations = require("mutations")

local upgrade_me = component.upgrade_me--[[@as table]]

local doUntil = require("doUntil")
local device = require("device")
local bot = require("bot")
local beeData = require("beeData")

local chromosomeList = {"species", "speed", "lifespan", "fertility", "flowering", "flowerProvider", "territory", "effect", "temperatureTolerance", "humidityTolerance", "nocturnal", "tolerantFlyer", "caveDwelling"}

function M.mutate(princessSlot, droneSlot, targetSpecies, mutation)--单步突变
    --参与配对的杂交雄蜂被归为三类：亲代1纯合基因雄蜂（11型）、亲代2纯合基因雄蜂（22型）、双亲杂合基因雄蜂（12型）
    --突变过程存在种族基因存在丢失的可能，此时将返回nil（附带退回的备选雄蜂槽位），待上级函数重新获取可用母本后继续。
    --由于退出时不丢弃已有雄蜂，且已有雄蜂均打上了该品种基因突变标签，故可在下次突变调用中继承已有的雄蜂基因池。
    --1.校验输入
    if bot.inventory[princessSlot].type ~= "beePrincess" or bot.inventory[droneSlot].type ~= "beeDrone" or not targetSpecies or not mutation then
        error(string.format("错误的调用strategy.mutate(%d, %d, %s)",princessSlot, droneSlot, mutation.name))
    end
    for _, chromosome in pairs(chromosomeList) do
        local p1, p2 = bot.inventory[princessSlot][chromosome][1], bot.inventory[princessSlot][chromosome][2]
        local d1, d2 = bot.inventory[droneSlot][chromosome][1], bot.inventory[droneSlot][chromosome][2]
        if chromosome == "species" then
            local function isValid(gene)
                return gene == mutation.parents[1] or gene == mutation.parents[2]
            end
            if not (isValid(p1) and isValid(p2) and isValid(d1) and isValid(d2)) then
                error(string.format("错误的调用strategy.mutate(%d, %d, %s)，参与突变的公主蜂和雄蜂含有非亲本的species基因",princessSlot, droneSlot, mutation.name))
            end
            local hasP1 = p1 == mutation.parents[1] or p2 == mutation.parents[1] or d1 == mutation.parents[1] or d2 == mutation.parents[1]
            local hasP2 = p1 == mutation.parents[2] or p2 == mutation.parents[2] or d1 == mutation.parents[2] or d2 == mutation.parents[2]
            if not (hasP1 and hasP2) then
                error(string.format("错误的调用strategy.mutate(%d, %d, %s)，参与突变的公主蜂和雄蜂无法凑齐突变所需品种",princessSlot, droneSlot, mutation.name))
            end
        elseif chromosome ~= "speed" and chromosome ~= "lifespan" and chromosome ~= "effect" then
            if p1 ~= p2 or d1 ~= d2 or p1 ~= d1 then
                error(string.format("错误的调用strategy.mutate(%d, %d, %s)，参与突变的公主蜂和雄蜂在 %s 基因上不为同种纯合",princessSlot, droneSlot, mutation.name, chromosome))
            end
        end
    end
    local allele1Genes, allele2Genes = {}, {}
    for _, chromosome in pairs(chromosomeList) do
        allele1Genes[chromosome] = bot.inventory[princessSlot][chromosome][1]
        allele2Genes[chromosome] = bot.inventory[droneSlot][chromosome][2]
    end
    if mutation.dimension then
        error(string.format("错误的调用strategy.mutate(%d, %d, %s)，当前突变仅在特定维度发生",princessSlot, droneSlot, mutation.name))
    end
    if mutation.foundation and not bot.checkItem({name = mutation.foundation.name, damage = mutation.foundation.damage}) then
        doUntil(function ()
            return bot.checkItem({name = mutation.foundation.name, damage = mutation.foundation.damage})
        end, "缺少突变所需的基石："..mutation.foundation.label)
    end
    --2.执行突变
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "mutate:"..targetSpecies
    bot.inventory[droneSlot].inventoryLabel = bot.inventoryLabel
    local function nextGeneration(droneSlot)--追踪公主蜂
        device.nextGeneration(princessSlot, droneSlot, mutation)
        princessSlot = nil
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beePrincess" then
                if princessSlot then
                    error("错误的调用strategy.mutate().nextGeneration，突变过程中出现了两只公主蜂")
                end
                princessSlot = slot
            end
        end
        if not princessSlot then
            error("错误的调用strategy.mutate().nextGeneration，突变过程中未找到公主蜂")
        end
    end
    nextGeneration(droneSlot)
    droneSlot = nil
    local targetBeeSlots = {}
    local allele11, allele12, allele22 = {}, {}, {}
    while true do
        targetBeeSlots = {}
        allele11, allele12, allele22 = {}, {}, {}
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" then
                local d1, d2 = bot.inventory[slot].species[1], bot.inventory[slot].species[2]
                if d1 == targetSpecies or d2 == targetSpecies then
                    table.insert(targetBeeSlots, slot)
                elseif d1 == mutation.parents[1] and d2 == mutation.parents[1] then
                    table.insert(allele11, slot)
                elseif d1 == mutation.parents[2] and d2 == mutation.parents[2] then
                    table.insert(allele22, slot)
                elseif (d1 == mutation.parents[1] and d2 == mutation.parents[2]) or (d1 == mutation.parents[2] and d2 == mutation.parents[1]) then
                    table.insert(allele12, slot)
                else
                    robot.select(slot)
                    robot.dropUp()
                end
            end
        end
        --丢弃杂蜂
        for _, allele in pairs({allele11, allele12, allele22}) do
            for i=#allele,4,-1 do
                robot.select(allele[i])
                robot.dropUp()
                table.remove(allele, i)
            end
        end
        local p1, p2 = bot.inventory[princessSlot].species[1], bot.inventory[princessSlot].species[2]
        if p1 == targetSpecies or p2 == targetSpecies then
            table.insert(targetBeeSlots, 1, princessSlot)
        end
        if #targetBeeSlots > 0 then
            break
        end
        if p1 == p2 then
            if p1 == mutation.parents[1] then
                local droneSlot = allele22[1] or allele12[1]
                if droneSlot then
                    nextGeneration(droneSlot)
                else
                    bot.inventoryLabel = previousLabel
                    return nil, princessSlot
                end
            elseif p1 == mutation.parents[2] then
                local droneSlot = allele11[1] or allele12[1]
                if droneSlot then
                    nextGeneration(droneSlot)
                else
                    bot.inventoryLabel = previousLabel
                    return nil, princessSlot
                end
            else
                bot.inventoryLabel = previousLabel
                return nil, princessSlot, allele22[1] or allele12[1]
            end
        elseif (p1 == mutation.parents[1] and p2 == mutation.parents[2]) or (p1 == mutation.parents[2] and p2 == mutation.parents[1]) then
            local lack11 = #allele11 == 1 and robot.count(allele11[1]) == 1
            local lack22 = #allele22 == 1 and robot.count(allele22[1]) == 1
            local droneSlot
            if #allele11 == 0 or #allele22 == 0 then
                droneSlot = allele12[1] or allele11[1] or allele22[1]
            elseif lack11 and not lack22 then
                droneSlot = allele11[1] or allele12[1] or allele22[1]
            elseif lack22 and not lack11 then
                droneSlot = allele22[1] or allele12[1] or allele11[1]
            else
                droneSlot = allele12[1] or allele11[1] or allele22[1]
            end
            if droneSlot then
                nextGeneration(droneSlot)
            else
                bot.inventoryLabel = previousLabel
                return nil, princessSlot
            end
        else
            bot.inventoryLabel = previousLabel
            return nil, princessSlot, allele12[1] or allele22[1] or allele11[1]
        end
    end
    --3.丢弃杂蜂并返回
    for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
        local isTarget = false
        for _, tSlot in pairs(targetBeeSlots) do
            if slot == tSlot then
                isTarget = true
                break
            end
        end
        if not isTarget and slot ~= princessSlot then
            robot.select(slot)
            if bot.inventory[slot].type == "beeDrone" then
                local isPure1, isPure2 = true, true
                for _, chromosome in pairs(chromosomeList) do
                    if bot.inventory[slot][chromosome][1] ~= allele1Genes[chromosome] or bot.inventory[slot][chromosome][2] ~= allele1Genes[chromosome] then
                        isPure1 = false
                    end
                    if bot.inventory[slot][chromosome][1] ~= allele2Genes[chromosome] or bot.inventory[slot][chromosome][2] ~= allele2Genes[chromosome] then
                        isPure2 = false
                    end
                end
                if isPure1 or isPure2 then
                    upgrade_me.sendItems()
                else
                    robot.dropUp()
                end
            else
                robot.dropUp()
            end
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    for _, slot in pairs(targetBeeSlots) do
        bot.inventory[slot].inventoryLabel = previousLabel
    end
    return targetBeeSlots, princessSlot
end

function M.purify(princessSlot, droneSlot, targetGenes, assistantDroneSlot, labelSuffix)--纯化
    --目标基因分为以下四类：生育基因、突变产生的值得保留的新基因（Ⅱ类基因）、样板蜂已有的基因（Ⅲ类基因）、突变产生与样板已有重合的基因（不纳入计算因素）
    --提纯过程存在基因丢失的概率，若导致Ⅱ类基因丢失，则应当返回nil，待上级函数调用冲洗函数将公主蜂洗成母本基因，并调用突变函数进行新一轮的突变获取新的Ⅱ类基因后，再调用此函数继续提纯。
    --由于返回时不丢弃已有雄蜂，且已有雄蜂均打上了该品种基因提纯标签，故可在下一轮调用中继承已有的提纯进度。
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "purify"..targetGenes.species..(labelSuffix or "")
    bot.inventory[princessSlot].inventoryLabel = bot.inventoryLabel
    if droneSlot and droneSlot ~= assistantDroneSlot then
        bot.inventory[droneSlot].inventoryLabel = bot.inventoryLabel
    end
    --1.校验输入，对基因进行分类
    local newGenes, templateGenes = {}, {}
    if bot.inventory[assistantDroneSlot].fertility[1] ~= 4 or bot.inventory[assistantDroneSlot].fertility[2] ~= 4 then
        error("错误的调用strategy("..tostring(princessSlot)..","..tostring(droneSlot)..","..tostring(assistantDroneSlot)..","..tostring(targetGenes.species)..")，样板雄蜂的生育基因必须为纯合4x")
    end
    for _, chromosome in pairs(chromosomeList) do
        local gene = bot.inventory[princessSlot][chromosome]
        --校验目标基因是否存在
        if gene[1] ~= targetGenes[chromosome] and gene[2] ~= targetGenes[chromosome] and bot.inventory[droneSlot][chromosome][1] ~= targetGenes[chromosome] and bot.inventory[droneSlot][chromosome][2] ~= targetGenes[chromosome] 
        and bot.inventory[assistantDroneSlot][chromosome][1] ~= targetGenes[chromosome] and bot.inventory[assistantDroneSlot][chromosome][2] ~= targetGenes[chromosome] or bot.inventory[assistantDroneSlot][chromosome][1] ~= bot.inventory[assistantDroneSlot][chromosome][2] then
            error("错误的调用strategy("..tostring(princessSlot)..","..tostring(droneSlot)..","..tostring(chromosome).."="..tostring(targetGenes[chromosome])..")")
        --分类
        elseif chromosome ~= "fertility" and not(gene[1] == targetGenes[chromosome] and gene[2] == targetGenes[chromosome] and bot.inventory[droneSlot][chromosome][1] == targetGenes[chromosome]
        and bot.inventory[droneSlot][chromosome][2] == targetGenes[chromosome] and bot.inventory[assistantDroneSlot][chromosome][1] == targetGenes[chromosome]) then
            if bot.inventory[assistantDroneSlot][chromosome][1] == targetGenes[chromosome] then
                table.insert(templateGenes, chromosome)
            else
                table.insert(newGenes, chromosome)
            end
        end
    end
    local function getDrones(highFertilityOnly, includeAssistant)
        local result = {}
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" and (not highFertilityOnly or bot.inventory[slot].fertility[1] == 4 and bot.inventory[slot].fertility[2] == 4) then
                table.insert(result, slot)
            end
        end
        if includeAssistant then
            local isPresent = false
            for _, slot in pairs(result) do
                if slot == assistantDroneSlot then isPresent = true break end
            end
            if not isPresent then
                table.insert(result, assistantDroneSlot)
            end
        end
        return result
    end
    local function nextGeneration(droneSlot)--追踪公主蜂
        device.nextGeneration(princessSlot, droneSlot)
        princessSlot = nil
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beePrincess" then
                if princessSlot then
                    error("错误的调用strategy.purify().nextGeneration，提纯过程中出现了两只公主蜂")
                end
                princessSlot = slot
            end
        end
        if not princessSlot then
            error("错误的调用strategy.purify().nextGeneration，提纯过程中未找到公主蜂")
        end
    end
    --2.提纯生育基因，终止条件是所有生育为纯合4x的雄蜂携带全部Ⅱ类基因且公主蜂生育基因为纯合4x。
    local newGenesWithHighFertility
    local function checkNewGenesWithHighFertility()
        --检查
        newGenesWithHighFertility = {}
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if (bot.inventory[slot].type == "beeDrone" or bot.inventory[slot].type == "beePrincess") and bot.inventory[slot].fertility[1] == 4 and bot.inventory[slot].fertility[2] == 4 then
                for _,chromosome in pairs(newGenes) do
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        newGenesWithHighFertility[chromosome] = true
                    end
                end
            end
        end
        for _,chromosome in pairs(newGenes) do
            if not newGenesWithHighFertility[chromosome] then
                return
            end
        end
        if bot.inventory[princessSlot].fertility[1] == 4 and bot.inventory[princessSlot].fertility[2] == 4 then
            newGenesWithHighFertility = "All"
        end
        --丢弃不包含Ⅱ类基因的雄蜂
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" and (bot.inventory[slot].fertility[1] ~= 4 or bot.inventory[slot].fertility[2] ~= 4) then
                local shouldDrop = true
                for _,chromosome in pairs(newGenes) do
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        shouldDrop = false
                        break
                    end
                end
                if shouldDrop then
                    robot.select(slot)
                    robot.dropUp()
                    while bot.inventory[slot] do
                        os.sleep(0)
                    end
                end
            end
        end
    end
    ::FERTILITY::
    checkNewGenesWithHighFertility()
    while newGenesWithHighFertility ~= "All" do
        local weights = {}
        --若公主蜂携带不在newGenesWithHighFertility表内的Ⅱ类基因，则使用样板雄蜂与公主蜂杂交
        for _,chromosome in pairs(newGenes) do
            if not newGenesWithHighFertility[chromosome] and (bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome]) then
                nextGeneration(assistantDroneSlot)
                goto CONTINUE
            end
        end
        --如果发生了基因丢失，直接返回nil
        for _,chromosome in pairs(newGenes) do
            local isLost = true
            if bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] then
                isLost = false
            else
                for _,slot in pairs(getDrones()) do
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        isLost = false
                        break
                    end
                end
            end
            if isLost then
                bot.inventoryLabel = previousLabel
                return nil, princessSlot
            end
        end
        --若公主蜂生育基因不为纯合4x，则使用样板雄蜂与公主蜂杂交
        if bot.inventory[princessSlot].fertility[1] ~= 4 or bot.inventory[princessSlot].fertility[2] ~= 4 then
            nextGeneration(assistantDroneSlot)
            goto CONTINUE
        end
        --选择包含最多不在newGenesWithHighFertility表内的Ⅱ类基因的雄蜂与公主蜂杂交
        for _,slot in pairs(getDrones()) do
            weights[slot] = 0
            for _,chromosome in pairs(newGenes) do
                if newGenesWithHighFertility[chromosome] then
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] then
                        weights[slot] = weights[slot] + 1
                    end
                    if bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        weights[slot] = weights[slot] + 1
                    end
                elseif bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                    if bot.inventory[slot][chromosome][1] == bot.inventory[slot][chromosome][2] then
                        weights[slot] = weights[slot] + 95
                    else
                        weights[slot] = weights[slot] + 64
                    end
                end
            end
            if bot.inventory[slot].fertility[1] == 4 or bot.inventory[slot].fertility[2] == 4 then
                weights[slot] = weights[slot] + 16
            end
        end
        droneSlot = nil
        for slot,weight in pairs(weights) do
            if droneSlot then
                if weight > weights[droneSlot] then
                    droneSlot = slot
                end
            else
                droneSlot = slot
            end
        end
        nextGeneration(droneSlot)
        ::CONTINUE::
        checkNewGenesWithHighFertility()
    end
    --3.提纯其余所有基因
    local genes = {}
    for _,chromosome in pairs(newGenes) do
        table.insert(genes, chromosome)
    end
    for _,chromosome in pairs(templateGenes) do
        table.insert(genes, chromosome)
    end
    local function dropDrones()
        --处理生育非纯合4x雄蜂
        local lackGenes = {}
        for _,chromosome in pairs(genes) do
            local amount = (bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
            for _,slot in pairs(getDrones(true)) do
                amount = amount + (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[slot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                if amount >= 2 then
                    break
                end
            end
            if amount < 2 then
                table.insert(lackGenes, chromosome)
            end
        end
        for _,slot in pairs(getDrones()) do
            local shouldDrop = true
            if bot.inventory[slot].fertility[1] == 4 and bot.inventory[slot].fertility[2] == 4 then
                shouldDrop = false
            else
                for _,chromosome in pairs(lackGenes) do
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        shouldDrop = false
                        break
                    end
                end
            end
            if shouldDrop then
                robot.select(slot)
                robot.dropUp()
                while bot.inventory[slot] do
                    os.sleep(0)
                end
            end
        end
        --处理生育纯合4x雄蜂
        for i = #genes, 1, -1 do
            local pureChromosome = genes[i]
            if bot.inventory[princessSlot][pureChromosome][1] == targetGenes[pureChromosome] and bot.inventory[princessSlot][pureChromosome][2] == targetGenes[pureChromosome] then
                local isPureEnough = true
                for _,chromosome in pairs(genes) do
                    local amount = (bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                    for _,slot in pairs(getDrones(true)) do
                        if bot.inventory[slot][pureChromosome][1] == targetGenes[pureChromosome] and bot.inventory[slot][pureChromosome][2] == targetGenes[pureChromosome] then
                            amount = amount + (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[slot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                        end
                        if amount >= 3 then
                            break
                        end
                    end
                    if amount < 3 then
                        isPureEnough = false
                        break
                    end
                end
                if isPureEnough then
                    for _,slot in pairs(getDrones()) do
                        if bot.inventory[slot][pureChromosome][1] ~= targetGenes[pureChromosome] or bot.inventory[slot][pureChromosome][2] ~= targetGenes[pureChromosome] then
                            robot.select(slot)
                            robot.dropUp()
                            while bot.inventory[slot] do
                                os.sleep(0)
                            end
                        end
                    end
                    table.remove(genes, i)
                end
            end
        end
        --处理生育纯合4x雄蜂
        while true do
            if not next(genes) then break end
            local abundantGenes = {}
            for _,chromosome in pairs(genes) do
                local amount = (bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                for _,slot in pairs(getDrones(true)) do
                    amount = amount + (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[slot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                    if amount >= 7 then
                        abundantGenes[chromosome] = true
                        break
                    end
                end
            end
            local weights = {}
            for _,slot in pairs(getDrones()) do
                local hasRareGene = false
                for _,chromosome in pairs(genes) do
                    if not abundantGenes[chromosome] and (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome]) then
                        hasRareGene = true
                        break
                    end
                end
                if not hasRareGene then
                    weights[slot] = 0
                    for _,chromosome in pairs(genes) do
                        if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                            weights[slot] = weights[slot] + 3
                        elseif bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                            weights[slot] = weights[slot] + 1
                        end
                    end
                end
            end
            if next(weights) then
                local minWeightSlot
                for slot, weight in pairs(weights) do
                    if minWeightSlot then
                        if weight < weights[minWeightSlot] then
                            minWeightSlot = slot
                        end
                    else
                        minWeightSlot = slot
                    end
                end
                robot.select(minWeightSlot)
                robot.dropUp()
                while bot.inventory[minWeightSlot] do
                    os.sleep(0)
                end
            else
                break
            end
        end
    end
    while true do
        ::CONTINUE2::
        --若存在纯合目标基因公主蜂与纯合目标基因雄蜂，跳出循环
        local hasPurePrincess = true
        for _,chromosome in pairs(newGenes) do
            if bot.inventory[princessSlot][chromosome][1] ~= targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] ~= targetGenes[chromosome] then
                hasPurePrincess = false
                break
            end
        end
        if hasPurePrincess then
            for _,chromosome in pairs(templateGenes) do
                if bot.inventory[princessSlot][chromosome][1] ~= targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] ~= targetGenes[chromosome] then
                    hasPurePrincess = false
                    break
                end
            end
        end
        if hasPurePrincess then
            local hasPureDrone = false
            for _,slot in pairs(getDrones(true, true)) do
                if bot.inventory[slot] and bot.inventory[slot].type == "beeDrone" and bot.inventory[slot].fertility[1] == 4 and bot.inventory[slot].fertility[2] == 4 then
                    local isPure = true
                    for _,chromosome in pairs(newGenes) do
                        if bot.inventory[slot][chromosome][1] ~= targetGenes[chromosome] or bot.inventory[slot][chromosome][2] ~= targetGenes[chromosome] then
                            isPure = false
                            break
                        end
                    end
                    if isPure then
                        for _,chromosome in pairs(templateGenes) do
                            if bot.inventory[slot][chromosome][1] ~= targetGenes[chromosome] or bot.inventory[slot][chromosome][2] ~= targetGenes[chromosome] then
                                isPure = false
                                break
                            end
                        end
                    end
                    if isPure then
                        droneSlot = slot
                        hasPureDrone = true
                        break
                    end
                end
            end
            if hasPureDrone then
                break
            end
        end
        dropDrones()
        --统计每个基因的纯合和杂合数量
        local statistics = {}
        for _,chromosome in pairs(genes) do
            statistics[chromosome] = {0, 0}
        end
        for _,slot in pairs(getDrones(true, #newGenes==0)) do
            for _,chromosome in pairs(genes) do
                if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                    if bot.inventory[slot][chromosome][1] == bot.inventory[slot][chromosome][2] then
                        statistics[chromosome][1] = statistics[chromosome][1] + bot.inventory[slot].size
                    else
                        statistics[chromosome][2] = statistics[chromosome][2] + bot.inventory[slot].size
                    end
                end
            end
        end
        --若发生Ⅱ类基因丢失，退回到生育基因提纯阶段
        for _,chromosome in pairs(newGenes) do
            if bot.inventory[princessSlot][chromosome][1] ~= targetGenes[chromosome] and bot.inventory[princessSlot][chromosome][2] ~= targetGenes[chromosome] and statistics[chromosome] and statistics[chromosome][1] == 0 and statistics[chromosome][2] == 0 then
                goto FERTILITY
            end
        end
        --若雄蜂中无Ⅲ类基因，则与样板雄蜂杂交
        for _,count in pairs(statistics) do
            if count[1] == 0 and count[2] == 0 then
                nextGeneration(assistantDroneSlot)
                goto CONTINUE2
            end
        end
        --根据公主蜂对应基因的基因型与雄蜂基因统计结果计算权重
        local weights = {}
        for _,slot in pairs(getDrones(true, #newGenes==0)) do
            weights[slot] = {0, 0, 0, 0, 0, 0}
            for _,chromosome in pairs(genes) do
                local count = (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[slot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                if bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] and bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] then
                    if count == 2 then
                        weights[slot][5] = weights[slot][5] + 1
                    elseif count == 1 then
                        weights[slot][6] = weights[slot][6] + 1
                    end
                elseif bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] then
                    if count == 2 then
                        weights[slot][3] = weights[slot][3] + 1
                    elseif count == 1 then
                        weights[slot][4] = weights[slot][4] + 1
                    end
                else
                    if count == 2 and statistics[chromosome][1] > 2 or count == 1 and statistics[chromosome][1] <= 2 then
                        weights[slot][1] = weights[slot][1] + 1
                    elseif count == 1 and statistics[chromosome][1] > 2 or count == 2 and statistics[chromosome][1] <= 2 then
                        weights[slot][2] = weights[slot][2] + 1
                    end
                end
            end
        end
        --选择权重最高的雄蜂与公主蜂杂交
        droneSlot = nil
        for slot,weight in pairs(weights) do
            if droneSlot then
                for i=1,6 do
                    if weights[droneSlot][i] < weight[i] then
                        droneSlot = slot
                        break
                    elseif weights[droneSlot][i] > weight[i] then
                        break
                    end
                end
            else
                droneSlot = slot
            end
        end
        nextGeneration(droneSlot)
    end
    --4.丢弃期间产生的所有杂蜂，将雄蜂数量繁殖到16以上后返回
    for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
        if slot ~= droneSlot and bot.inventory[slot].type == "beeDrone" then
            robot.select(slot)
            robot.dropUp()
        end
    end
    while robot.count(droneSlot--[[@as number]]) < 16 do
        nextGeneration(droneSlot)
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" then
                droneSlot = slot
                break
            end
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    if droneSlot ~= assistantDroneSlot then
        bot.inventory[droneSlot].inventoryLabel = previousLabel
    end
    return droneSlot, princessSlot
end

function M.breedDrones(princessSlot, droneSlot, targetAmount)--繁殖雄蜂
    if bot.inventory[princessSlot].type ~= "beePrincess" or bot.inventory[droneSlot].type ~= "beeDrone" then
        error(string.format("错误的调用strategy.breedDrones(%d, %d, %d)",princessSlot, droneSlot, targetAmount))
    end
    for _, chromosome in pairs(chromosomeList) do
        local p1, p2 = bot.inventory[princessSlot][chromosome][1], bot.inventory[princessSlot][chromosome][2]
        local d1, d2 = bot.inventory[droneSlot][chromosome][1], bot.inventory[droneSlot][chromosome][2]
        if p1 ~= p2 or d1 ~= d2 or p1 ~= d1 then
            error(string.format("错误的调用strategy.breedDrones(%d, %d, %d)，参与繁殖的公主蜂和雄蜂在 %s 基因上不为同种纯合",princessSlot, droneSlot, targetAmount, chromosome))
        end
    end
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "breedDrones:"..bot.inventory[princessSlot].species[1]
    bot.inventory[droneSlot].inventoryLabel = bot.inventoryLabel
    while robot.count(droneSlot) < targetAmount do
        device.nextGeneration(princessSlot, droneSlot)
        princessSlot = nil
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beePrincess" then
                if princessSlot then
                    error("错误的调用strategy.breedDrones()，繁殖过程中出现了两只公主蜂")
                end
                princessSlot = slot
            end
        end
        if not princessSlot then
            error("错误的调用strategy.breedDrones().nextGeneration，繁殖过程中未找到公主蜂")
        end
        droneSlot = nil
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" then
                if droneSlot and bot.inventory[slot].tag ~= bot.inventory[droneSlot].tag then
                    error("错误的调用strategy.breedDrones()，繁殖过程中出现了多种基因型的雄蜂")
                end
                droneSlot = slot
            end
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    bot.inventory[droneSlot].inventoryLabel = previousLabel
    return princessSlot, droneSlot
end

function M.getAssistantDrones()--获取样板雄蜂
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "breedAssistantDrones"
    local droneTag, princess = beeData.getAssistantBeesTag()
    local droneSlot = bot.checkItem({name="Forestry:beeDroneGE",tag=droneTag}, 16)
    if not droneSlot then
        error("获取样板雄蜂失败：未能提供足够的样板雄蜂")
    end
    local temp = upgrade_me.getItemsInNetwork({label=bot.inventory[droneSlot].label})
    local droneCount = 0
    for _, stack in pairs(temp) do
        if stack.tag == droneTag then
            droneCount = stack.size
            break
        end
    end
    if droneCount < 20 then
        if princess then
            princess = bot.checkItem({name="Forestry:beePrincessGE",tag=princess}, 1)
            if not princess then
                error("获取辅助公主蜂失败：未找到现存的辅助公主蜂")
            end
        else
            princess = beeData.getPrincessTag(true)
            princess = bot.checkItem({name="Forestry:beePrincessGE",tag=princess}, 1)
            if not princess then
                error("培育样板雄蜂失败：未找到可用的初始公主蜂")
            end
            local targetGenes = {}
            for _, chromosome in pairs(chromosomeList) do
                targetGenes[chromosome] = bot.inventory[droneSlot][chromosome][1]
            end
            droneSlot, princess = M.purify(princess, droneSlot, targetGenes, droneSlot, ":assistant")
            if not droneSlot then
                error("培育样板雄蜂过程中发生基因丢失")
            end
        end
        princess, droneSlot = M.breedDrones(princess, droneSlot, 48-droneCount)
        beeData.updateAssistantPrincess(princess)
        robot.select(princess)
        upgrade_me.sendItems()
    end
    bot.inventoryLabel = previousLabel
    local excess = robot.count(droneSlot--[[@as number]]) - 16
    if excess > 0 then
        robot.select(droneSlot--[[@as number]])
        upgrade_me.sendItems(excess)
    end
    bot.inventory[droneSlot].inventoryLabel = previousLabel
    return droneSlot
end

function M.newSpecies(species, mutation)--突变新品种并优化基因
    --校验输入
    local allele1Tag, allele2Tag = beeData.getDroneTag(mutation.parents[1]), beeData.getDroneTag(mutation.parents[2])
    if not allele1Tag or not allele2Tag then
        error(string.format("错误的调用strategy.newSpecies(%s, %s)，突变所需的亲本品种不存在",species, mutation.name))
    end
    if not mutation.dimension then
        local function confirmMutation()
            io.write("是否继续执行突变？[Y/n]：")
            local answer = io.read()
            if answer ~= "Y" and answer ~= "y" then
                error("突变"..mutation.name.."：已取消")
            end
        end
        if mutation.date then
            print(mutation.name.."蜂突变仅在"..mutation.date[1].."到"..mutation.date[2].."之间发生")
            confirmMutation()
        end
        if mutation.lunar_phase then
            if type(mutation.lunar_phase) == "table" then
                print(mutation.name.."蜂突变仅在月相在"..mutation.lunar_phase[1].."到"..mutation.lunar_phase[2].."之间发生")
            else
                print(mutation.name.."蜂突变仅在月相为"..mutation.lunar_phase.."时发生")
            end
            confirmMutation()
        end
        if mutation.time then
            print(mutation.name.."蜂突变仅在"..mutation.time.."时发生")
            confirmMutation()
        end
    end
    --初始化
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "newSpecies:"..species
    local allele1Slot, allele2Slot, assistantDroneSlot, princessSlot
    local mutatedBeeList, droneSlot
    local function isTemplatedGenes(tag)
        local genes = require("analyzeGenes")({name="Forestry:beeDroneGE",individual={},tag=tag})
        for chromosome, gene in pairs({flowering=1,flowerProvider="extrabees.flower.rock",fertility=4,territory=1,temperatureTolerance="BOTH_5",humidityTolerance="BOTH_5",nocturnal=true,tolerantFlyer=true,caveDwelling=true}) do
            if genes[chromosome][1] ~= gene or genes[chromosome][2] ~= gene then
                return false
            end
        end
        return true
    end
    local function getOperations(isPrincessParent, isPrincessTemplated, isAllele1Templated, isAllele2Templated)
        --以最小purify步数，快速将公主蜂转换为一亲本纯种，同时让亲本蜂具备模板基因
        if isPrincessParent == 1 and isAllele2Templated then
            return isPrincessTemplated and {} or {"purify(1)"}, false
        end
        if isPrincessParent == 2 and isAllele1Templated then
            return isPrincessTemplated and {} or {"purify(2)"}, true
        end
        if isAllele2Templated then
            return {"purify(1)"}, false
        end
        if isAllele1Templated then
            return {"purify(2)"}, true
        end
        return {"purify(2)", "purify(1)"}, false
    end
    ::GET_PARENT_BEES::
    --获取亲本公主蜂与雄蜂
    assistantDroneSlot = M.getAssistantDrones()--[[@as number]]
    princessSlot = bot.checkItem({name="Forestry:beePrincessGE",tag=beeData.getPrincessTag(true)}, 1)
    if not princessSlot then
        error(string.format("突变%s：无法获取公主蜂", mutation.name))
    end
    local isPrincessParent
    if bot.inventory[princessSlot].species[1] == mutation.parents[1] and bot.inventory[princessSlot].species[2] == mutation.parents[1] then
        isPrincessParent = 1
    elseif bot.inventory[princessSlot].species[1] == mutation.parents[2] and bot.inventory[princessSlot].species[2] == mutation.parents[2] then
        isPrincessParent = 2
    end
    allele1Tag, allele2Tag = beeData.getDroneTag(mutation.parents[1]), beeData.getDroneTag(mutation.parents[2])
    local operations, exchanged = getOperations(isPrincessParent, isTemplatedGenes(bot.inventory[princessSlot].tag), isTemplatedGenes(allele1Tag), isTemplatedGenes(allele2Tag))
    allele1Slot = bot.checkItem({name="Forestry:beeDroneGE",tag=allele1Tag}, 16)
    allele2Slot = bot.checkItem({name="Forestry:beeDroneGE",tag=allele2Tag}, 16)
    if not allele1Slot and not allele2Slot then
        error(string.format("突变%s：缺乏必需的亲本雄蜂", mutation.name))
    end
    for _, operation in ipairs(operations) do
        if operation == "purify(1)" then
            allele1Slot, princessSlot = M.purify(princessSlot, allele1Slot, beeData.getTargetGenes(mutation.parents[1]), assistantDroneSlot, ":allele1")
            if not allele1Slot then
                beeData.updateUsingPrincess(princessSlot)
                error("突变"..mutation.name.."亲本雄蜂1基因丢失")
            end
        elseif operation == "purify(2)" then
            allele2Slot, princessSlot = M.purify(princessSlot, allele2Slot, beeData.getTargetGenes(mutation.parents[2]), assistantDroneSlot, ":allele2")
            if not allele2Slot then
                beeData.updateUsingPrincess(princessSlot)
                error("突变"..mutation.name.."亲本雄蜂2基因丢失")
            end
        end
    end
    if exchanged then
        if allele2Slot ~= assistantDroneSlot then
            robot.select(allele2Slot)
            upgrade_me.sendItems()
        end
        allele2Slot = nil
    else
        if allele1Slot ~= assistantDroneSlot then
            robot.select(allele1Slot)
            upgrade_me.sendItems()
        end
        allele1Slot = nil
    end
    if bot.inventory[assistantDroneSlot] and assistantDroneSlot ~= (exchanged and allele1Slot or allele2Slot) then
        robot.select(assistantDroneSlot)
        upgrade_me.sendItems()
        assistantDroneSlot = nil
    end
    if exchanged then
        robot.select(allele1Slot--[[@as number]])
        upgrade_me.sendItems(robot.count(allele1Slot--[[@as number]])-1)
        mutatedBeeList, princessSlot = M.mutate(princessSlot, allele1Slot, species, mutation)
        allele1Slot = nil
    else
        robot.select(allele2Slot--[[@as number]])
        upgrade_me.sendItems(robot.count(allele2Slot--[[@as number]])-1)
        mutatedBeeList, princessSlot = M.mutate(princessSlot, allele2Slot, species, mutation)
        allele2Slot = nil
    end
    if not mutatedBeeList then
        beeData.updateUsingPrincess(princessSlot)
        goto GET_PARENT_BEES
    end
    --纯化突变产生的基因
    while true do
        if not mutatedBeeList[1] then
            beeData.updateUsingPrincess(princessSlot)
            goto GET_PARENT_BEES
        end
        local mDrone = mutatedBeeList[1]
        table.remove(mutatedBeeList, 1)
        assistantDroneSlot = M.getAssistantDrones()--[[@as number]]
        if mDrone == princessSlot then
            mDrone = assistantDroneSlot
        end
        droneSlot, princessSlot = M.purify(princessSlot, mDrone, beeData.getTargetGenes(species), assistantDroneSlot, ":mutated")
        if bot.inventory[assistantDroneSlot] and assistantDroneSlot ~= droneSlot and assistantDroneSlot ~= princessSlot then
            robot.select(assistantDroneSlot)
            upgrade_me.sendItems()
            assistantDroneSlot = nil
        end
        if droneSlot then
            break
        end
    end
    --处理结果
    for _,slot in pairs(mutatedBeeList--[[@as table]]) do
        robot.select(slot)
        robot.dropUp()
    end
    for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
        if slot ~= droneSlot and slot ~= princessSlot then
            robot.select(slot)
            upgrade_me.sendItems()
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    bot.inventory[droneSlot].inventoryLabel = previousLabel
    beeData.updateUsingPrincess(princessSlot)
    local updated, oldAssistantPrincessTag = beeData.updateAssistantDrone(droneSlot)
    if updated then
        beeData.updateAssistantPrincess(princessSlot, oldAssistantPrincessTag)
    end
    return droneSlot, princessSlot
end

function M.task(species)--制定突变链
    --计算突变路径
    print("计算突变路径")
    local mutationChain, lackSpecies = {}, {}
    if not beeData.initialized then
        if not beeData.getDroneTag("forestry.speciesWintry") then
            table.insert(lackSpecies, "forestry.speciesWintry")
        end
        if not beeData.getDroneTag("extrabees.species.rock") then
            table.insert(lackSpecies, "extrabees.species.rock")
        end
    end
    do
        local visited = {}
        local function addMutation(species)
            if visited[species] then
                return
            end
            visited[species] = true
            if beeData.getDroneTag(species) then
                return
            end
            if not beeData.initialized and (species == "forestry.speciesCultivated" or species == "forestry.speciesCommon") then
                return
            end
            --[[component.database.set(1, "Forestry:beeDroneGE", 0, '{IsAnalyzed:1b,Genome:{Chromosomes:[0:{Slot:0b,UID0:"'..species..'",UID1:"'..species..'"}]}}')
            if bot.checkItem({label=component.database.get(1).label}) then
                return
            end]]--无需检查公主蜂
            if mutations[species] then
                local parents
                if mutations[species][1] then
                    parents = mutations[species][1].parents
                else
                    parents = mutations[species].parents
                end
                addMutation(parents[1])
                addMutation(parents[2])
                table.insert(mutationChain, {species, mutations[species][1] or mutations[species]})
            else
                table.insert(lackSpecies, species)
                return
            end
        end
        addMutation(species)
    end
    if lackSpecies[1] then
        print("无法完成此突变任务，缺乏以下品种：")
        for _, species in ipairs(lackSpecies) do
            print("  - " .. species)
        end
        return
    end
    --校验突变条件
    print("校验突变条件")
    local lackFoundation, lackEnvironmentConditions, requiredDimension, requiredMutatron = {}, {}, {}, {}
    local requiredDate, requiredLunarPhase, requiredTime = {}, {}, {}
    for i = 1, #mutationChain do
        local isSuitable, missingConditions = device.checkMutationEnvironment(mutationChain[i][2])
        if not isSuitable then
            lackEnvironmentConditions[i] = missingConditions
        end
        if mutationChain[i][2].foundation and not bot.checkItem({name=mutationChain[i][2].foundation.name,damage=mutationChain[i][2].foundation.damage}) then
            lackFoundation[i] = mutationChain[i][2].foundation.label
        end
        for _, condition in pairs({"dimension", "date", "lunar_phase", "time"}) do
            if mutationChain[i][2][condition] then
                if condition == "dimension" then
                    requiredDimension[i] = mutationChain[i][2][condition]
                elseif condition == "date" then
                    requiredDate[i] = mutationChain[i][2][condition]
                elseif condition == "lunar_phase" then
                    requiredLunarPhase[i] = mutationChain[i][2][condition]
                elseif condition == "time" then
                    requiredTime[i] = mutationChain[i][2][condition]
                end
            end
        end
        if requiredDimension[i] then
            lackFoundation[i] = nil
            lackEnvironmentConditions[i] = nil
        end
        if mutationChain[i][2].requiredMutatron then
            requiredMutatron[i] = true
        end
    end
    if next(lackEnvironmentConditions) or next(requiredMutatron) then
        if next(lackEnvironmentConditions) then
            print("无法完成此突变任务，以下突变不满足环境条件：")
        end
        for i, conditions in pairs(lackEnvironmentConditions) do
            for _, condition in pairs(conditions) do
                if condition == "temperature" then
                    if type(mutationChain[i][2].temperature) == "table" then
                        print(string.format("  - %s蜂突变仅在温度在%s到%s之间发生", mutationChain[i][2].name, mutationChain[i][2].temperature[1], mutationChain[i][2].temperature[2]))
                    else
                        print(string.format("  - %s蜂突变仅在温度为%s时发生", mutationChain[i][2].name, mutationChain[i][2].temperature))
                    end
                elseif condition == "humidity" then
                    print(string.format("  - %s蜂突变仅在湿度为%s时发生", mutationChain[i][2].name, mutationChain[i][2].humidity))
                elseif condition == "biome" then
                    print(string.format("  - %s蜂突变仅在%s生物群系中发生", mutationChain[i][2].name, mutationChain[i][2].biome))
                elseif condition == "biomeType" then
                    if mutationChain[i][2].biomeType == "ScummyBee" then
                        print("浮渣蜂突变仅在和[ocean, hot]或[ocean, wet]类似的生物群系中发生")
                    else
                        print(string.format("  - %s蜂突变仅在带有%s标签的生物群系中发生", mutationChain[i][2].name, mutationChain[i][2].biomeType))
                    end
                end
            end
        end
        if next(requiredMutatron) then
            print("以下突变仅支持通过诱变机进行：")
        end
        for i, _ in pairs(requiredMutatron) do
            print(string.format("  - %s蜂", mutationChain[i][2].name))
        end
        return
    end
    while next(lackFoundation) do
        print("以下突变缺少基石：")
        for i, foundationName in pairs(lackFoundation) do
            print(string.format("  - %s蜂突变缺少：%s", mutationChain[i][2].name, foundationName))
        end
        io.write("是否重新检查？[Y/n]：")
        local answer = io.read()
        if answer ~= "Y" and answer ~= "y" then
            print("突变任务已取消")
            return
        else
            print("重新检查中")
            for i, _ in pairs(lackFoundation) do
                if bot.checkItem({name=mutationChain[i][2].foundation.name,damage=mutationChain[i][2].foundation.damage}) then
                    lackFoundation[i] = nil
                end
            end
        end
    end
    local function confirmContinue()
        io.write("是否继续执行突变？[Y/n]：")
        local answer = io.read()
        if answer == "Y" or answer == "y" then
            return true
        else
            print("突变任务已取消")
            return false
        end
    end
    if next(requiredDimension) then
        print("以下突变需要在员工前往对应维度手动进行：")
        for i, condition in pairs(requiredDimension) do
            print(string.format("  - %s蜂突变需要维度%s", mutationChain[i][2].name, condition))
        end
        return
        --[[if not confirmContinue() then
            return
        end]]
    end
    if next(requiredDate) then
        print("以下突变需要在对应日期进行：")
        for i, condition in pairs(requiredDate) do
            print(string.format("  - %s蜂突变仅在%s到%s之间发生", mutationChain[i][2].name, condition[1], condition[2]))
        end
        if not confirmContinue() then
            return
        end
    end
    if next(requiredLunarPhase) then
        print("以下突变需要在对应月相进行：")
        for i, condition in pairs(requiredLunarPhase) do
            if type(condition) == "table" then
                print(string.format("  - %s蜂突变需要月相在%s到%s之间", mutationChain[i][2].name, condition[1], condition[2]))
            else
                print(string.format("  - %s蜂突变需要月相为%s", mutationChain[i][2].name, condition))
            end
        end
        if not confirmContinue() then
            return
        end
    end
    if next(requiredTime) then
        print("以下突变需要在对应时间进行：")
        for i, condition in pairs(requiredTime) do
            print(string.format("  - %s蜂突变仅在%s时发生", mutationChain[i][2].name, condition))
        end
        if not confirmContinue() then
            return
        end
    end
    print("突变条件核验完毕，开始执行突变")
    --执行
    if not beeData.initialized then
        M.initialize()
    end
    for i = 1, #mutationChain do
        print(string.format("正在培育%s蜂", mutationChain[i][2].name))
        local droneSlot, princessSlot = M.newSpecies(mutationChain[i][1], mutationChain[i][2])
        robot.select(droneSlot--[[@as number]])
        upgrade_me.sendItems()
        robot.select(princessSlot--[[@as number]])
        upgrade_me.sendItems()
        bot.charge()
    end
    print("培育完毕！")
    device.destruct()
end

function M.initialize()--初始化至田野蜂以制造样板蜂
    local function hasTargetGenes(genes, targetGenes)
        for chromosome, gene in pairs(targetGenes) do
            if genes[chromosome][1] ~= gene and genes[chromosome][2] ~= gene then
                return false
            end
        end
        return true
    end
    local templateGenes = {
        [1] = {species = "forestry.speciesWintry",speed = 2,lifespan = 3,fertility = 4,flowering = 1,flowerProvider = "forestry.flowersSnow",territory = 1,effect = "forestry.effectGlacial",temperatureTolerance = "BOTH_5",humidityTolerance = "BOTH_5",nocturnal = false,tolerantFlyer = false,caveDwelling = false},
        [2] = {species = "extrabees.species.rock",speed = 2,lifespan = 3,fertility = 4,flowering = 1,flowerProvider = "extrabees.flower.rock",territory = 1,effect = "forestry.effectNone",temperatureTolerance = "BOTH_5",humidityTolerance = "BOTH_5",nocturnal = true,tolerantFlyer = true,caveDwelling = true},
        [3] = {species = "forestry.speciesWintry",speed = 2,lifespan = 3,fertility = 4,flowering = 1,flowerProvider = "extrabees.flower.rock",territory = 1,effect = "forestry.effectGlacial",temperatureTolerance = "BOTH_5",humidityTolerance = "BOTH_5",nocturnal = true,tolerantFlyer = true,caveDwelling = true}
    }
    --温度适应性5与湿度适应性5的凛冬公主蜂
    print("请提供一只使用适应性调整器将温度适应性、湿度适应性均调整到全5的始祖种凛冬公主蜂")
    local princess1Slot, drone1Slot
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "initialize:getingTorlance5Princess"
    while true do
        os.sleep(1)
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beePrincess" and bot.inventory[slot].isNatural == true and hasTargetGenes(bot.inventory[slot], {species = "forestry.speciesWintry", temperatureTolerance = "BOTH_5", humidityTolerance = "BOTH_5"}) then
                princess1Slot = slot
                break
            else
                robot.select(slot)
                upgrade_me.sendItems()
            end
        end
        if princess1Slot then
            break
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princess1Slot].inventoryLabel = previousLabel
    local wintryDroneSlot = doUntil(function()
        return bot.checkItem({name="Forestry:beeDroneGE",tag=
            doUntil(function()
                return beeData.getDroneTag("forestry.speciesWintry")
            end, "缺少凛冬雄蜂")
        }, 16)
    end, "缺少凛冬雄蜂")
    print("正在提纯温度适应性全5、湿度适应性全5基因")
    drone1Slot, princess1Slot = M.purify(princess1Slot, wintryDroneSlot, templateGenes[1], wintryDroneSlot, ":initializing")
    if not drone1Slot then
        error("初始化失败")
    end
    robot.select(wintryDroneSlot)
    upgrade_me.sendItems()
    --夜行、穴居、耐雨、石头采蜜的石头蜂
    local drone2Slot = doUntil(function()
        return bot.checkItem({name="Forestry:beeDroneGE",tag=
            doUntil(function()
                return beeData.getDroneTag("extrabees.species.rock")
            end, "缺少石头雄蜂")
        }, 1)
    end, "缺少石头雄蜂")
    print("正在向石头蜂引入生育4x、温度适应性全5、湿度适应性全5基因")
    drone2Slot, princess1Slot = M.purify(princess1Slot, drone2Slot, templateGenes[2], drone1Slot, ":initializing")
    if not drone2Slot then
        error("初始化失败")
    end
    --同性状凛冬蜂
    local princess2Slot = bot.checkItem({name="Forestry:beePrincessGE",tag=beeData.getPrincessTag(true)}, 1)
    if not princess2Slot then
        error("初始化失败：ME网络内缺少初始公主蜂")
    end
    print("正在向凛冬蜂引入采蜜对象石头、夜行性、耐雨飞行性、穴居性基因")
    robot.select(drone1Slot--[[@as number]])
    robot.dropUp(robot.count(drone1Slot--[[@as number]])-1)
    drone1Slot, princess2Slot = M.purify(princess2Slot, drone1Slot, templateGenes[3], drone2Slot, ":initializing")
    --寻常蜂
    beeData.updateAssistantDrone(drone2Slot, true)
    beeData.updateAssistantPrincess(princess1Slot)
    beeData.updateUsingPrincess(princess2Slot)
    for _,slot in pairs({drone1Slot, princess1Slot, drone2Slot, princess2Slot}) do
        robot.select(slot--[[@as number]])
        upgrade_me.sendItems()
    end
    drone1Slot, princess1Slot, drone2Slot, princess2Slot = nil, nil, nil, nil
    print("正在培育寻常蜂")
    local tempDrone, tempPrincess = M.newSpecies("forestry.speciesCommon", {name="寻常",parents={"forestry.speciesWintry","extrabees.species.rock"},baseChance=15.0})
    if tempDrone then
        robot.select(tempDrone)
        upgrade_me.sendItems()
        robot.select(tempPrincess)
        upgrade_me.sendItems()
    else
        error("初始化失败")
    end
    --田野蜂（获取早夭）
    print("正在培育田野蜂")
    tempDrone, tempPrincess = M.newSpecies("forestry.speciesCultivated", {name="田野",parents={"forestry.speciesCommon","extrabees.species.rock"},baseChance=12.0})
    if tempDrone then
        robot.select(tempDrone)
        upgrade_me.sendItems()
        robot.select(tempPrincess)
        upgrade_me.sendItems()
    else
        error("初始化失败")
    end
    bot.inventoryLabel = previousLabel
    beeData.initialized = true
end

return M
