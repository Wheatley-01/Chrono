--!strict
--!native

--added native for larping

local config = require(script.Parent.Parent.shared.config)

export type KalmanFilter = {
	state: {
		position: vector,
		velocity: vector,
		acceleration: vector,
	},

	--simplified diagonal reperesentation of covariance matrix
	--the full 9x9 is overkill
	covariance: {
		position: number,
		velocity: number,
		acceleration: number,
	},

	--how much we expect it to deviate
	processNoise: {
		position: number,
		velocity: number,
		acceleration: number,
	},

	--how much we trust new measurements
	measurementNoise: {
		position: number,
		velocity: number,
		acceleration: number,
	},

	predict: (self: KalmanFilter, deltaTime: number) -> (vector, vector, vector),
	update: (self: KalmanFilter, deltaTime: number, measuredPosition: vector, measuredVelocity: vector?) -> (),
	getConfidence: (self: KalmanFilter) -> (),
}

--prediction step
local function predict(self: KalmanFilter, deltaTime: number)
	local dt = deltaTime
	local dt2 = dt * dt

	--acceleration assumed constant
	local predictedPosition = self.state.position + self.state.velocity * dt + 0.5 * self.state.acceleration * dt2
	local predictedVelocity = self.state.velocity + self.state.acceleration * dt

	--increase uncertainty during prediction step
	self.covariance.position = self.covariance.position
		+ self.covariance.velocity * dt2
		+ self.covariance.acceleration * dt2 * dt2 * 0.25
		+ self.processNoise.position --extra noise

	self.covariance.velocity = self.covariance.velocity
		+ self.covariance.acceleration * dt2
		+ self.processNoise.velocity * dt2

	self.covariance.acceleration = self.covariance.acceleration + self.processNoise.acceleration * dt

	return predictedPosition, predictedVelocity, self.state.acceleration
end

--correction step
local function update(self: KalmanFilter, deltaTime: number, measuredPosition: vector, measuredVelocity: vector?)
	--calculate the kalman gain (how much we trust prediction vs how much we trust measurement)
	--https://en.wikipedia.org/wiki/Kalman_filter

	local positionGain = self.covariance.position / (self.covariance.position + self.measurementNoise.position)
	local velocityGain = self.covariance.velocity / (self.covariance.velocity + self.measurementNoise.velocity)

	--by how much our predicction was off
	local innovation = measuredPosition - self.state.position

	if vector.magnitude(innovation) > config.ERROR_THRESHOLD then
		--predictions are unreliable
		self.measurementNoise.position = math.min(self.measurementNoise.position * 1.5, 2.0)
		positionGain = positionGain * 0.5
	else
		self.measurementNoise.position = math.max(self.measurementNoise.position * config.ADAPTIVE_GAIN, 0.05)
	end

	self.state.position += positionGain * innovation

	if measuredVelocity then
		--https://www.cs.unc.edu/~welch/media/pdf/kalman_intro.pdf
		--https://www.kalmanfilter.net/kalman1d.html

		local velocityInnovation = measuredVelocity - self.state.velocity
		self.state.velocity += velocityGain * velocityInnovation

		local estimatedAcceleration = (measuredVelocity - self.state.velocity) / deltaTime
		local accelerationGain = self.covariance.acceleration
			/ (self.covariance.acceleration + self.measurementNoise.acceleration)

		self.state.acceleration = self.state.acceleration
			+ accelerationGain * (estimatedAcceleration - self.state.acceleration)
	end

	self.covariance.position = (1 - positionGain) * self.covariance.position
	self.covariance.velocity = (1 - velocityGain) * self.covariance.velocity
end

--thsi is only for debugging
local function getConfidence(self: KalmanFilter): number
	local totalVariance = self.covariance.position + self.covariance.velocity * 0.1
	return math.max(0, 1 - math.min(totalVariance, 1))
end

return function(initialPosition: vector, initialVelocity: vector): KalmanFilter
	return {
		state = {
			position = initialPosition,
			velocity = initialVelocity,
			acceleration = vector.zero,
		},

		covariance = {
			position = 1.0,
			velocity = 1.0,
			acceleration = 2.0,
		},

		processNoise = {
			position = 0.01,
			velocity = 0.1,
			acceleration = 0.5,
		},

		measurementNoise = {
			position = 0.1,
			velocity = 0.3,
			acceleration = 1.0,
		},

		predict = predict,
		update = update,
		getConfidence = getConfidence,
	}
end
