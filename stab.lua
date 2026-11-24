local Players = game:GetService("Players")
local UIS = game:GetService("UserInputService")
local LocalPlayer = Players.LocalPlayer
local isHoldingKnife = false

local function updateKnifeState(char)
    if not char then
        isHoldingKnife = false
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

local wrap = newcclosure or function(f) return f end

if hookmetamethod then
    local oldIndex
    oldIndex = hookmetamethod(game, "__index", wrap(function(self, key)
        if not (checkcaller and checkcaller()) and self == UIS then
            if key == "TouchEnabled" or key == "MouseEnabled" or key == "KeyboardEnabled" then
                local scr = getcallingscript and getcallingscript()
                if scr then
                    local sName = string.lower(scr.Name)
                    local sParent = scr.Parent
                    if string.find(sName, "knife", 1, true) or (sParent and string.find(string.lower(sParent.Name), "knife", 1, true)) then
                        if key == "TouchEnabled" then
                            return false
                        else
                            return true
                        end
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
            if (method == "FireServer" or method == "InvokeServer") and shouldBlockRemote(self) then
                return nil
            end
        end
        return oldNamecall(self, ...)
    end))
elseif getrawmetatable and getnamecallmethod then
    pcall(function()
        local mt = getrawmetatable(game)
        local oldNamecall = mt.__namecall
        if setreadonly then setreadonly(mt, false) end
        mt.__namecall = wrap(function(self, ...)
            if not (checkcaller and checkcaller()) then
                local method = getnamecallmethod()
                if (method == "FireServer" or method == "InvokeServer") and shouldBlockRemote(self) then
                    return nil
                end
            end
            return oldNamecall(self, ...)
        end)
        if setreadonly then setreadonly(mt, true) end
    end)
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
        task.wait(0.1)
        disableKnifeConnections(tool)
        tool.DescendantAdded:Connect(nerfKnifePart)
        tool.Equipped:Connect(function()
            isHoldingKnife = true
            task.wait(0.05)
            disableKnifeConnections(tool)
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
    local playerGui = LocalPlayer:WaitForChild("PlayerGui")
    local blockedUIs = {"trade", "shop", "inv", "lobby", "crate", "menu", "chat", "perk", "effect", "emote", "settings", "profile", "leaderboard"}

    local function isSafeButton(obj)
        if not obj:IsA("GuiButton") then return false end
        local name = string.lower(obj.Name)
        if name ~= "stab" and name ~= "slash" and name ~= "stabbutton" and name ~= "slashbutton" and name ~= "knifestab" and name ~= "knifeslash" then
            return false
        end
        local fullName = string.lower(obj:GetFullName())
        for _, w in ipairs(blockedUIs) do
            if string.find(fullName, w, 1, true) then
                return false
            end
        end
        return true
    end

    local function disableStabButton(obj)
        if not isSafeButton(obj) then return end
        obj.Visible = false
        obj.Active = false
        obj:GetPropertyChangedSignal("Visible"):Connect(function()
            if obj.Visible then
                obj.Visible = false
            end
        end)
        if getconnections then
            for _, ev in ipairs({"Activated", "MouseButton1Click", "MouseButton1Down", "TouchTap"}) do
                local ok, sig = pcall(function() return obj[ev] end)
                if ok and sig then
                    for _, conn in pairs(getconnections(sig)) do
                        pcall(function() conn:Disable() end)
                    end
                end
            end
        end
    end

    for _, desc in ipairs(playerGui:GetDescendants()) do
        disableStabButton(desc)
    end
    playerGui.DescendantAdded:Connect(disableStabButton)
end)
