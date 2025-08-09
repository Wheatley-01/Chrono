local config = require(script.Parent.Parent.shared.config)
local kalmanFilter = require(script.Parent.kalmanFilter)

export type DeadReckoning = {
	lastCFrame: CFrame,
	lastVelocity: vector,
	lastAcceleration: vector,
	lastAngularVelocity: number,
	lastUpdateTime: number,

	movementHistory: {
		{
			velocity: vector,
			time: number,
		}
	},

	historySize: number,
	currentPattern: string,
	patternConfidence: number,

	entityType: string?, --for npc support
	kalmanFilter: kalmanFilter.KalmanFilter,

	predictionError: number,
	errorHistory: {},
	adaptiveThresholds: {
		direction: number,
		position: number,
		velocity: number,
	},

	updateMovementHistory: (self: DeadReckoning, velocity: vector) -> (),
	analyzeMovementPattern: (self: DeadReckoning) -> (string, number),
	adaptThresholds: (self: DeadReckoning) -> (),
	calculateMetrics: (self: DeadReckoning, currentCFrame: CFrame, deltaTime: number) -> (vector, vector, number),
	predictCFrame: (self: DeadReckoning, targetTime: number) -> CFrame?,
	shouldSendUpdate: (self: DeadReckoning, currentCFrame: CFrame, deltaTime: number) -> (boolean, string),
	onUpdateSent: (self: DeadReckoning, currentCFrame: CFrame, deltaTime: number) -> (),
	updatePredictionQuality: (self: DeadReckoning, actualCFrame: CFrame) -> (),
	getDebugInfo: (
		self: DeadReckoning
	) -> {
		pattern: string,
		patternConfidence: number,
		predictionError: number,
		kalmanConfidence: number,
	},
}

local function updateMovementHistory(self: DeadReckoning, velocity: vector)
	table.insert(self.movementHistory, {
		velocity = velocity,
		time = os.clock(),
	})

	while #self.movementHistory > self.historySize do
		table.remove(self.movementHistory, 1)
	end
end

