local M = {}

function M.getTemperatureLevel(temperature, biomeTypes)
    for _, biomeType in ipairs(biomeTypes) do
        if biomeType == "nether" then
            return 3 --地狱
        end
    end
    if temperature <= 0 then
        return -2 --严寒
    elseif temperature < 0.35 then
        return -1 --寒冷
    elseif temperature < 0.85 then
        return 0 --一般
    elseif temperature <= 1 then
        return 1 --温暖
    else
        return 2 --炙热
    end
end

function M.getHumidityLevel(rainfall)
    if rainfall <= 0.2 then
        return -1 --干旱
    elseif rainfall <= 0.8 then
        return 0 --一般
    else
        return 1 --潮湿
    end
end

function M.getTemperatureRange(temperatureGene, toleranceGene)
    if not temperatureGene or not toleranceGene then
        return nil
    end
    local temperatureUpperLimit, temperatureLowerLimit = temperatureGene, temperatureGene
    if toleranceGene:sub(1,3) == "BOT" or toleranceGene:sub(1,3) == "UP_" then
        temperatureUpperLimit = temperatureUpperLimit + tonumber(toleranceGene:sub(-1))
    end
    if toleranceGene:sub(1,3) == "BOT" or toleranceGene:sub(1,3) == "DOW" then
        temperatureLowerLimit = temperatureLowerLimit - tonumber(toleranceGene:sub(-1))
    end
    return math.max(temperatureLowerLimit, -2), math.min(temperatureUpperLimit, 3)
end

function M.getHumidityRange(humidityGene, toleranceGene)
    if not humidityGene or not toleranceGene then
        return nil
    end
    local humidityUpperLimit, humidityLowerLimit = humidityGene, humidityGene
    if toleranceGene:sub(1,3) == "BOT" or toleranceGene:sub(1,3) == "UP_" then
        humidityUpperLimit = humidityUpperLimit + tonumber(toleranceGene:sub(-1))
    end
    if toleranceGene:sub(1,3) == "BOT" or toleranceGene:sub(1,3) == "DOW" then
        humidityLowerLimit = humidityLowerLimit - tonumber(toleranceGene:sub(-1))
    end
    return math.max(humidityLowerLimit, -1), math.min(humidityUpperLimit, 1)
end



return M