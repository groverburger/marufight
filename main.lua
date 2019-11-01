--local inspect = require "inspect"

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

function NewCreature(xg,yg, braing,lineage,generation, radius,noselength, mutations)
	local c = {}
	c.brain = braing
	c.lineage = lineage
	c.generation = generation
	c.x = xg
	c.y = yg
	c.xSpeed = 0
	c.ySpeed = 0
	c.direction = love.math.random()*2*math.pi
	c.speed = 0
	c.radius = radius
	c.noseLength = noseLength
	c.mutations = mutations
	c.noseOut = 1
	c.noseOutCooldown = 0
	c.brainOut = {0,0,0,0}
	c.brainOutRaw = {0,0,0,0}
	c.lifeTimer = 0
	c.lifeTimerMax = 600*2

	c.name = "creature"
	c.offspringCount = 0
	c.lastChild = nil
	c.murdered = false
	c.iFrames = 60
	c.visionRange = 128*1.5

	c.lastFoodDist = c.visionRange
	c.lastFamilyDist = c.visionRange
	c.lastThingDist = c.visionRange
	c.lastDeadFoodDist = c.visionRange

	c.map = {{xg,yg}}
	c.mapTimer = 0
	c.lastMapDist = WorldSize
	c.shielding = false
	c.shieldingCooldown = 0

	c.mutate = function (self)
		self.brain:mutate()
		self.lineage.hue = (self.lineage.hue + love.math.random()*6*choose{1,-1})%255
		self.lineage.sat = (self.lineage.sat + love.math.random()*6*choose{1,-1})%127 + 128
		self.lineage.firstName = Name()
		self.mutations = self.mutations + 1

		if love.math.random()>0.95 then
			self.radius = self.radius + love.math.random()*3
			self.radius = math.min(math.max(self.radius, 3), 16)
		end

	end

	c.update = function (self, dt)
		if self.iFrames > 0 then self.iFrames = self.iFrames - 1 end
		self.lifeTimer = self.lifeTimer + 1

		if self.murdered then
			if Visual then
				for i=1, 16 do
					CreateThing(NewMurderAnim(self.x,self.y, {self.lineage.hue, self.lineage.sat}))
				end
			end

			return false
		end

		self.mapTimer = self.mapTimer + 1
		if self.mapTimer > 30 then
			self.lastMapDist = math.dist(self.x,self.y, self.map[#self.map][1],self.map[#self.map][2])
			self.map[#self.map+1] = {self.x, self.y}
			self.mapTimer = 0

			-- if self.lastMapDist < 10 and self.lifeTimer < 60 then
				-- return false
			-- end
		end

		local friction = 0.95
		self.xSpeed = self.xSpeed*friction
		self.ySpeed = self.ySpeed*friction

		-- extend or retract nose
		-- if self.noseOutCooldown > 0 then
		-- 	self.noseOutCooldown = self.noseOutCooldown - 1
		-- end
		-- if self.brainOut[3] < 0 then
		-- 	if self.noseOutCooldown <= 0 then
		-- 		self.noseOutCooldown = 60
		-- 		self.noseOut = 0
		-- 	end
		-- end
		-- if self.brainOut[3] > 0 then
		-- 	if self.noseOutCooldown <= 0 then
		-- 		self.noseOutCooldown = 60
		-- 		self.noseOut = 1
		-- 	end
		-- end

		-- to prevent spinners
		local maxTurnSpeed = 0.2
		-- if self.noseOut == 1 then
		-- 	maxTurnSpeed = 0.05
		-- end

		self.speed = self.speed + self.brainOut[2]

		local directionDelta = self.brainOut[1]
		directionDelta = math.max(math.min(directionDelta, maxTurnSpeed), -1*maxTurnSpeed)

		if self.shieldingCooldown <= 0 then
			if self.brainOut[4] > 0.5 then
				self.shielding = false
				self.shieldingCooldown = 20
			else
				self.shielding = false
				self.shieldingCooldown = 20
			end
		else
			self.shieldingCooldown = self.shieldingCooldown-1
		end

		if self.shielding then
			directionDelta = 0 --directionDelta/5
		end

		if math.abs(directionDelta) > maxTurnSpeed/2 then
			self.noseOut = 0
			self.noseOutCooldown = 60
		else
			self.noseOut = 1
		end
		self.noseLength = math.floor(16-self.radius +0.5)

		self.direction = self.direction + directionDelta
		self.direction = self.direction%(math.pi*2)


		self.speed = math.max(math.min(self.speed, 1), -1)
		self.xSpeed = self.xSpeed + math.cos(self.direction)*self.speed*0.05
		self.ySpeed = self.ySpeed + math.sin(self.direction)*self.speed*0.05

		if self.x+self.xSpeed < 0 or self.x+self.xSpeed > WorldSize then
			self.xSpeed = self.xSpeed*-1
		end
		if self.y+self.ySpeed < 0 or self.y+self.ySpeed > WorldSize then
			self.ySpeed = self.ySpeed*-1
		end

		local moveSpeed = 0.1
		self.x = self.x + self.xSpeed
		self.y = self.y + self.ySpeed

		local foodDist = self.visionRange
		local foodDirection = self.direction
		local foodSourceDist = self.visionRange
		local deadFoodDist = self.visionRange
		local deadFoodDirection = self.direction
		local thingDist = self.visionRange*3
		local thingDirection = self.direction
		local thingPointDirection = self.direction
		local familyDist = self.visionRange*3
		local familyDirection = self.direction
		local thingCount = 0
		local thingNoseOut = 0

		local interactions = function (self, xx,yy)
			local octreeGrid = WorldSize/OctreeSize
			local cx,cy = math.floor(self.x/octreeGrid)+1 +xx, math.floor(self.y/octreeGrid)+1 +yy
			if cx <= 0 or cy <= 0 or cx > #ThingOctree or cy > #ThingOctree then return end
			local myOctree = ThingOctree[cx][cy]
			if myOctree == nil then return end
			for i=1, #myOctree do
				local thing = myOctree[i]
				local dist = math.dist(thing.x,thing.y, self.x,self.y)
				if thing.name == "food" then
					local food = thing

					if dist < foodDist then
						if not food.dead then
							foodDist = dist
							foodDirection = math.angle(self.x,self.y, food.x,food.y)
						else
							deadFoodDist = dist
							deadFoodDirection = math.angle(self.x,self.y, food.x,food.y)
						end
					end

					if dist < foodSourceDist then
						foodSourceDist = dist
					end

					--can only eat food if nose is not out
					if dist <= self.radius+1 then --and self.noseOut == 0 then
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
					local collisionAngle = math.angle(self.x+self.xSpeed,self.y+self.ySpeed, thing.x,thing.y)
					local isPoked = math.dist(self.x+math.cos(self.direction)*(self.radius+self.noseLength)*self.noseOut, self.y+math.sin(self.direction)*(self.radius+self.noseLength)*self.noseOut, thing.x,thing.y) <= thing.radius

					if dist < thingDist and not isFamily then
						thingCount = thingCount + 1
						thingDist = dist
						thingDirection = math.angle(self.x,self.y, thing.x,thing.y)
						thingPointDirection = thing.direction
						thingNoseOut = thing.noseOut
					end
					if dist < familyDist and isFamily then
						familyDist = dist
						familyDirection = math.angle(self.x,self.y, thing.x,thing.y)
					end

					if isPoked and self.noseOut > 0 and not thing.shielding and not self.shielding and not isFamily then
						local winner = self
						local loser = thing
						local can = true

						if can and not loser.murdered and loser.iFrames <= 0 then
							loser.murdered = true
							winner:reproduce()
							DeathSpawns = DeathSpawns + 1
						end
					end
					if dist <= self.radius+thing.radius then
						local bumpSpeed = 6*1.6/8
						self.xSpeed = math.cos(collisionAngle)*-bumpSpeed
						self.ySpeed = math.sin(collisionAngle)*-bumpSpeed
						thing.xSpeed = math.cos(collisionAngle)*bumpSpeed
						thing.ySpeed = math.sin(collisionAngle)*bumpSpeed
					end
				end
			end
		end

		-- do interactions for all octree chunks around me 3x3
		local checkRange = 3
		for xx=-checkRange, checkRange do
			for yy =-checkRange, checkRange do
				interactions(self,xx,yy)
			end
		end

		local foodDirectionDiff = math.abs(self.direction%(math.pi*2)-foodDirection%(math.pi*2))
		local thingDirectionDiff = math.abs(self.direction%(math.pi*2)-thingDirection%(math.pi*2))
		local familyDirectionDiff = math.abs(self.direction%(math.pi*2)-familyDirection%(math.pi*2))
        local foodDistDelta = foodDist - self.lastFoodDist
        local thingDistDelta = thingDist - self.lastThingDist

		self.brainOut = self.brain:cycle({
			{foodDistDelta},
			{foodSourceDist},
			{thingDirectionDiff},--{thingDist - self.lastThingDist},
			{thingDistDelta},
		})
		self.brainOutRaw = deepcopy(self.brainOut)
		for i=1, #self.brainOut do
			self.brainOut[i] = self.brainOut[i]*2 -1
		end

		self.lastThingDist = thingDist
		self.lastFamilyDist = familyDist
		self.lastFoodDist = foodDist
		self.lastDeadFoodDist = deadFoodDist

		if love.mouse.isDown(1) then
			local dist = math.dist(love.mouse.getX(),love.mouse.getY(),self.x-Camera.x,self.y-Camera.y)
			if dist < self.radius*1.5 then
				SelectedThing = self
			end
		end

		if SelectedThing == self and Follow then
			Camera.x = self.x-love.graphics.getWidth()/2
			Camera.y = self.y-love.graphics.getHeight()/2
		end

		local ret = self.lifeTimer < self.lifeTimerMax
		if not ret and SelectedThing == self then
			SelectedThing = self.lastChild
		end

		return ret
	end

	c.reproduce = function (self)
		local child = CreateThing(NewCreature(self.x,self.y, deepcopy(self.brain),deepcopy(self.lineage),self.generation+1, self.radius,self.noseLength, self.mutations))
		for j=1, choose{0,0,0,0,0,1,1,rand(0,10)} do
			child:mutate()
		end
		self.lastChild = child
		self.iFrames = 60
		self.offspringCount = self.offspringCount+1
		if child.mutations>15 then
			child.generation = 0
			child.mutations = 0
			child.lineage.middleName = self.lineage.firstName
		end
	end

	c.draw = function (self)
		local dx,dy = self.x-Camera.x,self.y-Camera.y
		local r,g,b = HSV(self.lineage.hue,self.lineage.sat,255)
		SetColor(r,g,b)
		love.graphics.circle("fill", dx,dy, self.radius,16)
		SetColor(255,255,255)
		if self.noseOut == 0 then
			SetColor(0,0,0)
		end
		love.graphics.line(dx,dy, dx+math.cos(self.direction)*(self.radius+self.noseLength*self.noseOut),dy+math.sin(self.direction)*(self.radius+self.noseLength*self.noseOut))

		if self.shielding then
			SetColor(255,255,255)
			love.graphics.circle("line", dx,dy, self.radius+4,8)
		end

		if SelectedThing == self then
			SetColor(255,255,0)
			love.graphics.rectangle("line", dx-self.radius,dy-self.radius, self.radius*2,self.radius*2)

			self.brain:draw()

			love.graphics.print("age: "..math.floor((self.lifeTimer/self.lifeTimerMax)*100).."%",8,250)
			love.graphics.print("offspringCount: "..self.offspringCount,8,250+16)
			love.graphics.print("family: "..self.lineage.firstName.." "..self.lineage.middleName.." "..self.lineage.lastName,8,250+32)
			love.graphics.print("generation: "..self.generation,8,250+48)
			love.graphics.print("radius: "..math.floor(self.radius).." noseLength: "..math.floor(self.noseLength),8,250+64)
			love.graphics.print("mutations: "..math.floor(self.mutations),8,250+64+16)

			-- love.graphics.circle("line", dx,dy, self.visionRange,64)
			local drawMap = {}
			for i=1, #self.map do
				drawMap[#drawMap+1] = self.map[i][1] -Camera.x
				drawMap[#drawMap+1] = self.map[i][2] -Camera.y
			end

			if drawMap ~= nil and #drawMap%2 == 0 and #drawMap >= 4 then
				love.graphics.line(drawMap)
			end
		end
	end

	if c.mutations == nil then
		c.mutations = 0
	end
	if c.radius == nil then
		c.radius = 8
	end
	if c.noseLength == nil then
		c.noseLength = 8
	end
	if c.lineage == nil then
		c.lineage = {}
		c.lineage.name = ""
		c.lineage.hue = math.floor(love.math.random()*255 +0.5)
		c.lineage.sat = math.floor(love.math.random()*128 +0.5) +128
		c.lineage.lastName = Name()
		c.lineage.middleName = Name()
		c.lineage.firstName = Name()
	end
	if c.generation == nil then
		c.generation = 1
	end
	if c.brain == nil then
		c.brain = NewBrain()
		for i=1, 30 do
			c:mutate()
		end
	end

	c.lineage.unique = math.floor(love.math.random()*100000000)

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

function NewBrain()
	local b = {}
	local width = 4
	local depth = 3
	b.width = width
	b.depth = depth
	b.brain = {}
	b.inputs = {}
	b.outputs = {}
	b.givenTable = {}

	for i=1, width do
		b.brain[i] = {}
		for j=1, depth do
			b.brain[i][j] = NewNeuron(width)
		end
	end

	b.mutate = function (self)
		for i=1, self.width do
			for j=1, self.depth do
				self.brain[i][j]:mutate()
			end
		end
	end

	b.cycle = function (self, givenTable)
		local inputs = {}
		local finals = {}
		local outputs = {}
		self.givenTable = givenTable
		-- for i=1, #givenTable do
			-- self.givenTable[i] = math.floor(self.givenTable[i]*100)/100
		-- end
		for i=1, self.width do
			inputs[i] = {}
			outputs[i] = {}
			for j=1, self.depth do
				inputs[i][j] = {}
				outputs[i][j] = 0
			end

			for j=1, #givenTable[i] do
				inputs[i][1][j] = givenTable[i][j]
			end
		end

		for j=1, self.depth do
			for i=1, self.width do
				local nret = self.brain[i][j]:output(inputs[i][j])
				outputs[i][j] = nret

				if j < self.depth then
					for k=1, self.width do
						table.insert(inputs[k][j+1], nret)
					end
				else
					table.insert(finals, nret)
				end
			end
		end

		self.inputs = inputs
		self.outputs = outputs

		return finals
	end

	b.draw = function (self)
		for i=1, self.width do
			for j=1, self.depth do
				local c = (128 + self.outputs[i][j]*128)-1
				c = math.min(c, 255)
				c = math.max(c, 0)
				local sq = 48
				local sep = 8

				SetColor(c,c,c)
				local dx,dy = (i-1)*(sq+sep) +sep, (j-1)*(sq+sep) +sep
				love.graphics.rectangle("fill", dx,dy, sq,sq)
				SetColor(255,0,0)
				love.graphics.print(math.floor(self.outputs[i][j]*1000)/1000, dx+4,dy+4)
			end
		end

		local mx = math.floor(love.mouse.getX()/56) + 1
		local my = math.floor(love.mouse.getY()/56) + 1

		if mx <= self.width and my <= self.depth then
			--love.graphics.print(inspect(self.inputs[mx][my]), 300,100)
			--love.graphics.print(self.brain[mx][my].bias.." --- "..inspect(self.brain[mx][my].weights), 300,150)
		end
		for i=1, #self.givenTable do
			love.graphics.print(self.givenTable[i], 300, 8 + i*16)
		end
	end

	return b
end

function NewNeuron(weightCount)
	local n = {}
	n.weightCount = weightCount
	n.weights = {}
	n.bias = 0

	for i=1, weightCount do
		n.weights[i] = 0
	end

	n.mutate = function (self)
		if love.math.random() > 0.8 then
			for i=1, self.weightCount do
				if love.math.random() <= 0.25 then
					local mult = 0.125

					if love.math.random() <= 0.25 then
						mult = 2
					end

					self.weights[i] = self.weights[i] + love.math.random()*choose{1,-1}*0.25
				end

				local c = rand(1,20)
				if c == 20 then
					self.weights[i] = 1
				end
				if c == 19 then
					self.weights[i] = -1
				end
				if c == 18 then
					self.weights[i] = 0
				end
				if c == 17 then
					self.weights[i] = self.weights[i]*10
				end
			end
		end

		if love.math.random() > 0.8 then
			if love.math.random() > 0.5 then
				self.bias = self.bias + love.math.random()*choose{1,-1}*0.25
			end
			local c = rand(1,20)
			if c == 20 then
				self.bias = 1
			end
			if c == 19 then
				self.bias = -1
			end
			if c == 18 then
				self.bias = 0
			end
			if c == 17 then
				self.bias = self.bias*10
			end
		end
	end

	n.output = function (self, inputs)
		local adder = 0
		for i=1, math.min(#self.weights, #inputs) do
			-- print(inspect(inputs)..":"..inspect(self.weights))
			adder = adder + self.weights[i]*inputs[i]
		end

		adder = adder + self.bias

		return 1/( 1+ (2.71828^(-1*adder)) )
	end

	return n
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
