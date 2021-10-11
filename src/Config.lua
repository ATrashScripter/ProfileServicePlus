local Config = {
	DEFAULT_NOT_RELEASED_HANDLER = "ForceLoad",
	AUTOMATICALLY_UPDATE_LEADERSTATS = true,
	GAME_PROFILE_TEMPLATES = {
		PlayerStats = {
			_Key = "PlayerStats-UserId",
			_LoadOnJoin = true,
			Gold = 0,
			Level = 1,
			Inventory = {
				"Turret",
			}
		},
	},
}

return Config
