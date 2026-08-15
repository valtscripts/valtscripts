--[[==============================================================
    🐒 POTATO — MONKEY ESCAPE AUTO   (place 114697347887839)
    Features:
      🛡️ Anti-Death   — blocks the client's Died signal = invincible
                        (crushers/axes can't kill you)
      Auto Rebirth        — rebirths when eligible (more speed)
      Auto Spin Wheel     — spins the wheel
      Auto Free Reward    — claims free playtime reward
      Auto Offline Earn.  — claims offline earnings
      Auto Join Race      — auto-joins races
      Auto Equip Charms   — equips your best charms
      ⚡ Speed Boost      — walkspeed boost (it's a speed game)
    Unload: End key.
================================================================]]--
if getgenv().__PM then getgenv().__PM.u() end

local RS   = game:GetService("ReplicatedStorage")
local RunS = game:GetService("RunService")
local UIS  = game:GetService("UserInputService")
local LP   = game:GetService("Players").LocalPlayer

local Rem = RS:WaitForChild("Remotes")
local function F(name) local r = Rem:FindFirstChild(name); if r then pcall(function() r:FireServer() end) end end

local W=Color3.fromRGB(255,255,255); local G=Color3.fromRGB(70,220,120); local R=Color3.fromRGB(255,80,80); local GD=Color3.fromRGB(255,190,70)

local S = { AntiDeath=false, Rebirth=false, Wheel=false, FreeReward=false, Offline=false, Race=false, Charms=false, Speed=false }
local T = {}
local alive = true

--== ANTI-DEATH: block the client from firing Died ==--
local Died = Rem:FindFirstChild("Died")
local oldNC
oldNC = hookmetamethod(game, "__namecall", newcclosure(function(self, ...)
    if S.AntiDeath and self == Died and getnamecallmethod() == "FireServer" then return end
    return oldNC(self, ...)
end))

--== SPEED BOOST ==--
task.spawn(function()
    while alive do
        if S.Speed then
            local c = LP.Character; local h = c and c:FindFirstChildOfClass("Humanoid")
            if h then pcall(function() h.WalkSpeed = math.max(h.WalkSpeed, 60) * 1.6 end) end
        end
        task.wait(0.25)
    end
end)

--== AUTO LOOPS ==--
local run = RunS.Heartbeat:Connect(function()
    local n = os.clock()
    local jobs = {
        {"Rebirth",1.5,"Rebirth"}, {"Wheel",1.5,"SpawnWheel"},
        {"FreeReward",2,"ClaimFreeReward"}, {"Race",3,"JoinRace"}, {"Charms",3,"EquipBestCharms"},
    }
    for _, j in ipairs(jobs) do
        if S[j[1]] and (n - (T[j[1]] or 0)) >= j[2] then T[j[1]] = n; F(j[3]) end
    end
    if S.Offline and (n - (T.Off or 0)) >= 3 then T.Off = n; F("RequestOfflineEarnings"); F("ClaimOfflineEarnings") end
end)

--== GUI ==--
local hui = (typeof(gethui)=="function") and gethui() or game:GetService("CoreGui")
local sg = Instance.new("ScreenGui"); sg.ResetOnSpawn=false; sg.IgnoreGuiInset=true; sg.Parent=hui
local m = Instance.new("Frame"); m.Size=UDim2.fromOffset(266,364); m.Position=UDim2.fromOffset(40,110)
m.BackgroundColor3=Color3.fromRGB(18,18,24); m.BorderSizePixel=0; m.Active=true; m.Parent=sg
Instance.new("UICorner",m).CornerRadius=UDim.new(0,10)
local sk=Instance.new("UIStroke",m); sk.Color=GD; sk.Thickness=1.5
local bar=Instance.new("Frame"); bar.Size=UDim2.new(1,0,0,32); bar.BackgroundColor3=Color3.fromRGB(28,28,38); bar.BorderSizePixel=0; bar.Parent=m
Instance.new("UICorner",bar).CornerRadius=UDim.new(0,10)
local tt=Instance.new("TextLabel"); tt.Size=UDim2.new(1,-12,1,0); tt.Position=UDim2.fromOffset(12,0); tt.BackgroundTransparency=1
tt.Font=Enum.Font.GothamBold; tt.TextSize=14; tt.TextColor3=GD; tt.TextXAlignment=Enum.TextXAlignment.Left; tt.Text="🐒 MONKEY ESCAPE AUTO"; tt.Parent=bar
local lf=Instance.new("Frame"); lf.Size=UDim2.new(1,-16,1,-42); lf.Position=UDim2.fromOffset(8,38); lf.BackgroundTransparency=1; lf.Parent=m
local ly=Instance.new("UIListLayout",lf); ly.Padding=UDim.new(0,5); local od=0
local function tg(k,txt,col)
    od+=1; local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,28); b.BackgroundColor3=Color3.fromRGB(26,26,34); b.BorderSizePixel=0
    b.Font=Enum.Font.GothamBold; b.TextSize=13; b.TextColor3=col or W; b.TextXAlignment=Enum.TextXAlignment.Left; b.LayoutOrder=od; b.Parent=lf
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); Instance.new("UIPadding",b).PaddingLeft=UDim.new(0,10); b.Text=txt
    local dt=Instance.new("Frame"); dt.Size=UDim2.fromOffset(11,11); dt.Position=UDim2.new(1,-22,0.5,-5); dt.BorderSizePixel=0; dt.Parent=b
    Instance.new("UICorner",dt).CornerRadius=UDim.new(1,0)
    local function pt() dt.BackgroundColor3=S[k] and G or R end pt()
    b.MouseButton1Click:Connect(function() S[k]=not S[k]; pt() end)
