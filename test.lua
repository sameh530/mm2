-- STANDALONE READABLE AUTOFARM
-- Derived ONLY from the readable stage3 body, not any obfuscated payload.
-- No arbitrary HTTP, downloaded code, trade remotes, or file/clipboard access.
-- Roblox image assets remain. Halloween bag capacity is 50 for everyone.
-- Murderer detection optionally queries the game's GetPlayerData role data.
-- All toggles start OFF. Auto Respawn kills your character when the bag is full.
-- Use only where permitted. Client automation may violate game rules.
-- This file cannot make an untrusted executor safe.
-- Compiled with a real Lua compiler and run in a simulated Roblox session;
-- NOT yet tested inside a live Roblox game.
--
-- v2 changes:
--  * Farming pauses ("BAG FULL") when the bag is full and Auto Respawn is off,
--    instead of flying between coins that can no longer be collected.
--  * Character parts are cached for noclip instead of GetDescendants every frame.
--  * Full-workspace radar sweep throttled 3s -> 8s (events still catch spawns).
--  * Per Hour is based on active farming time; session clock shows hours.
--  * One Died connection per character (no connection pile-up across respawns).
--  * RightControl hides/shows the GUI.
--
-- v14: FIX - the fallback bag scan could read the lobby's total coin balance
--      as the bag ("1234 / 50"): it paused farming, inflated Collected and
--      could make Auto Respawn kill the character. Values above the bag
--      capacity are now rejected.
-- v13: FIX - the script exceeded Luau's limit of 200 local variables per
--      function and could not compile (the original file had the same
--      problem). Interface objects now live in one table `W`; behaviour is
--      unchanged. Verified with a real Lua compiler and a simulated session.
-- v12: bag text parser checks the object type before walking its ancestors;
--      hovered active rows keep their red tint.
-- v11: mobile button moved right (no overlap); keybinds hidden on phones;
--      device-aware restore message; guard for duplicate saved keys.
-- v10: floating round button on phones/tablets (tap = hide/show, drag = move).
-- v9: red and black theme; active rows highlighted; full bag highlighted; round logo picture (amo_logo.png, see LOGO_ASSET_ID).
-- v8: header shows "عمو مغوليتشريب"; shadow + glow, animated gradients,
--     tab hover and underline.
-- v7: Esc cancels key capture; round-over check computed once per frame;
--     round-end coin observation throttled to 10x/s; dead code removed.
-- v6: tabs (Farm / Stats / Settings), round stats, activity log,
--     rebindable keys.
--
-- FILE MAP (search for these headers):
--   SETTINGS + NOTIFICATIONS ......... settings file, notify()
--   ANTI FLING / ANTI VOID / ANTI AFK  protection loops
--   INTERFACE (v6 ...) ............... window, tabs, Farm tab toggles
--   INTERFACE BAG SCANNER ............ reads the bag counter from the game GUI
--   Optional MM2 read-only role query  murderer lookup (fling test)
--   Experimental client-side contact . fling test (unchanged original)
--   Stats tab / Settings tab ......... statistics, log, keybinds, reset
--   WINDOW SIZE, SCALE, TABS, DRAG ... layout and dragging
--   MINIMIZE / CLOSE / HOTKEYS ....... buttons and keyboard shortcuts
--   LIVE UPDATES ..................... per-frame stats/status refresh
--   SAVE / RESTORE SETTINGS .......... what is remembered between runs
--   FILING ........................... multi-fling GUI (separate window)


local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VirtualUser = game:GetService("VirtualUser")

if not RunService:IsClient() then
    return
end

local player = Players.LocalPlayer
while not player do
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    player = Players.LocalPlayer
end


local uiInstanceNew = Instance.new

local GUI_NAME = "SkoblikoHalloweenGUI" -- same name: rerunning replaces the old window

-- v3 interface: drawn entirely in code (no image assets).
local UI = {
    Width = 340,
    HeaderHeight = 54,
    Padding = 14,
    Gap = 10,
    MinScale = 0.55,
    ToggleKey = Enum.KeyCode.RightControl, -- hide / show the window
    FarmKey = Enum.KeyCode.F6,             -- turn Auto Farm on / off (RightShift is shift-lock)
    SettingsFile = "MM2Autofarm_settings.json",
}
local BAG_LIMIT_DEFAULT = 50 -- Halloween: 50 for everyone; no gamepass required.
local MAX_FARM_DISTANCE = 180
-- Executor touch spoof: lets the character stay deep under the map while the
-- coin hitbox is still triggered remotely.
local fireTouch = (typeof(firetouchinterest) == "function" and firetouchinterest)
    or (typeof(firetouchtransmitter) == "function" and firetouchtransmitter)
    or nil
-- Stay deep under the map when touch spoofing works, gentle offset otherwise.
-- No anti-cheat or account-ban safety guarantee.
local FLY_BELOW_OFFSET = fireTouch and 2.8 or 0.75
-- Original camera occlusion mode, restored when farming stops.
local originalOcclusionMode = player.DevCameraOcclusionMode

-- Red and black: deep black surfaces with a slight red tint, one strong red accent.
local Theme = {
    Background = Color3.fromRGB(9, 8, 9),
    Surface = Color3.fromRGB(20, 16, 17),
    SurfaceHover = Color3.fromRGB(30, 22, 24),
    Stroke = Color3.fromRGB(48, 30, 33),
    Track = Color3.fromRGB(44, 32, 35),
    Accent = Color3.fromRGB(229, 31, 46),
    AccentSoft = Color3.fromRGB(255, 104, 110),
    AccentAlt = Color3.fromRGB(122, 8, 20),
    TitleShine = Color3.fromRGB(255, 205, 205),
    ActiveRow = Color3.fromRGB(34, 14, 17),
    ActiveRowHover = Color3.fromRGB(44, 18, 22),
    Text = Color3.fromRGB(245, 240, 241),
    Muted = Color3.fromRGB(160, 140, 143),
    Faint = Color3.fromRGB(104, 86, 89),
    Good = Color3.fromRGB(74, 222, 128),
    Warn = Color3.fromRGB(250, 204, 21),
    Bad = Color3.fromRGB(255, 82, 82),
}
-- Names still used by the untouched fling section.
Theme.Navy = Theme.Surface
Theme.White = Theme.Text

-- Interface objects and helpers live in ONE table. Luau allows at most
-- 200 local variables per function; as separate top-level locals the
-- script exceeded that and could not compile.
local W = {}

local function create(className, properties, parent)
    local object = uiInstanceNew(className)
    for property, value in pairs(properties or {}) do
        object[property] = value
    end
    object.Parent = parent
    return object
end

local function addCorner(parent, radius)
    return create("UICorner", { CornerRadius = UDim.new(0, radius) }, parent)
end

local function addStroke(parent, color, thickness, transparency)
    return create("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Color = color,
        Thickness = thickness or 1,
        Transparency = transparency or 0,
    }, parent)
end

local function addGradient(parent, colors, rotation, transparency)
    local keypoints = {}
    for index, entry in ipairs(colors) do
        keypoints[index] = ColorSequenceKeypoint.new(entry[1], entry[2])
    end
    return create("UIGradient", {
        Color = ColorSequence.new(keypoints),
        Rotation = rotation or 0,
        Transparency = transparency or NumberSequence.new(0),
    }, parent)
end

local activeTweens = setmetatable({}, { __mode = "k" })
local function smoothTween(object, duration, goals, style, direction)
    -- Only cancel a running tween of the SAME properties (e.g. a Size tween
    -- must not stop a Position tween on the same window).
    local names = {}
    for property in pairs(goals) do table.insert(names, property) end
    table.sort(names)
    local slot = table.concat(names, ",")
    local perObject = activeTweens[object]
    if not perObject then
        perObject = {}
        activeTweens[object] = perObject
    end
    if perObject[slot] then
        perObject[slot]:Cancel()
    end
    local animation = TweenService:Create(
        object,
        TweenInfo.new(
            duration or 0.28,
            style or Enum.EasingStyle.Sine,
            direction or Enum.EasingDirection.Out
        ),
        goals
    )
    perObject[slot] = animation
    animation.Completed:Once(function()
        if perObject[slot] == animation then
            perObject[slot] = nil
        end
    end)
    animation:Play()
    return animation
end

local guiParent = player:WaitForChild("PlayerGui")
-- Replace either edition on rerun; destroying it also invokes its cleanup.
for _, previousName in ipairs({ GUI_NAME, "SkoblikoSummerNeonGUI" }) do
    local previous = guiParent:FindFirstChild(previousName)
    if previous then
        previous:Destroy()
    end
end

local state = {
    alive = true,
    closing = false,
    minimized = false,
    autofarm = false,
    farmSpeed = 25,
    farmed = 0,
    dieOnFullBag = false,
    protection = false,
    flingEnabled = false,
    flingActive = false,
    farmPaused = false,
    pauseReason = "",
    bagCount = 0,
    bagLimit = BAG_LIMIT_DEFAULT,
    bagFound = false,
    sessionStarted = os.clock(),
    activeFarmTime = 0, -- seconds actually spent with Auto Farm ON
}

-- Cached BaseParts of the current character (rebuilt only when it changes).
local partCache = { character = nil, parts = {}, dirty = true }
local function getCharacterParts(character)
    if partCache.character ~= character then
        partCache.character = character
        partCache.dirty = true
    end
    if partCache.dirty then
        local parts = {}
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then table.insert(parts, part) end
        end
        partCache.parts = parts
        partCache.dirty = false
    end
    return partCache.parts
end

local function isBagFull()
    return state.bagFound and state.bagLimit > 0 and state.bagCount >= state.bagLimit
end

-- Bag / auto-respawn state (declared early: the farm loop reads it too).
local bagKillTriggered = false
local bagCheckEnabledAt = 0
local bagFullConfirmations = 0
local bagResetArmed = false

-- True only when a full bag is really about to be emptied by Auto Respawn.
-- A bag that was already full when farming started is never "armed", so it
-- will not reset; the farm must pause instead of chasing dead pickups.
local function bagWillReset()
    return state.dieOnFullBag and bagResetArmed
end

local connections = {}
local characterConnections = {} -- replaced on every respawn
local farmConnection
local cameraConnection
local cleaned = false
local cancelFling = function() end
local cleanupRadar = function() end -- assigned when the registry is created
local collisionCache = {}
local humanoidCache = setmetatable({}, { __mode = "k" })

local function connect(signal, callback)
    local connection = signal:Connect(callback)
    if not state.alive then
        connection:Disconnect()
        return connection
    end
    table.insert(connections, connection)
    return connection
end

local function restoreCharacter()
    -- Camera noclip off: restore the original camera occlusion mode.
    pcall(function()
        player.DevCameraOcclusionMode = originalOcclusionMode
    end)

    local character = player.Character
    for humanoid, saved in pairs(humanoidCache) do
        if humanoid.Parent then
            humanoid.PlatformStand = saved.PlatformStand
            humanoid.AutoRotate = saved.AutoRotate
        end
        humanoidCache[humanoid] = nil
    end

    for part, oldCanCollide in pairs(collisionCache) do
        if part and part.Parent then
            part.CanCollide = oldCanCollide
        end
    end
    table.clear(collisionCache)
end

local function cleanup()
    if cleaned then return end
    cleaned = true
    cancelFling()
    cleanupRadar()
    state.alive = false
    state.autofarm = false
    restoreCharacter()

    if cameraConnection then
        cameraConnection:Disconnect()
        cameraConnection = nil
    end
    if farmConnection then
        farmConnection:Disconnect()
        farmConnection = nil
    end
    for _, connection in ipairs(connections) do
        connection:Disconnect()
    end
    table.clear(connections)
    for _, connection in ipairs(characterConnections) do
        connection:Disconnect()
    end
    table.clear(characterConnections)
end

-- Autofarm: accept live pickups, not invisible pre-spawn or leftover hitboxes.
local coinBlacklist = {}
local coinTouchFails = setmetatable({}, { __mode = "k" })
local deadCoins = setmetatable({}, { __mode = "k" })
local coinPresence = setmetatable({}, { __mode = "k" })
local roundRetiredCoins = setmetatable({}, { __mode = "k" })
local currentTarget
local retargetAccumulator = 0
local farmIdle = false
local roundEnded = false

-- Only explicit currency containers/names are eligible. Generic "Server"
-- parts, clustered map decorations and arbitrary small parts are not pickups.
local PICKUP_CONTAINERS = {
    coincontainer = true, candycontainer = true, tokencontainer = true,
    eggcontainer = true, giftcontainer = true, beachballcontainer = true,
}
local PICKUP_NAMES = {
    coin = true, candy = true, token = true, egg = true,
    snow = true, gift = true, present = true, beachball = true,
    shell = true, star = true, gem = true,
}
local coinSet = {}
local trackedContainers = {}
local lastRadarSweep = -math.huge
local registryVersion = 0

local function isPickupContainer(container)
    return (container:IsA("Folder") or container:IsA("Model"))
        and PICKUP_CONTAINERS[string.lower(container.Name)] == true
        and container:IsDescendantOf(workspace)
end

local function isCoinPart(coin)
    if not coin:IsA("BasePart") then return false end
    -- Live Halloween pickup: Coin_Server with CoinID="Candy" and a CoinVisual child.
    local coinID=coin:GetAttribute("CoinID")
    if type(coinID)=="string" and PICKUP_NAMES[string.lower(coinID)] then return true end
    local name = string.lower(coin.Name)
    local currency = string.match(name, "^(%a+)_server$") or name
    return PICKUP_NAMES[currency] == true
end

local function isVisiblePart(part)
    return part.Transparency < 0.99 and part.LocalTransparencyModifier < 0.99
end

local function hasPickupVisual(coin)
    if isVisiblePart(coin) then return true end
    -- An invisible hitbox may carry visible client-side geometry. A
    -- TouchTransmitter, attachment or empty mesh alone is not a visible coin.
    for _, child in ipairs(coin:GetDescendants()) do
        if child:IsA("BasePart") and isVisiblePart(child) then
            return true
        end
    end
    return false
end

local function isCoinAvailable(coin)
    if not coin or not coinSet[coin] or not isCoinPart(coin)
        or not coin:IsDescendantOf(workspace)
        or not coin.Parent or not trackedContainers[coin.Parent]
        or not isPickupContainer(coin.Parent) then
        return false
    end
    -- Collected hitboxes can remain touchable after their candy has disappeared.
    local visual=coin:FindFirstChild("CoinVisual")
    local collected=coin:GetAttribute("Collected")==true
        or (visual and visual:GetAttribute("Collected")==true)
    local present = not collected and coin.CanTouch and hasPickupVisual(coin)
    local previousPresence = coinPresence[coin]
    coinPresence[coin] = present
    if not present then return false end
    if previousPresence == false then
        -- A genuinely hidden/disabled pickup became live again (pooled instance).
        deadCoins[coin] = nil
        coinTouchFails[coin] = nil
        coinBlacklist[coin] = nil
        roundRetiredCoins[coin] = nil
    end
    return not deadCoins[coin] and not roundRetiredCoins[coin]
end

local function registerCoin(coin)
    if isCoinPart(coin) and not coinSet[coin] then
        coinSet[coin] = true
        registryVersion += 1
    end
end

local function unregisterCoin(coin)
    if coinSet[coin] then registryVersion += 1 end
    coinSet[coin] = nil
    coinBlacklist[coin] = nil
    coinTouchFails[coin] = nil
    deadCoins[coin] = nil
    coinPresence[coin] = nil
    roundRetiredCoins[coin] = nil
    if currentTarget == coin then currentTarget = nil end
end

local function unwatchContainer(container)
    local entry = trackedContainers[container]
    if not entry then return end
    trackedContainers[container] = nil
    for _, connection in ipairs(entry) do connection:Disconnect() end
    for coin in pairs(coinSet) do
        if coin.Parent == container or not coin:IsDescendantOf(workspace) then
            unregisterCoin(coin)
        end
    end
    registryVersion += 1
end

local function watchContainer(container)
    if trackedContainers[container] or not isPickupContainer(container) then return end
    local entry = {}
    trackedContainers[container] = entry
    table.insert(entry, container.ChildAdded:Connect(registerCoin))
    table.insert(entry, container.ChildRemoved:Connect(unregisterCoin))
    table.insert(entry, container.AncestryChanged:Connect(function()
        if not container:IsDescendantOf(workspace) then unwatchContainer(container) end
    end))
    for _, coin in ipairs(container:GetChildren()) do registerCoin(coin) end
    registryVersion += 1
end

cleanupRadar = function()
    for container in pairs(trackedContainers) do unwatchContainer(container) end
    table.clear(coinSet)
    table.clear(coinBlacklist)
    table.clear(coinPresence)
    table.clear(coinTouchFails)
    table.clear(deadCoins)
    table.clear(roundRetiredCoins)
    currentTarget = nil
end

