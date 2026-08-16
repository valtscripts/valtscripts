--[[==============================================================
    POTATO - THE SEA   (place 139802517550914)
    Trimmed build: chests, fly, base teleport, ESP. Nothing else.

    NETWORK
      Nothing here is a plain remote. Everything goes through
      ReplicatedStorage.Network, which stamps a token from
      workspace.ServerAge and encodes args with DataCodec. Requiring the
      module fresh hands back an unbound copy with no .RE, so the live
      table is pulled out of getgc - it is the only one carrying both
      FireServer and a bound .RE.

    VERIFIED
      OpenChest  InvokeServer("OpenChest", <chest model>)
                 -> true on the first open, false once already looted.
                 Range checked server side, so we warp to it first.
      Item names The loot models are named by spawn id ("1786886736");
                 the readable name lives in an Item attribute.

    Q toggles fly. Unload: End.
================================================================]]--
if getgenv().__POTATO_SEA then pcall(getgenv().__POTATO_SEA.u) end

local Players   = game:GetService("Players")
local RunS      = game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local CS        = game:GetService("CollectionService")
local Workspace = game:GetService("Workspace")
local LP        = Players.LocalPlayer

local W  = Color3.fromRGB(255,255,255)
local G  = Color3.fromRGB(120,220,120)
local R  = Color3.fromRGB(255,90,90)
local GD = Color3.fromRGB(120,190,230)

