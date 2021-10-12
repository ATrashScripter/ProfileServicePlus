local Config = {
	DEFAULT_NOT_RELEASED_HANDLER = "ForceLoad",
	AUTOMATICALLY_UPDATE_LEADERSTATS = true,
	LOAD_ALL_PROFILES_ON_JOIN = true,
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