end
tg("AntiDeath","🛡️ Anti-Death",GD)
tg("Rebirth","Auto Rebirth")
tg("Wheel","Auto Spin Wheel")
tg("FreeReward","Auto Free Reward")
tg("Offline","Auto Offline Earnings")
tg("Race","Auto Join Race")
tg("Charms","Auto Equip Best Charms")
tg("Speed","⚡ Speed Boost")

-- Discord invite — an ACTION button (not a toggle): copies the link on click.
-- This GUI has no tabs and no notification popups, so the confirmation is
-- shown right on the button's own text.
do
    od+=1
    local DISCORD_INVITE = "https://discord.gg/SgBZtPnTkd"
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,28); b.BackgroundColor3=Color3.fromRGB(38,42,70); b.BorderSizePixel=0
    b.Font=Enum.Font.GothamBold; b.TextSize=13; b.TextColor3=Color3.fromRGB(150,175,255); b.TextXAlignment=Enum.TextXAlignment.Left; b.LayoutOrder=od; b.Parent=lf
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); Instance.new("UIPadding",b).PaddingLeft=UDim.new(0,10)
    b.Text="💬 Discord - Copy Invite"
    b.MouseButton1Click:Connect(function()
        local copy = (setclipboard) or (toclipboard) or (writeclipboard) or (syn and syn.write_clipboard)
        local ok = copy ~= nil and pcall(copy, DISCORD_INVITE)
        b.Text = ok and "✓ Copied! discord.gg/SgBZtPnTkd" or "discord.gg/SgBZtPnTkd"
        task.delay(2.5, function() if b and b.Parent then b.Text = "💬 Discord - Copy Invite" end end)
    end)
end

do
    local dg,ds,sp
    bar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dg=true; ds=i.Position; sp=m.Position
        i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dg=false end end) end end)
    UIS.InputChanged:Connect(function(i) if dg and i.UserInputType==Enum.UserInputType.MouseMovement then
        local d=i.Position-ds; m.Position=UDim2.fromOffset(sp.X.Offset+d.X, sp.Y.Offset+d.Y) end end)
end

local function u()
    alive=false; for k in pairs(S) do S[k]=false end
    pcall(function() run:Disconnect() end)
    pcall(function() hookmetamethod(game,"__namecall",oldNC) end)
    pcall(function() sg:Destroy() end); getgenv().__PM=nil
end
UIS.InputBegan:Connect(function(i,gp) if not gp and i.KeyCode==Enum.KeyCode.End then u() end end)
getgenv().__PM = { S=S, u=u }
warn("[🐒 POTATO MONKEY ESCAPE AUTO] loaded — End to unload.")