local function analyzeMovementPattern(self: DeadReckoning): (string, number)
	if #self.movementHistory < 3 then
		return "idle", 0
	end

	local averageSpeed = 0
	local directionChanges = 0
	local verticalMovement = 0

	for i, sample in self.movementHistory do
		averageSpeed = averageSpeed + vector.magnitude(sample.velocity)
		verticalMovement = verticalMovement + math.abs(sample.velocity.y)

		if i == 1 then
			continue
		end

		local previousSample = self.movementHistory[i - 1]
		local directionChange = math.acos(
			math.clamp(vector.dot(vector.normalize(sample.velocity), vector.normalize(previousSample.velocity)), -1, 1)
		)

		directionChanges += directionChange
	end

	averageSpeed = averageSpeed / #self.movementHistory
	directionChanges = directionChanges / (#self.movementHistory - 1)
	verticalMovement = verticalMovement / #self.movementHistory

	local confidence = 0.8
	local pattern = "walking"

	if averageSpeed < 1 then
		pattern = "idle"
		confidence = 0.9
		--stylua doesnt let me add an empty line here :pensive:
	elseif directionChanges > math.rad(45) then
		pattern = "erratic"
		confidence = 0.6
	elseif verticalMovement > 5 then
		pattern = "jumping"
		confidence = 0.7
	elseif averageSpeed > 20 then
		pattern = "running"
		confidence = 0.85
	elseif directionChanges < math.rad(5) then
		pattern = "straight"
		confidence = 0.9
	end

	return pattern, confidence
end

local function adaptThresholds(self: DeadReckoning)
	local pattern, confidence = self:analyzeMovementPattern()
	self.currentPattern = pattern
	self.patternConfidence = confidence

	local errorFactor = math.clamp(1 - (self.predictionError / 5), 0.5, 2)

	local baseThresholds = config.BASE_THRESHOLDS[self.entityType]
	local multipliers = config.ADAPTIVE_THRESHOLD_MULTIPLIERS
	local multiplier = multipliers[pattern] or multipliers.walking

	self.adaptiveThresholds.direction = baseThresholds.direction * multiplier.direction * errorFactor
	self.adaptiveThresholds.velocity = baseThresholds.velocity * multiplier.velocity * errorFactor
	self.adaptiveThresholds.position = baseThresholds.position * multiplier.position * errorFactor
end

local function calculateMetrics(self: DeadReckoning, currentCFrame: CFrame, deltaTime: number)
	if deltaTime <= 0 then
		return vector.create(0, 0, 0), vector.create(0, 0, 0), 0
	end

	local displacement = currentCFrame.Position - self.lastCFrame.Position :: any --pmo
	local velocity = displacement / deltaTime
	local acceleration = (velocity - self.lastVelocity) / deltaTime

	--doesnt support MakeNetworkable for now :pensive:
	local _, lastY, _ = self.lastCFrame:ToEulerAnglesYXZ()
	local _, currentY, _ = currentCFrame:ToEulerAnglesYXZ()
	local angularVelocity = (currentY - lastY) / deltaTime

	if math.abs(angularVelocity) > math.pi then
		angularVelocity = angularVelocity - math.sign(angularVelocity) * 2 * math.pi
	end

	return velocity, acceleration, angularVelocity
end

local function shouldSendUpdate(
	self: DeadReckoning,
	currentCFrame: CFrame,
	deltaTime: number
): (boolean, string) --the string is for debugging
	local currentTime = os.clock()
	local velocity, acceleration, angularVelocity = self:calculateMetrics(currentCFrame, deltaTime)
	local baseThresholds = config.BASE_THRESHOLDS[self.entityType]

	self:updateMovementHistory(velocity)
	self:adaptThresholds()

	if currentTime - self.lastUpdateTime > baseThresholds.maxUpdateInterval then
		return true, "timeout"
	end

	local wasMoving = vector.magnitude(self.lastVelocity) > self.adaptiveThresholds.velocity
	local isMoving = vector.magnitude(velocity) > self.adaptiveThresholds.velocity

	if wasMoving ~= isMoving then
		return true, isMoving and "start moving" or "stop moving"
	end

	local displacement = currentCFrame.Position - self.lastCFrame.Position
	if displacement.Magnitude > self.adaptiveThresholds.position * 10 then
		return true, "teleport"
	end

	if not isMoving then
		if math.abs(angularVelocity) > baseThresholds.angularVelocity then
			return true, "rotation only"
		end

		return false, "stationary"
	end

	if vector.magnitude(self.lastVelocity) > 0 and vector.magnitude(velocity) > 0 then
		local dotProduct = vector.dot(vector.normalize(self.lastVelocity), vector.normalize(velocity))
		local directionChange = math.acos(math.clamp(dotProduct, -1, 1))

		if directionChange > self.adaptiveThresholds.direction then
			return true, "direction change" .. math.deg(directionChange) .. " degrees"
		end
	end

	local speedChange = math.abs(vector.magnitude(velocity) - vector.magnitude(self.lastVelocity))
	if speedChange > self.adaptiveThresholds.velocity then
		return true, "speed change"
	end

	local accelerationChange = vector.magnitude(acceleration - self.lastAcceleration)
	if accelerationChange > 5 then
		return true, "acceleration change"
	end

	local angularVelocityChange = math.abs(angularVelocity - self.lastAngularVelocity)
	if angularVelocityChange > baseThresholds.angularVelocity then
		return true, "angular change"
	end

	return false, "no change"
end

local function onUpdateSent(self: DeadReckoning, currentCFrame: CFrame, deltaTime: number)
	local velocity, acceleration, angularVelocity = self:calculateMetrics(currentCFrame, deltaTime)
	self.kalmanFilter:update(deltaTime, velocity, currentCFrame.Position :: any)

	self.lastCFrame = currentCFrame
	self.lastVelocity = velocity
	self.lastAcceleration = acceleration
	self.lastAngularVelocity = angularVelocity
	self.lastUpdateTime = os.clock()

	self:updatePredictionQuality(currentCFrame)
end

local function updatePredictionQuality(self: DeadReckoning, actualCFrame: CFrame)
	if #self.errorHistory > 0 then
		local lastPredicted = self.errorHistory[#self.errorHistory].predicted
		local error = (actualCFrame.Position - lastPredicted).Magnitude
		self.predictionError = self.predictionError * 0.9 + error * 0.1 --exponential smoothing
	end

	table.insert(self.errorHistory, {
		predicted = actualCFrame.Position,
		time = os.clock(),
	})

	while #self.errorHistory > 5 do
		table.remove(self.errorHistory, 1)
	end
end

local function predictCFrame(self: DeadReckoning, targetTime: number): CFrame?
	local deltaTime = targetTime - self.lastUpdateTime
	if deltaTime <= 0 then
		return self.lastCFrame
	end

	local predictedPosition = self.kalmanFilter:predict(deltaTime)

	local predictedAngle = self.lastAngularVelocity * deltaTime
	local currentY = select(2, self.lastCFrame:ToEulerAnglesYXZ())
	local newY = currentY + predictedAngle

	local predictedCFrame = CFrame.new(predictedPosition :: any) * CFrame.Angles(0, newY, 0)

	table.insert(self.errorHistory, {
		predicted = predictedPosition,
		time = targetTime,
	})

	return predictedCFrame
end

local function getDebugInfo(self: DeadReckoning)
	return {
		pattern = self.currentPattern,
		patternConfidence = self.patternConfidence,
		predictionError = self.predictionError,
		kalmanConfidence = self.kalmanFilter:getConfidence(),
	}
end

return function(initialCFrame: CFrame, entityType: string?): DeadReckoning
	entityType = entityType or "player"

	return {

		lastCFrame = initialCFrame,
		lastVelocity = vector.create(0, 0, 0),
		lastAcceleration = vector.create(0, 0, 0),
		lastAngularVelocity = 0,
		lastUpdateTime = os.clock(),

		movementHistory = {},
		historySize = 10,
		currentPattern = "idle",
		patternConfidence = 0,

		entityType = entityType,
		kalmanFilter = kalmanFilter(initialCFrame.Position :: any, vector.create(0, 0, 0)),

		predictionError = 0,
		errorHistory = {},
		adaptiveThresholds = {
			direction = config.BASE_THRESHOLDS[entityType].direction,
			position = config.BASE_THRESHOLDS[entityType].position,
			velocity = config.BASE_THRESHOLDS[entityType].velocity,
		},

		updateMovementHistory = updateMovementHistory,
		adaptThresholds = adaptThresholds,
		onUpdateSent = onUpdateSent,
		analyzeMovementPattern = analyzeMovementPattern,
		calculateMetrics = calculateMetrics,
		predictCFrame = predictCFrame,
		shouldSendUpdate = shouldSendUpdate,
		updatePredictionQuality = updatePredictionQuality,
		getDebugInfo = getDebugInfo :: any, --cba
	}
end