local alive = true
local conns = {}
local function bind(sig, fn) local c = sig:Connect(fn); conns[#conns+1] = c; return c end

local S = { Chest=false, Fly=false, ESP=false, AntiAFK=false }

local RANGE      = 900     -- chest / ESP search radius
local SETTLE     = 0.45    -- pause after warping so the server sees us arrive
local ACT_WAIT   = 0.25
local O2_FLOOR   = 25      -- surface below this: chests can sit underwater
local FLY_SPEED  = 90      -- studs/sec, Shift doubles it

-- ---------- character ----------
local function char() return LP.Character end
local function hrp() local c=char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c=char(); return c and c:FindFirstChildOfClass("Humanoid") end
local function att(n) return LP:GetAttribute(n) end

local function warp(cf)
    local hp = hrp(); if not hp then return false end
    hp.AssemblyLinearVelocity = Vector3.zero
    hp.CFrame = cf
    return true
end

local function pivotOf(inst)
    local ok, p = pcall(function() return inst:GetPivot().Position end)
    return ok and p or nil
end

local function partOf(inst)
    if inst:IsA("BasePart") then return inst end
    return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
end

-- creatures and chests are named properly on the model; only loot spawns hide
-- behind an id, and their real name is the Item attribute
local function itemName(inst, kind)
    if kind == "creature" or kind == "chest" then
        return (inst.Name:gsub("_CLIENT$", ""))
    end
    local n = inst:GetAttribute("Item")
    if type(n) == "string" and n ~= "" then return n end
    local sackKind = inst:GetAttribute("Sack")
    if type(sackKind) == "string" and sackKind ~= "" then return sackKind end
    local p = partOf(inst)
    if p and not tonumber(p.Name) and p.Name ~= "HumanoidRootPart" then return p.Name end
    return inst.Name
end

-- ================= NETWORK =================
local Net = nil
local function network()
    if Net and rawget(Net, "RE") then return Net end
    Net = nil
    if typeof(getgc) == "function" then
        pcall(function()
            for _, v in pairs(getgc(true)) do
                if type(v) == "table" and rawget(v, "FireServer") and rawget(v, "RE") then
                    Net = v
                    return
                end
            end
        end)
    end
    return Net
end

local function invoke(name, ...)
    local n = network(); if not n then return false, nil end
    return pcall(function(...) return n:InvokeServer(name, ...) end, ...)
end

-- ================= STATE =================
local stats = { chests=0 }
local mode, logLine = "idle", ""
local function say(fmt, ...)
    local ok, s = pcall(string.format, fmt, ...)
    logLine = ok and s or tostring(fmt)
end

-- Where you were standing the moment the script loaded. Never overwritten, so
-- Base TP always means the spot you started from.
local baseCF = nil
local function returnToBase()
    if not baseCF then return false end
    mode = "base tp"
    warp(baseCF)
    say("back at base %d, %d, %d",
        math.floor(baseCF.Position.X), math.floor(baseCF.Position.Y), math.floor(baseCF.Position.Z))
    return true
end

-- O2 only drains underwater, so surfacing is a straight Y push
local function o2Guard()
    local o2, hp = att("O2"), hrp()
    if not hp or type(o2) ~= "number" or o2 > O2_FLOOR then return false end
    mode = "surfacing"
    warp(CFrame.new(hp.Position + Vector3.new(0, 18, 0)))
    task.wait(0.6)
    return true
end

-- ================= CHESTS =================
local chestDone = {}

local function chestTargets()
    local hp = hrp(); if not hp then return {} end
    local out = {}
    local folder = Workspace:FindFirstChild("Chests")
    if not folder then return out end
    for _, c in ipairs(folder:GetChildren()) do
        if c:IsA("Model") and not chestDone[c] then
            local p = pivotOf(c)
            if p then
                local d = (p - hp.Position).Magnitude
                if d <= RANGE then out[#out+1] = { inst=c, pos=p, d=d } end
            end
        end
    end
    table.sort(out, function(a,b) return a.d < b.d end)
    return out
end

local function openOne(t)
    warp(CFrame.new(t.pos + Vector3.new(0, 5, 0)))
    task.wait(SETTLE)
    local ok, res = invoke("OpenChest", t.inst)
    task.wait(ACT_WAIT)
    chestDone[t.inst] = true          -- false means already looted; never retry
    if ok and res then
        stats.chests = stats.chests + 1
        say("opened %s", t.inst.Name)
        return true
    end
    return false
end

-- ================= FLY =================
-- BodyVelocity on the root aimed off the camera. Zero input hovers instead of
-- dropping you.
local flyBV, flyGyro

local function stopFly()
    if flyBV then pcall(function() flyBV:Destroy() end); flyBV = nil end
    if flyGyro then pcall(function() flyGyro:Destroy() end); flyGyro = nil end
end

local function startFly()
    local hp = hrp(); if not hp then return end
    stopFly()
    flyBV = Instance.new("BodyVelocity")
    flyBV.Name = "PotatoFly"
    flyBV.MaxForce = Vector3.new(1e6, 1e6, 1e6)
    flyBV.Velocity = Vector3.zero
    flyBV.Parent = hp

    flyGyro = Instance.new("BodyGyro")
    flyGyro.Name = "PotatoFlyGyro"
    flyGyro.MaxTorque = Vector3.new(4e5, 4e5, 4e5)
    flyGyro.P = 1e4
    flyGyro.CFrame = hp.CFrame
    flyGyro.Parent = hp
end

bind(RunS.Heartbeat, function()
    if not alive then return end
    if not S.Fly then
        if flyBV then stopFly() end
        return
    end
    local hp = hrp(); if not hp then return end
    if not flyBV or flyBV.Parent ~= hp then startFly() end
    if not flyBV then return end

    local cam = Workspace.CurrentCamera
    if not cam then return end
    local cf = cam.CFrame
    local dir = Vector3.zero
    if UIS:IsKeyDown(Enum.KeyCode.W) then dir = dir + cf.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.S) then dir = dir - cf.LookVector end
    if UIS:IsKeyDown(Enum.KeyCode.D) then dir = dir + cf.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.A) then dir = dir - cf.RightVector end
    if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
    if UIS:IsKeyDown(Enum.KeyCode.LeftControl) or UIS:IsKeyDown(Enum.KeyCode.LeftAlt) then
        dir = dir - Vector3.new(0, 1, 0)
    end

    local speed = FLY_SPEED * (UIS:IsKeyDown(Enum.KeyCode.LeftShift) and 2 or 1)
    flyBV.Velocity = (dir.Magnitude > 0) and (dir.Unit * speed) or Vector3.zero
    if flyGyro then flyGyro.CFrame = cf end
end)

