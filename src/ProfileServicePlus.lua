--[[
	By: ATrashScripter, ATrashScripter#9599
	V1.00
	
	API

	ProfileServicePlus
	
	VARIABLES

	ProfileServicePlus.ProfileAdded - A signal that fires every time a profile is loaded through ProfileServicePlus:LoadProfile() 
	ProfileServicePlus.ProfileRemoving - A signal that fires every time a profile is released through ProfileServicePlus:ReleaseProfile()
	ProfileServicePlus.intiated - a boolean value for checking if the module has already initiated
	
	METHODS

	<table> ProfileServiceWrapper:LoadProfile(<Instance> player, <string> storeKey) - Attempts to load a profile

	<boolean>, <any> ProfileServicePlus:ReleaseProfile(<Instance> player, <string> storeKey) - Releases a profile
	

	<table> ProfileServicePlus:GetProfile(<Instance> player, <string> storeKey) - Attempts to return a loaded profile
	

	<table> ProfileServicePlus:GetProfiles(<string> storeKey) - Returns a table of profiles based on the storeKey or returns the Loaded_Profiles table itself

	Not Done
--]]

--Dependancies
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ProfileService = require(script.ProfileService or script.Parent.ProfileService) 
local Signal = require(script.Signal or script.Parent.Signal)
local Config = require(script.Config or script.Parent.Config)

local ProfileServicePlus = { 
	ProfileAdded = Signal.new(),
	ProfileRemoving = Signal.new(),
	Initialized = false, --boolean if module has initialized
}




local Global_Update_Types = {}
local Loaded_Profiles = {}
local Loaded_Profile_Stores = {}

--Handles locked global updates
local function handleLockedUpdate(profile: table, update, player: Instance)
	local globalUpdates = profile.GlobalUpdates
	print("[PSPlus]: New locked update added")

	local updateID = update[1]
	local updateData = update[2]

	--Check if update type exists in Global_Update_Types
	local listener = Global_Update_Types[updateData.Type]
	if listener ~= nil then
		--Fire the listener
		task.spawn(listener, profile, updateData, player)
	else
		warn(("[PSPlus]: No listener found for update %s!"):format(updateID))
	end
	--Clear the locked update
	globalUpdates:ClearLockedUpdate(updateID)
	print("[PSPlus]: Cleared locked update")
end



--Runs after a profile has successfully loaded
local function onProfileAdded(profile: table, player: string)
	if Config.AUTOMATICALLY_UPDATE_LEADERSTATS then
		--[[profile.Data.DataChanged:Connect(function(key, value)
			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats then
				if leaderstats[key] then
					leaderstats[key].Value = value
				end
			end
		end)--]]
	end
end


--Returns the default key for the profile
local function getDefaultKey(player: string, profileStoreKey: string): string
	local playerKey = profileStoreKey.. "-%s"

	return playerKey:format(tostring(player.UserId))
end

