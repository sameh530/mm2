local SCRIPT_BODY = [=[
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local VIM = game:GetService("VirtualInputManager")

local isHoldingKnife = false
local wrap = newcclosure or function(f) return f end

local function isCoreControlScript(scr)
    if not scr then return false end
    local sName = string.lower(scr.Name)
    if string.find(sName, "control", 1, true)
        or string.find(sName, "touch", 1, true)
        or string.find(sName, "thumbstick", 1, true)
        or string.find(sName, "camera", 1, true)
        or string.find(sName, "playermodule", 1, true)
        or string.find(sName, "jump", 1, true) then
        return true
    end
    local p = scr.Parent
    if p then
        local pName = string.lower(p.Name)
        if string.find(pName, "control", 1, true)
            or string.find(pName, "playermodule", 1, true)
            or string.find(pName, "camera", 1, true) then
            return true
        end
    end
    return false
end

local function shouldBlockRemote(self)
    if typeof(self) ~= "Instance" then return false end
    local className = self.ClassName
    if className ~= "RemoteEvent" and className ~= "RemoteFunction" then return false end
    local name = string.lower(self.Name)
    if string.find(name, "throw", 1, true) then return false end

    local p1 = self.Parent
    local p2 = p1 and p1.Parent
    local p3 = p2 and p2.Parent

    if (p1 and p1.ClassName == "Tool" and string.find(string.lower(p1.Name), "knife", 1, true))
        or (p2 and p2.ClassName == "Tool" and string.find(string.lower(p2.Name), "knife", 1, true))
        or (p3 and p3.ClassName == "Tool" and string.find(string.lower(p3.Name), "knife", 1, true)) then
        return true
    end

    if isHoldingKnife then
        if p1 then
            local pName = string.lower(p1.Name)
            if string.find(pName, "trade", 1, true) or string.find(pName, "shop", 1, true) or string.find(pName, "inv", 1, true) then
                return false
            end
        end
        if name == "stab" or name == "slash" or name == "attack" or name == "swing" or name == "hit"
            or ((string.find(name, "stab", 1, true) or string.find(name, "slash", 1, true)) and not string.find(name, "slasher", 1, true)) then
            return true
        end
    end

    return false
end

if hookmetamethod then
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", wrap(function(self, key)
        if not (checkcaller and checkcaller()) and self == UIS then
            if key == "TouchEnabled" or key == "MouseEnabled" or key == "KeyboardEnabled" or key == "GamepadEnabled" then
                local scr = getcallingscript and getcallingscript()
                if not isCoreControlScript(scr) then
                    if key == "TouchEnabled" or key == "GamepadEnabled" then
                        return false
                    else
                        return true
                    end
                end
            end
        end
        return oldIndex(self, key)
    end))
end

if hookmetamethod and getnamecallmethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        if not (checkcaller and checkcaller()) then
            local method = getnamecallmethod()
            if self == UIS and method == "GetLastInputType" then
                return Enum.UserInputType.MouseMovement
            end
            if (method == "FireServer" or method == "InvokeServer") and shouldBlockRemote(self) then
                return nil
            end
        end
        return oldNamecall(self, ...)
    end))
end

if not game:IsLoaded() then
    game.Loaded:Wait()
end

local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do
    task.wait()
    LocalPlayer = Players.LocalPlayer
end

local throwBtnRef = nil

local function updateKnifeState(char)
    if not char then
        isHoldingKnife = false
        if throwBtnRef then throwBtnRef.Visible = false end
        return
    end
    local found = false
    for _, child in ipairs(char:GetChildren()) do
        if child:IsA("Tool") and string.find(string.lower(child.Name), "knife", 1, true) then
            found = true
            break
        end
    end
    isHoldingKnife = found
    if throwBtnRef then
        throwBtnRef.Visible = found
    end
end

local function nerfKnifePart(obj)
    if obj:IsA("TouchTransmitter") then
        pcall(function() obj:Destroy() end)
    elseif obj:IsA("BasePart") then
        pcall(function()
            obj.CanTouch = false
            obj:GetPropertyChangedSignal("CanTouch"):Connect(function()
                if obj.CanTouch then
                    obj.CanTouch = false
                end
            end)
        end)
        if getconnections then
            for _, conn in pairs(getconnections(obj.Touched)) do
                pcall(function() conn:Disable() end)
            end
        end
    end
