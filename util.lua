local Util = {}

function Util.choose(arr)
    return arr[math.floor(love.math.random() * #arr) + 1]
end

function Util.rand(min, max, interval)
    interval = interval or 1
    local choices = {}
    local index = 1
    for i = min, max, interval do
        choices[index] = i
        index = index + 1
    end

    return Util.choose(choices)
end

function Util.syllable()
    local cons = {"b", "c", "d", "f", "g", "h", "j", "k", "l", "m", "n", "p", "q", "r", "s", "t", "v", "w", "x", "y", "ss", "ch", "th", "ck", "gh", "st"}
    local vows = {"a", "e", "i", "o", "u", "y", "ie", "ee", "oo", "ei", "au"}

    return Util.choose(cons) .. Util.choose(vows)
end

function Util.name()
    return Util.syllable() .. Util.syllable()
end

function Util.round(n)
    return math.floor(n + 0.5)
end

function Util.angle(x1, y1, x2, y2)
    return math.atan2(y2 - y1, x2 - x1)
end

function Util.dist(x1, y1, x2, y2)
    return ((x2 - x1) ^ 2 + (y2 - y1) ^ 2) ^ 0.5
end

function Util.hsv(h, s, v)
    if s <= 0 then return v, v, v end
    h, s, v = h / 256 * 6, s / 255, v / 255
    local c = v * s
    local x = (1 - math.abs((h % 2) - 1)) * c
    local m, r, g, b = (v - c), 0, 0, 0
    if h < 1 then r, g, b = c, x, 0
    elseif h < 2 then r, g, b = x, c, 0
    elseif h < 3 then r, g, b = 0, c, x
    elseif h < 4 then r, g, b = 0, x, c
    elseif h < 5 then r, g, b = x, 0, c
    else r, g, b = c, 0, x end
    return (r + m) * 255, (g + m) * 255, (b + m) * 255
end

function Util.deepcopy(orig, copies)
    copies = copies or {}
    local origType = type(orig)
    local copy
    if origType == "table" then
        if copies[orig] then
            return copies[orig]
        end
        copy = {}
        copies[orig] = copy
        for origKey, origValue in next, orig, nil do
            copy[Util.deepcopy(origKey, copies)] = Util.deepcopy(origValue, copies)
        end
        setmetatable(copy, getmetatable(orig))
    else
        copy = orig
    end
    return copy
end

function Util.setColor(r, g, b, a)
    a = a or 255
    love.graphics.setColor(r / 255, g / 255, b / 255, a / 255)
end

return Util
