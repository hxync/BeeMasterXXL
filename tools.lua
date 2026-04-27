local M = {}

local bot = require("bot")
local doUntil = require("doUntil")

local robot = require("robot")

function M.swingDown(tool)
    if tool == "bucket" then
        if not bot.inventory[0] or bot.inventory[0].name ~= "minecraft:bucket" then
            robot.select(
                doUntil(function()
                    return bot.checkItem({name = "minecraft:bucket"}, 1)
                end, "缺少桶")
            )
            bot.equip()
        end
        robot.useDown()
    elseif tool == nil then
        if not bot.inventory[0] or bot.inventory[0].name ~= "gregtech:gt.Tool_Vajra" then
            robot.select(
                doUntil(function()
                    return bot.checkItem({name = "gregtech:gt.Tool_Vajra"}, 1)
                end, "缺少金刚杵")
            )
            bot.equip()
        end
        if not (bot.inventory[0].enchantments and bot.inventory[0].enchantments[1] and bot.inventory[0].enchantments[1].name == "enchantment.untouching") then
            robot.useUp(nil, true)
            bot.inventory[0].enchantments = {{name = "enchantment.untouching", level = 1, label = "精准采集"}}
        end
        local _1, _2 = robot.swingDown()
        if _1 and _2 == "block" then
            os.sleep(0.01)
        end
    else
        error("错误的调用tools.swingDown()")
    end
end

function M.placeDown(item)
    if not item or not item.name then
        error("错误的调用tools.placeDown()")
    end
    if item.tool then
        if item.tool == "bucket" then
            robot.select(
                doUntil(function()
                    return bot.checkItem({name = item.name, damage = item.damage}, 1)
                end, "缺少"..(item.label or item.name))
            )
            bot.equip()
            robot.useDown()
        else
            error("错误的调用tools.placeDown()")
        end
    else
        robot.select(
            doUntil(function()
                return bot.checkItem({name = item.name, damage = item.damage}, 1)
            end, "缺少"..(item.label or item.name))
        )
        robot.placeDown()
    end
end

return M