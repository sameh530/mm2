local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local LocalPlayer = Players.LocalPlayer
local wrap = newcclosure or function(f) return f end

-- 1. حظر HandleTouched عبر __namecall
if hookmetamethod and getnamecallmethod then
    local oldNamecall
    oldNamecall = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        local method = getnamecallmethod()
        if (method == "FireServer" or method == "InvokeServer") and typeof(self) == "Instance" then
            if self.Name == "HandleTouched" then
                return nil
            end
        end
        return oldNamecall(self, ...)
    end))
end

-- 2. حظر HandleTouched عبر الاستدعاء المباشر FireServer (حماية إضافية ضد السكربتات)
if hookfunction then
    pcall(function()
        local dummy = Instance.new("RemoteEvent")
        local oldFire
        oldFire = hookfunction(dummy.FireServer, wrap(function(self, ...)
            if typeof(self) == "Instance" and self.Name == "HandleTouched" then
                return nil
            end
            return oldFire(self, ...)
        end))
        dummy:Destroy()
    end)
end

-- 3. تعطيل التلامس الفيزيائي للسكين فقط
RunService.Heartbeat:Connect(function()
    local char = LocalPlayer.Character
    if not char then return end
    local knife = char:FindFirstChild("Knife")
    if knife then
        for _, desc in ipairs(knife:GetDescendants()) do
            if desc:IsA("TouchTransmitter") then
                pcall(function() desc:Destroy() end)
            elseif desc:IsA("BasePart") and desc.CanTouch then
                desc.CanTouch = false
            end
        end
    end
end)

-- 4. إخفاء زر الطعن في الهاتف فقط
task.spawn(function()
    local pGui = LocalPlayer:WaitForChild("PlayerGui")
    local function hideStabOnly(obj)
        if obj:IsA("GuiButton") then
            local n = obj.Name:lower()
            if (n:find("stab") or n:find("slash")) and not (n:find("throw") or n:find("shoot") or n:find("gun")) then
                obj.Visible = false
                obj.Active = false
                obj:GetPropertyChangedSignal("Visible"):Connect(function()
                    if obj.Visible then obj.Visible = false end
                end)
            end
        end
    end
    for _, v in ipairs(pGui:GetDescendants()) do hideStabOnly(v) end
    pGui.DescendantAdded:Connect(hideStabOnly)
end)
