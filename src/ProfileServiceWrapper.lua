--[[
	By: ATrashScripter, ATrashScripter#9599
	V1.00
	-- no docs yet
--]]

--Dependancies
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ProfileService = require(script.ProfileService) 
local Signal = require(script.Signal)
local Config = require(script.Config)

local ProfileServiceWrapper = { 
	ProfileAdded = Signal.new(),
	ProfileRemoving = Signal.new(),
	initiated = false, --boolean if module has initialized
}




local Global_Update_Types = {}
local LoadedProfiles = {}
local Loaded_Profile_Stores = {}

--Custom assert function
local function assert(condition: boolean, errorMsg, warnOnly: boolean)
	if not condition then
		if warnOnly then
			warn(errorMsg)
		else	
			error(errorMsg, 3)
		end
	end
end


--Convert seconds to miliseconds
local function SecondsToMS(n: number, amountOfDecimals: number)
	local format = "%.".. amountOfDecimals.. "f"
	return string.format(format, n * 1000)
end



--Automatically updates leaderstats if it exists
local function updateLeaderstats(profile, newData, player)
	local leaderstats = player:FindFirstChild("leaderstats")
	if profile and player:IsDescendantOf(Players) and leaderstats ~= nil then
		for _, stat in ipairs(leaderstats:GetChildren()) do
			local profileData = newData[stat.Name]
			if profileData ~= nil then
				stat.Value = profileData
			end
		end
	end
end



local function handleLockedUpdate(globalUpdates, update, fakeProfile, player)
	print("[Data Manager]: New locked update added")
	
	local updateID = update[1]
	local updateData = update[2]
	
	--Check if update type exists in Global_Update_Types
	local listener = Global_Update_Types[updateData.Type]
	if listener ~= nil then
		--Fire the listener
		listener(fakeProfile, updateData, player)
	else
		warn(("[Data Manager]: No listener found for update %s!"):format(updateID))
	end
	--Clear the locked update
	globalUpdates:ClearLockedUpdate(updateID)
	print("[Data Manager]: Cleared locked update")
end


--Proxy for profile.Data for DataChanged or KeyChanged events
local function setProxy(tbl): table
	local self = {}
	self._state = {}

	--table.freeze(self._state)

	local meta = {
		__index = function(self, index)
			return tbl[index]
		end,
		__newindex = function(self, index, value)
			if tbl[index] ~= nil then
				if tbl._Key and self.DataChanged then
					tbl[index] = value
					self.DataChanged:Fire()
				else
					tbl[index] = value
				end
			end
		end
	}


	if tbl._Key ~= nil then
		self.DataChanged = Signal.new()

		for k, v in pairs(tbl) do
			if typeof(v) == "table" then
				tbl[k] = setProxy(v)
			end
		end

		setmetatable(self, meta)

		return self
	end

	self.KeyChanged = Signal.new()

	for k, v in pairs(tbl) do
		if typeof(v) == "table" then
			setProxy(tbl)
		end
	end

	setmetatable(self, meta)

	return self
end

--Runs after a profile has successfully loaded
local function onProfileAdded(profile, player)
	if Config.AUTOMATICALLY_UPDATE_LEADERSTATS then
		profile.Data.DataChanged:Connect(function(key, value)
			local leaderstats = player:FindFirstChild("leaderstats")
			if leaderstats then
				if leaderstats[key] then
					leaderstats[key].Value = value
				end
			end
		end)
	end
end



local function getDefaultKey(player, profileStoreKey)
	local playerKey = profileStoreKey.. "-%s"
	
	return playerKey:format(tostring(player.UserId))
end


local function getPlayerkey(player, profileStore)
	local playerKey
	local profileKey = profileStore._Key

	local stringStart, stringEnd = string.find(profileKey, "UserId")

	playerKey = string.sub(profileKey, 0, stringStart - 1).. player.UserId.. string.sub(profileKey, stringEnd + 1, #profileKey)

	return playerKey
end

local function loadProfile(player, storeKey, not_released_handler)
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
		Config.DEFAULT_NOT_RELEASED_HANDLER
	)

	if playerProfile then	
		playerProfile:Reconcile()
		playerProfile:ListenToRelease(function()
			player:Kick("Profile could've loaded on another Roblox server")
		end)

		if player:IsDescendantOf(Players) then
			--Get fake profile of the player
			playerProfile.Data = setProxy(playerProfile.Data)

			local globalUpdates = playerProfile.GlobalUpdates

			for i, update in pairs(globalUpdates:GetActiveUpdates()) do
				globalUpdates:LockActiveUpdate(update[1])
			end

			for i, lockedUpdate in pairs(globalUpdates:GetLockedUpdates()) do
				handleLockedUpdate(globalUpdates, lockedUpdate, playerProfile, player)
			end

			globalUpdates:ListenToNewActiveUpdate(function(updateID, updateData)
				--Lock the current active update
				globalUpdates:LockActiveUpdate(updateID)
			end)

			globalUpdates:ListenToNewLockedUpdate(function(updateID, updateData)
				handleLockedUpdate(globalUpdates, {updateID, updateData}, playerProfile, player)
			end)

			
			ProfileServiceWrapper.ProfileAdded:Fire(playerProfile, loadedProfileStore, player)
			return playerProfile
		else
			print("Player left before profile loaded, releasing profile")
			playerProfile:Release()
		end
	else
		player:Kick("Profile could'nt load because other Roblox servers were trying to load it")
	end
