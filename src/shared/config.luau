return table.freeze({
	MIN_BUFFER = 0.09,
	MAX_BUFFER = 0.5,
	TICK_RATE = 1 / 20,

	PROXIMITY = 100,

	ENABLE_CUSTOM_CHARACTERS = false, -- this will disable default roblox replication as well.
	DISABLE_DEFAULT_REPLICATION = true, -- this is if you want to disable the default roblox replication, but still use their controller

	NPC_TYPES = table.freeze({
		DEFAULT = table.freeze({
			TICK_RATE = 1 / 30,
			BUFFER = 0.1,
		}),
	}),

	--these constants were made by gpt and tuned a little bit b y me
	ERROR_THRESHOLD = 2.0,

	ADAPTIVE_GAIN = 0.95,
	INNOVATION_THRESHOLD = 2.0,

	BASE_THRESHOLDS = {
		player = {
			direction = math.rad(12),
			velocity = 1.5,
			position = 1.8,
			maxUpdateInterval = 0.4,
			angularVelocity = math.rad(30),
		},

		npc = {
			direction = math.rad(20),
			velocity = 3,
			position = 1.0,
			maxUpdateInterval = 0.6,
			angularVelocity = math.rad(45),
		},
	},

	ADAPTIVE_THRESHOLD_MULTIPLIERS = {
		idle = { direction = 2.0, velocity = 2.0, position = 2.0 },
		walking = { direction = 1.0, velocity = 1.0, position = 1.0 },
		running = { direction = 0.7, velocity = 0.8, position = 0.8 },
		jumping = { direction = 1.5, velocity = 1.2, position = 1.5 },
		erratic = { direction = 0.5, velocity = 0.6, position = 0.7 },
		straight = { direction = 1.2, velocity = 1.1, position = 1.1 },
	},
})