local function radarSweep(force)
    if not force and os.clock() - lastRadarSweep < 8 then return end
    lastRadarSweep = os.clock()
    for container in pairs(trackedContainers) do
        if not isPickupContainer(container) then unwatchContainer(container) end
    end
    for coin in pairs(coinSet) do
        if not coin:IsDescendantOf(workspace) or not trackedContainers[coin.Parent] then
            unregisterCoin(coin)
        end
    end
    -- Initial/throttled discovery handles nested maps. Event hooks handle spawns.
    for _, object in ipairs(workspace:GetDescendants()) do
        if isPickupContainer(object) then watchContainer(object) end
    end
end

connect(workspace.DescendantAdded, function(object)
    if isPickupContainer(object) then watchContainer(object) end
end)
radarSweep(true)



-- Cluster-aware pick: prefer close coins sitting in dense groups, so the
-- route sweeps whole clusters instead of zigzagging across the map.
local CLUSTER_RADIUS = 24
local CLUSTER_BONUS = 7

-- Perf: the picker briefly reuses its last result (no full rescan every
-- frame while idle), caches part positions once per scan instead of touching
-- the .Position property O(n^2) times, and prunes candidates that cannot
-- mathematically beat the current best. Selection results are identical.
local lastPickTime = -math.huge
local lastPickCoin = nil
local lastPickScore = math.huge
local lastPickHadResult = false
local lastPickVersion = -1

local function findClosestItem(rootPart)
    local now = os.clock()

    if now - lastPickTime < 0.15 and lastPickVersion == registryVersion then
        if not lastPickHadResult then
            return nil, math.huge, math.huge
        end
        local cached = lastPickCoin
        if isCoinAvailable(cached) and not coinBlacklist[cached]
            and (cached.Position - rootPart.Position).Magnitude <= MAX_FARM_DISTANCE then
            return cached, (cached.Position - rootPart.Position).Magnitude, lastPickScore
        end
    end
    lastPickTime = now

    for coin, timestamp in pairs(coinBlacklist) do
        if not coin.Parent or now - timestamp > 1.5 then
            coinBlacklist[coin] = nil
        end
    end

    radarSweep(false)

    local candidates = {}
    for coin in pairs(coinSet) do
        if isCoinAvailable(coin) and not coinBlacklist[coin]
            and (coin.Position - rootPart.Position).Magnitude <= MAX_FARM_DISTANCE then
            table.insert(candidates, coin)
        end
    end
    -- No HTTP/helper execution inside the pickup search loop.
    local count = #candidates
    local rootPosition = rootPart.Position
    local positions = table.create(count)
    local distances = table.create(count)
    local order = table.create(count)
    for index = 1, count do
        local position = candidates[index].Position
        positions[index] = position
        distances[index] = (position - rootPosition).Magnitude
        order[index] = index
    end
    table.sort(order, function(a, b)
        return distances[a] < distances[b]
    end)

    local best, bestDistance, bestScore = nil, math.huge, math.huge
    local maxBonus = 6 * CLUSTER_BONUS
    for _, index in ipairs(order) do
        local distance = distances[index]
        if distance - maxBonus >= bestScore then
            break -- Even a max cluster bonus cannot beat the current best.
        end
        local position = positions[index]
        local neighbors = 0
        for otherIndex = 1, count do
            if otherIndex ~= index and (positions[otherIndex] - position).Magnitude <= CLUSTER_RADIUS then
                neighbors += 1
                if neighbors >= 6 then
                    break -- The cluster bonus is capped at 6 neighbours.
                end
            end
        end
        local score = distance - neighbors * CLUSTER_BONUS
        if score < bestScore then
            best = candidates[index]
            bestDistance = distance
            bestScore = score
        end
    end

    lastPickVersion = registryVersion
    lastPickCoin = best
    lastPickScore = bestScore
    lastPickHadResult = best ~= nil

    return best, bestDistance, bestScore
end

local SCOREBOARD_NAMES = { "Scoreboard", "Scoreboard_Phone" }
local function scanRoundOver()
    -- The end-of-round scoreboard (Scoreboard / Scoreboard_Phone) becomes
    -- visible when the round finishes; farming must pause immediately.
    for _, guiName in ipairs(SCOREBOARD_NAMES) do
        local scoreboard = guiParent:FindFirstChild(guiName)
        if scoreboard and scoreboard:IsA("ScreenGui") and scoreboard.Enabled then
            for _, modeFrame in ipairs(scoreboard:GetChildren()) do
                if modeFrame:IsA("GuiObject") and modeFrame.Visible then
                    return true
                end
            end
        end
    end
    return false
end

-- Called from many places every frame (farm loop, role query, fling test,
-- stats). Scan the GUI once per frame and reuse the answer.
local roundOverFrame, roundOverValue = -1, false
local frameCounter = 0
connect(RunService.Heartbeat, function() frameCounter += 1 end)
local function isRoundOver()
    if roundOverFrame ~= frameCounter then
        roundOverFrame = frameCounter
        roundOverValue = scanRoundOver()
    end
    return roundOverValue
end
local lastRoundEndObserve = -math.huge

farmConnection = RunService.Heartbeat:Connect(function(deltaTime)
    if not state.alive then return end

    if state.flingActive then return end
    if not state.autofarm then
        state.farmPaused = false
        state.pauseReason = ""
        return
    end

    local character = player.Character
    if not character then
        state.farmPaused = true
        state.pauseReason = "RESPAWN"
        return
    end

    local rootPart = character:FindFirstChild("HumanoidRootPart")
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid or humanoid.Health <= 0 then
        state.farmPaused = true
        state.pauseReason = "RESPAWN"
        return
    end

    -- Round finished: stop moving and stop counting until the next round.
    if isRoundOver() then
        if not roundEnded then
            roundEnded = true
            radarSweep(true)
            for coin in pairs(coinSet) do roundRetiredCoins[coin] = true end
            registryVersion += 1
        end
        -- Observe disabled/hidden pooled pickups while the scoreboard is up
        -- (10x per second is plenty; every frame cost a full scan of all coins).
        if os.clock() - lastRoundEndObserve >= 0.1 then
            lastRoundEndObserve = os.clock()
            for coin in pairs(coinSet) do isCoinAvailable(coin) end
        end
        currentTarget = nil
        state.farmPaused = true
        state.pauseReason = "ROUND END"
        restoreCharacter()
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        return
    end

    roundEnded = false

    -- Bag full and no Auto Respawn: nothing more can be collected this life.
    -- Stop flying and hand control back once, instead of touching dead coins.
    if isBagFull() and not bagWillReset() then
        currentTarget = nil
        state.farmPaused = true
        state.pauseReason = "BAG FULL"
        if not farmIdle then
            farmIdle = true
            restoreCharacter()
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
        end
        return
    end

    -- Revalidate the live target every frame, not just its Parent reference.
    if not isCoinAvailable(currentTarget) or coinBlacklist[currentTarget] then
        local candidate, candidateDistance = findClosestItem(rootPart)

        if candidate and candidateDistance <= MAX_FARM_DISTANCE then
            currentTarget = candidate
            state.farmPaused = false
            state.pauseReason = ""
        else
            currentTarget = nil
            state.farmPaused = true
            state.pauseReason = candidate and "TOO FAR" or "WAITING"
        end
    end

    -- Mid-flight retarget: if a clearly better coin appeared (fresh spawn or
    -- a dense cluster nearby), switch to it instead of finishing a bad route.
    retargetAccumulator += deltaTime
    if currentTarget and retargetAccumulator >= 0.5 then
        retargetAccumulator = 0
        local candidate, candidateDistance, candidateScore = findClosestItem(rootPart)
        if candidate and currentTarget and candidate ~= currentTarget and candidateDistance <= MAX_FARM_DISTANCE then
            local currentDistance = (currentTarget.Position - rootPart.Position).Magnitude
            -- Hysteresis: never abandon a coin we are about to grab -
            -- that caused the annoying last-moment turn-aways.
            if currentDistance > 15 and candidateScore + 12 < currentDistance then
                currentTarget = candidate
            end
        end
    end

    local target = currentTarget
    if not isCoinAvailable(target) then
        currentTarget = nil
        state.farmPaused = true
        state.pauseReason = "WAITING"
        -- Nothing to farm on the map: switch off temporarily. Restore the
        -- character ONCE and give control back to the player instead of
        -- freezing them every frame; farming resumes by itself as soon as
        -- the radar sees new pickups.
        if not farmIdle then
            farmIdle = true
            restoreCharacter()
            rootPart.AssemblyLinearVelocity = Vector3.zero
            rootPart.AssemblyAngularVelocity = Vector3.zero
        end
        return
    end
    farmIdle = false

    local targetPosition = target.Position - Vector3.new(0, FLY_BELOW_OFFSET, 0)
    local offset = targetPosition - rootPart.Position
    local distance = offset.Magnitude

    if distance > MAX_FARM_DISTANCE then
        currentTarget = nil
        state.farmPaused = true
        state.pauseReason = "TOO FAR"
        restoreCharacter()
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        return
    end

    state.farmPaused = false
    state.pauseReason = ""

    -- Camera noclip: the map between the camera and the character becomes
    -- see-through, so everything can be watched from above while farming.
    if player.DevCameraOcclusionMode ~= Enum.DevCameraOcclusionMode.Invisicam then
        pcall(function()
            player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
        end)
    end

    -- Original working noclip behavior, only while a nearby target exists.
    for _, part in ipairs(getCharacterParts(character)) do
        if part.Parent then
            if collisionCache[part] == nil then
                collisionCache[part] = part.CanCollide
            end
            part.CanCollide = false
        end
    end

    if not humanoidCache[humanoid] then
        humanoidCache[humanoid] = {
            PlatformStand = humanoid.PlatformStand,
            AutoRotate = humanoid.AutoRotate,
        }
    end
    humanoid.PlatformStand = true
    rootPart.AssemblyLinearVelocity = Vector3.zero
    rootPart.AssemblyAngularVelocity = Vector3.zero

    if distance <= 0.45 then
        -- Reach the coin hitbox from under the map.
        if fireTouch then
            pcall(fireTouch, rootPart, target, 0)
            pcall(fireTouch, rootPart, target, 1)
        end
        coinBlacklist[target] = os.clock()
        -- A real coin disappears right after a touch. One that survives
        -- several touch rounds is a dead hitbox - retire it for good.
        -- Never count failures while the bag is full: nothing can be
        -- collected then and every coin would get wrongly retired.
        if not isBagFull() then
            coinTouchFails[target] = (coinTouchFails[target] or 0) + 1
            if coinTouchFails[target] >= 3 then
                deadCoins[target] = true
            end
        end
        currentTarget = nil
        return
    end

    if distance <= 0.001 then return end

    local safeDelta = math.min(deltaTime, 1 / 30)
    local step = math.min(state.farmSpeed * safeDelta, math.max(distance - 0.1, 0))
    local nextPosition = rootPart.Position + offset.Unit * step

    -- Static horizontal pose: the body always stays perfectly flat.
    -- Only the yaw (horizontal heading) follows the coin, so there is no
    -- rocking/tilting when approaching a coin from above or below.
    local flatOffset = Vector3.new(offset.X, 0, offset.Z)
    if flatOffset.Magnitude > 0.05 then
        rootPart.CFrame = CFrame.lookAt(nextPosition, nextPosition + flatOffset.Unit) * CFrame.Angles(-math.pi / 2, 0, 0)
    else
        rootPart.CFrame = rootPart.CFrame.Rotation + nextPosition
    end
end)

-- ================= ANTI FLING / ANTI VOID =================
-- Protection from exploiters: abnormal velocity is cancelled instantly and
-- the character is pulled back onto the last safe spot instead of flying
-- away or falling into the void.
local lastSafePosition = nil
local lastFramePosition = nil
local safePosAccumulator = 0
local voidThreshold = -440
do
    local ok, destroyHeight = pcall(function()
        return workspace.FallenPartsDestroyHeight
    end)
    if ok and typeof(destroyHeight) == "number" then
        voidThreshold = destroyHeight + 80
    end
end

connect(RunService.Heartbeat, function(deltaTime)
    if not state.alive or state.closing or state.flingActive or not state.protection then
        lastSafePosition = nil
        lastFramePosition = nil
        safePosAccumulator = 0
        return
    end

    local character = player.Character
    local rootPart = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not rootPart or not humanoid or humanoid.Health <= 0 then return end

    local farmingActively = state.autofarm and not state.farmPaused

    -- ANTI FLING: the fling simply fails. Abnormal velocity is cancelled
    -- and the character stays exactly where it was one frame ago, so the
    -- farm keeps running as if nothing happened. Vertical speed is checked
    -- separately so normal jumps and falls never trigger the protection.
    local velocity = rootPart.AssemblyLinearVelocity
    local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    local flingLimit = farmingActively and 300 or 120
    if horizontalSpeed > flingLimit
        or velocity.Y > 150
        or velocity.Y < -260
        or rootPart.AssemblyAngularVelocity.Magnitude > 60 then
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        if lastFramePosition then
            rootPart.CFrame = rootPart.CFrame.Rotation + lastFramePosition
        end
    end

    -- Legit game teleport (lobby -> map at round start, respawn): a huge
    -- position jump WITHOUT abnormal velocity. Flings cannot do this - they
    -- work through velocity and get caught above. Accept the teleport and
    -- rebase all anchors so the protection never bounces the player back.
    if lastFramePosition and (rootPart.Position - lastFramePosition).Magnitude > 120 then
        lastFramePosition = rootPart.Position
        lastSafePosition = nil
        safePosAccumulator = 0
    end

    -- ANTI VOID: only below the absolute kill height of the world.
    local inVoid = rootPart.Position.Y < voidThreshold
    if inVoid and lastSafePosition and not farmingActively then
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        rootPart.CFrame = CFrame.new(lastSafePosition + Vector3.new(0, 3, 0))
    end

    -- Remember the last calm, grounded position as the rescue point.
    safePosAccumulator += deltaTime
    if safePosAccumulator >= 0.5 then
        safePosAccumulator = 0
        if not humanoid.PlatformStand
            and humanoid.FloorMaterial ~= Enum.Material.Air
            and rootPart.AssemblyLinearVelocity.Magnitude < 60 then
            lastSafePosition = rootPart.Position
        end
    end

    -- Frame-by-frame anchor for the silent fling rollback.
    lastFramePosition = rootPart.Position
end)

-- ================= ANTI AFK =================
-- Roblox kicks idle players after ~20 minutes. When the game marks the
-- player as idle, a tiny virtual input resets the idle timer, so the farm
-- can run for hours unattended.
connect(player.Idled, function()
    if not state.alive or state.closing or not state.autofarm then return end
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end)



local screenGui = create("ScreenGui", {
    Name = GUI_NAME,
    DisplayOrder = 1000,
    IgnoreGuiInset = true,
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
}, guiParent)

connect(screenGui.AncestryChanged, function(_, parent)
    if parent == nil then
        cleanup()
    end
end)


-- UI sounds use a built-in asset, not a remote loader.
local SoundService = game:GetService("SoundService")
local function playUiSound(speed, volume)
    pcall(function()
        local sound = Instance.new("Sound")
        sound.SoundId = "rbxasset://sounds/button.wav"
        sound.PlaybackSpeed, sound.Volume = speed or 1, volume or 0.45
        sound.PlayOnRemove, sound.Parent = true, SoundService
        sound:Destroy()
    end)
end


-- ================= SETTINGS + NOTIFICATIONS =================
-- Settings are kept in ONE small local JSON file in the executor's workspace
-- folder (only if the executor offers readfile/writefile). Nothing is sent
-- anywhere. Delete the file to go back to defaults.
local HttpService = game:GetService("HttpService")
local StarterGui = game:GetService("StarterGui")
local canSaveFiles = typeof(writefile) == "function" and typeof(readfile) == "function"
    and typeof(isfile) == "function"

local Settings = { data = {}, collect = function() return {} end, pending = false }
if canSaveFiles then
    local ok, loaded = pcall(function()
        if isfile(UI.SettingsFile) then
            return HttpService:JSONDecode(readfile(UI.SettingsFile))
        end
        return nil
    end)
    if ok and type(loaded) == "table" then Settings.data = loaded end
end

-- Debounced: many quick changes produce a single write half a second later.
local function requestSave()
    if not canSaveFiles or Settings.pending then return end
    Settings.pending = true
    task.delay(0.5, function()
        Settings.pending = false
        -- Closing turns farming off on purpose; that must not be remembered.
        if state.closing or not state.alive then return end
        pcall(function()
            writefile(UI.SettingsFile, HttpService:JSONEncode(Settings.collect()))
        end)
    end)
end

-- Phone / tablet without a keyboard: hotkeys can't be used there.
local TOUCH_ONLY = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function notify(title, text, duration)
    pcall(function()
        StarterGui:SetCore("SendNotification", {
            Title = title, Text = text, Duration = duration or 4,
        })
    end)
end

