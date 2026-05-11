local Brain = require "brain"
local Util = require "util"

local angle = Util.angle
local choose = Util.choose
local deepcopy = Util.deepcopy
local dist = Util.dist
local hsv = Util.hsv
local name = Util.name
local rand = Util.rand
local setColor = Util.setColor

local Creature = {}
Creature.__index = Creature

local createThing
local newMurderAnim

function Creature.setWorldHooks(hooks)
    createThing = hooks.createThing
    newMurderAnim = hooks.newMurderAnim
end

function Creature.new(xg, yg, brain, lineage, generation, radius, noseLength, mutations)
    local self = setmetatable({
        brain = brain,
        lineage = lineage,
        generation = generation,
        x = xg,
        y = yg,
        xSpeed = 0,
        ySpeed = 0,
        direction = love.math.random() * 2 * math.pi,
        speed = 0,
        radius = radius,
        noseLength = noseLength,
        mutations = mutations,
        noseOut = 1,
        noseOutCooldown = 0,
        brainOut = {0, 0, 0, 0},
        brainOutRaw = {0, 0, 0, 0},
        lifeTimer = 0,
        lifeTimerMax = 600 * 2,
        name = "creature",
        offspringCount = 0,
        lastChild = nil,
        murdered = false,
        iFrames = 60,
        visionRange = 128 * 2,
        map = {{xg, yg}},
        mapTimer = 0,
        shielding = false,
        shieldingCooldown = 0,
    }, Creature)

    self.lastFoodDist = self.visionRange
    self.lastFamilyDist = self.visionRange
    self.lastThingDist = self.visionRange
    self.lastDeadFoodDist = self.visionRange
    self.lastMapDist = WorldSize

    if self.mutations == nil then
        self.mutations = 0
    end
    if self.radius == nil then
        self.radius = 8
    end
    if self.noseLength == nil then
        self.noseLength = 8
    end
    if self.lineage == nil then
        self.lineage = {
            name = "",
            hue = math.floor(love.math.random() * 255 + 0.5),
            sat = math.floor(love.math.random() * 128 + 0.5) + 128,
            lastName = name(),
            middleName = name(),
            firstName = name(),
        }
    end
    if self.generation == nil then
        self.generation = 1
    end
    if self.brain == nil then
        self.brain = Brain.new()
        for i = 1, 30 do
            self:mutate()
        end
    end

    self.lineage.unique = math.floor(love.math.random() * 100000000)

    return self
end

function Creature:mutate()
    self.brain:mutate()
    self.lineage.hue = (self.lineage.hue + love.math.random() * 6 * choose({1, -1})) % 255
    self.lineage.sat = (self.lineage.sat + love.math.random() * 6 * choose({1, -1})) % 127 + 128
    self.lineage.firstName = name()
    self.mutations = self.mutations + 1

    if love.math.random() > 0.95 then
        self.radius = self.radius + love.math.random() * 3
        self.radius = math.min(math.max(self.radius, 3), 16)
    end
end

