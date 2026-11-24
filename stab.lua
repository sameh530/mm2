local TeleportService = game:GetService("TeleportService")
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local qot = queue_on_teleport or (syn and syn.queue_on_teleport) or (fluxus and fluxus.queue_on_teleport) or queueonteleport
local env = (getgenv and getgenv()) or _G

-- الجزء الخاص بتزييف البيسي ومنع الطعن (يتم حفظه وتشغيله بعد الـ Rejoin)
local mainCode = [[
local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local wrap = newcclosure or function(f) return f end

local function isCoreControl(scr)
    if not scr then return false end
    local n = scr.Name:lower()
    local p = scr.Parent and scr.Parent.Name:lower() or ""
    return n:find("control") or n:find("touch") or n:find("thumbstick") or n:find("camera") or n:find("jump") or n:find("playermodule")
        or p:find("control") or p:find("playermodule")
end

if hookmetamethod then
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", wrap(function(self, key)
        if not (checkcaller and checkcaller()) and self == UIS then
            local scr = getcallingscript and getcallingscript()
            if not isCoreControl(scr) then
                if key == "TouchEnabled" or key == "GamepadEnabled" then
                    return false
                elseif key == "MouseEnabled" or key == "KeyboardEnabled" then
                    return true
                end
            end
        end
        return oldIndex(self, key)
    end))

    if getnamecallmethod then
        local oldNamecall
        oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
            if not (checkcaller and checkcaller()) then
                local method = getnamecallmethod()
                local scr = getcallingscript and getcallingscript()

                if self == UIS and not isCoreControl(scr) then
                    if method == "GetLastInputType" then
                        return Enum.UserInputType.MouseMovement
                    elseif method == "GetPlatform" then
                        return Enum.Platform.Windows
                    end
                end

                if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
                    local name = self.Name:lower()
                    if not name:find("throw") then
                        local p1 = self.Parent
                        local p2 = p1 and p1.Parent
                        local isKnife = (p1 and p1:IsA("Tool") and p1.Name:lower():find("knife"))
                            or (p2 and p2:IsA("Tool") and p2.Name:lower():find("knife"))
                        if isKnife or name:find("stab") or name:find("slash") then
                            return nil
                        end
                    end
                end
            end
            return oldNamecall(self, ...)
        end))
    end
end

if not game:IsLoaded() then game.Loaded:Wait() end
local LocalPlayer = Players.LocalPlayer
while not LocalPlayer do task.wait(); LocalPlayer = Players.LocalPlayer end

local isHoldingKnife = false
local throwBtnRef = nil

local function getEquippedKnife()
    local char = LocalPlayer.Character
    if not char then return nil end
    for _, c in ipairs(char:GetChildren()) do
        if c:IsA("Tool") and c.Name:lower():find("knife") then return c end
    end
    return nil
end

local function updateKnifeState()
    local k = getEquippedKnife()
    isHoldingKnife = (k ~= nil)
    if throwBtnRef then throwBtnRef.Visible = isHoldingKnife end
end

local function nerfKnife(tool)
    if not (tool:IsA("Tool") and tool.Name:lower():find("knife")) then return end
    task.wait(0.15)
    if getconnections then
        for _, conn in pairs(getconnections(tool.Activated)) do
            pcall(function() conn:Disable() end)
        end
    end
    for _, desc in ipairs(tool:GetDescendants()) do
        if desc:IsA("TouchTransmitter") then
            pcall(function() desc:Destroy() end)
        elseif desc:IsA("BasePart") then
            pcall(function() desc.CanTouch = false end)
        elseif (desc:IsA("RemoteEvent") or desc:IsA("RemoteFunction")) and not desc.Name:lower():find("throw") then
            pcall(function() desc:Destroy() end)
        end
    end
end

local function watch(container)
    if not container then return end
    container.ChildAdded:Connect(function(c) updateKnifeState(); nerfKnife(c) end)
    container.ChildRemoved:Connect(updateKnifeState)
    for _, c in ipairs(container:GetChildren()) do nerfKnife(c) end
    updateKnifeState()
end

if LocalPlayer.Character then watch(LocalPlayer.Character) end
LocalPlayer.CharacterAdded:Connect(watch)
if LocalPlayer:FindFirstChildOfClass("Backpack") then watch(LocalPlayer:FindFirstChildOfClass("Backpack")) end
LocalPlayer.ChildAdded:Connect(function(c) if c:IsA("Backpack") then watch(c) end end)