-- ================= INTERFACE (v6: tabs, drawn in code) =================
local function makeLabel(properties, parent)
    local base = {
        BackgroundTransparency = 1, BorderSizePixel = 0, Text = "",
        Font = Enum.Font.GothamMedium, TextSize = 14, TextColor3 = Theme.Text,
        TextXAlignment = Enum.TextXAlignment.Left,
    }
    for key, value in pairs(properties) do base[key] = value end
    return create("TextLabel", base, parent)
end

local function makeSurface(name, height, order, parent)
    local frame = create("Frame", {
        Name = name, BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
        Size = UDim2.new(1, 0, 0, height), LayoutOrder = order,
    }, parent)
    addCorner(frame, 10)
    addStroke(frame, Theme.Stroke, 1, 0)
    return frame
end

local function makeCaption(text, order, parent)
    return makeLabel({
        Name = text .. "Caption", Text = text, Font = Enum.Font.GothamBold, TextSize = 11,
        TextColor3 = Theme.Faint, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = order,
    }, parent)
end

local function formatInteger(value)
    local reversed = string.reverse(string.format("%.0f", value))
    local grouped = string.gsub(reversed, "(%d%d%d)", "%1,")
    return (string.gsub(string.reverse(grouped), "^,", ""))
end

-- Outer frame: position, scale and border. Inner CanvasGroup: content + fade.
local window = create("Frame", {
    Name = "Window", BackgroundTransparency = 1, BorderSizePixel = 0,
    Position = UDim2.fromOffset(24, 120), Size = UDim2.fromOffset(UI.Width, 420),
}, screenGui)
addCorner(window, 14)
W.windowStroke = addStroke(window, Theme.Stroke, 1, 1)
W.uiScale = create("UIScale", { Scale = 1 }, window)

-- Soft shadow + coloured glow behind the window (follow its size, fade with it).
W.SHADOW_LAYERS = {
    { grow = 6, offsetY = 4, color = Color3.new(0, 0, 0), alpha = 0.55 },
    { grow = 14, offsetY = 8, color = Color3.new(0, 0, 0), alpha = 0.78 },
    { grow = 3, offsetY = 0, color = Theme.Accent, alpha = 0.86 },
}
W.shadowFrames = {}
for index, layer in ipairs(W.SHADOW_LAYERS) do
    local frame = create("Frame", {
        Name = "Shadow" .. index, AnchorPoint = Vector2.new(0.5, 0.5),
        BackgroundColor3 = layer.color, BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.new(0.5, 0, 0.5, layer.offsetY),
        Size = UDim2.new(1, layer.grow * 2, 1, layer.grow * 2), ZIndex = 0,
    }, window)
    addCorner(frame, 14 + layer.grow)
    W.shadowFrames[index] = { frame = frame, alpha = layer.alpha }
end
function W.tweenShadows(duration, visible)
    for _, shadow in ipairs(W.shadowFrames) do
        smoothTween(shadow.frame, duration, {
            BackgroundTransparency = visible and shadow.alpha or 1,
        }, Enum.EasingStyle.Quart)
    end
end

W.canvas = create("CanvasGroup", {
    Name = "Canvas", BackgroundColor3 = Theme.Background, BorderSizePixel = 0,
    Size = UDim2.fromScale(1, 1), GroupTransparency = 1, ZIndex = 1,
}, window)
addCorner(W.canvas, 14)
-- Faint red tint across the top of the window. Its own frame: a UIGradient
-- placed on the CanvasGroup itself would tint every child inside it.
W.headerTint = create("Frame", {
    Name = "HeaderTint", BackgroundColor3 = Theme.Accent, BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 120), ZIndex = 0,
}, W.canvas)
addGradient(W.headerTint, { { 0, Color3.new(1, 1, 1) }, { 1, Color3.new(1, 1, 1) } }, 90,
    NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 1) }))

-- Accent bar: red → dark red → red, slowly sliding (animated in LIVE UPDATES).
W.accentBar = create("Frame", {
    Name = "AccentBar", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 3), ZIndex = 5,
}, W.canvas)
W.accentGradient = addGradient(W.accentBar, {
    { 0, Theme.Accent }, { 0.5, Theme.AccentAlt }, { 1, Theme.Accent },
}, 0)

-- Header: logo, title, live subtitle, minimize / close.
W.header = create("Frame", {
    Name = "Header", Active = true, BackgroundTransparency = 1,
    Size = UDim2.new(1, 0, 0, UI.HeaderHeight),
}, W.canvas)

-- Window name shown in the header (Arabic text uses Roblox's font fallback).
W.BRAND_NAME = "عمو مغوليتشريب"
W.BRAND_SUBTITLE = "MM2 Autofarm  ·  Halloween"

-- Logo picture. Roblox can't read an image straight from a script, so:
--   1) LOGO_ASSET_ID: upload amo_logo.png to Roblox (Creator Hub > Decals/Images)
--      and paste the number here, e.g. "rbxassetid://1234567890".
--   2) Otherwise, if the executor supports getcustomasset, put amo_logo.png in
--      the executor's workspace folder and it is loaded from there.
--   3) If neither works, the letter "ع" is shown instead.
local LOGO_ASSET_ID = ""
local LOGO_FILE = "amo_logo.png"

local function resolveLogoImage()
    if LOGO_ASSET_ID ~= "" then return LOGO_ASSET_ID end
    local loader = (typeof(getcustomasset) == "function" and getcustomasset)
        or (typeof(getsynasset) == "function" and getsynasset) or nil
    if loader and typeof(isfile) == "function" then
        local ok, image = pcall(function()
            if isfile(LOGO_FILE) then return loader(LOGO_FILE) end
            return nil
        end)
        if ok and type(image) == "string" and image ~= "" then return image end
    end
    return nil
end

W.LOGO_SIZE = 38
W.logo = create("Frame", {
    Name = "Logo", AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Color3.new(1, 1, 1),
    BorderSizePixel = 0, Position = UDim2.new(0, UI.Padding - 2, 0.5, 1),
    Size = UDim2.fromOffset(W.LOGO_SIZE, W.LOGO_SIZE),
}, W.header)
addCorner(W.logo, 99)
W.logoGradient = addGradient(W.logo, { { 0, Theme.Accent }, { 1, Theme.AccentAlt } }, 45)
-- Red ring around the round picture.
W.logoRing = addStroke(W.logo, Theme.Accent, 2, 0)
W.logoImage = resolveLogoImage()
if W.logoImage then
    local picture = create("ImageLabel", {
        Name = "Picture", BackgroundTransparency = 1, BorderSizePixel = 0,
        Image = W.logoImage, ScaleType = Enum.ScaleType.Crop,
        Size = UDim2.fromScale(1, 1),
    }, W.logo)
    addCorner(picture, 99)
else
    makeLabel({
        Text = "ع", Font = Enum.Font.GothamBlack, TextSize = 20,
        TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1),
    }, W.logo)
end

W.titleLabel = makeLabel({
    Name = "Title", Text = W.BRAND_NAME, Font = Enum.Font.GothamBlack, TextSize = 16,
    TextColor3 = Color3.new(1, 1, 1),
    Position = UDim2.fromOffset(UI.Padding + 46, 9), Size = UDim2.new(1, -156, 0, 20),
    TextTruncate = Enum.TextTruncate.AtEnd,
}, W.header)
-- Sliding light-red shine on the title text (animated in LIVE UPDATES).
W.titleGradient = addGradient(W.titleLabel, {
    { 0, Theme.AccentSoft }, { 0.5, Theme.TitleShine }, { 1, Theme.AccentSoft },
}, 0)
W.subtitle = makeLabel({
    Name = "Subtitle", Text = W.BRAND_SUBTITLE, TextSize = 11, TextColor3 = Theme.Muted,
    Position = UDim2.fromOffset(UI.Padding + 46, 30), Size = UDim2.new(1, -156, 0, 14),
    TextTruncate = Enum.TextTruncate.AtEnd,
}, W.header)

function W.headerButton(name, text, rightOffset, hoverColor)
    local button = create("TextButton", {
        Name = name, AnchorPoint = Vector2.new(1, 0.5), AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface, BackgroundTransparency = 1, BorderSizePixel = 0,
        Position = UDim2.new(1, -rightOffset, 0.5, 1), Size = UDim2.fromOffset(28, 28),
        Text = text, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = Theme.Muted, ZIndex = 3,
    }, W.header)
    addCorner(button, 8)
    connect(button.MouseEnter, function()
        smoothTween(button, 0.15, { BackgroundTransparency = 0, TextColor3 = hoverColor })
    end)
    connect(button.MouseLeave, function()
        smoothTween(button, 0.15, { BackgroundTransparency = 1, TextColor3 = Theme.Muted })
    end)
    return button
end
W.closeButton = W.headerButton("Close", "×", UI.Padding - 2, Theme.Bad)
W.minimizeButton = W.headerButton("Minimize", "–", UI.Padding + 30, Theme.Text)

create("Frame", {
    Name = "Divider", BackgroundColor3 = Theme.Stroke, BorderSizePixel = 0,
    Position = UDim2.new(0, 0, 0, UI.HeaderHeight - 1), Size = UDim2.new(1, 0, 0, 1),
}, W.canvas)

-- ---------- Fixed top area: status row + tab bar (visible on every tab) ----------
W.TAB_BAR_HEIGHT = 32
W.TOP_HEIGHT = 36 + UI.Gap + W.TAB_BAR_HEIGHT
W.PAGE_Y = UI.HeaderHeight + UI.Padding + W.TOP_HEIGHT + UI.Gap

W.topArea = create("Frame", {
    Name = "TopArea", BackgroundTransparency = 1,
    Position = UDim2.fromOffset(UI.Padding, UI.HeaderHeight + UI.Padding),
    Size = UDim2.new(1, -UI.Padding * 2, 0, W.TOP_HEIGHT),
}, W.canvas)

W.statusRow = create("Frame", {
    Name = "Status", BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Size = UDim2.new(1, 0, 0, 36),
}, W.topArea)
addCorner(W.statusRow, 10)
addStroke(W.statusRow, Theme.Stroke, 1, 0)
W.statusDot = create("Frame", {
    Name = "Dot", AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Theme.Bad,
    BorderSizePixel = 0, Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(8, 8),
}, W.statusRow)
addCorner(W.statusDot, 99)
W.statusText = makeLabel({
    Name = "StatusText", Text = "Off", Font = Enum.Font.GothamBold, TextSize = 13,
    TextColor3 = Theme.Bad, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(0.62, -28, 1, 0),
    TextTruncate = Enum.TextTruncate.AtEnd,
}, W.statusRow)
W.sessionText = makeLabel({
    Name = "Session", Text = "00:00", TextSize = 12, TextColor3 = Theme.Muted,
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0.38, 0, 1, 0),
    TextXAlignment = Enum.TextXAlignment.Right,
}, W.statusRow)

W.tabBar = create("Frame", {
    Name = "Tabs", BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
    Position = UDim2.fromOffset(0, 36 + UI.Gap), Size = UDim2.new(1, 0, 0, W.TAB_BAR_HEIGHT),
}, W.topArea)
addCorner(W.tabBar, 9)
addStroke(W.tabBar, Theme.Stroke, 1, 0)
W.tabIndicator = create("Frame", {
    Name = "Indicator", BackgroundColor3 = Theme.Track, BorderSizePixel = 0,
    Position = UDim2.new(0, 3, 0, 3), Size = UDim2.new(1 / 3, -6, 1, -6),
}, W.tabBar)
addCorner(W.tabIndicator, 7)

-- ---------- Pages ----------
W.TAB_ORDER = { "Farm", "Stats", "Settings" }
local pages, tabButtons = {}, {}
W.currentTab = "Farm"

function W.makePage(name)
    local page = create("Frame", {
        Name = name .. "Page", BackgroundTransparency = 1, BorderSizePixel = 0, Visible = name == "Farm",
        Position = UDim2.fromOffset(UI.Padding, W.PAGE_Y),
        Size = UDim2.new(1, -UI.Padding * 2, 1, -(W.PAGE_Y + UI.Padding)),
    }, W.canvas)
    create("UIListLayout", {
        Padding = UDim.new(0, UI.Gap), SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Enum.FillDirection.Vertical,
    }, page)
    pages[name] = page
    return page
end
for _, name in ipairs(W.TAB_ORDER) do W.makePage(name) end
-- The untouched fling section parents its button to `content`: the Farm page.
local content = pages.Farm

for index, name in ipairs(W.TAB_ORDER) do
    tabButtons[name] = create("TextButton", {
        Name = name .. "Tab", AutoButtonColor = false, BackgroundTransparency = 1,
        Position = UDim2.new((index - 1) / 3, 0, 0, 0), Size = UDim2.new(1 / 3, 0, 1, 0),
        Text = name, Font = Enum.Font.GothamBold, TextSize = 13,
        TextColor3 = name == "Farm" and Theme.Text or Theme.Muted, ZIndex = 2,
    }, W.tabBar)
    -- Hover brightens inactive tabs only.
    connect(tabButtons[name].MouseEnter, function()
        if W.currentTab ~= name then smoothTween(tabButtons[name], 0.15, { TextColor3 = Theme.Text }) end
    end)
    connect(tabButtons[name].MouseLeave, function()
        if W.currentTab ~= name then smoothTween(tabButtons[name], 0.15, { TextColor3 = Theme.Muted }) end
    end)
end
-- Small accent underline on the selected tab.
W.tabUnderline = create("Frame", {
    Name = "Underline", AnchorPoint = Vector2.new(0.5, 1), BackgroundColor3 = Theme.Accent,
    BorderSizePixel = 0, Position = UDim2.new(0.5, 0, 1, -3), Size = UDim2.fromOffset(18, 2),
}, W.tabIndicator)
addCorner(W.tabUnderline, 99)

-- ---------- Activity log (Stats tab) ----------
W.LOG_LINES = 5
W.logEntries = {}
W.logLabels = {}
function W.renderLog()
    for index = 1, W.LOG_LINES do
        local entry, label = W.logEntries[index], W.logLabels[index]
        if label then
            if entry then
                label.Text = entry.time .. "   " .. entry.text
                label.TextColor3 = index == 1 and entry.color or Theme.Muted
            else
                label.Text = index == 1 and "No activity yet" or ""
                label.TextColor3 = Theme.Faint
            end
        end
    end
end
local function addLog(text, color)
    local ok, stamp = pcall(os.date, "%H:%M")
    table.insert(W.logEntries, 1, { time = ok and stamp or "--:--", text = text, color = color or Theme.Text })
    while #W.logEntries > W.LOG_LINES do table.remove(W.logEntries) end
    W.renderLog()
end

-- Per-round statistics (a round = from scoreboard gone to scoreboard shown).
W.roundStats = { count = 0, best = 0, total = 0, startFarmed = 0, wasOver = false }

-- ---------- Farm tab ----------
W.bagCard = makeSurface("Bag", 58, 1, pages.Farm)
makeLabel({
    Text = "BAG", Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Theme.Faint,
    Position = UDim2.fromOffset(12, 10), Size = UDim2.new(0.5, 0, 0, 13),
}, W.bagCard)
W.bagValue = makeLabel({
    Name = "Value", Text = "– / " .. BAG_LIMIT_DEFAULT, Font = Enum.Font.GothamBold, TextSize = 14,
    AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 7), Size = UDim2.new(0.5, 0, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Right,
}, W.bagCard)
W.bagTrack = create("Frame", {
    Name = "Track", BackgroundColor3 = Theme.Track, BorderSizePixel = 0,
    Position = UDim2.new(0, 12, 0, 36), Size = UDim2.new(1, -24, 0, 8),
}, W.bagCard)
addCorner(W.bagTrack, 99)
W.bagFill = create("Frame", {
    Name = "Fill", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Size = UDim2.fromScale(0, 1),
}, W.bagTrack)
addCorner(W.bagFill, 99)
addGradient(W.bagFill, { { 0, Theme.AccentAlt }, { 1, Theme.Accent } }, 0)
W.bagStroke = W.bagCard:FindFirstChildOfClass("UIStroke")

makeCaption("CONTROLS", 2, pages.Farm)