function Creature:update(dt)
    if self.iFrames > 0 then self.iFrames = self.iFrames - 1 end
    self.lifeTimer = self.lifeTimer + 1

    if self.murdered then
        if Visual then
            for i = 1, 16 do
                createThing(newMurderAnim(self.x, self.y, {self.lineage.hue, self.lineage.sat}))
            end
        end

        return false
    end

    self.mapTimer = self.mapTimer + 1
    if self.mapTimer > 30 and SelectedThing == self then
        self.lastMapDist = dist(self.x, self.y, self.map[#self.map][1], self.map[#self.map][2])
        self.map[#self.map + 1] = {self.x, self.y}
        self.mapTimer = 0
    end

    local friction = 0.95
    self.xSpeed = self.xSpeed * friction
    self.ySpeed = self.ySpeed * friction

    local maxTurnSpeed = 0.2

    self.speed = self.speed + self.brainOut[2]

    local directionDelta = self.brainOut[1]
    directionDelta = math.max(math.min(directionDelta, maxTurnSpeed), -1 * maxTurnSpeed)

    if self.shielding then
        directionDelta = 0
    end

    if math.abs(directionDelta) > maxTurnSpeed / 2 then
        self.noseOut = 0
        self.noseOutCooldown = 60
    else
        self.noseOut = 1
    end
    self.noseLength = math.floor(16 - self.radius + 0.5)

    self.direction = self.direction + directionDelta
    self.direction = self.direction % (math.pi * 2)

    self.speed = math.max(math.min(self.speed, 1), -1)
    self.xSpeed = self.xSpeed + math.cos(self.direction) * self.speed * 0.05
    self.ySpeed = self.ySpeed + math.sin(self.direction) * self.speed * 0.05

    if self.x + self.xSpeed < 0 or self.x + self.xSpeed > WorldSize then
        self.xSpeed = self.xSpeed * -1
    end
    if self.y + self.ySpeed < 0 or self.y + self.ySpeed > WorldSize then
        self.ySpeed = self.ySpeed * -1
    end

    self.x = self.x + self.xSpeed
    self.y = self.y + self.ySpeed

    local foodDist = self.visionRange
    local foodDirection = self.direction
    local foodSourceDist = self.visionRange
    local deadFoodDist = self.visionRange
    local deadFoodDirection = self.direction
    local thingDist = self.visionRange
    local thingDirection = self.direction
    local thingPointDirection = self.direction
    local familyDist = self.visionRange * 3
    local familyDirection = self.direction
    local thingShielding = 0
    local thingCount = 0
    local thingNoseOut = 0

    local function interactions(xx, yy)
        local octreeGrid = WorldSize / OctreeSize
        local cx = math.floor(self.x / octreeGrid) + 1 + xx
        local cy = math.floor(self.y / octreeGrid) + 1 + yy
        if cx <= 0 or cy <= 0 or cx > #ThingOctree or cy > #ThingOctree then return end
        local myOctree = ThingOctree[cx][cy]
        if myOctree == nil then return end

        for i = 1, #myOctree do
            local thing = myOctree[i]
            local thingDistToSelf = dist(thing.x, thing.y, self.x, self.y)

            if thing.name == "food" then
                local food = thing

                if thingDistToSelf < foodDist then
                    if not food.dead then
                        foodDist = thingDistToSelf
                        foodDirection = angle(self.x, self.y, food.x, food.y)
                    else
                        deadFoodDist = thingDistToSelf
                        deadFoodDirection = angle(self.x, self.y, food.x, food.y)
                    end
                end

                if thingDistToSelf < foodSourceDist then
                    foodSourceDist = thingDistToSelf
                end

                if thingDistToSelf <= self.radius + 1 then
                    food.growthTimer = 0
                    if not food.dead and #ThingList < 1024 then
                        food.dead = true
                        self:reproduce()
                        FoodSpawns = FoodSpawns + 1
                    end
                end
            end

            if thing.name == "creature" and thing ~= self then
                local isFamily = self.lineage.firstName == thing.lineage.firstName or self.lineage.middleName == thing.lineage.middleName
                local collisionAngle = angle(self.x + self.xSpeed, self.y + self.ySpeed, thing.x, thing.y)
                local noseX = self.x + math.cos(self.direction) * (self.radius + self.noseLength) * self.noseOut
                local noseY = self.y + math.sin(self.direction) * (self.radius + self.noseLength) * self.noseOut
                local isPoked = dist(noseX, noseY, thing.x, thing.y) <= thing.radius

                if thingDistToSelf < thingDist and not isFamily then
                    thingCount = thingCount + 1
                    thingDist = thingDistToSelf
                    thingDirection = angle(self.x, self.y, thing.x, thing.y)
                    thingPointDirection = thing.direction
                    thingNoseOut = thing.noseOut
                    if thing.shielding then
                        thingShielding = 1
                    else
                        thingShielding = 0
                    end
                end

                if thingDistToSelf < familyDist and isFamily then
                    familyDist = thingDistToSelf
                    familyDirection = angle(self.x, self.y, thing.x, thing.y)
                end

                if isPoked
                    and self.noseOut > 0
                    and not thing.shielding
                    and not self.shielding
                    and not isFamily then
                    local winner = self
                    local loser = thing
                    local can = true

                    if can and not loser.murdered and loser.iFrames <= 0 then
                        loser.murdered = true
                        winner:reproduce()
                        DeathSpawns = DeathSpawns + 1
                    end
                end

                if thingDistToSelf <= self.radius + thing.radius then
                    local bumpSpeed = 6 * 1.6 / 8
                    self.xSpeed = math.cos(collisionAngle) * -bumpSpeed
                    self.ySpeed = math.sin(collisionAngle) * -bumpSpeed
                    thing.xSpeed = math.cos(collisionAngle) * bumpSpeed
                    thing.ySpeed = math.sin(collisionAngle) * bumpSpeed
                end
            end
        end
    end

    local checkRange = 3
    for xx = -checkRange, checkRange do
        for yy = -checkRange, checkRange do
            interactions(xx, yy)
        end
    end

    local foodDirectionDiff = math.abs(self.direction % (math.pi * 2) - foodDirection % (math.pi * 2))
    local thingDirectionDiff = math.abs(self.direction % (math.pi * 2) - thingDirection % (math.pi * 2))
    local familyDirectionDiff = math.abs(self.direction % (math.pi * 2) - familyDirection % (math.pi * 2))
    local foodDistDelta = foodDist - self.lastFoodDist
    local thingDistDelta = thingDist - self.lastThingDist

    self.brainOut = self.brain:cycle({
        {foodDistDelta},
        {thingShielding},
        {thingDirectionDiff},
        {thingDistDelta},
    })
    self.brainOutRaw = deepcopy(self.brainOut)
    for i = 1, #self.brainOut do
        self.brainOut[i] = self.brainOut[i] * 2 - 1
    end

    self.lastThingDist = thingDist
    self.lastFamilyDist = familyDist
    self.lastFoodDist = foodDist
    self.lastDeadFoodDist = deadFoodDist

    if love.mouse.isDown(1) then
        local mouseX = love.mouse.getX() / Camera.scale + Camera.x
        local mouseY = love.mouse.getY() / Camera.scale + Camera.y
        local mouseDist = dist(mouseX, mouseY, self.x, self.y)
        if mouseDist < self.radius * 1.5 then
            SelectedThing = self
        end
    end

    if SelectedThing == self and Follow then
        Camera.x = self.x - love.graphics.getWidth() / 2
        Camera.y = self.y - love.graphics.getHeight() / 2
    end

    local ret = self.lifeTimer < self.lifeTimerMax
    if not ret and SelectedThing == self then
        SelectedThing = self.lastChild
    end

    return ret
end

function Creature:reproduce()
    local child = createThing(Creature.new(
        self.x,
        self.y,
        deepcopy(self.brain),
        deepcopy(self.lineage),
        self.generation + 1,
        self.radius,
        self.noseLength,
        self.mutations
    ))
    for j = 1, choose({0, 0, 0, 0, 0, 1, 1, rand(0, 10)}) do
        child:mutate()
    end
    self.lastChild = child
    self.iFrames = 60
    self.offspringCount = self.offspringCount + 1
    if child.mutations > 15 then
        child.generation = 0
        child.mutations = 0
        child.lineage.middleName = self.lineage.firstName
    end
end

function Creature:draw()
    local r, g, b = hsv(self.lineage.hue, self.lineage.sat, 255)
    setColor(r, g, b)
    love.graphics.circle("fill", self.x, self.y, self.radius, 16)
    setColor(255, 255, 255)
    if self.noseOut == 0 then
        setColor(0, 0, 0)
    end
    love.graphics.line(
        self.x,
        self.y,
        self.x + math.cos(self.direction) * (self.radius + self.noseLength * self.noseOut),
        self.y + math.sin(self.direction) * (self.radius + self.noseLength * self.noseOut)
    )

    if self.shielding then
        setColor(255, 255, 255)
        love.graphics.circle("line", self.x, self.y, self.radius + 4, 8)
    end

    if SelectedThing == self then
        setColor(255, 255, 0)
        love.graphics.rectangle("line", self.x - self.radius, self.y - self.radius, self.radius * 2, self.radius * 2)

        love.graphics.circle("line", self.x, self.y, self.visionRange, 64)
        local drawMap = {}
        for i = 1, #self.map do
            drawMap[#drawMap + 1] = self.map[i][1]
            drawMap[#drawMap + 1] = self.map[i][2]
        end

        if drawMap ~= nil and #drawMap % 2 == 0 and #drawMap >= 4 then
            love.graphics.line(drawMap)
        end
    end
end

function Creature:drawUi()
    self.brain:draw()

    love.graphics.print("age: " .. math.floor((self.lifeTimer / self.lifeTimerMax) * 100) .. "%", 8, 250)
    love.graphics.print("offspringCount: " .. self.offspringCount, 8, 250 + 16)
    love.graphics.print("family: " .. self.lineage.firstName .. " " .. self.lineage.middleName .. " " .. self.lineage.lastName, 8, 250 + 32)
    love.graphics.print("generation: " .. self.generation, 8, 250 + 48)
    love.graphics.print("radius: " .. math.floor(self.radius) .. " noseLength: " .. math.floor(self.noseLength), 8, 250 + 64)
    love.graphics.print("mutations: " .. math.floor(self.mutations), 8, 250 + 64 + 16)
end

return Creature
