--====================================================================================
-- All work by Titch2000, jojos38 & 20dka.
-- You have no permission to edit, redistribute or upload other than for the purposes of contributing. 
-- Contact BeamMP for more info!
--====================================================================================

--- MPCoreNetwork API - This is the main networking and starting point for the BeamMP Multiplayer mod. It handles the Initial TCP connection establishment with the Launcher.
-- Author of this documentation is Titch2000
-- @module MPCoreNetwork
-- @usage connectToLauncher() -- internal access
-- @usage MPCoreNetwork.connectToLauncher() -- external access



local M = {}



-- ============= VARIABLES =============

local socket = require('socket')
local TCPSocket
local launcherConnected = false
local isConnecting = false
local eventTriggers = {}

--keypress handling

local keyStates = {} -- table of keys and their states, used as a reference
local keysToPoll = {} -- list of keys we want to poll for state changes
local keypressTriggers = {}

-- ============= VARIABLES =============

setmetatable(_G,{}) -- temporarily disable global notifications


--- Attempt to establish a connection to the Launcher, Note that this connection is only used for when in-session.
-- @usage `MPGameNetwork.connectToLauncher(true)`
local function connectToLauncher()
	log('M', 'connectToLauncher', "Connecting MPGameNetwork!")
	if not launcherConnected then
		isConnecting = true
		TCPSocket = socket.tcp()
		TCPSocket:setoption("keepalive", true)
		TCPSocket:settimeout(0) -- Set timeout to 0 to avoid freezing
		TCPSocket:connect(settings.getValue("launcherIp", '127.0.0.1'), settings.getValue("launcherPort", 4444)+1)
		M.send('A')
	else
		log('W', 'connectToLauncher', 'Launcher already connected!')
	end
end


--- Disconnect from the Launcher by closing the TCP connection, Note that this connection is only used for when in-session.
-- @usage `MPGameNetwork.disconnectLauncher(true)`
local function disconnectLauncher()
	if launcherConnected then
		TCPSocket:close()
		launcherConnected = false
	end
end


