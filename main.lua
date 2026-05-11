local Creature = require "creature"
local Util = require "util"

local choose = Util.choose
local hsv = Util.hsv
local rand = Util.rand
local round = Util.round
local setColor = Util.setColor

local Food = {}
Food.__index = Food

local MurderAnim = {}
MurderAnim.__index = MurderAnim

local function createThing(thing)
    table.insert(ThingList, thing)
    return thing
end

function love.load()
    love.window.setMode(640 * 2, 640 * 2 * 9 / 16, {
        vsync = false,
        fullscreen = false,
        resizable = true,
    })
    Reset()
end

function Reset()
    Camera = {x = 0, y = 0, scale = 1}
    WorldSize = 2048 * 2
    WorldCanvas = love.graphics.newCanvas(WorldSize, WorldSize)
    ThingList = {}
    ThingOctree = {}
    OctreeSize = 32
    for i = 1, OctreeSize do
        ThingOctree[i] = {}
        for j = 1, OctreeSize do
            ThingOctree[i][j] = {}
        end
    end
    FoodCount = 256 * 4
    CreatureCount = 128 * 3
    SelectedThing = nil
    StartDragX = -1
    StartDragY = -1
    StartCameraX = Camera.x
    StartCameraY = Camera.y
    RandomSpawns = true
    Paused = false
    Follow = false
    Visual = true
    FoodSpawns = 0
    DeathSpawns = 0
    Year = 1
    YearTimer = 0

    local saltx = love.math.random() * 10000 * choose({1, -1})
    local salty = love.math.random() * 10000 * choose({1, -1})
    local foodMap = {}
    local gridSize = 12
    local freq = 60
    local interval = 7
    for i = 1, WorldSize / gridSize do
        for j = 1, WorldSize / gridSize do
            local isFoodCell = i % interval == 0 and j % interval == 0
            local noise = love.math.noise(i / freq + saltx, j / freq + salty)
            if noise + love.math.random() * 0.4 > 1 and isFoodCell then
                local x = (
                    i * gridSize
                    + love.math.random() * gridSize * interval * 0.5 * choose({1, -1})
                    - gridSize / 2
                )
                x = math.max(math.min(x, WorldSize), 0)
                local y = (
                    j * gridSize
                    + love.math.random() * gridSize * interval * 0.5 * choose({1, -1})
                    - gridSize / 2
                )
                y = math.max(math.min(y, WorldSize), 0)
                foodMap[#foodMap + 1] = {x, y}
            end
        end
    end

    for i = 1, CreatureCount do
        createThing(Creature.new(love.math.random() * WorldSize, love.math.random() * WorldSize))
    end

    for i = 1, math.min(FoodCount, #foodMap) do
        local index = rand(1, #foodMap)
        local cx, cy = foodMap[index][1], foodMap[index][2]
        table.remove(foodMap, index)
        createThing(Food.new(cx, cy))
    end

    GridCanvas = love.graphics.newCanvas(WorldSize, WorldSize)
    love.graphics.setCanvas(GridCanvas)
    setColor(15, 15, 15)
    local octreeGrid = WorldSize / OctreeSize
    for i = 1, OctreeSize do
        for j = 1, OctreeSize do
                love.graphics.rectangle(
                    "line",
                    (i - 1) * octreeGrid,
                    (j - 1) * octreeGrid,
                    octreeGrid,
                    octreeGrid
                )
        end
    end
    love.graphics.setCanvas()
end

function Food.new(xg, yg)
    return setmetatable({
        x = xg,
        y = yg,
        dead = false,
        name = "food",
        growthTimer = 0,
        trample = 0,
    }, Food)
end

function Food:update(dt)
    if self.dead then
        self.growthTimer = self.growthTimer + 1

        if self.growthTimer > 60 * 5 + self.trample then
            self.growthTimer = 0
            self.dead = false
            --self.trample = self.trample + 60 * 1.5
        end
    --else
        --self.trample = math.max(self.trample - (1 / 5), 0)
    end
    return true
end

function Food:draw()
    if self.dead then
        local c = 128
        setColor(c, c, c)
    else
        setColor(255, 255, 0)
    end
    love.graphics.circle("fill", self.x, self.y, 3, 3)

    --if math.dist(love.mouse.getX(), love.mouse.getY(), self.x, self.y) < 8 then
        --setColor(255, 0, 0)
        --love.graphics.print(math.floor((self.trample / 60) * 10 + 0.5) / 10, self.x, self.y - 16)
    --end
end

function MurderAnim.new(xg, yg, color)
    return setmetatable({
        x = xg,
        y = yg,
        direction = love.math.random() * 2 * math.pi,
        timer = 0,
        color = color,
        speed = love.math.random() * 1.5 + 0.5,
    }, MurderAnim)
end

function MurderAnim:update(dt)
    self.x = self.x + math.cos(self.direction) * self.speed
    self.y = self.y + math.sin(self.direction) * self.speed
    self.timer = self.timer + 1

    return self.timer < 40
end

function MurderAnim:draw()
    local r, g, b = hsv(self.color[1], self.color[2], 255)
    setColor(r, g, b)
    local length = 10
    love.graphics.line(
        self.x,
        self.y,
        self.x + math.cos(self.direction) * length,
        self.y + math.sin(self.direction) * length
    )
    setColor(255, 255, 255)
end

Creature.setWorldHooks({
    createThing = createThing,
    newMurderAnim = MurderAnim.new,
})

function love.update(dt)
    if love.mouse.isDown(2) then
        Camera.x = -1 * (love.mouse.getX() - StartDragX) + StartCameraX
        Camera.y = -1 * (love.mouse.getY() - StartDragY) + StartCameraY
    end

    local camSpeed = 150 * dt
    if love.keyboard.isDown("lshift") then
        camSpeed = 500 * dt
    end
    if love.keyboard.isDown("d") then
        Camera.x = Camera.x + camSpeed
    end
    if love.keyboard.isDown("a") then
        Camera.x = Camera.x - camSpeed
    end
    if love.keyboard.isDown("w") then
        Camera.y = Camera.y - camSpeed
    end
    if love.keyboard.isDown("s") then
        Camera.y = Camera.y + camSpeed
    end

    if Paused then
        return
    end

    YearTimer = YearTimer + 1
    if YearTimer > 60 * 15 then
        Year = Year + 1
        YearTimer = 0
        FoodSpawns = 0
        DeathSpawns = 0
    end

    local nextOctree = {}
    for i = 1, OctreeSize do
        nextOctree[i] = {}
        for j = 1, OctreeSize do
            nextOctree[i][j] = {}
        end
    end
    local octreeGrid = WorldSize / OctreeSize
    local fittestCreature = nil
    local fittestCount = 0
    local creatureCount = 0
    local i = 1
    while i <= #ThingList do
        local thing = ThingList[i]
        if thing:update(dt) then
            i = i + 1
            if thing.name == "creature" then
                creatureCount = creatureCount + 1
                if thing.offspringCount > fittestCount then
                    fittestCount = thing.offspringCount
                    fittestCreature = thing
                end
            end

            local ox, oy = math.floor(thing.x / octreeGrid) + 1, math.floor(thing.y / octreeGrid) + 1
            ox = math.max(math.min(ox, OctreeSize), 1)
            oy = math.max(math.min(oy, OctreeSize), 1)
            if nextOctree ~= nil and thing ~= nil then
                table.insert(nextOctree[ox][oy], thing)
            end
        else
            table.remove(ThingList, i)
        end
    end
    ThingOctree = nextOctree

    if creatureCount < CreatureCount and RandomSpawns then
        createThing(Creature.new(love.math.random() * WorldSize, love.math.random() * WorldSize))
    end

    if Follow and fittestCreature ~= nil then
        SelectedThing = fittestCreature
    end
end

function love.draw()
    if Visual then
        --setColor(0, 0.6, 0.6)
        --love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.push()
        love.graphics.scale(Camera.scale)
        love.graphics.translate(-Camera.x, -Camera.y)

        setColor(255, 255, 255)
        love.graphics.draw(GridCanvas, 0, 0)
        love.graphics.rectangle("line", 0, 0, WorldSize, WorldSize)
        for i = 1, #ThingList do
            setColor(255, 255, 255)
            ThingList[i]:draw()
        end
        setColor(255, 255, 255)

        love.graphics.pop()

        if SelectedThing then
            SelectedThing:drawUi()
        end
    end
    local totalSpawns = FoodSpawns + DeathSpawns
    local fper = "0"
    local dper = "0"
    if totalSpawns > 0 then
        fper = "" .. round((FoodSpawns / totalSpawns) * 100)
        dper = "" .. round((DeathSpawns / totalSpawns) * 100)
    end
    love.graphics.print("F/D: " .. fper .. " - " .. dper, 8, love.graphics.getHeight() - 16 - 32)
    love.graphics.print("#ThingList: " .. #ThingList, 8, love.graphics.getHeight() - 32 - 32)
    love.graphics.print("fps: " .. love.timer.getFPS(), 8, love.graphics.getHeight() - 48 - 32)
    love.graphics.print("Year: " .. Year, 8, love.graphics.getHeight() - 64 - 32)
end

function love.keypressed(k)
    if k == "escape" then
        love.event.push("quit")
    end

    if k == "space" then
        Paused = not Paused
    end
    if k == "e" then
        RandomSpawns = not RandomSpawns
    end
    if k == "f" then
        Follow = not Follow
    end
    if k == "v" then
        Visual = not Visual
    end

    if k == "r" then
        Reset()
    end
end

function love.mousepressed(x, y, b)
    if b == 2 then
        StartDragX = x
        StartDragY = y
        StartCameraX = Camera.x
        StartCameraY = Camera.y
    end
end