end

local function destroyKnifeStabRemotes(tool)
    for _, desc in ipairs(tool:GetDescendants()) do
        if (desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction")) and not string.find(string.lower(desc.Name), "throw", 1, true) then
            pcall(function() desc:Destroy() end)
        end
    end
end

local function disableKnifeConnections(tool)
    if getconnections then
        for _, conn in pairs(getconnections(tool.Activated)) do
            pcall(function() conn:Disable() end)
        end
    end
    for _, desc in ipairs(tool:GetDescendants()) do
        nerfKnifePart(desc)
    end
end

local function handleKnife(tool)
    if tool:IsA("Tool") and string.find(string.lower(tool.Name), "knife", 1, true) then
        task.wait(0.3)
        disableKnifeConnections(tool)
        destroyKnifeStabRemotes(tool)
        tool.DescendantAdded:Connect(function(desc)
            nerfKnifePart(desc)
            if (desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction")) and not string.find(string.lower(desc.Name), "throw", 1, true) then
                task.defer(function()
                    pcall(function() desc:Destroy() end)
                end)
            end
        end)
        tool.Equipped:Connect(function()
            isHoldingKnife = true
            if throwBtnRef then throwBtnRef.Visible = true end
            task.wait(0.05)
            disableKnifeConnections(tool)
            destroyKnifeStabRemotes(tool)
        end)
        tool.Unequipped:Connect(function()
            updateKnifeState(LocalPlayer.Character)
        end)
    end
end

local function watchCharacter(char)
    if not char then return end
    updateKnifeState(char)
    char.ChildAdded:Connect(function(child)
        updateKnifeState(char)
        handleKnife(child)
    end)
    char.ChildRemoved:Connect(function()
        updateKnifeState(char)
    end)
    for _, child in ipairs(char:GetChildren()) do
        handleKnife(child)
    end
end

local function watchBackpack(bp)
    if not bp then return end
    bp.ChildAdded:Connect(handleKnife)
    for _, child in ipairs(bp:GetChildren()) do
        handleKnife(child)
    end
end

if LocalPlayer.Character then
    watchCharacter(LocalPlayer.Character)
end
LocalPlayer.CharacterAdded:Connect(watchCharacter)
LocalPlayer.CharacterRemoving:Connect(function()
    isHoldingKnife = false
    if throwBtnRef then throwBtnRef.Visible = false end
end)

local backpack = LocalPlayer:FindFirstChildOfClass("Backpack")
if backpack then
    watchBackpack(backpack)
end
LocalPlayer.ChildAdded:Connect(function(child)
    if child:IsA("Backpack") then
        watchBackpack(child)
    end
end)

task.spawn(function()
    local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
    local ok = pcall(function() return guiParent.Name end)
    if not ok then
        guiParent = LocalPlayer:WaitForChild("PlayerGui")
    end

    local oldGui = guiParent:FindFirstChild("MM2MobilePCControls")
    if oldGui then oldGui:Destroy() end

    local screenGui = Instance.new("ScreenGui")
    screenGui.Name = "MM2MobilePCControls"
    screenGui.ResetOnSpawn = false
    screenGui.IgnoreGuiInset = true
    screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
    screenGui.Parent = guiParent

    local crosshair = Instance.new("Frame")
    crosshair.Name = "Crosshair"
    crosshair.Size = UDim2.new(0, 8, 0, 8)
    crosshair.Position = UDim2.new(0.5, -4, 0.5, -4)
    crosshair.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    crosshair.BorderSizePixel = 0
    crosshair.Visible = false
    crosshair.Parent = screenGui

    local chCorner = Instance.new("UICorner")
    chCorner.CornerRadius = UDim.new(1, 0)
    chCorner.Parent = crosshair

    local chStroke = Instance.new("UIStroke")
    chStroke.Color = Color3.fromRGB(0, 0, 0)
    chStroke.Thickness = 1.5
    chStroke.Parent = crosshair

    local shiftBtn = Instance.new("TextButton")
    shiftBtn.Name = "ShiftLockButton"
    shiftBtn.Size = UDim2.new(0, 62, 0, 62)
    shiftBtn.Position = UDim2.new(1, -95, 1, -205)
    shiftBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    shiftBtn.BackgroundTransparency = 0.35
    shiftBtn.Text = "LOCK"
    shiftBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    shiftBtn.TextSize = 14
    shiftBtn.Font = Enum.Font.GothamBold
    shiftBtn.AutoButtonColor = true
    shiftBtn.Parent = screenGui

    local shiftCorner = Instance.new("UICorner")
    shiftCorner.CornerRadius = UDim.new(1, 0)
    shiftCorner.Parent = shiftBtn

    local shiftStroke = Instance.new("UIStroke")
    shiftStroke.Color = Color3.fromRGB(255, 255, 255)
    shiftStroke.Thickness = 2
    shiftStroke.Transparency = 0.4
    shiftStroke.Parent = shiftBtn

    local throwBtn = Instance.new("TextButton")
    throwBtn.Name = "ThrowButton"
    throwBtn.Size = UDim2.new(0, 74, 0, 74)
    throwBtn.Position = UDim2.new(1, -185, 1, -140)
    throwBtn.BackgroundColor3 = Color3.fromRGB(180, 35, 35)
    throwBtn.BackgroundTransparency = 0.25
    throwBtn.Text = "THROW"
    throwBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    throwBtn.TextSize = 15
    throwBtn.Font = Enum.Font.GothamBold
    throwBtn.AutoButtonColor = true
    throwBtn.Visible = isHoldingKnife
    throwBtn.Parent = screenGui
    throwBtnRef = throwBtn

    local throwCorner = Instance.new("UICorner")
    throwCorner.CornerRadius = UDim.new(1, 0)
    throwCorner.Parent = throwBtn

    local throwStroke = Instance.new("UIStroke")
    throwStroke.Color = Color3.fromRGB(255, 255, 255)
    throwStroke.Thickness = 2
    throwStroke.Transparency = 0.3
    throwStroke.Parent = throwBtn

    local shiftLockOn = false

    local function setShiftLock(state)
        shiftLockOn = state
        crosshair.Visible = state
        if state then
            shiftBtn.BackgroundColor3 = Color3.fromRGB(0, 145, 255)
            shiftStroke.Color = Color3.fromRGB(120, 210, 255)
        else
            shiftBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
            shiftStroke.Color = Color3.fromRGB(255, 255, 255)
            local char = LocalPlayer.Character
            local hum = char and char:FindFirstChildOfClass("Humanoid")
            if hum then
                hum.AutoRotate = true
                hum.CameraOffset = Vector3.new(0, 0, 0)
            end
        end
    end

    shiftBtn.Activated:Connect(function()
        setShiftLock(not shiftLockOn)
    end)

    RunService.RenderStepped:Connect(function()
        if not shiftLockOn then return end
        local char = LocalPlayer.Character
        if not char then return end
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if hum and hrp and cam and hum.Health > 0 then
            hum.AutoRotate = false
            hum.CameraOffset = Vector3.new(1.75, 0, 0)
            local look = cam.CFrame.LookVector
            local flatLook = Vector3.new(look.X, 0, look.Z)
            if flatLook.Magnitude > 0.001 then
                hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + flatLook)
            end
        end
    end)

    local throwDebounce = false
    throwBtn.Activated:Connect(function()
        if throwDebounce or not isHoldingKnife then return end
        throwDebounce = true
        pcall(function()
            local cam = workspace.CurrentCamera
            if cam then
                local vp = cam.ViewportSize
                VIM:SendMouseMoveEvent(vp.X * 0.5, vp.Y * 0.5, game)
            end
            VIM:SendKeyEvent(true, Enum.KeyCode.E, false, game)
            task.wait(0.06)
            VIM:SendKeyEvent(false, Enum.KeyCode.E, false, game)
        end)
        task.wait(0.15)
        throwDebounce = false
    end)
end)
]=]

local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport) or queueonteleport
local env = (getgenv and getgenv()) or _G

if not env.__MM2_PC_MODE and qot then
    qot("local e=(getgenv and getgenv())or _G;e.__MM2_PC_MODE=true\n" .. SCRIPT_BODY)
    game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, game.JobId, game:GetService("Players").LocalPlayer)
    return
end

loadstring(SCRIPT_BODY)()
