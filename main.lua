require "brain"
require "creature"

function love.load()
	love.window.setMode(640*2,640*2*9/16, {vsync=false, fullscreen=false, resizable=true})
	Reset()
end

function Reset()
	Camera = {x=0,y=0}
	WorldSize = 2048*2
    WorldCanvas = love.graphics.newCanvas(WorldSize,WorldSize)
	ThingList = {}
	ThingOctree = {}
	OctreeSize = 32
	for i=1, OctreeSize do
		ThingOctree[i] = {}
		for j=1, OctreeSize do
			ThingOctree[i][j] = {}
		end
	end
	FoodCount = 256*4
	CreatureCount = 128*3
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

	local saltx,salty = love.math.random()*10000*choose{1,-1},love.math.random()*10000*choose{1,-1}
	local foodMap = {}
	local gridSize = 12
	local freq = 60
	local interval = 7
	for i=1, WorldSize/gridSize do
		for j=1, WorldSize/gridSize do
			if love.math.noise(i/freq +saltx,j/freq +salty) + love.math.random()*0.4 > 1 and (i%interval == 0 and j%interval == 0) then
				local x = i*gridSize +love.math.random()*gridSize*interval*0.5*choose{1,-1} -gridSize/2
				x = math.max(math.min(x,WorldSize), 0)
				local y = j*gridSize +love.math.random()*gridSize*interval*0.5*choose{1,-1} -gridSize/2
				y = math.max(math.min(y,WorldSize), 0)
				foodMap[#foodMap +1] = {x,y}
			end
		end
	end

	for i=1, CreatureCount do
		CreateThing(NewCreature(love.math.random()*WorldSize,love.math.random()*WorldSize))
	end

	for i=1, math.min(FoodCount, #foodMap) do
		local index = rand(1, #foodMap)
		local cx,cy = foodMap[index][1], foodMap[index][2]
		table.remove(foodMap, index)
		CreateThing(NewFood(cx,cy))
	end

	GridCanvas = love.graphics.newCanvas(WorldSize,WorldSize)
	love.graphics.setCanvas(GridCanvas)
		SetColor(15,15,15)
		local octreeGrid = WorldSize/OctreeSize
		for i=1, OctreeSize do
			for j=1, OctreeSize do
				love.graphics.rectangle("line", (i-1)*octreeGrid-Camera.x,(j-1)*octreeGrid-Camera.y, octreeGrid,octreeGrid)
			end
		end
	love.graphics.setCanvas()
end

function CreateThing(thing)
	table.insert(ThingList, thing)
	return thing
end

function NewFood(xg,yg)
	local c = {}
	c.x = xg
	c.y = yg
	c.dead = false
	c.name = "food"
	c.growthTimer = 0
	c.trample = 0

	c.update = function (self, dt)
		if self.dead then
			self.growthTimer = self.growthTimer + 1

			if self.growthTimer > 60*5 + self.trample then
				self.growthTimer = 0
				self.dead = false
				self.trample = self.trample + 60*1.5
			end
		else
			self.trample = math.max(self.trample-(1/(5)), 0)
		end
		return true
	end

	c.draw = function (self)
		if self.dead then
			local c = 128
			SetColor(c,c,c)
		else
			SetColor(255,255,0)
		end
		love.graphics.circle("fill", self.x-Camera.x,self.y-Camera.y, 3,3)

		local dx,dy = self.x-Camera.x,self.y-Camera.y

		if math.dist(love.mouse.getX(),love.mouse.getY(),dx,dy) < 8 then
			SetColor(255,0,0)
			love.graphics.print(math.floor((self.trample/60)*10 +0.5)/10,dx,dy-16)
		end
	end

	return c
end

function NewMurderAnim(xg,yg, color)
	local c = {}
	c.x = xg
	c.y = yg
	c.direction = love.math.random()*2*math.pi
	c.timer = 0
	c.color = color
	c.speed = love.math.random()*1.5 +0.5

	c.update = function (self, dt)
		self.x = self.x + math.cos(self.direction)*self.speed
		self.y = self.y + math.sin(self.direction)*self.speed
		self.timer = self.timer + 1

		return self.timer < 40
	end

	c.draw = function (self)
		local r,g,b = HSV(self.color[1],self.color[2],255)
		SetColor(r,g,b)
		local length = 10
		love.graphics.line(self.x -Camera.x,self.y -Camera.y, self.x+math.cos(self.direction)*length -Camera.x,self.y+math.sin(self.direction)*length -Camera.y)
		SetColor(255,255,255)
	end

	return c
end

function Name()
	return Syllable()..Syllable()
end

function Syllable()
	local cons = {"b","c","d","f","g","h","j","k","l","m","n","p","q","r","s","t","v","w","x","y","ss","ch","th","ck","gh","st"}
	local vows = {"a","e","i","o","u","y","ie","ee","oo","ei","au"}

	return choose(cons)..choose(vows)
end

function love.update(dt)
	if love.mouse.isDown(2) then
		Camera.x = -1*(love.mouse.getX()-StartDragX) + StartCameraX
		Camera.y = -1*(love.mouse.getY()-StartDragY) + StartCameraY
	end

    local camSpeed = 150*dt
    if love.keyboard.isDown("lshift") then
        camSpeed = 500*dt
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
	if YearTimer > 60*15 then
		Year = Year + 1
		YearTimer = 0
		FoodSpawns = 0
		DeathSpawns = 0
	end

	local nextOctree = {}
	for i=1, OctreeSize do
		nextOctree[i] = {}
		for j=1, OctreeSize do
			nextOctree[i][j] = {}
		end
	end
	local octreeGrid = WorldSize/OctreeSize
	local fittestCreature = nil
	local fittestCount = 0
	local creatureCount = 0
	local i=1
	while i <= #ThingList do
		local thing = ThingList[i]
		if thing:update(dt) then
			i=i+1
			if thing.name == "creature" then
				creatureCount = creatureCount + 1
				if thing.offspringCount > fittestCount then
					fittestCount = thing.offspringCount
					fittestCreature = thing
				end
			end

			local ox,oy = math.floor(thing.x/octreeGrid)+1, math.floor(thing.y/octreeGrid)+1
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
		CreateThing(NewCreature(love.math.random()*WorldSize, love.math.random()*WorldSize))
	end

	if Follow and fittestCreature ~= nil then
		SelectedThing = fittestCreature
	end
end

function love.draw()
	if Visual then
		love.graphics.draw(GridCanvas, -Camera.x,-Camera.y)
		SetColor(255,255,255)
		love.graphics.rectangle("line", 0-Camera.x,0-Camera.y, WorldSize,WorldSize)
		for i=1, #ThingList do
			SetColor(255,255,255)
			ThingList[i]:draw()
		end
		SetColor(255,255,255)
	end
	local totalSpawns = FoodSpawns + DeathSpawns
	local fper = ""..math.round((FoodSpawns/totalSpawns)*100)
	local dper = ""..math.round((DeathSpawns/totalSpawns)*100)
	love.graphics.print("F/D: "..fper.." - "..dper,8,love.graphics.getHeight()-16-32)
	love.graphics.print("#ThingList: "..#ThingList,8,love.graphics.getHeight()-32-32)
	love.graphics.print("fps: "..love.timer.getFPS(),8,love.graphics.getHeight()-48-32)
	love.graphics.print("Year: "..Year,8,love.graphics.getHeight()-64-32)
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

function love.mousepressed(x,y,b)
	if b == 2 then
		StartDragX = x
		StartDragY = y
		StartCameraX = Camera.x
		StartCameraY = Camera.y
	end
end

function choose(arr)
    return arr[math.floor(love.math.random()*#arr)+1]
end
function rand(min,max, interval)
    local interval = interval or 1
    local c = {}
    local index = 1
    for i=min, max, interval do
        c[index] = i
        index = index + 1
    end

    return choose(c)
end
function GetSign(n)
    if n > 0 then return 1 end
    if n < 0 then return -1 end
    return 0
end
function lerp(a,b,t) return (1-t)*a + t*b end
function math.round(n) return math.floor(n+0.5) end
function math.angle(x1,y1, x2,y2) return math.atan2(y2-y1, x2-x1) end
function math.dist(x1,y1, x2,y2) return ((x2-x1)^2+(y2-y1)^2)^0.5 end
function HSV(h, s, v)
    if s <= 0 then return v,v,v end
    h, s, v = h/256*6, s/255, v/255
    local c = v*s
    local x = (1-math.abs((h%2)-1))*c
    local m,r,g,b = (v-c), 0,0,0
    if h < 1     then r,g,b = c,x,0
    elseif h < 2 then r,g,b = x,c,0
    elseif h < 3 then r,g,b = 0,c,x
    elseif h < 4 then r,g,b = 0,x,c
    elseif h < 5 then r,g,b = x,0,c
    else              r,g,b = c,0,x
    end return (r+m)*255,(g+m)*255,(b+m)*255
end
function deepcopy(orig)
    local orig_type = type(orig)
    local copy
    if orig_type == 'table' then
        copy = {}
        for orig_key, orig_value in next, orig, nil do
            copy[deepcopy(orig_key)] = deepcopy(orig_value)
        end
        setmetatable(copy, deepcopy(getmetatable(orig)))
    else -- number, string, boolean, etc
        copy = orig
    end
    return copy
end

function SetColor(r,g,b,a)
    if a == nil then
        a = 255
    end
    love.graphics.setColor(r/255,g/255,b/255,a/255)
end