-- Toggle row: title, short description and an animated switch.
function W.makeToggle(page, order, title, description, callback)
    local row = makeSurface(title, 52, order, page)
    makeLabel({
        Text = title, Font = Enum.Font.GothamBold, TextSize = 14,
        Position = UDim2.fromOffset(14, 9), Size = UDim2.new(1, -80, 0, 18),
    }, row)
    makeLabel({
        Text = description, TextSize = 12, TextColor3 = Theme.Muted,
        Position = UDim2.fromOffset(14, 28), Size = UDim2.new(1, -80, 0, 15),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, row)
    local track = create("Frame", {
        Name = "Switch", AnchorPoint = Vector2.new(1, 0.5), BackgroundColor3 = Theme.Track,
        BorderSizePixel = 0, Position = UDim2.new(1, -14, 0.5, 0), Size = UDim2.fromOffset(42, 24),
    }, row)
    addCorner(track, 99)
    local knob = create("Frame", {
        Name = "Knob", AnchorPoint = Vector2.new(0, 0.5), BackgroundColor3 = Theme.Text,
        BorderSizePixel = 0, Position = UDim2.new(0, 3, 0.5, 0), Size = UDim2.fromOffset(18, 18),
    }, track)
    addCorner(knob, 99)
    local hitbox = create("TextButton", {
        Name = "Hitbox", AutoButtonColor = false, BackgroundTransparency = 1, Text = "",
        Size = UDim2.fromScale(1, 1), ZIndex = 3,
    }, row)

    local rowStroke = row:FindFirstChildOfClass("UIStroke")
    local hovering = false
    local value = false
    -- One place decides the row colour for every on/off + hover combination.
    local function restColor()
        if value then return hovering and Theme.ActiveRowHover or Theme.ActiveRow end
        return hovering and Theme.SurfaceHover or Theme.Surface
    end
    local function setValue(nextValue)
        value = nextValue == true
        smoothTween(track, 0.2, { BackgroundColor3 = value and Theme.Accent or Theme.Track })
        -- Active rows get a red border and a faint red tint.
        smoothTween(row, 0.2, { BackgroundColor3 = restColor() })
        if rowStroke then
            smoothTween(rowStroke, 0.2, {
                Color = value and Theme.Accent or Theme.Stroke,
                Transparency = value and 0.35 or 0,
            })
        end
        smoothTween(knob, 0.2, {
            Position = value and UDim2.new(1, -21, 0.5, 0) or UDim2.new(0, 3, 0.5, 0),
        }, Enum.EasingStyle.Quart)
        callback(value)
    end
    connect(hitbox.Activated, function()
        if state.closing or state.minimized then return end
        setValue(not value)
        playUiSound(value and 1.2 or 0.9, 0.35)
        requestSave()
    end)
    connect(hitbox.MouseEnter, function()
        hovering = true
        smoothTween(row, 0.15, { BackgroundColor3 = restColor() })
    end)
    connect(hitbox.MouseLeave, function()
        hovering = false
        smoothTween(row, 0.15, { BackgroundColor3 = restColor() })
    end)
    return setValue
end

local setAutofarmEnabled = W.makeToggle(pages.Farm, 3, "Auto Farm", "Collects candy around the map", function(enabled)
    if state.autofarm ~= enabled then
        addLog(enabled and "Auto Farm on" or "Auto Farm off", enabled and Theme.Good or Theme.Muted)
    end
    state.autofarm = enabled
    if not enabled then
        cancelFling()
        currentTarget = nil
        restoreCharacter()
    end
end)



-- ================= INTERFACE BAG SCANNER =================
-- Reads the coin amount straight from the game's own interface, so the
-- bag counter always matches what the player actually sees on screen.

local trackedBagLabel = nil
local lastBagScan = 0

local function labelContext(object)
    local parts = { object.Name }
    local ancestor = object.Parent
    for _ = 1, 6 do
        if not ancestor then break end
        table.insert(parts, ancestor.Name)
        ancestor = ancestor.Parent
    end
    return string.lower(table.concat(parts, " "))
end

local function isBagVisible(object)
    local ancestor = object
    while ancestor and ancestor ~= guiParent do
        -- Script children are UI templates, not the active bag on screen.
        if ancestor:IsA("LuaSourceContainer") then return false end
        if ancestor:IsA("GuiObject") and not ancestor.Visible then return false end
        if ancestor:IsA("ScreenGui") and not ancestor.Enabled then return false end
        ancestor = ancestor.Parent
    end
    return ancestor == guiParent
end

local function parseBagText(object)
    -- Cheap type check FIRST: the fallback scan passes every PlayerGui object
    -- here, and isBagVisible walks all ancestors. Same result, far less work.
    if not (object:IsA("TextLabel") or object:IsA("TextButton")) then
        return nil
    end
    if object:IsDescendantOf(screenGui) or not isBagVisible(object) then return nil end

    local text = object.Text or ""
    -- Rich text markup and thousands separators must not break the parse.
    text = string.gsub(text, "<[^<>]->", "")
    text = string.gsub(text, ",", "")
    local currentText, capacityText = string.match(text, "^%s*(%d+)%s*/%s*(%d+)%s*$")
    if currentText then
        return tonumber(currentText), tonumber(capacityText)
    end

    local plain = string.match(text, "^%s*(%d+)%s*$")
    if plain then
        return tonumber(plain), nil
    end

    return nil
end

-- Exact counter location, confirmed by scanning the real MM2 interface:
-- MainGUI.Game.CoinBags.Container.<Coin/Candy/BeachBall/Egg/SnowToken>
--     .CurrencyFrame.Icon.Coins
local trackedBagContainer = nil
local lastDeepContainerScan = 0

local function findCoinBagContainer(playerGui)
    -- Reuse the container while it is still alive.
    if trackedBagContainer and trackedBagContainer.Parent then
        return trackedBagContainer
    end
    trackedBagContainer = nil

    -- Exact, confirmed path first.
    local mainGui = playerGui:FindFirstChild("MainGUI")
    local gameFrame = mainGui and mainGui:FindFirstChild("Game")
    local coinBags = gameFrame and gameFrame:FindFirstChild("CoinBags")
    local container = coinBags and coinBags:FindFirstChild("Container")
    if container then
        trackedBagContainer = container
        return container
    end

    -- The game moved/renamed its GUI: look for CoinBags anywhere (throttled).
    if os.clock() - lastDeepContainerScan < 1.5 then
        return nil
    end
    lastDeepContainerScan = os.clock()
    for _, object in ipairs(playerGui:GetDescendants()) do
        if object.Name == "CoinBags" then
            local found = object:FindFirstChild("Container") or object
            trackedBagContainer = found
            return found
        end
    end
    return nil
end

local function findCoinBagLabel(playerGui)
    local container = findCoinBagContainer(playerGui)
    if not container then return nil end

    for _, bag in ipairs(container:GetChildren()) do
        if bag:IsA("GuiObject") then
            local currencyFrame = bag:FindFirstChild("CurrencyFrame")
            local icon = currencyFrame and currencyFrame:FindFirstChild("Icon")
            local label = icon and icon:FindFirstChild("Coins")
            if not label then
                -- Layout inside the bag changed: search the whole bag.
                label = bag:FindFirstChild("Coins", true)
            end
            if label and label:IsA("TextLabel") then
                -- Event bags (Candy, BeachBall, ...) are hidden outside
                -- their events, so prefer the bag that is shown right now.
                if isBagVisible(label) and parseBagText(label)~=nil then
                    return label
                end
            end
        end
    end
    return nil -- hidden currency panels must never supply an old full-bag value
end

local announcedBagPath = nil
local function announceBagLabel(label)
    local path = label:GetFullName()
    if path ~= announcedBagPath then
        announcedBagPath = path
        print("[MM2 AUTOFARM] coin counter found:", path)
    end
end

-- A real bag can never hold more than its capacity. Numbers found by the
-- generic fallback scan that exceed it are something else (for example the
-- total coin balance shown in the lobby) and must not be read as the bag:
-- that showed "1234 / 50", paused the farm and could trigger Auto Respawn.
local trackedFromFallback = false
local function plausibleBag(current, capacity)
    if capacity then return current <= capacity end
    return current <= BAG_LIMIT_DEFAULT
end

local function scanBagFromInterface()
    -- Reuse the label found earlier while it is still on screen.
    if trackedBagLabel and trackedBagLabel.Parent then
        local current, capacity = parseBagText(trackedBagLabel)
        if current and (not trackedFromFallback or plausibleBag(current, capacity)) then
            return current, capacity
        end
    end
    trackedBagLabel = nil
    trackedFromFallback = false

    local playerGui = player:FindFirstChild("PlayerGui")
    if not playerGui then return nil end

    -- The exact counter path goes first: it is instant and precise.
    local exactLabel = findCoinBagLabel(playerGui)
    if exactLabel then
        local current, capacity = parseBagText(exactLabel)
        if current then
            trackedBagLabel = exactLabel
            trackedFromFallback = false
            announceBagLabel(exactLabel)
            return current, capacity
        end
    end

    -- Generic interface scans (fallback) are throttled to stay lightweight.
    if os.clock() - lastBagScan < 1.5 then
        return nil
    end
    lastBagScan = os.clock()

    local bestLabel, bestCurrent, bestCapacity, bestScore = nil, nil, nil, 0
    for _, object in ipairs(playerGui:GetDescendants()) do
        local current, capacity = parseBagText(object)
        if current and object.Visible and plausibleBag(current, capacity) then
            local context = labelContext(object)
            local score = 0
            if string.find(context, "coin", 1, true) then score += 4 end
            if string.find(context, "bag", 1, true) then score += 3 end
            if string.find(context, "candy", 1, true) then score += 2 end
            if string.find(context, "currency", 1, true) then score += 1 end
            if object.Name == "Coins" then score += 4 end
            if capacity == BAG_LIMIT_DEFAULT then
                score += 5
            end

            -- Plain numbers only count inside coin/bag related frames,
            -- otherwise timers and other counters would match too.
            local currencyContext = string.find(context, "coin", 1, true)
                or string.find(context, "bag", 1, true)
                or string.find(context, "candy", 1, true)
                or string.find(context, "currency", 1, true)
            if currencyContext and score >= 3 and score > bestScore then
                bestLabel = object
                bestCurrent = current
                bestCapacity = capacity
                bestScore = score
            end
        end
    end

    if bestLabel then
        trackedBagLabel = bestLabel
        trackedFromFallback = true
        announceBagLabel(bestLabel)
        return bestCurrent, bestCapacity
    end

    return nil
end

local lastSeenBagCount = nil
local lastSeenBagLabel = nil

local function updateBagFromInterface()
    local current, capacity = scanBagFromInterface()
    if current then
        -- Changing from Coin to Candy is a new counter, not a session gain.
        if lastSeenBagLabel~=trackedBagLabel then lastSeenBagCount=nil end
        lastSeenBagLabel=trackedBagLabel
        -- FARMED stat comes straight from the game's own bag counter: every
        -- increase of the interface number is added to the session total.
        if state.autofarm and lastSeenBagCount ~= nil and current > lastSeenBagCount then
            state.farmed += current - lastSeenBagCount
        end
        lastSeenBagCount = current
        state.bagFound = true
        state.bagCount = current
        if current < state.bagLimit then bagResetArmed = true end
        -- Use the numeric count; a stale Full label must not manufacture 50.
        state.bagLimit = BAG_LIMIT_DEFAULT
    else
        -- Unknown is not a full bag. Keep totals, never fabricate current capacity.
        state.bagFound = false
        state.bagCount = 0
        lastSeenBagCount = nil
        bagFullConfirmations = 0
    end
end

-- Halloween capacity is fixed at 50; no ownership lookup.

local function stopAutofarmOnDeath(character)
    if not state.alive or state.closing or player.Character ~= character then return end
    cancelFling()
    restoreCharacter()
    lastSafePosition = nil
    lastFramePosition = nil
    safePosAccumulator = 0
    currentTarget = nil
    state.bagFound = false
    state.bagCount = 0
    trackedBagLabel = nil
    trackedBagContainer = nil
    lastSeenBagCount = nil
    lastSeenBagLabel = nil
    bagFullConfirmations = 0
    bagCheckEnabledAt = os.clock()
    bagResetArmed = false
    bagKillTriggered = false
    if state.autofarm then
        state.farmPaused = true
        state.pauseReason = "RESPAWN"
    end
    -- Per-character connections replace the previous life's ones.
    for _, connection in ipairs(characterConnections) do connection:Disconnect() end
    table.clear(characterConnections)
    partCache.dirty = true
    local function markParts() partCache.dirty = true end
    table.insert(characterConnections, character.DescendantAdded:Connect(markParts))
    table.insert(characterConnections, character.DescendantRemoving:Connect(markParts))

    local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 8)
    if not humanoid or not state.alive or state.closing
        or player.Character ~= character then return end

    table.insert(characterConnections, humanoid.Died:Connect(function()
        if not state.alive or player.Character ~= character then return end
        cancelFling()
        currentTarget = nil
        state.farmPaused = state.autofarm
        state.pauseReason = state.autofarm and "RESPAWN" or ""
        restoreCharacter()
    end))
end

if player.Character then
    task.defer(stopAutofarmOnDeath, player.Character)
end
connect(player.CharacterAdded, stopAutofarmOnDeath)

-- Optional MM2 read-only role query. No guessed roles or knife fallback.
local roleStore = game:GetService("ReplicatedStorage")
local roleTarget, roleCharacter = nil, nil
local roleUpdated = -math.huge
local roleNextQuery = 0
local roleBusy = false
local roleEpoch = 0
local roleOwnCharacter = player.Character

local function clearMurdererRole()
    roleTarget, roleCharacter = nil, nil
    roleUpdated = -math.huge
    roleEpoch += 1
end

local function readMurdererRole()
    if not state.alive or state.closing or not state.autofarm or not state.flingEnabled
        or isRoundOver() or os.clock() - roleUpdated > 2.5 then return nil end
    if not roleTarget or roleTarget == player or roleTarget.Parent ~= Players
        or roleTarget.Character ~= roleCharacter then return nil end
    local humanoid = roleCharacter and roleCharacter:FindFirstChildOfClass("Humanoid")
    if not humanoid or humanoid.Health <= 0 then return nil end
    return roleTarget
end

local function refreshMurdererRole()
    if player.Character ~= roleOwnCharacter then
        clearMurdererRole()
        roleOwnCharacter = player.Character
    end
    if not state.alive or state.closing or not state.autofarm or not state.flingEnabled or isRoundOver() then
        clearMurdererRole()
        return
    end
    local now = os.clock()
    if roleBusy or now < roleNextQuery then return end
    roleNextQuery = now + 1.5
    local roleRemote = roleStore:FindFirstChild("GetPlayerData")
    if not roleRemote or not roleRemote:IsA("RemoteFunction") then
        clearMurdererRole()
        return
    end
    roleBusy = true
    local epoch = roleEpoch
    task.defer(function()
        -- A queued query must not start after disabling/closing or a new round.
        if epoch ~= roleEpoch or not state.alive or state.closing
            or not state.autofarm or not state.flingEnabled or isRoundOver() then
            roleBusy = false
            return
        end
        local ok, data = pcall(function() return roleRemote:InvokeServer() end)
        roleBusy = false
        if epoch ~= roleEpoch then return end
        clearMurdererRole()
        if not ok or type(data) ~= "table" or os.clock() - now > 2.5
            or not state.alive or state.closing or not state.autofarm
            or not state.flingEnabled or isRoundOver() then return end
        local candidate = nil
        for _, other in ipairs(Players:GetPlayers()) do
            local info = data[other.Name]
            local character = other.Character
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if type(info) == "table" and info.Role == "Murderer"
                and info.Dead ~= true and info.Killed ~= true and humanoid and humanoid.Health > 0 then
                if candidate then return end
                candidate = other
            end
        end
        if candidate and candidate ~= player then
            roleTarget = candidate
            roleCharacter = candidate.Character
            roleUpdated = os.clock()
        end
    end)
end

-- Experimental client-side contact only. No server kill or guaranteed effect.
-- Never writes another player's character. Finite speeds, duration and deadline.
local flingConsumed = false
local flingConfirmations = 0
local flingCharacter = nil
local flingSerial = 0
local flingButton = create("TextButton", {
    Name = "ExperimentalFling", Text = "Murderer at 50 (TEST): OFF",
    Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = Theme.White, BackgroundColor3 = Theme.Navy,
    BorderSizePixel = 0, AutoButtonColor = true, ZIndex = 25,
    Position = UDim2.fromScale(0.15, 0.855),
    Size = UDim2.fromScale(0.70, 0.065),
}, content)
addCorner(flingButton, 8)

local function flingLabel(value)
    if state.alive and flingButton.Parent then flingButton.Text = value end
end

-- Only fresh role data supplied by the game; never infer from a visible tool.
local function findMurderer()
    return readMurdererRole()
end

local function bystandersClear(targetPlayer)
    local target = targetPlayer and targetPlayer.Character
    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
    if not targetRoot then return false end
    for _, other in ipairs(Players:GetPlayers()) do
        if other ~= player and other ~= targetPlayer then
            local character = other.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if root and humanoid and humanoid.Health > 0
                and (root.Position - targetRoot.Position).Magnitude < 12 then return false end
        end
    end
    return true
end

local function canStartFling()
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    local murderer = findMurderer()
    return root ~= nil and humanoid ~= nil and humanoid.Health > 0 and not root.Anchored
        and state.alive and not state.closing and state.autofarm
        and state.flingEnabled and not state.flingActive and not flingConsumed
        and state.bagFound and state.bagCount >= 50 and bagResetArmed
        and os.clock() - bagCheckEnabledAt >= 3 and not isRoundOver()
        and murderer ~= nil and bystandersClear(murderer)
end