-- a fresh character loses the movers, so rebuild them on respawn
bind(LP.CharacterAdded, function()
    task.wait(1)
    if alive and S.Fly then startFly() end
end)

-- ================= ESP =================
local ESP_MAX  = 130
local ESP_TICK = 1.0
local espBoard = nil
local espMarks = {}

local ESP_COLOR = {
    loot     = Color3.fromRGB(120, 200, 255),
    chest    = Color3.fromRGB(255, 205, 90),
    creature = Color3.fromRGB(255, 105, 105),
}

local function espClear()
    for inst, mark in pairs(espMarks) do
        pcall(function() if mark.hl then mark.hl:Destroy() end end)
        pcall(function() if mark.gui then mark.gui:Destroy() end end)
        espMarks[inst] = nil
    end
end

local function espMark(inst, kind, dist)
    local mark = espMarks[inst]
    if not mark then
        local hl = Instance.new("Highlight")
        hl.FillColor = ESP_COLOR[kind]
        hl.FillTransparency = 0.65
        hl.OutlineColor = ESP_COLOR[kind]
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        hl.Adornee = inst
        hl.Parent = espBoard

        local gui = Instance.new("BillboardGui")
        gui.Size = UDim2.fromOffset(150, 16)
        gui.StudsOffset = Vector3.new(0, 2.2, 0)
        gui.AlwaysOnTop = true
        gui.MaxDistance = RANGE
        gui.Adornee = partOf(inst)
        gui.Parent = espBoard

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.fromScale(1, 1)
        lbl.BackgroundTransparency = 1
        lbl.Font = Enum.Font.GothamBold
        lbl.TextSize = 11
        lbl.TextColor3 = ESP_COLOR[kind]
        lbl.TextStrokeTransparency = 0.4
        lbl.Parent = gui

        mark = { hl = hl, gui = gui, lbl = lbl }
        espMarks[inst] = mark
    end
    if mark.lbl then
        mark.lbl.Text = string.format("%s  %dm", itemName(inst, kind), math.floor(dist))
    end
    mark.seen = true
end