--- Send data over the TCP connection to the Launcher and then onto the Server.
-- @tparam string s The data to be sent to the Launcher/server.
-- @usage `MPGameNetwork.sendData(<data>)`
local function sendData(s)
	if not TCPSocket then return end
	local bytes, error, index = TCPSocket:send(#s..'>'..s)
	if error then
		isConnecting = false
		log('E', 'sendData', 'Socket error: '..error)
		if error == "closed" and launcherConnected then
			log('W', 'sendData', 'Lost launcher connection!')
			launcherConnected = false
		elseif error == "Socket is not connected" then

		else
			log('E', 'sendData', 'Stopped at index: '..index..' while trying to send '..#s..' bytes of data.')
		end
		return
	else
		if not launcherConnected then launcherConnected = true isConnecting = false end
		if settings.getValue("showDebugOutput") then
			log('M', 'sendData', 'Sending Data ('..bytes..'): '..s)
		end
		if MPDebug then MPDebug.packetSent(bytes) end
	end
end

--- Process session data received from the Launcher.
-- @tparam string data The session data received.
-- @usage `MPGameNetwork.sessionData(<data>)`
local function sessionData(data)
	local code = string.sub(data, 1, 1)
	local data = string.sub(data, 2)
	if code == "s" then
		local playerCount, playerList = string.match(data, "^(%d+%/%d+)%:(.*)") -- 1/10:player1,player2
		UI.setPlayerCount(playerCount)
		UI.updatePlayersList(playerList)
	elseif code == "n" then
		UI.setNickname(data)
		MPConfig.setNickname(data)
	end
end

--- Quit the multiplayer session.
-- @tparam string reason The reason for quitting the session.
-- @usage `MPGameNetwork.quitMP(<reason>)`
local function quitMP(reason)
	local text = reason~="" and ("Reason: ".. reason) or ""
	log('M','quitMP',"Quit MP Called! reason: "..tostring(reason))

	UI.showMdDialog({
		dialogtype="alert", title="You have been disconnected from the server", text=text, okText="Return to menu",
		okLua="MPCoreNetwork.leaveServer(true)" -- return to main menu when clicking OK
	})
end

-------------------------------------------------------------------------------
-- Events System
-------------------------------------------------------------------------------

--- Handles events triggered by TriggerClientEvent.
-- @tparam string p - The event data to be parsed and handled. Should be in the format ":<NAME>:<DATA>"
-- @usage `MPGameNetwork.CallEvent(<event data string>)
local function handleEvents(p)  --- code=E  p=:<NAME>:<DATA>
	local eventName, eventData = string.match(p,"^%:([^%:]+)%:(.*)")
	if not eventName then quitMP(p) return end
	for i=1,#eventTriggers do
		if eventTriggers[i].name == eventName then
			if type(eventTriggers[i].func) == "function" then eventTriggers[i].func(eventData) end
		end
	end
end

--- Triggers a server event with the specified name and data.
-- @tparam string name - The name of the event
-- @tparam string data - The data to be sent with the event
-- @usage `TriggerServerEvent(<name>, <data>)`
function TriggerServerEvent(name, data)
	sendData('E:'..name..':'..data)
end

--- Triggers a client event with the specified name and data.
-- @tparam string name - The name of the event
-- @tparam string data - The data to be sent with the event
-- @usage `TriggerClientEvent(<name>, <data>)`
function TriggerClientEvent(name, data)
	handleEvents(':'..name..':'..data)
end

--- Adds an event handler for the specified event name and function.
-- @tparam string n - The name of the event
-- @tparam function f - The event handler function
-- @usage `AddEventHandler(<name>, function (<data>) ... end)`
function AddEventHandler(n, f)
	log('M', 'AddEventHandler', "Adding Event Handler: Name = "..tostring(n))
	if type(f) ~= "function" or f == nop then
		log('W', 'AddEventHandler', "Event handler function can not be nil")
	else
		table.insert(eventTriggers, {name = n, func = f})
	end
end

-------------------------------------------------------------------------------
-- Keypress handling
-------------------------------------------------------------------------------

--- Sets a function to be called when the specified key is pressed.
-- @tparam string keyname - The name of the key
-- @tparam function f - The function to be called when the key is pressed
-- @usage `onKeyPressed("NUMPAD1", function (<data>) ... end)`
function onKeyPressed(keyname, f)
	addKeyEventListener(keyname, f, 'down')
end

--- Sets a function to be called when the specified key is released.
-- @tparam string keyname - The name of the key
-- @tparam function f - The function to be called when the key is released
-- @usage `onKeyPressed("NUMPAD1", function (<data>) ... end)`
function onKeyReleased(keyname, f)
	addKeyEventListener(keyname, f, 'up')
end

--- Adds a key event listener for the specified key and function.
-- @tparam string keyname - The name of the key
-- @tparam function f - The function to be called when the key event is triggered
-- @tparam string type - The type of key event ('down', 'up', or 'both')
-- @usage `addKeyEventListener("NUMPAD1", function (<data>) ... end, "up")`
function addKeyEventListener(keyname, f, type)
	f = f or function() end
	log('W','addKeyEventListener', "Adding a key event listener for key '"..keyname.."'")
	table.insert(keypressTriggers, {key = keyname, func = f, type = type or 'both'})
	table.insert(keysToPoll, keyname)

	be:queueAllObjectLua("if true then addKeyEventListener(".. serialize(keysToPoll) ..") end")
end

--- Handles the state change of a key.
-- @tparam string key - The name of the key
-- @tparam boolean state - The state of the key ('true' for pressed, 'false' for released)
-- @usage INTERNAL ONLY / GAME SPECIFIC
local function onKeyStateChanged(key, state)
	keyStates[key] = state
	--dump(keyStates)
	--dump(keypressTriggers)
	for i=1,#keypressTriggers do
		if keypressTriggers[i].key == key and (keypressTriggers[i].type == 'both' or keypressTriggers[i].type == (state and 'down' or 'up')) then
			keypressTriggers[i].func(state)
		end
	end
end

--- Returns the state of the specified key.
-- @tparam string key - The name of the key
-- @return boolean - The state of the key ('true' for pressed, 'false' for released)
-- @usage `local state = getKeyState('NUMPAD1')`
function getKeyState(key)
	return keyStates[key] or false
end

--- Handles the event when a vehicle is ready.
-- @tparam integer gameVehicleID - The ID of the game vehicle
-- @usage `MPGameNetwork.onVehicleReady(<game vehicle id>)`
local function onVehicleReady(gameVehicleID)
	local veh = be:getObjectByID(gameVehicleID)
	if not veh then
		log('R', 'onVehicleReady', 'Vehicle does not exist!')
		return
	end
	veh:queueLuaCommand("addKeyEventListener(".. serialize(keysToPoll) ..")")
end

-------------------------------------------------------------------------------

local HandleNetwork = {
	['V'] = function(params) MPInputsGE.handle(params) end, -- inputs and gears
	['W'] = function(params) MPElectricsGE.handle(params) end,
	['X'] = function(params) nodesGE.handle(params) end, -- currently disabled
	['Y'] = function(params) MPPowertrainGE.handle(params) end, -- powertrain related things like diff locks and transfercases
	['Z'] = function(params) positionGE.handle(params) end, -- position and velocity
	['O'] = function(params) MPVehicleGE.handle(params) end, -- all vehicle spawn, modification and delete events, couplers
	['P'] = function(params) MPConfig.setPlayerServerID(params) end,
	['J'] = function(params) MPUpdatesGE.onPlayerConnect() UI.showNotification(params) end, -- A player joined
	['L'] = function(params) UI.showNotification(params) end, -- Display custom notification
	['S'] = function(params) sessionData(params) end, -- Update Session Data
	['E'] = function(params) handleEvents(params) end, -- Event For another Resource
	['T'] = function(params) quitMP(params) end, -- Player Kicked Event (old, doesn't contain reason)
	['K'] = function(params) quitMP(params) end, -- Player Kicked Event (new, contains reason)
	['C'] = function(params) UI.chatMessage(params) end, -- Chat Message Event
}


local heartbeatTimer = 0

--- onUpdate is called each game frame by the games engine. It is used to run scripts in a loop such as getting data from the network buffer.
-- @tparam integer delta time
-- @usage INTERNAL ONLY / GAME SPECIFIC
local function onUpdate(dt)
	--====================================================== DATA RECEIVE ======================================================
	if launcherConnected then
		while(true) do
			local received, status, partial = TCPSocket:receive() -- Receive data
			if received == nil or received == "" then break end

			if settings.getValue("showDebugOutput") == true then
				log('M', 'onUpdate', 'Receiving Data ('..#received..'): '..received)
			end

			-- break it up into code + data
			local code = string.sub(received, 1, 1)
			local data = string.sub(received, 2)
			HandleNetwork[code](data)

			if MPDebug then MPDebug.packetReceived(#received) end
		end
	end
	if heartbeatTimer >= 1 and MPCoreNetwork.isMPSession() then --TODO: something
		heartbeatTimer = 0
		sendData('A')
	end
end


--- Return whether the launcher is connected to the game or not.
-- @treturn[1] boolean Return the connection state of TCP with the launcher
-- @usage `local connected = MPGameNetwork.isLauncherConnected()`
local function isLauncherConnected()
	return launcherConnected
end

--- Return the launcher connection status.
-- @treturn[1] boolean Return the connection state of TCP with the launcher
-- @usage `local status = MPGameNetwork.connectionStatus()`
local function connectionStatus() --legacy, here because some mods use it
	return launcherConnected and 1 or 0
end

detectGlobalWrites() -- reenable global write notifications


--events
M.onUpdate = onUpdate
M.onKeyStateChanged = onKeyStateChanged

--functions
M.launcherConnected   = isLauncherConnected
M.connectionStatus    = connectionStatus --legacy
M.connectToLauncher   = connectToLauncher
M.disconnectLauncher  = disconnectLauncher
M.send                = sendData
M.CallEvent           = handleEvents
M.quitMP              = quitMP

M.addKeyEventListener = addKeyEventListener -- takes: string keyName, function listenerFunction
M.getKeyState         = getKeyState         -- takes: string keyName
M.onVehicleReady      = onVehicleReady

return M