local function beginFling()
    local murderer = findMurderer()
    if not murderer or not bystandersClear(murderer) then return end
    local character = player.Character
    local root = character and character:FindFirstChild("HumanoidRootPart")
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if not root or not humanoid or humanoid.Health <= 0 or root.Anchored then return end
    restoreCharacter()
    local origin = root.CFrame
    local savedPlatform = humanoid.PlatformStand
    local savedRotate = humanoid.AutoRotate
    local collisions = {}
    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") then collisions[part] = part.CanCollide end
    end
    flingSerial += 1
    local serial = flingSerial
    flingConsumed = true
    state.flingActive = true
    state.farmPaused = true
    state.pauseReason = "FLING TEST"
    currentTarget = nil
    local finished = false
    local function finish()
        if finished then return end
        finished = true
        -- This also invalidates a task queued but not started yet.
        if flingSerial == serial then flingSerial += 1 end
        for part, value in pairs(collisions) do
            if part.Parent then pcall(function() part.CanCollide = value end) end
        end
        if humanoid.Parent then
            pcall(function()
                humanoid.PlatformStand = savedPlatform
                humanoid.AutoRotate = savedRotate
            end)
        end
        if root.Parent then
            pcall(function()
                root.AssemblyLinearVelocity = Vector3.zero
                root.AssemblyAngularVelocity = Vector3.zero
                if player.Character == character and humanoid.Health > 0 and not isRoundOver() then
                    root.CFrame = origin
                end
            end)
        end
        state.flingActive = false
        state.farmPaused = false
        state.pauseReason = ""
        flingLabel(state.flingEnabled and "Murderer: ON (attempt ended)" or "Murderer at 50 (TEST): OFF")
    end
    cancelFling = finish
    local function valid()
        return not finished and flingSerial == serial and state.alive and not state.closing
            and state.autofarm and state.flingEnabled and player.Character == character
            and root.Parent and humanoid.Health > 0 and not root.Anchored and not isRoundOver()
            and findMurderer() == murderer and bystandersClear(murderer)
    end
    task.defer(function()
        local ok, message = pcall(function()
            if not valid() then return end
            humanoid.PlatformStand = true
            humanoid.AutoRotate = false
            for part in pairs(collisions) do
                if part.Parent then part.CanCollide = true end
            end
            local deadline = os.clock() + 20
            for _, other in ipairs({murderer}) do
                if not valid() or os.clock() >= deadline then break end
                if other ~= player then
                    local target = other.Character
                    local targetRoot = target and target:FindFirstChild("HumanoidRootPart")
                    local targetHumanoid = target and target:FindFirstChildOfClass("Humanoid")
                    if targetRoot and targetHumanoid and targetHumanoid.Health > 0
                        and not targetRoot.Anchored and not target:FindFirstChildOfClass("ForceField") then
                        flingLabel("Murderer test: " .. other.Name)
                        local untilTime = math.min(deadline, os.clock() + 0.8)
                        local step = 0
                        while valid() and os.clock() < untilTime
                            and other.Character == target and targetRoot.Parent and targetHumanoid.Health > 0
                            and not targetRoot.Anchored and not target:FindFirstChildOfClass("ForceField") do
                            step += 1
                            local angle = step * math.pi / 2
                            local side = Vector3.new(math.cos(angle), 0, math.sin(angle))
                            root.CFrame = CFrame.new(targetRoot.Position + side * 1.5 + Vector3.new(0, 0.5, 0))
                            root.AssemblyLinearVelocity = side * -180 + Vector3.new(0, 100, 0)
                            root.AssemblyAngularVelocity = Vector3.new(0, 80, 0)
                            task.wait(0.08)
                        end
                    end
                end
            end
        end)
        finish()
        if not ok then
            warn("[Fling test] stopped: " .. tostring(message))
            flingLabel("Fling test stopped: error")
        end
    end)
end

connect(flingButton.Activated, function()
    if not state.alive or state.closing or state.minimized then return end
    state.flingEnabled = not state.flingEnabled
    if not state.flingEnabled then cancelFling() end
    flingLabel(state.flingEnabled and "Murderer at 50 (TEST): ON" or "Murderer at 50 (TEST): OFF")
end)

local function updateFlingAt50()
    refreshMurdererRole()
    if not state.alive or state.closing then cancelFling(); return end
    if not state.autofarm or not state.flingEnabled or isRoundOver() then
        if state.flingActive then cancelFling() end
        flingConfirmations = 0
        return
    end
    if player.Character ~= flingCharacter then
        if state.flingActive then cancelFling() end
        flingCharacter = player.Character
        flingConsumed = false
        flingConfirmations = 0
    end
    if state.bagFound and state.bagCount < 50 then
        flingConsumed = false
        flingConfirmations = 0
    end
    if canStartFling() then
        flingConfirmations += 1
        if flingConfirmations >= 2 then beginFling() end
    else
        flingConfirmations = 0
        if state.bagFound and state.bagCount >= 50 and not state.flingActive and not flingConsumed then
            flingLabel(findMurderer() and "Murderer: waiting for clearance" or "Murderer: unknown - waiting")
        end
    end
end

local setDieOnFullBagEnabled = W.makeToggle(pages.Farm, 4, "Auto Respawn", "Resets when the bag is full", function(enabled)
    state.dieOnFullBag = enabled
    bagKillTriggered = false
    bagFullConfirmations = 0
    if enabled then
        -- Allow the game's GUI to finish updating before any full-bag decision.
        bagCheckEnabledAt = os.clock()
    end
end)
local function killCharacterWhenBagIsFull()
    if state.flingActive or canStartFling() then return end
    if not state.alive or state.closing or not state.autofarm
        or bagKillTriggered or not state.dieOnFullBag or not state.bagFound then
        bagFullConfirmations = 0
        return
    end

    -- Reset only after the visible numeric counter reaches 50.
    if state.bagCount < state.bagLimit or not bagResetArmed
        or os.clock() - bagCheckEnabledAt < 3 then
        bagFullConfirmations = 0
        return
    end
    bagFullConfirmations += 1
    if bagFullConfirmations < 2 then return end
    local currentCharacter = player.Character
    local currentHumanoid = currentCharacter and currentCharacter:FindFirstChildOfClass("Humanoid")
    if not currentHumanoid or currentHumanoid.Health <= 0 then return end
    bagKillTriggered = true
    bagResetArmed = false
    currentTarget = nil
    state.farmPaused = state.autofarm
    state.pauseReason = state.autofarm and "RESET" or ""
    restoreCharacter()

    -- Keep AUTOFARM and AUTO RESET enabled through the respawn.
    local character = player.Character
    local humanoid = character and character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.Health > 0 then
        humanoid.Health = 0
        humanoid:ChangeState(Enum.HumanoidStateType.Dead)
        task.delay(0.05, function()
            if state.alive and not state.closing and state.autofarm
                and state.dieOnFullBag and player.Character == character and character.Parent then
                character:BreakJoints()
            end
        end)
    end
end



local setProtectionEnabled = W.makeToggle(pages.Farm, 5, "Anti Fling / Void", "Blocks flings and void falls", function(enabled)
    state.protection = enabled
end)

-- ---------- Farm speed (original 20..30 range, unchanged) ----------
local SPEED_MIN, SPEED_MAX = 20, 30
W.speedRow = makeSurface("FarmSpeed", 62, 6, pages.Farm)
makeLabel({
    Text = "Farm Speed", Font = Enum.Font.GothamBold, TextSize = 14,
    Position = UDim2.fromOffset(14, 10), Size = UDim2.new(0.6, 0, 0, 18),
}, W.speedRow)
W.speedValue = makeLabel({
    Name = "Value", Text = tostring(state.farmSpeed), Font = Enum.Font.GothamBold, TextSize = 14,
    TextColor3 = Theme.AccentSoft, AnchorPoint = Vector2.new(1, 0),
    Position = UDim2.new(1, -14, 0, 10), Size = UDim2.new(0.4, 0, 0, 18),
    TextXAlignment = Enum.TextXAlignment.Right,
}, W.speedRow)
W.slider = create("Frame", {
    Name = "Slider", BackgroundColor3 = Theme.Track, BorderSizePixel = 0,
    Position = UDim2.new(0, 14, 0, 40), Size = UDim2.new(1, -28, 0, 6),
}, W.speedRow)
addCorner(W.slider, 99)
W.initialProgress = (state.farmSpeed - SPEED_MIN) / (SPEED_MAX - SPEED_MIN)
W.sliderFill = create("Frame", {
    Name = "Fill", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0,
    Size = UDim2.fromScale(W.initialProgress, 1),
}, W.slider)
addCorner(W.sliderFill, 99)
addGradient(W.sliderFill, { { 0, Theme.Accent }, { 1, Theme.AccentSoft } }, 0)
W.sliderKnob = create("Frame", {
    Name = "Knob", AnchorPoint = Vector2.new(0.5, 0.5), BackgroundColor3 = Theme.Text,
    BorderSizePixel = 0, Position = UDim2.new(W.initialProgress, 0, 0.5, 0),
    Size = UDim2.fromOffset(16, 16), ZIndex = 2,
}, W.slider)
addCorner(W.sliderKnob, 99)
addStroke(W.sliderKnob, Theme.Accent, 2, 0)
W.sliderHitbox = create("TextButton", {
    Name = "Hitbox", AutoButtonColor = false, BackgroundTransparency = 1, Text = "",
    Position = UDim2.fromOffset(-8, -14), Size = UDim2.new(1, 16, 1, 28), ZIndex = 3,
}, W.slider)

W.sliderInput = nil
W.displayedProgress = W.initialProgress
W.targetProgress = W.initialProgress

function W.setSpeedTarget(screenX)
    local width = W.slider.AbsoluteSize.X
    if width <= 0 then return end
    W.targetProgress = math.clamp((screenX - W.slider.AbsolutePosition.X) / width, 0, 1)
    state.farmSpeed = math.floor(SPEED_MIN + W.targetProgress * (SPEED_MAX - SPEED_MIN) + 0.5)
    W.speedValue.Text = tostring(state.farmSpeed)
end

connect(W.sliderHitbox.InputBegan, function(input)
    if state.closing or state.minimized then return end
    if input.UserInputType == Enum.UserInputType.MouseButton1
        or input.UserInputType == Enum.UserInputType.Touch then
        W.sliderInput = input
        W.setSpeedTarget(input.Position.X)
        smoothTween(W.sliderKnob, 0.18, { Size = UDim2.fromOffset(20, 20) }, Enum.EasingStyle.Back)
    end
end)
connect(UserInputService.InputChanged, function(input)
    if not W.sliderInput then return end
    local mouse = input.UserInputType == Enum.UserInputType.MouseMovement
        and W.sliderInput.UserInputType == Enum.UserInputType.MouseButton1
    if mouse or input == W.sliderInput then W.setSpeedTarget(input.Position.X) end
end)
connect(UserInputService.InputEnded, function(input)
    if not W.sliderInput then return end
    local released = W.sliderInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1
    if input == W.sliderInput or released then
        W.sliderInput = nil
        smoothTween(W.sliderKnob, 0.25, { Size = UDim2.fromOffset(16, 16) }, Enum.EasingStyle.Back)
        requestSave()
    end
end)

-- Existing fling-test button: restyled only, its behaviour is unchanged.
flingButton.LayoutOrder = 7
flingButton.Size = UDim2.new(1, 0, 0, 36)
flingButton.AutoButtonColor = false
flingButton.BackgroundColor3 = Theme.Surface
flingButton.Font = Enum.Font.GothamMedium
flingButton.TextSize = 13
flingButton.TextColor3 = Theme.Muted
addStroke(flingButton, Theme.Stroke, 1, 0)

W.hintLabel = makeLabel({
    Name = "Hint", Text = "", TextSize = 11, TextColor3 = Theme.Faint,
    TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 14), LayoutOrder = 8,
}, pages.Farm)

-- ---------- Stats tab ----------
function W.statRow(name, order, captions)
    local row = create("Frame", {
        Name = name, BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 62), LayoutOrder = order,
    }, pages.Stats)
    local count = #captions
    local values = {}
    for index, caption in ipairs(captions) do
        local card = create("Frame", {
            Name = caption, BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
            Position = UDim2.new((index - 1) / count, (index - 1) * UI.Gap / count, 0, 0),
            Size = UDim2.new(1 / count, -UI.Gap * (count - 1) / count, 1, 0),
        }, row)
        addCorner(card, 10)
        addStroke(card, Theme.Stroke, 1, 0)
        makeLabel({
            Text = caption, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Theme.Faint,
            Position = UDim2.fromOffset(12, 9), Size = UDim2.new(1, -24, 0, 13),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)
        values[index] = makeLabel({
            Name = "Value", Text = "0", Font = Enum.Font.GothamBold, TextSize = count > 2 and 19 or 22,
            Position = UDim2.fromOffset(12, 26), Size = UDim2.new(1, -24, 0, 26),
            TextTruncate = Enum.TextTruncate.AtEnd,
        }, card)
    end
    return values
end
W.totals = W.statRow("Totals", 1, { "COLLECTED", "PER HOUR" })
local collectedValue, rateValue = W.totals[1], W.totals[2]
W.rounds = W.statRow("Rounds", 2, { "ROUNDS", "BEST", "AVERAGE" })
local roundsValue, bestValue, averageValue = W.rounds[1], W.rounds[2], W.rounds[3]

makeCaption("ACTIVITY", 3, pages.Stats)
W.logCard = makeSurface("Activity", W.LOG_LINES * 18 + 14, 4, pages.Stats)
for index = 1, W.LOG_LINES do
    W.logLabels[index] = makeLabel({
        Name = "Line" .. index, TextSize = 12, TextColor3 = Theme.Muted,
        Position = UDim2.fromOffset(12, 7 + (index - 1) * 18), Size = UDim2.new(1, -24, 0, 18),
        TextTruncate = Enum.TextTruncate.AtEnd,
    }, W.logCard)
end
W.renderLog()

-- ---------- Settings tab ----------
function W.resetStats()
    state.farmed = 0
    state.activeFarmTime = 0
    state.sessionStarted = os.clock()
    W.roundStats.count, W.roundStats.best, W.roundStats.total = 0, 0, 0
    W.roundStats.startFarmed = 0
    addLog("Stats reset", Theme.Muted)
end

function W.settingsButton(row, text)
    local button = create("TextButton", {
        Name = "Button", AnchorPoint = Vector2.new(1, 0.5), AutoButtonColor = false,
        BackgroundColor3 = Theme.Track, BorderSizePixel = 0,
        Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(118, 28),
        Text = text, Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Theme.Text,
    }, row)
    addCorner(button, 7)
    return button
end

makeCaption("KEYBINDS", 1, pages.Settings)

-- Keys that would clash with movement, chat or menus cannot be bound.
W.BLOCKED_KEYS = {
    [Enum.KeyCode.W] = true, [Enum.KeyCode.A] = true, [Enum.KeyCode.S] = true, [Enum.KeyCode.D] = true,
    [Enum.KeyCode.Space] = true, [Enum.KeyCode.LeftShift] = true, [Enum.KeyCode.RightShift] = true,
    [Enum.KeyCode.Slash] = true, [Enum.KeyCode.Tab] = true, [Enum.KeyCode.Return] = true,
    [Enum.KeyCode.Backquote] = true, [Enum.KeyCode.Unknown] = true,
    [Enum.KeyCode.Up] = true, [Enum.KeyCode.Down] = true, [Enum.KeyCode.Left] = true, [Enum.KeyCode.Right] = true,
}
W.KEY_FIELDS = { ToggleKey = "Hide / show window", FarmKey = "Auto Farm on / off" }
W.keyButtons = {}
W.capturingKey = nil

function W.refreshKeyButtons()
    for field, button in pairs(W.keyButtons) do
        local capturing = W.capturingKey == field
        button.Text = capturing and "Press a key (Esc)" or UI[field].Name
        button.BackgroundColor3 = capturing and Theme.Accent or Theme.Track
    end
    if TOUCH_ONLY then
        W.hintLabel.Text = "Tap the round button to hide / show"
    else
        W.hintLabel.Text = string.format("%s  farm on/off   ·   %s  hide", UI.FarmKey.Name, UI.ToggleKey.Name)
    end
end

function W.makeKeyRow(order, field)
    local row = makeSurface(field, 44, order, pages.Settings)
    makeLabel({
        Text = W.KEY_FIELDS[field], Font = Enum.Font.GothamBold, TextSize = 13,
        Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -150, 1, 0),
    }, row)
    local button = W.settingsButton(row, UI[field].Name)
    W.keyButtons[field] = button
    connect(button.Activated, function()
        if state.closing or state.minimized then return end
        W.capturingKey = W.capturingKey ~= field and field or nil
        W.refreshKeyButtons()
        playUiSound(1, 0.3)
    end)
end
W.makeKeyRow(2, "ToggleKey")
W.makeKeyRow(3, "FarmKey")
-- No keyboard: keybinds are meaningless, so hide that section entirely.
if TOUCH_ONLY then
    for _, childName in ipairs({ "KEYBINDSCaption", "ToggleKey", "FarmKey" }) do
        local child = pages.Settings:FindFirstChild(childName)
        if child then child.Visible = false end
    end