task.spawn(function()
    while alive do
        pcall(function()
            if not S.ESP then
                if next(espMarks) then espClear() end
                return
            end
            if not espBoard or not espBoard.Parent then
                espBoard = Instance.new("Folder")
                espBoard.Name = "PotatoESP"
                espBoard.Parent = (typeof(gethui)=="function") and gethui() or game:GetService("CoreGui")
            end
            local hp = hrp(); if not hp then return end

            for _, mark in pairs(espMarks) do mark.seen = false end

            local pool = {}
            for _, v in ipairs(CS:GetTagged("Interactable")) do
                if v.Parent then
                    local p = pivotOf(v)
                    if p then
                        local d = (p - hp.Position).Magnitude
                        if d <= RANGE then pool[#pool+1] = { inst=v, kind="loot", d=d } end
                    end
                end
            end
            local chests = Workspace:FindFirstChild("Chests")
            if chests then
                for _, c in ipairs(chests:GetChildren()) do
                    if c:IsA("Model") and not chestDone[c] then
                        local p = pivotOf(c)
                        if p then
                            local d = (p - hp.Position).Magnitude
                            if d <= RANGE then pool[#pool+1] = { inst=c, kind="chest", d=d } end
                        end
                    end
                end
            end
            local cc = Workspace:FindFirstChild("CreatureContainer")
            if cc then
                for _, m in ipairs(cc:GetChildren()) do
                    if m:IsA("Model") then
                        local h = m:FindFirstChildOfClass("Humanoid")
                        if (not h) or h.Health > 0 then
                            local p = pivotOf(m)
                            if p then
                                local d = (p - hp.Position).Magnitude
                                if d <= RANGE then pool[#pool+1] = { inst=m, kind="creature", d=d } end
                            end
                        end
                    end
                end
            end

            table.sort(pool, function(a,b) return a.d < b.d end)
            for i = 1, math.min(#pool, ESP_MAX) do
                espMark(pool[i].inst, pool[i].kind, pool[i].d)
            end

            for inst, mark in pairs(espMarks) do
                if not mark.seen or not inst.Parent then
                    pcall(function() if mark.hl then mark.hl:Destroy() end end)
                    pcall(function() if mark.gui then mark.gui:Destroy() end end)
                    espMarks[inst] = nil
                end
            end
        end)
        task.wait(ESP_TICK)
    end
end)

-- ================= MAIN LOOP =================
task.spawn(function()
    while alive do
        local ok, err = pcall(function()
            if not S.Chest then mode = "idle"; task.wait(0.4); return end
            if not network() then mode = "no network"; task.wait(1); return end
            if o2Guard() then return end

            local targets = chestTargets()
            if #targets == 0 then
                mode = "no chests in range"
                task.wait(1)
                return
            end
            mode = "chests"
            openOne(targets[1])
        end)
        if not ok then mode = "err"; say("%s", tostring(err)) end
        task.wait(0.15)
    end
end)

-- ---------- anti afk ----------
local VirtualUser = game:GetService("VirtualUser")
bind(LP.Idled, function()
    if S.AntiAFK then
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
    end
end)

-- ================= GUI =================
local hui = (typeof(gethui)=="function") and gethui() or game:GetService("CoreGui")
local sg = Instance.new("ScreenGui"); sg.ResetOnSpawn=false; sg.IgnoreGuiInset=true; sg.Parent=hui
local m = Instance.new("Frame"); m.Size=UDim2.fromOffset(300,370); m.Position=UDim2.fromOffset(40,60)
m.BackgroundColor3=Color3.fromRGB(16,22,28); m.BorderSizePixel=0; m.Active=true; m.Parent=sg
Instance.new("UICorner",m).CornerRadius=UDim.new(0,10)
local sk=Instance.new("UIStroke",m); sk.Color=GD; sk.Thickness=1.5
local bar=Instance.new("Frame"); bar.Size=UDim2.new(1,0,0,32); bar.BackgroundColor3=Color3.fromRGB(22,32,42)
bar.BorderSizePixel=0; bar.Parent=m
Instance.new("UICorner",bar).CornerRadius=UDim.new(0,10)
local tt=Instance.new("TextLabel"); tt.Size=UDim2.new(1,-12,1,0); tt.Position=UDim2.fromOffset(12,0)
tt.BackgroundTransparency=1; tt.Font=Enum.Font.GothamBold; tt.TextSize=14; tt.TextColor3=GD
tt.TextXAlignment=Enum.TextXAlignment.Left; tt.Text="POTATO - THE SEA"; tt.Parent=bar

local scroll=Instance.new("ScrollingFrame"); scroll.Size=UDim2.new(1,-16,1,-44); scroll.Position=UDim2.fromOffset(8,38)
scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4; scroll.ScrollBarImageColor3=GD
scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=m
local ly=Instance.new("UIListLayout",scroll); ly.Padding=UDim.new(0,5)
local od=0

od=od+1
local stat=Instance.new("TextLabel"); stat.Size=UDim2.new(1,0,0,60); stat.BackgroundColor3=Color3.fromRGB(24,32,40)
stat.BorderSizePixel=0; stat.Font=Enum.Font.Gotham; stat.TextSize=11; stat.TextColor3=W
stat.TextXAlignment=Enum.TextXAlignment.Left; stat.TextYAlignment=Enum.TextYAlignment.Top
stat.LayoutOrder=od; stat.Text="  ready"; stat.Parent=scroll
Instance.new("UICorner",stat).CornerRadius=UDim.new(0,6)
local pad=Instance.new("UIPadding",stat); pad.PaddingLeft=UDim.new(0,8); pad.PaddingTop=UDim.new(0,6)

local function section(txt)
    od=od+1
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,18); l.BackgroundTransparency=1
    l.Font=Enum.Font.GothamBold; l.TextSize=11; l.TextColor3=Color3.fromRGB(120,150,170)
    l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=txt:upper(); l.LayoutOrder=od; l.Parent=scroll
end

local function tg(key, txt, hint)
    od=od+1
    local h=Instance.new("Frame"); h.Size=UDim2.new(1,0,0,38); h.BackgroundColor3=Color3.fromRGB(24,32,40)
    h.BorderSizePixel=0; h.LayoutOrder=od; h.Parent=scroll
    Instance.new("UICorner",h).CornerRadius=UDim.new(0,6)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-30,0,22); b.Position=UDim2.fromOffset(10,2)
    b.BackgroundTransparency=1; b.Font=Enum.Font.GothamBold; b.TextSize=13; b.TextColor3=W
    b.TextXAlignment=Enum.TextXAlignment.Left; b.Text=txt; b.Parent=h
    local dt=Instance.new("Frame"); dt.Size=UDim2.fromOffset(11,11); dt.Position=UDim2.new(1,-22,0,6)
    dt.BorderSizePixel=0; dt.Parent=h; Instance.new("UICorner",dt).CornerRadius=UDim.new(1,0)
    local hl=Instance.new("TextLabel"); hl.Size=UDim2.new(1,-16,0,12); hl.Position=UDim2.fromOffset(10,23)
    hl.BackgroundTransparency=1; hl.Font=Enum.Font.Gotham; hl.TextSize=10; hl.TextColor3=Color3.fromRGB(130,145,155)
    hl.TextXAlignment=Enum.TextXAlignment.Left; hl.Text=hint; hl.Parent=h
    local function paint() dt.BackgroundColor3 = S[key] and G or R end
    paint()
    b.MouseButton1Click:Connect(function() S[key] = not S[key]; paint() end)
end

local function btn(txt, fn)
    od=od+1
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,28); b.BackgroundColor3=Color3.fromRGB(30,42,54)
    b.BorderSizePixel=0; b.Font=Enum.Font.GothamBold; b.TextSize=12; b.TextColor3=W
    b.Text=txt; b.LayoutOrder=od; b.Parent=scroll
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
    b.MouseButton1Click:Connect(function() pcall(fn, b) end)
    return b
end

section("Farming")
tg("Chest", "Auto Chests", "opens every unlooted chest in range")

section("Movement")
tg("Fly", "Fly  [Q]", "WASD + Space up, Ctrl down, Shift double speed")
btn("Fly Speed  -", function(b)
    FLY_SPEED = math.max(20, FLY_SPEED - 20)
    b.Text = "Fly Speed  -   (" .. FLY_SPEED .. ")"
end)
btn("Fly Speed  +", function(b)
    FLY_SPEED = math.min(400, FLY_SPEED + 20)
    b.Text = "Fly Speed  +   (" .. FLY_SPEED .. ")"
end)
btn("BASE TP", function(b)
    b.Text = returnToBase() and "Back At Base" or "No base recorded"
    task.delay(2, function() if b and b.Parent then b.Text="BASE TP" end end)
end)

section("Visuals")
tg("ESP", "Item ESP", "loot blue, chests gold, creatures red + distance")

section("Misc")
tg("AntiAFK", "Anti AFK", "never get kicked for idling")
btn("Reset Chest List", function(b)
    chestDone = {}
    say("chest list cleared")
    b.Text = "Chest List Reset"
    task.delay(2, function() if b and b.Parent then b.Text="Reset Chest List" end end)
end)

do
    od=od+1
    local DISCORD="https://discord.gg/SgBZtPnTkd"
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,28); b.BackgroundColor3=Color3.fromRGB(38,42,70)
    b.BorderSizePixel=0; b.Font=Enum.Font.GothamBold; b.TextSize=13; b.TextColor3=Color3.fromRGB(150,175,255)
    b.Text="Discord - Copy Invite"; b.LayoutOrder=od; b.Parent=scroll
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6)
    b.MouseButton1Click:Connect(function()
        local copy=(setclipboard) or (toclipboard) or (writeclipboard) or (syn and syn.write_clipboard)
        local ok=copy~=nil and pcall(copy,DISCORD)
        b.Text=ok and "Copied! discord.gg/SgBZtPnTkd" or "discord.gg/SgBZtPnTkd"
        task.delay(2.5,function() if b and b.Parent then b.Text="Discord - Copy Invite" end end)
    end)
