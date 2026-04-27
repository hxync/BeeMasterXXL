local module = {}

local spack, sunpack = string.pack, string.unpack
local ssub = string.sub

function module.getValue(obj)
    if type(obj) == 'table' and type(obj._type) == 'number' and obj.value ~= nil then
        return obj.value
    end
    return obj
end

module.TAGS = {
    END = 0,
    BYTE = 1,
    SHORT = 2,
    INT = 3,
    LONG = 4,
    FLOAT = 5,
    DOUBLE = 6,
    BYTE_ARRAY = 7,
    STRING = 8,
    LIST = 9,
    COMPOUND = 10,
    INT_ARRAY = 11,
    LONG_ARRAY = 12
}

--- byte tag
module.TAGS[module.TAGS.BYTE] = {
    decode = function (reader)
        return {
            _type = module.TAGS.BYTE,
            value = sunpack('b', reader(1))
        }
    end,
    encode = function (obj)
        return spack('b', module.getValue(obj))
    end
}

--- short tag
module.TAGS[module.TAGS.SHORT] = {
    decode = function (reader)
        return {
            _type = module.TAGS.SHORT,
            value = sunpack('>h', reader(2))
        }
    end,
    encode = function (obj)
        return spack('>h', module.getValue(obj))
    end
}

--- int tag
module.TAGS[module.TAGS.INT] = {
    decode = function (reader)
        return {
            _type = module.TAGS.INT,
            value = sunpack('>i4', reader(4))
        }
    end,
    encode = function (obj)
        return spack('>i4', module.getValue(obj))
    end
}

--- long tag
module.TAGS[module.TAGS.LONG] = {
    decode = function (reader)
        return {
            _type = module.TAGS.LONG,
            value = sunpack('>l', reader(8))
        }
    end,
    encode = function (obj)
        return spack('>l', module.getValue(obj))
    end
}

--- float tag
module.TAGS[module.TAGS.FLOAT] = {
    decode = function (reader)
        return {
            _type = module.TAGS.FLOAT,
            value = sunpack('>f', reader(4))
        }
    end,
    encode = function (obj)
        return spack('>f', module.getValue(obj))
    end
}

--- double tag
module.TAGS[module.TAGS.DOUBLE] = {
    decode = function (reader)
        return {
            _type = module.TAGS.DOUBLE,
            value = sunpack('>d', reader(8))
        }
    end,
    encode = function (obj)
        return spack('>d', module.getValue(obj))
    end
}