task.spawn(function()
    local guiParent = (gethui and gethui()) or game:GetService("CoreGui")
    if guiParent:FindFirstChild("MM2PCModeUI") then guiParent.MM2PCModeUI:Destroy() end

    local sg = Instance.new("ScreenGui", guiParent)
    sg.Name = "MM2PCModeUI"
    sg.ResetOnSpawn = false
    sg.IgnoreGuiInset = true

    local ch = Instance.new("Frame", sg)
    ch.Size = UDim2.new(0, 8, 0, 8)
    ch.Position = UDim2.new(0.5, -4, 0.5, -4)
    ch.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    ch.Visible = false
    Instance.new("UICorner", ch).CornerRadius = UDim.new(1, 0)
    Instance.new("UIStroke", ch).Thickness = 1.5

    local lockBtn = Instance.new("TextButton", sg)
    lockBtn.Size = UDim2.new(0, 60, 0, 60)
    lockBtn.Position = UDim2.new(1, -90, 1, -210)
    lockBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
    lockBtn.BackgroundTransparency = 0.3
    lockBtn.Text = "LOCK"
    lockBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    lockBtn.Font = Enum.Font.GothamBold
    lockBtn.TextSize = 14
    Instance.new("UICorner", lockBtn).CornerRadius = UDim.new(1, 0)
    local lStroke = Instance.new("UIStroke", lockBtn)
    lStroke.Color = Color3.fromRGB(255, 255, 255)
    lStroke.Thickness = 2

    local throwBtn = Instance.new("TextButton", sg)
    throwBtn.Size = UDim2.new(0, 72, 0, 72)
    throwBtn.Position = UDim2.new(1, -180, 1, -145)
    throwBtn.BackgroundColor3 = Color3.fromRGB(190, 30, 30)
    throwBtn.BackgroundTransparency = 0.2
    throwBtn.Text = "THROW"
    throwBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
    throwBtn.Font = Enum.Font.GothamBold
    throwBtn.TextSize = 15
    throwBtn.Visible = isHoldingKnife
    Instance.new("UICorner", throwBtn).CornerRadius = UDim.new(1, 0)
    local tStroke = Instance.new("UIStroke", throwBtn)
    tStroke.Color = Color3.fromRGB(255, 255, 255)
    tStroke.Thickness = 2
    throwBtnRef = throwBtn

    local shiftOn = false
    lockBtn.Activated:Connect(function()
        shiftOn = not shiftOn
        ch.Visible = shiftOn
        lockBtn.BackgroundColor3 = shiftOn and Color3.fromRGB(0, 145, 255) or Color3.fromRGB(25, 25, 25)
        if not shiftOn then
            local hum = LocalPlayer.Character and LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
            if hum then hum.AutoRotate = true; hum.CameraOffset = Vector3.new(0, 0, 0) end
        end
    end)

    RunService.RenderStepped:Connect(function()
        if not shiftOn then return end
        local char = LocalPlayer.Character
        local hum = char and char:FindFirstChildOfClass("Humanoid")
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if hum and hrp and cam and hum.Health > 0 then
            hum.AutoRotate = false
            hum.CameraOffset = Vector3.new(1.75, 0, 0)
            local look = cam.CFrame.LookVector
            local flat = Vector3.new(look.X, 0, look.Z)
            if flat.Magnitude > 0.001 then
                hrp.CFrame = CFrame.new(hrp.Position, hrp.Position + flat)
            end
        end
    end)

    local debounce = false
    throwBtn.Activated:Connect(function()
        if debounce then return end
        local knife = getEquippedKnife()
        local cam = workspace.CurrentCamera
        if not (knife and cam) then return end
        debounce = true
        pcall(function()
            local vp = cam.ViewportSize
            local ray = cam:ViewportPointToRay(vp.X * 0.5, vp.Y * 0.5)
            local targetPos = ray.Origin + (ray.Direction * 500)
            for _, desc in ipairs(knife:GetDescendants()) do
                if desc:IsA("RemoteEvent") and desc.Name:lower():find("throw") then
                    desc:FireServer(CFrame.new(targetPos), targetPos)
                end
            end
        end)
        task.wait(0.2)
        debounce = false
    end)
end)
]]

-- حفظ الكود في ذاكرة Delta المحلية وعمل Rejoin فوري
if not env.__MM2_PC_SPOOFED then
    if writefile and readfile and qot then
        writefile("mm2_pc_mode.lua", mainCode)
        qot('local e=(getgenv and getgenv())or _G;e.__MM2_PC_SPOOFED=true;loadstring(readfile("mm2_pc_mode.lua"))()')
        
        local lp = Players.LocalPlayer
        while not lp do task.wait(); lp = Players.LocalPlayer end
        
        local ok = pcall(function()
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, lp)
        end)
        if not ok then
            TeleportService:Teleport(game.PlaceId, lp)
        end
        return
    end
end

-- تشغيل مباشر في حال لم يدعم الهاك إعادة الدخول
loadstring(mainCode)()