end

do
    od=od+1
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,16); l.BackgroundTransparency=1
    l.Font=Enum.Font.Gotham; l.TextSize=10; l.TextColor3=Color3.fromRGB(110,125,135)
    l.Text="Press  End  to unload"; l.LayoutOrder=od; l.Parent=scroll
end

do
    local dragging, dragStart, startPos
    bind(bar.InputBegan, function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dragging=true; dragStart=i.Position; startPos=m.Position
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dragging=false end end)
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dragging and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-dragStart
            m.Position=UDim2.fromOffset(startPos.X.Offset+d.X, startPos.Y.Offset+d.Y)
        end
    end)
end

-- ---------- fly: Q key + an on-screen button for touch ----------
do
    local fg = Instance.new("Frame")
    fg.Size = UDim2.fromOffset(88, 88)
    fg.Position = UDim2.new(1, -110, 1, -180)
    fg.BackgroundTransparency = 1
    fg.Parent = sg

    local flyBtn = Instance.new("TextButton")
    flyBtn.Size = UDim2.fromScale(1, 1)
    flyBtn.BackgroundColor3 = Color3.fromRGB(24, 32, 40)
    flyBtn.BackgroundTransparency = 0.15
    flyBtn.BorderSizePixel = 0
    flyBtn.AutoButtonColor = false
    flyBtn.Font = Enum.Font.GothamBold
    flyBtn.TextSize = 15
    flyBtn.TextColor3 = W
    flyBtn.Text = "FLY\nOFF"
    flyBtn.Parent = fg
    Instance.new("UICorner", flyBtn).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", flyBtn); st.Color = R; st.Thickness = 2

    local function paintFly()
        flyBtn.Text = S.Fly and "FLY\nON" or "FLY\nOFF"
        st.Color = S.Fly and G or R
    end
    paintFly()

    local function toggleFly() S.Fly = not S.Fly; paintFly() end

    flyBtn.MouseButton1Click:Connect(toggleFly)
    bind(UIS.InputBegan, function(i, gp)
        if not gp and i.KeyCode == Enum.KeyCode.Q then toggleFly() end
    end)
    bind(RunS.Heartbeat, function()
        if not alive then return end
        local want = S.Fly and "FLY\nON" or "FLY\nOFF"
        if flyBtn.Text ~= want then paintFly() end
    end)
end

local nextStat = 0
bind(RunS.Heartbeat, function()
    if not alive or os.clock() < nextStat then return end
    nextStat = os.clock() + 0.2
    local h = hum()
    stat.Text = string.format(
        "  %s\n  Food %d   O2 %d   HP %s\n  chests opened %d\n  %s",
        mode,
        math.floor(tonumber(att("Food")) or 0),
        math.floor(tonumber(att("O2")) or 0),
        h and tostring(math.floor(h.Health)) or "-",
        stats.chests,
        logLine)
end)

-- ---------- unload ----------
local function u()
    alive = false
    for k in pairs(S) do S[k] = false end
    pcall(stopFly)
    pcall(espClear)
    pcall(function() if espBoard then espBoard:Destroy() end end)
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() sg:Destroy() end)
    getgenv().__POTATO_SEA = nil
end
bind(UIS.InputBegan, function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.End then u() end
end)

do
    local hp = hrp()
    baseCF = hp and hp.CFrame or nil
end
getgenv().__POTATO_SEA = { S=S, u=u, net=network, stats=stats, base=returnToBase }
warn("[POTATO SEA] loaded. Q toggles fly. Unload: End.")