--- byte array tag
module.TAGS[module.TAGS.BYTE_ARRAY] = {
    decode = function (reader)
        local size = module.TAGS[module.TAGS.INT].decode(reader).value
        local t = {}
    
        for i = 1, size do
            t[i] = sunpack('b', reader(1))
        end
    
        return {
            _type = module.TAGS.BYTE_ARRAY,
            value = t
        }
    end,
    encode = function (wrapper)
        local array = wrapper.value
        local size = #array
        local parts = {
            module.TAGS[module.TAGS.INT].encode(size)
        }

        for i = 1, size do
            parts[#parts+1] = spack('b', array[i])
        end
        
        return table.concat(parts)
    end
}

--- string tag
module.TAGS[module.TAGS.STRING] = {
    decode = function (reader)
        local length = sunpack('>H', reader(2))
        local readed
        if length < 1 then
            readed = ''
        else
            readed = reader(length)
        end
        return {
            _type = module.TAGS.STRING,
            value = readed
        }
    end,
    encode = function (wrapper)
        return spack('>H', #wrapper.value) .. wrapper.value
    end
}

--- list tag
module.TAGS[module.TAGS.LIST] = {
    decode = function (reader)
        local itemID = module.TAGS[module.TAGS.BYTE].decode(reader).value
        local length = module.TAGS[module.TAGS.INT].decode(reader).value
        local tag = module.TAGS[itemID]
        local t = {}
    
        if itemID == module.TAGS.END then
            -- end tag
            if length ~= 0 then
                error("List with TAG_End item type must have length 0, got " .. length)
            end
            return {
                _type = module.TAGS.LIST,
                _itemID = module.TAGS.END,
                value = t
            }
        end
        if not tag then
            error('Unknown tag ID for list items: ' .. itemID)
        end
    
        for i = 1, length do
            t[i] = tag.decode(reader)
        end
    
        return {
            _type = module.TAGS.LIST,
            _itemID = itemID,
            value = t
        }
    end,
    encode = function (wrapper)
        local list = wrapper.value
        local size = #list
        local tag = module.TAGS[wrapper._itemID]
        local parts = {}
        if not tag and wrapper._itemID ~= module.TAGS.END then
            error('Encoder not found for list item type ID: ' .. wrapper._itemID)
        end

        parts[1] = module.TAGS[module.TAGS.BYTE].encode(wrapper._itemID)
        parts[2] = module.TAGS[module.TAGS.INT].encode(size)

        if tag then
            for i = 1, size do
                parts[#parts+1] = tag.encode(list[i])
            end
        end

        return table.concat(parts)
    end
}

--- compound tag
module.TAGS[module.TAGS.COMPOUND] = {
    decode = function (reader)
        local t = {}
        while true do
            local id = module.TAGS[module.TAGS.BYTE].decode(reader).value
    
            if id == module.TAGS.END then
                break
            end
    
            local name = module.TAGS[module.TAGS.STRING].decode(reader).value
            local tag = module.TAGS[id]
            if not tag then
                error('Unknown tag ID '.. id ..' in compound for tag "' .. name .. '"')
            end
    
            t[name] = tag.decode(reader)
        end
        return {
            _type = module.TAGS.COMPOUND,
            value = t
        }
    end,
    encode = function (wrapper)
        local compound = wrapper.value
        local parts = {}

        for name, itemWrapper in pairs(compound) do
            --- note: in compound tags, index are always string
            if type(name) ~= "string" then error("NBT Compound key must be a string") end
            if type(itemWrapper) ~= "table" or not itemWrapper._type or itemWrapper.value == nil then
                error("Invalid item data in compound for key '" .. name .. "'. Expected NBT wrapper.")
            end

            local item = module.TAGS[itemWrapper._type]
            if not item or not item.encode then
                error('Encoder not found for compound item type ID: ' .. itemWrapper._type .. ' for key "' .. name .. '"')
            end

            parts[#parts+1] = module.TAGS[module.TAGS.BYTE].encode(itemWrapper._type)
            parts[#parts+1] = module.TAGS[module.TAGS.STRING].encode({value = name})
            parts[#parts+1] = item.encode(itemWrapper)
        end

        parts[#parts+1] = module.TAGS[module.TAGS.BYTE].encode(module.TAGS.END)
        return table.concat(parts)
    end
}

--- int array
module.TAGS[module.TAGS.INT_ARRAY] = {
    decode = function (reader)
        local len = module.TAGS[module.TAGS.INT].decode(reader).value
        local t = {}
    
        for i = 1, len do
            t[i] = module.TAGS[module.TAGS.INT].decode(reader).value
        end
    
        --local raw = reader(len * 4) -- each INT allocates 4 bytes
        --local unpackPattern = srep('>i4', len)
        --local t = {sunpack(unpackPattern, raw)}

        return {
            _type = module.TAGS.INT_ARRAY,
            value = t
        }
    end,
    encode = function (wrapper)
        local array = wrapper.value
        local size = #array
        local parts = {
            module.TAGS[module.TAGS.INT].encode(size)
        }

        for i = 1, size do
            parts[#parts+1] = module.TAGS[module.TAGS.INT].encode(array[i])
        end
        --if size > 0 then
        --    parts[#parts+1] = spack(srep('>i4', size), unpack(array))
        --end

        return table.concat(parts)
    end
}

--- long array
module.TAGS[module.TAGS.LONG_ARRAY] = {
    decode = function (reader)
        local len = module.TAGS[module.TAGS.INT].decode(reader).value
        local t = {}
    
        for i = 1, len do
            t[i] = module.TAGS[module.TAGS.LONG].decode(reader).value
        end
    
        --local raw = reader(len * 8) -- each LONG allocates 8 bytes
        --local unpackPattern = srep('>l', len)
        --local t = {sunpack(unpackPattern, raw)}

        return {
            _type = module.TAGS.LONG_ARRAY,
            value = t
        }
    end,
    encode = function (wrapper)
        local array = wrapper.value
        local size = #array
        local parts = {
            module.TAGS[module.TAGS.INT].encode(size)
        }
        

        for i = 1, size do
            parts[#parts+1] = module.TAGS[module.TAGS.LONG].encode(array[i])
        end
        --if size > 0 then
        --    parts[#parts+1] = spack(srep('>l', size), unpack(array))
        --end

        return table.concat(parts)
    end
}

--- Create a string reader function.
--- @param str string The string to read from.
--- @return function reader A function that reads the specified number of bytes from the string.
function module.stringReader(str)
    assert(type(str) == 'string', 'not a string')
    
    local size = #str
    local totalOffset = 0
    
    return function(n)
        if n == nil then
            return size - totalOffset
        end
        if type(n) ~= 'number' or n < 1 then
            error('not a positive number')
        end
        
        local newEndOffset = totalOffset + n
        
        if newEndOffset <= size then
            local chunk = ssub(str, totalOffset + 1, newEndOffset)
            totalOffset = newEndOffset
            return chunk
        else
            error('overflow: ' .. newEndOffset .. ' > ' .. size)
        end
    end
end

function module.decodeNetwork(reader)
    local rootID = sunpack('b', reader(1))
    local tag = module.TAGS[rootID]
    if not tag then
        error('Unknown root tag ID: ' .. rootID)
    end

    local rootData = tag.decode(reader)

    return rootData
end

function module.decode(payload)
    local reader = module.stringReader(payload)

    local rootID = sunpack('b', reader(1))
    local rootName = module.TAGS[module.TAGS.STRING].decode(reader)
    local tag = module.TAGS[rootID]
    if not tag then
        error('Unknown root tag ID: ' .. rootID)
    end

    local rootData = tag.decode(reader)

    if reader() > 0 then
        error("Trailing data after NBT structure: " .. reader() .. " bytes remaining.")
    end

    return rootName, rootData
end

function module.encode(rootNameInput, rootDataWrapper)
    local root_name_str

    -- 1. Handling root tag name
    if type(rootNameInput) == "table" and rootNameInput._type == module.TAGS.STRING and rootNameInput.value ~= nil then
        root_name_str = rootNameInput.value
    elseif type(rootNameInput) == "string" then
        root_name_str = rootNameInput
    elseif rootNameInput ~= nil then
        error("Root name must be a string or a TAG_String wrapper { _type = TAGS.STRING, value = 'name' }.")
    end

    -- 2. Checking root data
    if type(rootDataWrapper) ~= "table" or
       type(rootDataWrapper._type) ~= "number" or
       rootDataWrapper.value == nil then -- value can be {} for empty list/compound
        error("Root data for encode must be a NBT wrapper table, e.g., { _type = TAGS.COMPOUND, value = {...} }.")
    end
    
    local root_tag_id = rootDataWrapper._type

    -- 3. Getting encoder function for root tag payload
    local payload_encoder_fn
    if module.TAGS[root_tag_id] and module.TAGS[root_tag_id].encode then
        payload_encoder_fn = module.TAGS[root_tag_id].encode
    else
        error("Encoder function not found for root tag ID: " .. root_tag_id)
    end

    local parts = {
        -- id tag
        module.TAGS[module.TAGS.BYTE].encode(root_tag_id)
    }

    -- on newer Minecraft versions
    -- nbt doesn't have root tag name
    if root_name_str ~= nil then
        parts[#parts+1] = module.TAGS[module.TAGS.STRING].encode({value = root_name_str})
    end

    parts[#parts+1] = payload_encoder_fn(rootDataWrapper)

    return table.concat(parts)
end

-- SNBT support
-- SNBT parser implementation inside nbt module

-- Helper function for error reporting with position
local function snbtError(msg, pos, input)
    local lineNumber = 1
    local column = 1
    for i = 1, pos do
        if input:sub(i, i) == "\n" then
            lineNumber = lineNumber + 1
            column = 1
        else
            column = column + 1
        end
    end
    error(string.format("SNBT parse error at line %d, column %d: %s", lineNumber, column, msg))
end

-- Tokenizer for SNBT string
local function snbtTokenize(input)
    local pos = 1
    local len = #input
    local peekedToken = nil
    
    local function skipWhitespace()
        local s, e = input:find("^%s+", pos)
        if s then
            pos = e + 1
        end
    end
    
    local function consumeNumber()
        local s, e, num = input:find("^([%-%+]?%d+%.?%d*[fFdDbBsSlL]?)", pos)
        if s then
            pos = e + 1
            return num
        end
        return nil
    end
    
    local function consumeString()
        local quote = input:sub(pos, pos)
        if quote ~= '"' and quote ~= "'" then
            return nil
        end
        
        local chars = {} -- use table for collecting characters
        local i = pos + 1
        local escaped = false
        local charCount = 0
        
        while i <= len do
            local c = input:sub(i, i)
            
            if escaped then
                if c == "n" then
                    charCount = charCount + 1; chars[charCount] = "\n"
                elseif c == "r" then
                    charCount = charCount + 1; chars[charCount] = "\r"
                elseif c == "t" then
                    charCount = charCount + 1; chars[charCount] = "\t"
                -- add other escape characters if needed (e.g., \uXXXX for unicode)
                -- but SNBT most often limits to \\, \", \' and \\n, \\r, \\t.
                else -- for \\, \", \' and other non-special characters after \
                    charCount = charCount + 1; chars[charCount] = c
                end
                escaped = false
            elseif c == "\\" then
                escaped = true
            elseif c == quote then
                pos = i + 1
                return table.concat(chars) -- concatenate once
            else
                charCount = charCount + 1; chars[charCount] = c
            end
            
            i = i + 1
        end
        
        snbtError("Unterminated string", pos, input)
    end
    
    local function consumeIdentifier()
        local s, e, id = input:find("^([a-zA-Z0-9_%.%-%+]+)", pos)
        if s then
            pos = e + 1
            return id
        end
        return nil
    end
    
    local function nextToken()
        if peekedToken ~= nil then
            local token = peekedToken
            peekedToken = nil
            return token
        end
        
        skipWhitespace()
        
        if pos > len then
            return nil
        end
        
        local c = input:sub(pos, pos)
        
        if c == "{" or c == "}" or c == "[" or c == "]" or c == ":" or c == "," or c == ";" then
            pos = pos + 1
            return c
        elseif c == '"' or c == "'" then
            return consumeString()
        elseif c:match("[%-%+0-9]") then
            return consumeNumber()
        elseif c:match("[a-zA-Z_]") then
            return consumeIdentifier()
        else
            snbtError("Unexpected character: " .. c, pos, input)
        end
    end
    
    local function peekToken()
        if peekedToken == nil then
            peekedToken = nextToken()
        end
        return peekedToken
    end
    
    local function putBackToken(token)
        peekedToken = token
    end
    
    return {
        nextToken = nextToken,
        peekToken = peekToken,
        putBackToken = putBackToken,
        getPos = function() return pos end
    }
end

-- function for parsing SNBT string
function module.decodeSNBT(input)
    local tokens = snbtTokenize(input)
    
    local parseValue
    local parseCompound
    local parseList
    
    parseCompound = function()
        local values = {}

        -- the opening '{' is consumed by parseValue before calling parseCompound.
        -- so, the first token peeked here is either the first key or '}' for empty compound.

        if tokens.peekToken() == "}" then -- handles empty compound {}
            tokens.nextToken() -- Consume '}'
            return {
                _type = module.TAGS.COMPOUND,
                value = values
            }
        end
        
        while true do
            local keyToken = tokens.nextToken()
            if type(keyToken) ~= "string" then
                snbtError("Expected string key in compound, got " .. tostring(keyToken) .. " at", tokens.getPos(), input)
            end
            
            local colon = tokens.nextToken()
            if colon ~= ":" then
                snbtError("Expected ':' after key '" .. keyToken .. "' in compound", tokens.getPos(), input)
            end
            
            local value = parseValue()
            values[keyToken] = value
            
            local separator = tokens.peekToken() -- Peek for separator
            if separator == "}" then
                tokens.nextToken() -- Consume '}'
                break -- End of compound
            elseif separator == "," or separator == ";" then
                tokens.nextToken() -- Consume the separator
                -- Handle trailing comma: if next is '}', then it's a trailing comma.
                if tokens.peekToken() == "}" then
                    tokens.nextToken() -- Consume '}'
                    break
                end
                -- Else, continue loop for next key-value pair
            else
                snbtError("Expected ',' or ';' or '}' after value for key '" .. keyToken .. "'", tokens.getPos(), input)
            end
        end
        
        return {
            _type = module.TAGS.COMPOUND,
            value = values
        }
    end
    parseList = function()
        -- The opening '[' is consumed by parseValue before calling parseList.
        -- So, the first token peeked here is either the first element or ']' for empty list.
        
        -- Check for empty list immediately
        if tokens.peekToken() == "]" then
            tokens.nextToken() -- Consume ']'
            return {
                _type = module.TAGS.LIST,
                _itemID = module.TAGS.END, -- Correct for empty list type
                value = {}
            }
        end

        -- Check for specialized arrays (B; I; L;)
        local potentialArrayType = tokens.peekToken()
        if potentialArrayType == "B" or potentialArrayType == "I" or potentialArrayType == "L" then
            tokens.nextToken() -- Consume B/I/L
            local sep = tokens.nextToken()
            if sep ~= ";" then
                snbtError("Expected ';' after array type for specialized array", tokens.getPos(), input)
            end
            
            local nbtTagType
            if potentialArrayType == "B" then nbtTagType = module.TAGS.BYTE_ARRAY
            elseif potentialArrayType == "I" then nbtTagType = module.TAGS.INT_ARRAY
            elseif potentialArrayType == "L" then nbtTagType = module.TAGS.LONG_ARRAY
            end

            local arrayValues = {}
            -- Check for empty array like [B;] or [I;] or [L;]
            if tokens.peekToken() == "]" then
                tokens.nextToken() -- Consume ']'
            else
                while true do
                    local numToken = tokens.nextToken()
                    if numToken == nil then
                        snbtError("Unexpected end of input inside array", tokens.getPos(), input)
                    end
                    
                    -- parse numeric value. Tokenizer already returned number string.
                    -- remove possible suffixes for tonumber if present (e.g., 1.0f -> 1.0)
                    local num_str = numToken:match("^[%-%+]?%d+%.?%d*")
                    local value = tonumber(num_str)
                    if value == nil then
                        snbtError("Expected number in array, got '" .. tostring(numToken) .. "'", tokens.getPos(), input)
                    end
                    table.insert(arrayValues, value)
                    
                    local separator = tokens.nextToken()
                    if separator == "]" then
                        break -- end of array
                    elseif separator ~= "," and separator ~= ";" then
                        snbtError("Expected ',' or ';' or ']' after array element", tokens.getPos(), input)
                    end
                end
            end
            
            return { _type = nbtTagType, value = arrayValues }
        else
            -- regular list
            local values = {}
            local itemType = nil
            
            -- parse first element (parseValue consumes it)
            local value = parseValue()
            table.insert(values, value)
            itemType = value._type
            
            -- parse remaining elements
            while true do
                local separator = tokens.peekToken() -- Peek to check for trailing comma scenario
                if separator == "]" then
                    tokens.nextToken() -- Consume ']'
                    break -- End of list
                elseif separator == "," or separator == ";" then
                    tokens.nextToken() -- Consume the separator
                    -- Now, check if this was a trailing separator
                    if tokens.peekToken() == "]" then
                        tokens.nextToken() -- Consume ']'
                        break
                    end
                    -- If not a trailing separator, parse the next value
                    local nextValue = parseValue()
                    if nextValue._type ~= itemType then
                        snbtError("Inconsistent list type", tokens.getPos(), input)
                    end
                    table.insert(values, nextValue)
                else
                    snbtError("Expected ',' or ';' or ']' after list element", tokens.getPos(), input)
                end
            end
            
            return {
                _type = module.TAGS.LIST,
                _itemID = itemType,
                value = values
            }
        end
    end
    
    -- parsing primitive value from token
    local function parseValueFromToken(token)
        if token == "{" then
            return parseCompound()
        elseif token == "[" then
            return parseList()
        elseif token == "true" then
            return {
                _type = module.TAGS.BYTE,
                value = 1
            }
        elseif token == "false" then
            return {
                _type = module.TAGS.BYTE,
                value = 0
            }
        elseif type(token) == "string" then
            local num_val
            local suffix = token:sub(-1) -- last character
            local is_numeric = false
            local nbt_type
            
            if suffix:lower() == "b" then
                num_val = tonumber(token:sub(1, -2))
                nbt_type = module.TAGS.BYTE
                is_numeric = true
            elseif suffix:lower() == "s" then
                num_val = tonumber(token:sub(1, -2))
                nbt_type = module.TAGS.SHORT
                is_numeric = true
            elseif suffix:lower() == "l" then
                num_val = tonumber(token:sub(1, -2))
                nbt_type = module.TAGS.LONG
                is_numeric = true
            elseif suffix:lower() == "f" then
                num_val = tonumber(token:sub(1, -2))
                nbt_type = module.TAGS.FLOAT
                is_numeric = true
            elseif suffix:lower() == "d" then
                num_val = tonumber(token:sub(1, -2))
                nbt_type = module.TAGS.DOUBLE
                is_numeric = true
            end
        
            if is_numeric and num_val ~= nil then
                return { _type = nbt_type, value = num_val }
            end
        
            -- if no suffix or suffix not recognized as numeric
            -- check for default numeric types (int/double)
            local is_int_format = token:match("^[%-%+]?%d+$")
            local is_double_format = token:match("^[%-%+]?%d+%.%d*$")
        
            if is_int_format then
                num_val = tonumber(token)
                if num_val ~= nil then -- check for successful conversion
                    return { _type = module.TAGS.INT, value = num_val }
                end
            elseif is_double_format then
                num_val = tonumber(token)
                if num_val ~= nil then
                    return { _type = module.TAGS.DOUBLE, value = num_val }
                end
            end
            
            return { _type = module.TAGS.STRING, value = token }
        else
            snbtError("Unexpected token: " .. tostring(token), tokens.getPos(), input)
        end
    end
    
    parseValue = function(providedToken)
        local token = providedToken or tokens.nextToken()
        
        if token == nil then
            snbtError("Unexpected end of input", tokens.getPos(), input)
        end
        
        return parseValueFromToken(token)
    end
    
    local rootTag = parseValue()

    -- Ensure no trailing tokens after parsing the root
    if tokens.peekToken() ~= nil then
        snbtError("Trailing data after root tag", tokens.getPos(), input)
    end
    
    -- In SNBT the root tag often does not have a name
    return {_type = module.TAGS.STRING, value = ''}, rootTag
end

return module