end


local function onPlayerAdded(player)
	local total = 0
	local loaded = 0
	
	for storeKey, data in pairs(Config.GAME_PROFILE_TEMPLATES) do
		total += 1
	end
	
	for storeKey, data in pairs(Config.GAME_PROFILE_TEMPLATES) do
		if not data._LoadOnJoin then
			continue
		end
		
		local playerProfile = loadProfile(player, storeKey)
		print(playerProfile)
		if playerProfile then
			LoadedProfiles[storeKey][player] = playerProfile
			loaded += 1
		end
	end
	
	print(("[Data Manager]: Successfully loaded %s/%s profiles"):format(loaded, total))
end



local function onPlayerRemoving(player)
	local released = 0
	local total = 0

	for _, _ in pairs(Config.GAME_PROFILE_TEMPLATES) do
		total += 1
	end

	for storeKey, profileStores in pairs(LoadedProfiles) do
		local playerProfile = profileStores[player]
		if playerProfile ~= nil then
			playerProfile.Data = playerProfile.Data._state
			local profileStore = ProfileServiceWrapper:GetProfileStore(storeKey)
			ProfileServiceWrapper.ProfileRemoving:Fire(playerProfile, profileStore, player)
			playerProfile:Release()
			released += 1
		end
	end


	print(("[Data Manager]: Successfully released %s/%s profiles"):format(released, total))
end


local function Init()
	if ProfileServiceWrapper.initiated then
		warn("[Data Manager]: ProfileServiceWrapper has already initiated")
	else
		ProfileServiceWrapper.initiated = true
		
		for storeKey, data in pairs(Config.GAME_PROFILE_TEMPLATES) do
			LoadedProfiles[storeKey] = {}
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
		Players.PlayerRemoving:Connect(onPlayerRemoving)
		print("[Data Manager]: Intitiated ProfileServiceWrapper")
	end
end


if not ProfileServiceWrapper.initiated then
	Init()
end


ProfileServiceWrapper.ProfileAdded:Connect(onProfileAdded)



function ProfileServiceWrapper:AddGlobalUpdateType(updateType: string, overwriteExisting, listener)
	--Type check updateType
	assert(typeof(updateType) == "string",("[Data Manager]: Expected string, got %s"):format(typeof(updateType)))
	
	if type(overwriteExisting) == "boolean" then
		assert(typeof(listener) == "function", "A Message")
		if Global_Update_Types[updateType] ~= nil then
			if not overwriteExisting then
				warn("[Data Manager]: Update type already exists")
				return
			end
			Global_Update_Types[updateType] = listener
		else
			Global_Update_Types[updateType] = listener
		end
	elseif type(overwriteExisting) == "function" then
		assert(listener == nil, "A Message", true)
		
		if Global_Update_Types[updateType] ~= nil then
			warn("[Data Manager]: Update type already exists")
			return
		end
		Global_Update_Types[updateType] = overwriteExisting
	else
		error(("Expected boolean or function, got %s"):format(typeof(overwriteExisting)))
	end
end




function ProfileServiceWrapper:GetPlayerFromProfile(profileInput)
	local output

	for profileKey, profiles in pairs(LoadedProfiles) do
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



function ProfileServiceWrapper:GetPlayerProfileKey(storeKey: string, player)
	local profileStore = Config.GAME_PROFILE_TEMPLATES[storeKey]

	return getPlayerkey(player, profileStore)
end


function ProfileServiceWrapper:GetProfileStore(storeKey: string)
	local profileStore = Loaded_Profile_Stores[storeKey]
	assert(typeof(storeKey) == "string", ("[Data Manager]: Expected string, got %s"):format(typeof(storeKey)))
	
	if profileStore then
		return profileStore
	end
end



--Returns player's profile on a specific profile store key
function ProfileServiceWrapper:GetProfile(player, profileKey: string)
	local playerProfile = LoadedProfiles[profileKey][player]

	return playerProfile
end


function ProfileServiceWrapper:LoadProfile(player, storeKey, not_released_handler)
	return loadProfile(player, storeKey, not_released_handler)
end


--Returns table of profiles
function ProfileServiceWrapper:GetProfiles(profileStoreKey: string)
	if profileStoreKey == nil then
		return LoadedProfiles 
	end
	assert(typeof(profileStoreKey) == "string", ("[Data Manager]: Expected string, got %s"):format(typeof(profileStoreKey)))
	assert(LoadedProfiles[profileStoreKey], "[Data Manager]: Invalid profile key")

	return LoadedProfiles[profileStoreKey]
end


return ProfileServiceWrapper