--Returns a player's profile key
local function getPlayerkey(player: string, profileStore: table): string
	local playerKey
	local profileKey = profileStore._Key

	local stringStart, stringEnd = string.find(profileKey, "UserId")

	playerKey = string.sub(profileKey, 0, stringStart - 1).. player.UserId.. string.sub(profileKey, stringEnd + 1, #profileKey)

	return playerKey
end

--Destroys all profile.Data.DataChanged or table.KeyChanged signals
local function destroyAllSignals(tbl)
	local signal = tbl.DataChanged or tbl.KeyChanged
	if signal then
		signal:DisconnectAll()
	end
	
	for _, v in pairs(tbl) do
		if type(v) == "table" then
			destroyAllSignals(v)
		end
	end
end

--Runs whenever ProfileServicePlus:ReleaseProfile() is called or when a player leaves the game
local function releaseProfile(player: Instance, storeKey: string)
	local profileStore = Loaded_Profile_Stores[storeKey]
	local playerProfile = Loaded_Profiles[storeKey][player]
	if playerProfile then
		ProfileServicePlus.ProfileRemoving:Fire(playerProfile, profileStore, player)
		playerProfile:Release()
	end
end


--Runs whenever ProfileServicePlus:LoadProfile() is called or when a player joins the game
local function loadProfile(player: Instance, storeKey: string, not_released_handler: string)
	local loadedProfileStore = Loaded_Profile_Stores[storeKey]

	local data = Config.GAME_PROFILE_TEMPLATES[storeKey]

	local playerKey
	if data._Key ~= nil then
		playerKey = getPlayerkey(player, data)
	else
		playerKey = getDefaultKey(player, storeKey)
	end


	local playerProfile = loadedProfileStore:LoadProfileAsync(
		playerKey,
		not_released_handler or Config.DEFAULT_NOT_RELEASED_HANDLER 
	)

	if playerProfile then	
		playerProfile:Reconcile()
		playerProfile:ListenToRelease(function()
			player:Kick("Profile could've loaded on another Roblox server")
		end)

		if player:IsDescendantOf(Players) then
			local globalUpdates = playerProfile.GlobalUpdates

			for i, update in pairs(globalUpdates:GetActiveUpdates()) do
				globalUpdates:LockActiveUpdate(update[1])
			end

			for i, lockedUpdate in pairs(globalUpdates:GetLockedUpdates()) do
				handleLockedUpdate(playerProfile, lockedUpdate , player)
			end

			globalUpdates:ListenToNewActiveUpdate(function(updateID, updateData)
				--Lock the current active update
				globalUpdates:LockActiveUpdate(updateID)
			end)

			globalUpdates:ListenToNewLockedUpdate(function(updateID, updateData)
				handleLockedUpdate(playerProfile, {updateID, updateData} , player)
			end)


			ProfileServicePlus.ProfileAdded:Fire(playerProfile, loadedProfileStore, player)
			return playerProfile
		else
			print("[PSPlus]: Player left before profile loaded, releasing profile")
			ProfileServicePlus:ReleaseProfile(player, storeKey)
		end
	else
		player:Kick("Profile could'nt load because other Roblox servers were trying to load it")
	end
end

--Runs whenever a player joins the game
local function onPlayerAdded(player)
	local total = 0
	local loaded = 0

	for _, _ in pairs(Config.GAME_PROFILE_TEMPLATES) do
		total += 1
	end

	for storeKey, data in pairs(Config.GAME_PROFILE_TEMPLATES) do
		if not data._LoadOnJoin and not Config.LOAD_ALL_PROFILES_ON_JOIN then
			continue
		end

		local playerProfile = loadProfile(player, storeKey)
		if playerProfile then
			Loaded_Profiles[storeKey][player] = playerProfile
			loaded += 1
		end
	end

	print(("[PSPlus]: Successfully loaded %s/%s profiles"):format(loaded, total))
end


--Runs whenever a player leaves the game
local function onPlayerRemoving(player)
	local released = 0
	local total = 0

	for _, _ in pairs(Config.GAME_PROFILE_TEMPLATES) do
		total += 1
	end

	for storeKey, profileStores in pairs(Loaded_Profiles) do
		local playerProfile = profileStores[player]
		if playerProfile ~= nil then
			local success = releaseProfile(player, storeKey)
			if success then
				released += 1
			end
		end
	end


	print(("[PSPlus]: Successfully released %s/%s profiles"):format(released, total))
end


local function Init()
	if ProfileServicePlus.initiated then
		warn("[PSPlus]: ProfileServicePlus has already initiated")
	else
		ProfileServicePlus.initiated = true

		for storeKey, data in pairs(Config.GAME_PROFILE_TEMPLATES) do
			Loaded_Profiles[storeKey] = {}
			Loaded_Profile_Stores[storeKey] = ProfileService.GetProfileStore(
				storeKey,
				data
			)
			Loaded_Profile_Stores[storeKey].Key = storeKey
		end

		for _, player in ipairs(Players:GetPlayers()) do
			task.spawn(onPlayerAdded, player)
		end

		Players.PlayerAdded:Connect(onPlayerAdded)
		--Players.PlayerRemoving:Connect(onPlayerRemoving)
		print("[PSPlus]: Initialized ProfileServicePlus")
	end
end

--Initiates the module
if not ProfileServicePlus.Initialized and RunService:IsServer() then
	Init()
end


ProfileServicePlus.ProfileAdded:Connect(onProfileAdded)


--Adds a global update type that calls back the passed listener whenever a global update with the same Type value as the passed updateType argument
function ProfileServicePlus:AddGlobalUpdateType(updateType: string, listener, overwriteExisting: boolean)
	--Type check updateType

	if overwriteExisting then
		Global_Update_Types[updateType] = listener
	else
		if Global_Update_Types[updateType] ~= nil then
			warn(("[PSPlus]: Global update type %s already exists!"):format(updateType))
			return
		end

		Global_Update_Types[updateType] = listener
	end
end



--Returns a player instance from the passed profile argument
function ProfileServicePlus:GetPlayerFromProfile(profileInput)
	local output

	for _, profiles in pairs(Loaded_Profiles) do
		for player, profile in pairs(profiles) do
			if profile ~= profileInput or player == nil then
				continue
			end

			output = player
			break
		end
	end

	return output
end


--Returns the player's profile key. Mainly used for global updates
function ProfileServicePlus:GetPlayerProfileKey(storeKey: string, player: Instance)
	local profileStore = Config.GAME_PROFILE_TEMPLATES[storeKey]

	return getPlayerkey(player, profileStore)
end

--Returns a ProfileStore
function ProfileServicePlus:GetProfileStore(storeKey: string)
	local profileStore = Loaded_Profile_Stores[storeKey]

	return profileStore
end



--Returns a player's specific profile
function ProfileServicePlus:GetProfile(player: Instance, profileKey: string)
	local playerProfile = Loaded_Profiles[profileKey][player]

	return playerProfile
end



--Attempts to load a player's specific profile
function ProfileServicePlus:LoadProfile(player: Instance, storeKey: string, not_released_handler: string)
	return loadProfile(player, storeKey, not_released_handler)
end



--Attempts to release a player's speific profile 
function ProfileServicePlus:ReleaseProfile(player: Instance, storeKey: string)
	return releaseProfile(player, storeKey)
end



--Returns a table of profiles
function ProfileServicePlus:GetProfiles(profileStoreKey: string)
	if profileStoreKey == nil then
		return Loaded_Profiles 
	end

	return Loaded_Profiles[profileStoreKey]
end



return ProfileServicePlus