end

-- Handles a key press while a keybind button is waiting. Returns true if used.
function W.captureKey(input)
    if not W.capturingKey then return false end
    if input.UserInputType ~= Enum.UserInputType.Keyboard then return false end
    local field, code = W.capturingKey, input.KeyCode
    if code == Enum.KeyCode.Escape then
        W.capturingKey = nil
        W.refreshKeyButtons()
        return true
    end
    local other = field == "ToggleKey" and "FarmKey" or "ToggleKey"
    if W.BLOCKED_KEYS[code] then
        notify("Keybinds", code.Name .. " is used by the game. Pick another key.", 3)
        return true
    end
    if UI[other] == code then
        notify("Keybinds", code.Name .. " is already used for: " .. W.KEY_FIELDS[other], 3)
        return true
    end
    UI[field] = code
    W.capturingKey = nil
    W.refreshKeyButtons()
    addLog(W.KEY_FIELDS[field] .. " → " .. code.Name, Theme.AccentSoft)
    requestSave()
    return true
end

makeCaption("DATA", 4, pages.Settings)
W.resetRow = makeSurface("ResetStats", 44, 5, pages.Settings)
makeLabel({
    Text = "Reset statistics", Font = Enum.Font.GothamBold, TextSize = 13,
    Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -150, 1, 0),
}, W.resetRow)
W.resetButton = W.settingsButton(W.resetRow, "Reset")
connect(W.resetButton.Activated, function()
    if state.closing or state.minimized then return end
    W.resetStats()
    playUiSound(1.1, 0.35)
end)
makeLabel({
    Name = "SaveNote", TextSize = 11, TextColor3 = Theme.Faint, LayoutOrder = 6,
    Text = canSaveFiles and "Settings are saved automatically." or "This executor can't save files: settings reset on rerun.",
    TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 14),
}, pages.Settings)

-- ================= WINDOW SIZE, SCALE, TABS, DRAG =================
-- Heights come from the rows themselves (unaffected by UIScale).
function W.pageHeight(name)
    local total, count = 0, 0
    for _, child in ipairs(pages[name]:GetChildren()) do
        if child:IsA("GuiObject") and child.Visible then
            total += child.Size.Y.Offset
            count += 1
        end
    end
    return total + math.max(0, count - 1) * UI.Gap
end
function W.fullHeight(name)
    return W.PAGE_Y + W.pageHeight(name or W.currentTab) + UI.Padding
end
function W.tallestHeight()
    local tallest = 0
    for _, name in ipairs(W.TAB_ORDER) do tallest = math.max(tallest, W.fullHeight(name)) end
    return tallest
end

local function clampWindow()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local position, size = window.AbsolutePosition, window.AbsoluteSize
    local dx = math.clamp(position.X, 8, math.max(8, viewport.X - size.X - 8)) - position.X
    local dy = math.clamp(position.Y, 8, math.max(8, viewport.Y - size.Y - 8)) - position.Y
    if math.abs(dx) > 0.5 or math.abs(dy) > 0.5 then
        window.Position = window.Position + UDim2.fromOffset(dx, dy)
    end
end

-- Scale is based on the tallest tab, so switching tabs never rescales.
function W.refreshViewport()
    local camera = workspace.CurrentCamera
    if not camera then return end
    local viewport = camera.ViewportSize
    local scale = math.min(1, (viewport.Y - 24) / W.tallestHeight(), (viewport.X - 24) / UI.Width)
    W.uiScale.Scale = math.max(UI.MinScale, scale)
    clampWindow()
end

function W.bindCamera()
    if not state.alive then return end
    if cameraConnection then cameraConnection:Disconnect() end
    local camera = workspace.CurrentCamera
    if camera then
        cameraConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(W.refreshViewport)
    end
    W.refreshViewport()
end

function W.selectTab(name, instant)
    if not pages[name] then return end
    W.currentTab = name
    for index, tabName in ipairs(W.TAB_ORDER) do
        pages[tabName].Visible = tabName == name
        -- Tween (not a direct set) so it also cancels any running hover tween.
        smoothTween(tabButtons[tabName], instant and 0 or 0.15,
            { TextColor3 = tabName == name and Theme.Text or Theme.Muted })
        if tabName == name then
            local goal = UDim2.new((index - 1) / 3, 3, 0, 3)
            if instant then W.tabIndicator.Position = goal
            else smoothTween(W.tabIndicator, 0.25, { Position = goal }, Enum.EasingStyle.Quart) end
        end
    end
    if W.capturingKey and name ~= "Settings" then
        W.capturingKey = nil
        W.refreshKeyButtons()
    end
    if not state.minimized then
        local size = UDim2.fromOffset(UI.Width, W.fullHeight(name))
        if instant then window.Size = size
        else smoothTween(window, 0.3, { Size = size }, Enum.EasingStyle.Quart).Completed:Once(clampWindow) end
    end
end
for _, name in ipairs(W.TAB_ORDER) do
    connect(tabButtons[name].Activated, function()
        if state.closing or state.minimized or W.currentTab == name then return end
        W.selectTab(name)
        playUiSound(1.05, 0.25)
        requestSave()
    end)
end

W.selectTab("Farm", true)
connect(workspace:GetPropertyChangedSignal("CurrentCamera"), W.bindCamera)
W.bindCamera()
do -- start vertically centred on the left side
    local camera = workspace.CurrentCamera
    if camera then
        local height = W.fullHeight() * W.uiScale.Scale
        window.Position = UDim2.fromOffset(24, math.max(8, (camera.ViewportSize.Y - height) / 2))
    end
end

function W.pointInside(object, point)
    local topLeft, size = object.AbsolutePosition, object.AbsoluteSize
    return point.X >= topLeft.X and point.X <= topLeft.X + size.X
        and point.Y >= topLeft.Y and point.Y <= topLeft.Y + size.Y
end

local dragInput, dragStart, windowStart = nil, nil, nil
connect(W.header.InputBegan, function(input)
    if state.closing then return end
    if input.UserInputType ~= Enum.UserInputType.MouseButton1
        and input.UserInputType ~= Enum.UserInputType.Touch then return end
    if W.pointInside(W.minimizeButton, input.Position) or W.pointInside(W.closeButton, input.Position) then return end
    dragInput, dragStart, windowStart = input, input.Position, window.Position
end)
connect(UserInputService.InputChanged, function(input)
    if not dragInput then return end
    local mouse = input.UserInputType == Enum.UserInputType.MouseMovement
        and dragInput.UserInputType == Enum.UserInputType.MouseButton1
    if not mouse and input ~= dragInput then return end
    local delta = input.Position - dragStart
    window.Position = UDim2.new(
        windowStart.X.Scale, windowStart.X.Offset + delta.X,
        windowStart.Y.Scale, windowStart.Y.Offset + delta.Y)
    clampWindow()
end)
connect(UserInputService.InputEnded, function(input)
    if not dragInput then return end
    local released = dragInput.UserInputType == Enum.UserInputType.MouseButton1
        and input.UserInputType == Enum.UserInputType.MouseButton1
    if input == dragInput or released then
        dragInput = nil
        requestSave()
    end
end)

-- ================= MINIMIZE / CLOSE / HOTKEYS =================
function W.setMinimized(value)
    if state.closing or state.minimized == value then return end
    state.minimized = value
    W.minimizeButton.Text = value and "+" or "–"
    if value and W.capturingKey then
        W.capturingKey = nil
        W.refreshKeyButtons()
    end
    local target = value and UI.HeaderHeight or W.fullHeight()
    smoothTween(window, 0.35, { Size = UDim2.fromOffset(UI.Width, target) }, Enum.EasingStyle.Quart)
        .Completed:Once(clampWindow)
end
connect(W.minimizeButton.Activated, function()
    W.setMinimized(not state.minimized)
    playUiSound(1, 0.3)
    requestSave()
end)

connect(W.closeButton.Activated, function()
    if state.closing then return end
    state.closing = true
    cancelFling()
    state.autofarm = false
    restoreCharacter()
    smoothTween(W.canvas, 0.22, { GroupTransparency = 1 }, Enum.EasingStyle.Quart)
    W.tweenShadows(0.22, false)
    smoothTween(W.windowStroke, 0.22, { Transparency = 1 }, Enum.EasingStyle.Quart)
    task.delay(0.25, function()
        cleanup()
        if screenGui.Parent then screenGui:Destroy() end
    end)
end)

-- Hotkeys (ignored while typing in chat). Both are rebindable in Settings.
-- Hiding uses window.Visible (not screenGui.Enabled) so the mobile button,
-- which lives in the same ScreenGui, stays on screen while the window is hidden.
function W.isWindowShown() return window.Visible end
function W.setWindowShown(shown)
    window.Visible = shown
    if not shown and dragInput then dragInput = nil end
end

-- ---------- Mobile: floating round button (touch screens only) ----------
-- Phones and tablets have no keyboard, so the hotkeys can't be used there.
-- Tap = hide / show the window. Drag = move the button.
W.mobileButton = nil
if UserInputService.TouchEnabled then
    W.mobileButton = create("ImageButton", {
        Name = "MobileToggle", AnchorPoint = Vector2.new(0.5, 0.5), AutoButtonColor = false,
        BackgroundColor3 = Theme.Surface, BorderSizePixel = 0,
        -- Right side: the window opens on the left, so they never overlap.
        Position = UDim2.new(1, -44, 0.3, 0), Size = UDim2.fromOffset(52, 52),
        Image = W.logoImage or "", ScaleType = Enum.ScaleType.Crop, ZIndex = 50,
    }, screenGui)
    addCorner(W.mobileButton, 99)
    local mobileRing = addStroke(W.mobileButton, Theme.Accent, 2.5, 0)
    if not W.logoImage then
        makeLabel({
            Text = "ع", Font = Enum.Font.GothamBlack, TextSize = 22, ZIndex = 51,
            TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1),
        }, W.mobileButton)
    end

    local touchStart, buttonStart, moved = nil, nil, false
    connect(W.mobileButton.InputBegan, function(input)
        if input.UserInputType ~= Enum.UserInputType.Touch
            and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        touchStart, buttonStart, moved = input, W.mobileButton.Position, false
    end)
    connect(UserInputService.InputChanged, function(input)
        if not touchStart then return end
        if input ~= touchStart and input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        local delta = input.Position - touchStart.Position
        if delta.Magnitude > 8 then moved = true end
        if moved then
            local camera = workspace.CurrentCamera
            local viewport = camera and camera.ViewportSize or Vector2.new(1000, 600)
            local base = Vector2.new(
                buttonStart.X.Scale * viewport.X + buttonStart.X.Offset,
                buttonStart.Y.Scale * viewport.Y + buttonStart.Y.Offset)
            local target = base + Vector2.new(delta.X, delta.Y)
            W.mobileButton.Position = UDim2.fromOffset(
                math.clamp(target.X, 30, viewport.X - 30), math.clamp(target.Y, 30, viewport.Y - 30))
        end
    end)
    connect(UserInputService.InputEnded, function(input)
        if not touchStart then return end
        if input ~= touchStart and input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
        touchStart = nil
        if not moved and not state.closing then
            W.setWindowShown(not W.isWindowShown())
            playUiSound(1, 0.3)
        end
    end)

    -- The ring shows the farm state at a glance: red = farming, dim = off.
    connect(RunService.Heartbeat, function()
        mobileRing.Transparency = state.autofarm and 0 or 0.6
    end)
end

W.hiddenHintShown = false
connect(UserInputService.InputBegan, function(input, gameProcessed)
    if state.closing or not state.alive then return end
    -- Key capture runs before the gameProcessed check: Roblox marks Esc as
    -- processed (it opens the menu), which would make "Esc = cancel" dead.
    -- Typing in chat or any text box is still ignored.
    if W.capturingKey and not UserInputService:GetFocusedTextBox() then
        if W.captureKey(input) then return end
    end
    if gameProcessed then return end
    if input.KeyCode == UI.ToggleKey then
        W.setWindowShown(not W.isWindowShown())
        if not W.isWindowShown() and not W.hiddenHintShown then
            W.hiddenHintShown = true
            notify("MM2 Autofarm", "Window hidden. Press " .. UI.ToggleKey.Name .. " to show it.", 4)
        end
    elseif input.KeyCode == UI.FarmKey then
        setAutofarmEnabled(not state.autofarm)
        playUiSound(state.autofarm and 1.2 or 0.9, 0.35)
        requestSave()
        if not W.isWindowShown() then
            notify("MM2 Autofarm", state.autofarm and "Auto Farm ON" or "Auto Farm OFF", 2)
        end
    end
end)

-- ================= LIVE UPDATES =================
W.STATUS_TEXT = {
    ["WAITING"] = "Waiting for candy",
    ["BAG FULL"] = "Bag full",
    ["ROUND END"] = "Round over",
    ["RESPAWN"] = "Respawning",
    ["TOO FAR"] = "Candy too far",
    ["RESET"] = "Resetting",
    ["FLING TEST"] = "Fling test",
}

function W.formatClock(totalSeconds)
    local whole = math.floor(math.max(0, totalSeconds))
    local hours, minutes, seconds = math.floor(whole / 3600), math.floor(whole / 60) % 60, whole % 60
    return hours > 0 and string.format("%d:%02d:%02d", hours, minutes, seconds)
        or string.format("%02d:%02d", minutes, seconds)
end

W.elapsed = 0
W.statsAccumulator = 0
W.lastBagRatio = -1
W.bagFullNotified = false
W.respawnLogged = false
connect(RunService.RenderStepped, function(deltaTime)
    if not state.alive then return end
    W.elapsed += deltaTime
    W.statsAccumulator += deltaTime
    if state.autofarm then
        state.activeFarmTime += deltaTime
    end

    if W.statsAccumulator >= 0.2 then
        W.statsAccumulator = 0

        -- Totals. Per Hour uses time actually spent farming (stable after 30s).
        local activeSeconds = state.activeFarmTime
        local perHour = activeSeconds >= 30 and (state.farmed / activeSeconds) * 3600 or 0
        collectedValue.Text = formatInteger(state.farmed)
        rateValue.Text = formatInteger(perHour)
        W.sessionText.Text = W.formatClock(os.clock() - state.sessionStarted)

        -- Rounds: a round closes when the end scoreboard appears.
        local roundOver = isRoundOver()
        if roundOver and not W.roundStats.wasOver then
            local gained = state.farmed - W.roundStats.startFarmed
            if gained > 0 then
                W.roundStats.count += 1
                W.roundStats.total += gained
                W.roundStats.best = math.max(W.roundStats.best, gained)
                addLog("Round over  +" .. formatInteger(gained), Theme.AccentSoft)
            end
        elseif not roundOver and W.roundStats.wasOver then
            W.roundStats.startFarmed = state.farmed
        end
        W.roundStats.wasOver = roundOver
        roundsValue.Text = tostring(W.roundStats.count)
        bestValue.Text = formatInteger(W.roundStats.best)
        averageValue.Text = W.roundStats.count > 0
            and formatInteger(W.roundStats.total / W.roundStats.count) or "0"

        -- Bag.
        updateBagFromInterface()
        W.bagValue.Text = state.bagFound
            and string.format("%d / %d", state.bagCount, state.bagLimit)
            or ("– / " .. tostring(state.bagLimit))
        local ratio = state.bagFound and math.clamp(state.bagCount / math.max(state.bagLimit, 1), 0, 1) or 0
        if ratio ~= W.lastBagRatio then
            W.lastBagRatio = ratio
            smoothTween(W.bagFill, 0.3, { Size = UDim2.fromScale(ratio, 1) })
            -- Full bag: red border on the whole card and a red count.
            if W.bagStroke then
                smoothTween(W.bagStroke, 0.3, { Color = ratio >= 1 and Theme.Accent or Theme.Stroke })
            end
            smoothTween(W.bagValue, 0.3, { TextColor3 = ratio >= 1 and Theme.AccentSoft or Theme.Text })
        end
        if isBagFull() then
            if not W.bagFullNotified and state.autofarm then
                W.bagFullNotified = true
                addLog("Bag full", Theme.Bad)
                if not bagWillReset() then
                    notify("Bag full", state.dieOnFullBag
                        and "The bag was already full. Reset once and farming continues."
                        or "Turn on Auto Respawn to keep farming.", 5)
                end
            end
        else
            W.bagFullNotified = false
        end
        if bagKillTriggered and not W.respawnLogged then
            W.respawnLogged = true
            addLog("Auto respawn", Theme.Warn)
        elseif not bagKillTriggered then
            W.respawnLogged = false
        end

        -- Status line.
        local text, color
        if not state.autofarm then
            text, color = "Off", Theme.Bad
        elseif state.farmPaused then
            text = W.STATUS_TEXT[state.pauseReason] or (state.pauseReason ~= "" and state.pauseReason or "Paused")
            color = state.pauseReason == "BAG FULL" and Theme.Bad or Theme.Warn
        else
            text, color = "Farming", Theme.Good
        end
        W.statusText.Text = text
        W.statusText.TextColor3 = color
        W.statusDot.BackgroundColor3 = color
        W.subtitle.Text = state.minimized and ("● " .. text) or W.BRAND_SUBTITLE
        W.subtitle.TextColor3 = state.minimized and color or Theme.Muted

        updateFlingAt50()
        killCharacterWhenBagIsFull()
    end

    -- Gentle pulse on the status dot while farming.
    local farming = state.autofarm and not state.farmPaused
    W.statusDot.BackgroundTransparency = farming and (0.35 - 0.35 * math.cos(W.elapsed * 4)) or 0

    -- Living accents: sliding gradients on the bar and title, slow logo spin,
    -- and a glow that breathes a little while farming.
    local slide = math.sin(W.elapsed * 0.6) * 0.5
    W.accentGradient.Offset = Vector2.new(slide, 0)
    W.titleGradient.Offset = Vector2.new(-slide, 0)
    W.logoGradient.Rotation = (W.elapsed * 25) % 360
    -- Logo ring pulses while farming.
    W.logoRing.Transparency = farming and (0.35 - 0.35 * math.cos(W.elapsed * 3)) or 0
    local glow = W.shadowFrames[3]
    if glow and W.canvas.GroupTransparency < 0.05 then
        glow.frame.BackgroundTransparency = farming
            and (glow.alpha - 0.06 * (1 + math.sin(W.elapsed * 2.5)) / 2)
            or glow.alpha
    end

    -- Smooth slider knob; stop writing once settled.
    if math.abs(W.targetProgress - W.displayedProgress) > 0.0005 then
        W.displayedProgress += (W.targetProgress - W.displayedProgress) * math.min(1, deltaTime * 18)
        W.sliderFill.Size = UDim2.fromScale(W.displayedProgress, 1)
        W.sliderKnob.Position = UDim2.new(W.displayedProgress, 0, 0.5, 0)
    end
end)

