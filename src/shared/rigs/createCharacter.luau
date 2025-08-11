local Players = game:GetService("Players")

return function(player: Player, userId: number): { Model: Model }
	local rig = {}

	if userId < 0 then
		userId = 1242803262
	end

	print(userId)
	local humanoidDescription = Players:GetHumanoidDescriptionFromUserId(userId)
	local model = Players:CreateHumanoidModelFromDescription(humanoidDescription, Enum.HumanoidRigType.R15)
	model.Parent = workspace

	rig.Model = model

	return rig
end