-- ================= SAVE / RESTORE SETTINGS =================
-- Remembered: toggles, speed, keybinds, last tab, window position and
-- minimized state. The fling test and the statistics are never saved.
Settings.collect = function()
    local position = window.Position
    return {
        autofarm = state.autofarm,
        dieOnFullBag = state.dieOnFullBag,
        protection = state.protection,
        farmSpeed = state.farmSpeed,
        minimized = state.minimized,
        tab = W.currentTab,
        toggleKey = UI.ToggleKey.Name,
        farmKey = UI.FarmKey.Name,
        x = position.X.Offset,
        y = position.Y.Offset,
    }
end

do
    local saved = Settings.data
    local function savedKey(name)
        if type(name) ~= "string" then return nil end
        local ok, code = pcall(function() return Enum.KeyCode[name] end)
        if ok and code and not W.BLOCKED_KEYS[code] then return code end
        return nil
    end
    local toggleKey, farmKey = savedKey(saved.toggleKey), savedKey(saved.farmKey)
    if toggleKey then UI.ToggleKey = toggleKey end
    if farmKey and farmKey ~= UI.ToggleKey then UI.FarmKey = farmKey end
    -- A damaged file could still leave both on one key: fall back to defaults.
    if UI.ToggleKey == UI.FarmKey then
        UI.ToggleKey, UI.FarmKey = Enum.KeyCode.RightControl, Enum.KeyCode.F6
    end
    W.refreshKeyButtons()

    if type(saved.farmSpeed) == "number" then
        state.farmSpeed = math.clamp(math.floor(saved.farmSpeed + 0.5), SPEED_MIN, SPEED_MAX)
        W.targetProgress = (state.farmSpeed - SPEED_MIN) / (SPEED_MAX - SPEED_MIN)
        W.displayedProgress = W.targetProgress
        W.sliderFill.Size = UDim2.fromScale(W.targetProgress, 1)
        W.sliderKnob.Position = UDim2.new(W.targetProgress, 0, 0.5, 0)
        W.speedValue.Text = tostring(state.farmSpeed)
    end
    if type(saved.tab) == "string" and pages[saved.tab] then
        W.selectTab(saved.tab, true)
    end
    if type(saved.x) == "number" and type(saved.y) == "number" then
        window.Position = UDim2.fromOffset(saved.x, saved.y)
        clampWindow()
    end
    if saved.protection == true then setProtectionEnabled(true) end
    if saved.dieOnFullBag == true then setDieOnFullBagEnabled(true) end
    if saved.autofarm == true then
        setAutofarmEnabled(true)
        notify("MM2 Autofarm", TOUCH_ONLY
            and "Settings restored. Auto Farm is ON."
            or ("Settings restored. Auto Farm is ON (" .. UI.FarmKey.Name .. " to stop)."), 5)
    end
    if saved.minimized == true then
        -- Set directly: no animation needed while the window is still fading in.
        state.minimized = true
        W.minimizeButton.Text = "+"
        window.Size = UDim2.fromOffset(UI.Width, UI.HeaderHeight)
    end
end

-- Opening animation: fade in with a short slide from the left.
do
    local finalPosition = window.Position
    window.Position = finalPosition - UDim2.fromOffset(16, 0)
    smoothTween(W.canvas, 0.35, { GroupTransparency = 0 }, Enum.EasingStyle.Quart)
    W.tweenShadows(0.5, true)
    smoothTween(W.windowStroke, 0.35, { Transparency = 0 }, Enum.EasingStyle.Quart)
    smoothTween(window, 0.35, { Position = finalPosition }, Enum.EasingStyle.Quart)
end
playUiSound(1, 0.4)

-- ================= FILING =================
-- Separate "MULTI-FLING REMASTERED" window. Keeps its own GUI, state and
-- loops, so the main autofarm window stays untouched. Duplicates removed:
--   * Players, RunService: use the services declared at the top of the file.
--   * LocalPlayer: reuse the existing `player` via `local Player = player`.
--   * Message(): replaced with the existing notify() helper.

do
    local Player = player

    local ScreenGui = Instance.new("ScreenGui")
    ScreenGui.Name = "KilasikFlingGUI"
    ScreenGui.ResetOnSpawn = false
    ScreenGui.Parent = game:GetService("CoreGui")

    local MainFrame = Instance.new("Frame")
    MainFrame.Size = UDim2.new(0, 300, 0, 380)
    MainFrame.Position = UDim2.new(0.5, -150, 0.5, -175)
    MainFrame.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    MainFrame.BorderSizePixel = 0
    MainFrame.Active = true
    MainFrame.Draggable = true
    MainFrame.Parent = ScreenGui
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = MainFrame

    local TitleBar = Instance.new("Frame")
    TitleBar.Size = UDim2.new(1, 0, 0, 30)
    TitleBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
    TitleBar.BorderSizePixel = 0
    TitleBar.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = TitleBar

    local Title = Instance.new("TextLabel")
    Title.Size = UDim2.new(1, -30, 1, 0)
    Title.BackgroundTransparency = 1
    Title.Text = "MULTI-FLING REMASTERED"
    Title.TextColor3 = Color3.fromRGB(255, 255, 255)
    Title.Font = Enum.Font.SourceSansBold
    Title.TextSize = 18
    Title.Parent = TitleBar

    local CloseButton = Instance.new("TextButton")
    CloseButton.Position = UDim2.new(1, -30, 0, 0)
    CloseButton.Size = UDim2.new(0, 30, 0, 30)
    CloseButton.BackgroundColor3 = Color3.fromRGB(170, 0, 0)
    CloseButton.BorderSizePixel = 0
    CloseButton.Text = "X"
    CloseButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    CloseButton.Font = Enum.Font.SourceSansBold
    CloseButton.TextSize = 18
    CloseButton.Parent = TitleBar
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = CloseButton

    local StatusLabel = Instance.new("TextLabel")
    StatusLabel.Position = UDim2.new(0, 10, 0, 40)
    StatusLabel.Size = UDim2.new(1, -20, 0, 25)
    StatusLabel.BackgroundTransparency = 1
    StatusLabel.Text = "Select targets to fling"
    StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
    StatusLabel.Font = Enum.Font.SourceSans
    StatusLabel.TextSize = 16
    StatusLabel.TextXAlignment = Enum.TextXAlignment.Left
    StatusLabel.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = StatusLabel

    local SelectionFrame = Instance.new("Frame")
    SelectionFrame.Position = UDim2.new(0, 10, 0, 70)
    SelectionFrame.Size = UDim2.new(1, -20, 0, 200)
    SelectionFrame.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    SelectionFrame.BorderSizePixel = 0
    SelectionFrame.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = SelectionFrame

    local PlayerScrollFrame = Instance.new("ScrollingFrame")
    PlayerScrollFrame.Position = UDim2.new(0, 5, 0, 5)
    PlayerScrollFrame.Size = UDim2.new(1, -10, 1, -10)
    PlayerScrollFrame.BackgroundTransparency = 1
    PlayerScrollFrame.BorderSizePixel = 0
    PlayerScrollFrame.ScrollBarThickness = 6
    PlayerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    PlayerScrollFrame.Parent = SelectionFrame

    local MethodButton = Instance.new("TextButton")
    MethodButton.Position = UDim2.new(0, 155, 0, 40)
    MethodButton.Size = UDim2.new(0.5, -15, 0, 25)
    MethodButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    MethodButton.BorderSizePixel = 0
    MethodButton.Text = "Method: BodyVelocity"
    MethodButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    MethodButton.Font = Enum.Font.SourceSans
    MethodButton.TextSize = 14
    MethodButton.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = MethodButton

    local StartButton = Instance.new("TextButton")
    StartButton.Position = UDim2.new(0, 10, 0, 280)
    StartButton.Size = UDim2.new(0.5, -15, 0, 40)
    StartButton.BackgroundColor3 = Color3.fromRGB(0, 160, 0)
    StartButton.BorderSizePixel = 0
    StartButton.Text = "START FLING"
    StartButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    StartButton.Font = Enum.Font.SourceSansBold
    StartButton.TextSize = 18
    StartButton.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = StartButton

    local StopButton = Instance.new("TextButton")
    StopButton.Position = UDim2.new(0.5, 5, 0, 280)
    StopButton.Size = UDim2.new(0.5, -15, 0, 40)
    StopButton.BackgroundColor3 = Color3.fromRGB(160, 0, 0)
    StopButton.BorderSizePixel = 0
    StopButton.Text = "STOP FLING"
    StopButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    StopButton.Font = Enum.Font.SourceSansBold
    StopButton.TextSize = 18
    StopButton.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = StopButton

    local SelectAllButton = Instance.new("TextButton")
    SelectAllButton.Position = UDim2.new(0, 10, 0, 330)
    SelectAllButton.Size = UDim2.new(0.5, -15, 0, 30)
    SelectAllButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    SelectAllButton.BorderSizePixel = 0
    SelectAllButton.Text = "SELECT ALL"
    SelectAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    SelectAllButton.Font = Enum.Font.SourceSans
    SelectAllButton.TextSize = 14
    SelectAllButton.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = SelectAllButton
    local DeselectAllButton = Instance.new("TextButton")
    DeselectAllButton.Position = UDim2.new(0.5, 5, 0, 330)
    DeselectAllButton.Size = UDim2.new(0.5, -15, 0, 30)
    DeselectAllButton.BackgroundColor3 = Color3.fromRGB(60, 60, 60)
    DeselectAllButton.BorderSizePixel = 0
    DeselectAllButton.Text = "DESELECT ALL"
    DeselectAllButton.TextColor3 = Color3.fromRGB(255, 255, 255)
    DeselectAllButton.Font = Enum.Font.SourceSans
    DeselectAllButton.TextSize = 14
    DeselectAllButton.Parent = MainFrame
    local corner = Instance.new("UICorner")
    corner.CornerRadius = UDim.new(0, 12)
    corner.Parent = DeselectAllButton

    local SelectedTargets = {}
    local PlayerCheckboxes = {}
    local FlingActive = false
    local FlingConnection = nil
    getgenv().OldPos = nil
    getgenv().FPDH = workspace.FallenPartsDestroyHeight
    local function CountSelectedTargets()
        local count = 0
        for _ in pairs(SelectedTargets) do
            count = count + 1
        end
        return count
    end
    local function UpdateStatus()
        local count = CountSelectedTargets()
        if FlingActive then
            StatusLabel.Text = "Flinging " .. count .. " target(s)"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 80, 80)
        else
            StatusLabel.Text = count .. " target(s) selected"
            StatusLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
        end
    end

    local function hasNoCollision(character)
        if not character then return false end
        local hrp = character:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then
            if hrp.CanCollide == false then return true end
            if hrp.Massless == true then return true end
            if hrp.Anchored == true then return true end
        end
        return false
    end

    spawn(function()
        while true do
            task.wait(1)
            for playerName, checkboxData in pairs(PlayerCheckboxes) do
                local other = Players:FindFirstChild(playerName)
                if other and other.Character then
                    local hrp = other.Character:FindFirstChild("HumanoidRootPart")
                    local noCollision = hrp and (hrp.CanCollide == false or hrp.Massless == true or hrp.Anchored == true)
                    local label = checkboxData.Entry:FindFirstChildOfClass("TextLabel")
                    if label then
                        label.Text = string.format(
                            '<font color="#%s">%s</font> <font color="#999999">(%s)</font>',
                            noCollision and "FF0000" or "FFFFFF",
                            other.Name,
                            other.DisplayName
                        )
                    end
                end
            end
        end
    end)

    local function RefreshPlayerList()
        for _, child in pairs(PlayerScrollFrame:GetChildren()) do
            child:Destroy()
        end
        PlayerCheckboxes = {}

        local PlayerList = Players:GetPlayers()
        table.sort(PlayerList, function(a, b) return a.Name:lower() < b.Name:lower() end)

        local yPosition = 5
        for _, other in ipairs(PlayerList) do
            if other ~= Player then
                local PlayerEntry = Instance.new("Frame")
                PlayerEntry.Size = UDim2.new(1, -10, 0, 35)
                PlayerEntry.Position = UDim2.new(0, 5, 0, yPosition)
                PlayerEntry.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
                PlayerEntry.BorderSizePixel = 0
                PlayerEntry.Parent = PlayerScrollFrame
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 12)
                corner.Parent = PlayerEntry

                local Checkbox = Instance.new("TextButton")
                Checkbox.Size = UDim2.new(0, 24, 0, 24)
                Checkbox.Position = UDim2.new(0, 3, 0.5, -12)
                Checkbox.BackgroundColor3 = Color3.fromRGB(70, 70, 70)
                Checkbox.BorderSizePixel = 0
                Checkbox.Text = ""
                Checkbox.Parent = PlayerEntry
                local corner = Instance.new("UICorner")
                corner.CornerRadius = UDim.new(0, 12)
                corner.Parent = Checkbox

                local Checkmark = Instance.new("TextLabel")
                Checkmark.Size = UDim2.new(1, 0, 1, 0)
                Checkmark.BackgroundTransparency = 1
                Checkmark.Text = "✓"
                Checkmark.TextColor3 = Color3.fromRGB(0, 255, 0)
                Checkmark.TextSize = 18
                Checkmark.Font = Enum.Font.SourceSansBold
                Checkmark.Visible = SelectedTargets[other.Name] ~= nil
                Checkmark.Parent = Checkbox

                local noCollision = hasNoCollision(other.Character)

                local NameLabel = Instance.new("TextLabel")
                NameLabel.Size = UDim2.new(1, -35, 1, 0)
                NameLabel.Position = UDim2.new(0, 30, 0, 0)
                NameLabel.BackgroundTransparency = 1
                NameLabel.RichText = true
                NameLabel.Text = string.format(
                    '<font color="#%s">%s</font> <font color="#999999">(%s)</font>',
                    noCollision and "FF0000" or "FFFFFF",
                    other.Name,
                    other.DisplayName
                )
                NameLabel.TextSize = 16
                NameLabel.Font = Enum.Font.SourceSans
                NameLabel.TextXAlignment = Enum.TextXAlignment.Left
                NameLabel.Parent = PlayerEntry

                local ClickArea = Instance.new("TextButton")
                ClickArea.Size = UDim2.new(1, 0, 1, 0)
                ClickArea.BackgroundTransparency = 1
                ClickArea.Text = ""
                ClickArea.ZIndex = 2
                ClickArea.Parent = PlayerEntry

                ClickArea.MouseButton1Click:Connect(function()
                    if SelectedTargets[other.Name] then
                        SelectedTargets[other.Name] = nil
                        Checkmark.Visible = false
                    else
                        SelectedTargets[other.Name] = other
                        Checkmark.Visible = true
                    end
                    UpdateStatus()
                end)

                PlayerCheckboxes[other.Name] = {
                    Entry = PlayerEntry,
                    Checkmark = Checkmark
                }

                yPosition = yPosition + 40
            end
        end

        PlayerScrollFrame.CanvasSize = UDim2.new(0, 0, 0, yPosition + 5)
    end

    local function ToggleAllPlayers(select)
        for _, other in ipairs(Players:GetPlayers()) do
            if other ~= Player then
                local checkboxData = PlayerCheckboxes[other.Name]
                if checkboxData then
                    if select then
                        SelectedTargets[other.Name] = other
                        checkboxData.Checkmark.Visible = true
                    else
                        SelectedTargets[other.Name] = nil
                        checkboxData.Checkmark.Visible = false
                    end
                end
            end
        end

        UpdateStatus()
    end

    local FlingMethods = {
        ["BodyVelocity"] = function(rootPart, power, dir)
            local bv = Instance.new("BodyVelocity")
            bv.Velocity = dir * power * 100
            bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bv.Parent = rootPart
            return bv
        end,
        ["BodyThrust"] = function(rootPart, power, dir)
            local bt = Instance.new("BodyThrust")
            bt.Force = dir * power * 500
            bt.Location = rootPart.Position + Vector3.new(0, 1, 0)
            bt.Parent = rootPart
            return bt
        end,
        ["BodyForce"] = function(rootPart, power, dir)
            local bf = Instance.new("BodyForce")
            bf.Force = dir * power * 500
            bf.Parent = rootPart
            return bf
        end,
        ["VectorForce"] = function(rootPart, power, dir)
            local vf = Instance.new("VectorForce")
            vf.Force = dir * power * 500
            vf.Parent = rootPart
            return vf
        end,
        ["LinearVelocity"] = function(rootPart, power, dir)
            local lv = Instance.new("LinearVelocity")
            lv.Velocity = dir * power * 100
            lv.MaxForce = 9e9
            lv.Parent = rootPart
            return lv
        end,
        ["ExplodeFling"] = function(rootPart, power, dir)
            local bf = Instance.new("BodyForce")
            bf.Force = dir * power * 999999
            bf.Parent = rootPart

            local bv = Instance.new("BodyVelocity")
            bv.Velocity = Vector3.new(
                math.random(-1000, 1000),
                math.random(500, 1500),
                math.random(-1000, 1000)
            )
            bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
            bv.Parent = rootPart

            game:GetService("Debris"):AddItem(bf, 0.3)
            game:GetService("Debris"):AddItem(bv, 0.3)
            return {bf, bv}
        end,
        ["NaNFling"] = function(rootPart, power, dir)
            local targetRoot = nil
            for _, other in pairs(SelectedTargets) do
                if other and other.Character then
                    local tr = other.Character:FindFirstChild("HumanoidRootPart")
                    if tr then targetRoot = tr break end
                end
            end
            if not targetRoot then return nil end

            local nan_value = (0) / (0)
            local nan_vector = Vector3.new(nan_value, nan_value, nan_value)

            local humanoid = rootPart.Parent:FindFirstChildOfClass("Humanoid")
            if humanoid then humanoid.PlatformStand = true end

            rootPart.CFrame = targetRoot.CFrame
            rootPart.AssemblyLinearVelocity = nan_vector
            rootPart.AssemblyAngularVelocity = nan_vector
            pcall(function()
                sethiddenproperty(rootPart, "PhysicsRepRootPart", targetRoot)
            end)
            return nil
        end,
        ["PhysicsRepFling"] = function(rootPart, power, dir)
            if not sethiddenproperty then
                warn("sethiddenproperty not available!")
                return nil
            end

            local targetRoot = nil
            for _, other in pairs(SelectedTargets) do
                if other and other.Character then
                    local tr = other.Character:FindFirstChild("HumanoidRootPart")
                    if tr then targetRoot = tr break end
                end
            end

            if not targetRoot then
                return nil
            end

            pcall(function()
                sethiddenproperty(rootPart, "PhysicsRepRootPart", targetRoot)
            end)

            rootPart.CFrame = targetRoot.CFrame
            rootPart.Velocity = Vector3.new(9e9, 9e9, 9e9)
            rootPart.RotVelocity = Vector3.new(9e9, 9e9, 9e9)

            return nil
        end,
        ["FlingNEW"] = function(rootPart, power, dir)
            local bodies = {}

            local targetRoot = nil
            for _, other in pairs(SelectedTargets) do
                if other and other.Character then
                    local tr = other.Character:FindFirstChild("HumanoidRootPart")
                    if tr then targetRoot = tr break end
                end
            end
            if not targetRoot then return nil end

            pcall(function()
                sethiddenproperty(rootPart, "PhysicsRepRootPart", targetRoot)
                sethiddenproperty(game.Players.LocalPlayer, "SimulationRadius", math.huge)
            end)

            for i = 1, 100 do
                local bv = Instance.new("BodyVelocity")
                bv.Parent = rootPart
                local nan = 0/0
                bv.Velocity = Vector3.new(nan, nan, nan)
                bv.MaxForce = Vector3.new(9e30, 9e30, 9e30)
                table.insert(bodies, bv)
                game:GetService("Debris"):AddItem(bv, 0.05 + (i * 0.001))
            end

            return bodies
        end,
        ["RocketFling"] = function(rootPart, power, dir)
            local rp = Instance.new("RocketPropulsion")
            rp.Parent = rootPart

            local targetPart = Instance.new("Part")
            targetPart.Position = rootPart.Position + dir * 100
            targetPart.Anchored = true
            targetPart.CanCollide = false
            targetPart.Parent = workspace
            rp.Target = targetPart

            rp.MaxThrust = power * 1000
            rp.ThrustP = 1e5
            rp.ThrustD = math.huge

            rp:Fire()

            game:GetService("Debris"):AddItem(rp, 0.5)
            game:GetService("Debris"):AddItem(targetPart, 0.5)

            return rp
        end,
        ["TorqueFling"] = function(rootPart, power, dir)
            local torque = Instance.new("Torque")
            torque.Parent = rootPart
            torque.Torque = Vector3.new(power * 10000, power * 10000, power * 10000)

            game:GetService("Debris"):AddItem(torque, 0.5)
            return torque
        end,
        ["ImpulseFling1"] = function(rootPart, power, dir)
            local bodies = {}
            for i = 1, 100 do
                local bv = Instance.new("BodyVelocity")
                bv.Parent = rootPart
                bv.Velocity = Vector3.new(9e9, 9e9, 9e9)
                bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                table.insert(bodies, bv)
                game:GetService("Debris"):AddItem(bv, 0.05)
            end
            return bodies
        end,
        ["ImpulseFling2"] = function(rootPart, power, dir)
            local bodies = {}

            for i = 1, 100 do
                local bv = Instance.new("BodyVelocity")
                bv.Parent = rootPart
                bv.Velocity = dir * power * 9e9
                bv.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                table.insert(bodies, bv)
                game:GetService("Debris"):AddItem(bv, 0.05 + (i * 0.001))
            end

            for i = 1, 100 do
                local bf = Instance.new("BodyForce")
                bf.Parent = rootPart
                bf.Force = dir * power * 9e9
                table.insert(bodies, bf)
                game:GetService("Debris"):AddItem(bf, 0.1 + (i * 0.01))
            end

            for i = 1, 100 do
                local bt = Instance.new("BodyThrust")
                bt.Parent = rootPart
                bt.Force = dir * power * 9e9
                bt.Location = rootPart.Position + Vector3.new(0, 1, 0) * i
                table.insert(bodies, bt)
                game:GetService("Debris"):AddItem(bt, 0.1 + (i * 0.01))
            end

            for i = 1, 100 do
                local gyro = Instance.new("BodyGyro")
                gyro.Parent = rootPart
                gyro.MaxTorque = Vector3.new(9e9, 9e9, 9e9)
                gyro.CFrame = CFrame.new(rootPart.Position, rootPart.Position + Vector3.new(1, 1, 1) * i)
                table.insert(bodies, gyro)
                game:GetService("Debris"):AddItem(gyro, 0.1 + (i * 0.01))
            end

            for i = 1, 100 do
                local bp = Instance.new("BodyPosition")
                bp.Parent = rootPart
                bp.Position = rootPart.Position + dir * 9e9 * i
                bp.MaxForce = Vector3.new(9e9, 9e9, 9e9)
                table.insert(bodies, bp)
                game:GetService("Debris"):AddItem(bp, 0.1 + (i * 0.01))
            end

            return bodies
        end,
        ["AlignPositionFling"] = function(rootPart, power, dir)
            local align = Instance.new("AlignPosition")
            align.Parent = rootPart

            local att = Instance.new("Attachment")
            att.Parent = rootPart
            align.Attachment0 = att

            local targetPart = Instance.new("Part")
            targetPart.Position = rootPart.Position + dir * 100
            targetPart.Anchored = true
            targetPart.CanCollide = false
            targetPart.Parent = workspace

            local att2 = Instance.new("Attachment")
            att2.Parent = targetPart
            align.Attachment1 = att2

            align.RigidityEnabled = false
            align.MaxForce = power * 10000

            game:GetService("Debris"):AddItem(align, 0.5)
            game:GetService("Debris"):AddItem(targetPart, 0.5)
            return align
        end,
    }

    local currentMethod = "BodyVelocity"
    local methodList = {"BodyVelocity", "FlingNEW", "BodyThrust", "BodyForce", "VectorForce", "LinearVelocity","ExplodeFling","RocketFling","TorqueFling","ImpulseFling1","ImpulseFling2","AlignPositionFling","PhysicsRepFling","NaNFling"}
    local methodIndex = 1
    MethodButton.MouseButton1Click:Connect(function()
        methodIndex = methodIndex % #methodList + 1
        currentMethod = methodList[methodIndex]
        MethodButton.Text = "Method: " .. currentMethod
    end)

    local function SkidFling(TargetPlayer)
        local Character = Player.Character
        local Humanoid = Character and Character:FindFirstChildOfClass("Humanoid")
        local RootPart = Humanoid and Humanoid.RootPart
        local TCharacter = TargetPlayer.Character
        if not TCharacter then return end

        local THumanoid = TCharacter:FindFirstChildOfClass("Humanoid")
        local TRootPart = THumanoid and THumanoid.RootPart
        local THead = TCharacter:FindFirstChild("Head")
        local Accessory = TCharacter:FindFirstChildOfClass("Accessory")
        local Handle = Accessory and Accessory:FindFirstChild("Handle")

        if not Character or not Humanoid or not RootPart then return end

        if RootPart.Velocity.Magnitude < 50 then
            getgenv().OldPos = RootPart.CFrame
        end

        if THumanoid and THumanoid.Sit then
            return notify("Error", TargetPlayer.Name .. " is sitting", 2)
        end

        if THead then
            --workspace.CurrentCamera.CameraSubject = THead
        elseif Handle then
            --workspace.CurrentCamera.CameraSubject = Handle
        elseif THumanoid and TRootPart then
            --workspace.CurrentCamera.CameraSubject = THumanoid
        end

        if not TCharacter:FindFirstChildWhichIsA("BasePart") then
            return
        end

        local FPos = function(BasePart, Pos, Ang)
            RootPart.CFrame = CFrame.new(BasePart.Position) * Pos * Ang
            Character:SetPrimaryPartCFrame(CFrame.new(BasePart.Position) * Pos * Ang)
            RootPart.Velocity = Vector3.new(9e9, 9e9, 9e9)
            RootPart.RotVelocity = Vector3.new(9e9, 9e9, 9e9)
        end

        local SFBasePart = function(BasePart)
            local startTime = tick()
            local angle = 0
            local moveDir = THumanoid.MoveDirection
            local speed = THumanoid.WalkSpeed

            repeat
                if not RootPart or not THumanoid or not BasePart or not BasePart.Parent then break end

                local velMag = BasePart.Velocity.Magnitude
                local posOffset = CFrame.new(0, 1.5, 0) + moveDir * (velMag / 1.25)
                local negOffset = CFrame.new(0, -1.5, 0) + moveDir * (velMag / 1.25)

                if velMag < 50 then
                    angle = angle + 100
                    local ang = CFrame.Angles(math.rad(angle), 0, 0)

                    FPos(BasePart, posOffset, ang)
                    task.wait()
                    FPos(BasePart, negOffset, ang)
                    task.wait()
                    FPos(BasePart, posOffset, ang)
                    task.wait()
                    FPos(BasePart, negOffset, ang)
                    task.wait()
                    FPos(BasePart, CFrame.new(0, 1.5, 0) + moveDir, ang)
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, 0) + moveDir, ang)
                    task.wait()
                else
                    local high = CFrame.Angles(math.rad(90), 0, 0)
                    local zero = CFrame.new()

                    FPos(BasePart, CFrame.new(0, 1.5, speed), high)
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, -speed), zero)
                    task.wait()
                    FPos(BasePart, CFrame.new(0, 1.5, speed), high)
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, 0), high)
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, 0), zero)
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, 0), high)
                    task.wait()
                    FPos(BasePart, CFrame.new(0, -1.5, 0), zero)
                    task.wait()
                end
            until tick() - startTime >= 2 or not FlingActive
        end

        workspace.FallenPartsDestroyHeight = 0/0

        local dir = Vector3.new(0, 1, 0)
        local power = 10
        local body = FlingMethods[currentMethod](RootPart, power, dir)

        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, false)

        if TRootPart then
            SFBasePart(TRootPart)
        elseif THead then
            SFBasePart(THead)
        elseif Handle then
            SFBasePart(Handle)
        else
            return notify("Error", TargetPlayer.Name .. " has no valid parts", 2)
        end

        local body = FlingMethods[currentMethod](RootPart, power, dir)
        if type(body) == "table" then
            for _, obj in ipairs(body) do
                if obj and obj.Destroy then
                    obj:Destroy()
                end
            end
        elseif body and body.Destroy then
            body:Destroy()
        end
        Humanoid:SetStateEnabled(Enum.HumanoidStateType.Seated, true)
        --workspace.CurrentCamera.CameraSubject = Humanoid

        if getgenv().OldPos then
            repeat
                RootPart.CFrame = getgenv().OldPos * CFrame.new(0, .5, 0)
                Character:SetPrimaryPartCFrame(getgenv().OldPos * CFrame.new(0, .5, 0))
                Humanoid:ChangeState("GettingUp")
                for _, part in pairs(Character:GetChildren()) do
                    if part:IsA("BasePart") then
                        part.Velocity, part.RotVelocity = Vector3.new(), Vector3.new()
                    end
                end
                task.wait()
            until (RootPart.Position - getgenv().OldPos.p).Magnitude < 25
            workspace.FallenPartsDestroyHeight = getgenv().FPDH
        end
    end

    local function StartFling()
        if FlingActive then return end

        local count = CountSelectedTargets()
        if count == 0 then
            StatusLabel.Text = "No targets selected!"
            wait(1)
            StatusLabel.Text = "Select targets to fling"
            return
        end

        FlingActive = true
        UpdateStatus()
        notify("Started", "Flinging " .. count .. " targets", 2)

        spawn(function()
            while FlingActive do
                local validTargets = {}

                for name, other in pairs(SelectedTargets) do
                    if other and other.Parent then
                        validTargets[name] = other
                    else
                        SelectedTargets[name] = nil
                        local checkbox = PlayerCheckboxes[name]
                        if checkbox then
                            checkbox.Checkmark.Visible = false
                        end
                    end
                end

                for _, other in pairs(validTargets) do
                    if FlingActive then
                        SkidFling(other)
                        wait(0.1)
                    else
                        break
                    end
                end

                UpdateStatus()

                wait(0.5)
            end
        end)
    end

    local function StopFling()
        if not FlingActive then return end

        FlingActive = false

        local character = Player.Character
        if character then
            for _, v in pairs(character:GetDescendants()) do
                if v:IsA("BodyVelocity") or v:IsA("BodyForce") or v:IsA("BodyThrust") or
                   v:IsA("LinearVelocity") or v:IsA("VectorForce") or v:IsA("RocketPropulsion") or
                   v:IsA("AlignPosition") or v:IsA("Torque") then
                    v:Destroy()
                end
            end

            pcall(function()
                sethiddenproperty(character.HumanoidRootPart, "PhysicsRepRootPart", character.HumanoidRootPart)
            end)
        end

        UpdateStatus()
        notify("Stopped", "Fling has been stopped", 2)
    end

    StartButton.MouseButton1Click:Connect(StartFling)
    StopButton.MouseButton1Click:Connect(StopFling)
    SelectAllButton.MouseButton1Click:Connect(function() ToggleAllPlayers(true) end)
    DeselectAllButton.MouseButton1Click:Connect(function() ToggleAllPlayers(false) end)
    CloseButton.MouseButton1Click:Connect(function()
        StopFling()
        ScreenGui:Destroy()
    end)

    Players.PlayerAdded:Connect(RefreshPlayerList)
    Players.PlayerRemoving:Connect(function(other)
        if SelectedTargets[other.Name] then
            SelectedTargets[other.Name] = nil
        end
        RefreshPlayerList()
        UpdateStatus()
    end)

    RefreshPlayerList()
    UpdateStatus()
end
