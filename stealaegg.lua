--[[==============================================================
    POTATO - STEAL AN EGG  (place 107778070777162)
    Insta Steal (press E) + ESP + Auto Hatch + Equip Best + Auto Claim.

    v5 - MANUAL MODE
    ------------------------------------------------------------
    Auto Steal, Force Locked and the area picker are gone. One button
    now: Insta Steal. While it is on, pressing E grabs the nearest egg
    and puts it straight in your hand:

        save where you stand -> instant TP onto the egg -> short hold so
        the position replicates -> carry request -> instant TP back to
        exactly where you pressed E, landed on the ground.

    The hold is not padding. The server rejects the carry with "Get
    closer to the egg" if it has not seen your new position yet, so we
    sit on the egg for a moment first. If it still refuses, the same egg
    is retried up to 3 times with a longer hold before giving up. Whatever
    the server answers is printed in the status line.

    Eggs in areas you have not unlocked are skipped silently. That is not
    a safety preference, it is the game: entering a locked guard area
    kills you within half a second, tested live in Volcano without
    touching a single egg. Entry requirements are read from the game's own
    ResolveGuardSpeedRequirement:

        Forest 11 | Lake 900 | Desert 10K | Jungle 40K | Snow 170K
        Abyss Ocean 2.5M | Prehistoric 17M | Cosmic 700M | Volcano 450B

    There is no client-side bypass. SpeedPower is a server save value and
    Humanoid.WalkSpeed is re-derived from it every frame (set it to 400
    and it is back to your real value within a second), so the server
    never reads anything you can change.

    CAPABILITY-SAFE: everything touching an Instance runs on the main
    thread / inside Heartbeat; the yielding thread only writes plain
    tables. Unload: End.
================================================================]]--
if getgenv().__POTATO_EGG then pcall(getgenv().__POTATO_EGG.u) end

local Players   = game:GetService("Players")
local RunS      = game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")
local LP        = Players.LocalPlayer

local function tryReq(p) local ok, m = pcall(function() return require(p) end); return ok and m or nil end

local EggCmds  = require(RS.Library.Client.EggCmds)
local Network  = require(RS.Library.Client.Network)
local NM       = Network.NET_MAP
local PlotCmds = tryReq(RS.Library.Client.PlotCmds)
local GEP      = tryReq(RS.Library.Modules.GuardAreas.GuardEscapePrediction)
local GCP      = tryReq(RS.Library.Modules.GuardAreas.GuardChasePolicy)
local RGSR     = tryReq(RS.Library.Functions.ResolveGuardSpeedRequirement)
local SPP      = tryReq(RS.Library.Client.SpeedPowerProjection)
local GuardsD  = tryReq(RS.Directory.Guards)
local AreasD   = tryReq(RS.Directory.Areas)
local SlotId   = tryReq(RS.Library.Util.AreaEggSlotIdentity)

local W  = Color3.fromRGB(255,255,255)
local G  = Color3.fromRGB(70,220,120)
local R  = Color3.fromRGB(255,80,80)
local GD = Color3.fromRGB(255,190,70)

local S = { Insta=false, ESP=false, Hatch=false, EquipBest=false, Claim=false }
local alive = true

local STEAL_KEY = Enum.KeyCode.E

-- ---------- grab delay profiles ----------
-- Only how long we sit on the egg before asking to carry it, so the server
-- has our position. The teleports themselves are always instant.
local DELAYS = {
    { name = "Fast",   hold = 0.20 },
    { name = "Normal", hold = 0.35 },
    { name = "Safe",   hold = 0.60 },
}
local dIdx = 2
local function DL() return DELAYS[dIdx] end

-- ---------- static area data (main thread, plain values only) ----------
local EXIT_DIR = Vector3.new(-1,0,0)
local AREA = {}   -- [areaId] = { cf,size,guardPos,speed,radius,hit,reqSP }
do
    pcall(function()
        EXIT_DIR = -Workspace.__OBJECTS.Areas.SeparationLine.CFrame.LookVector
    end)
    local folder = Workspace:FindFirstChild("__OBJECTS")
    folder = folder and folder:FindFirstChild("Areas")
    folder = folder and folder:FindFirstChild("GuardAreas")
    if folder and GuardsD and AreasD and GCP then
        for _, a in ipairs(folder:GetChildren()) do
            pcall(function()
                local d = GuardsD.Directory[AreasD.Directory[a.Name].GuardId]
                local rec = {
                    cf       = a.Bounds.CFrame,
                    size     = a.Bounds.Size,
                    guardPos = a.Guard:GetPivot().Position,
                    speed    = d.WalkSpeed,
                    radius   = d.FlatRadius,
                    hit      = GCP.ResolveHitDistance(d.HitDistance),
                    reqSP    = nil,
                }
                if GEP and RGSR then
                    pcall(function()
                        local exitPos = a.ClosestExitPoint.Position
                        rec.reqSP = RGSR({
                            BaseGuardWalkSpeed  = rec.speed,
                            ExitDirection       = EXIT_DIR,
                            ExitDistance        = GEP.ResolveExitDistance(rec.cf, rec.size, exitPos, EXIT_DIR),
                            FlatRadius          = rec.radius,
                            GuardStartPosition  = rec.guardPos,
                            HitDistance         = rec.hit,
                            PlayerStartPosition = exitPos,
                        })
                    end)
                end
                AREA[a.Name] = rec
            end)
        end
    end
end

local function hrp() local c = LP.Character; return c and c:FindFirstChild("HumanoidRootPart") end
local function hum() local c = LP.Character; return c and c:FindFirstChildOfClass("Humanoid") end

local function shortNum(n)
    if not n then return "?" end
    local a = math.abs(n)
    if a >= 1e12 then return string.format("%.1fT", n/1e12) end
    if a >= 1e9  then return string.format("%.1fB", n/1e9)  end
    if a >= 1e6  then return string.format("%.1fM", n/1e6)  end
    if a >= 1e3  then return string.format("%.1fK", n/1e3)  end
    return string.format("%d", n)
end

-- ---------- shared plain-table caches ----------
local cachedEggs  = {}
local carriedByMe = nil
local blacklist   = {}
local curSP       = 0     -- live SpeedPower, written by Heartbeat

local function areaUnlocked(areaId)
    local A = AREA[areaId]
    if not A or not A.reqSP then return true end   -- unknown -> do not block
    return curSP >= A.reqSP
end

-- ---------- BACKGROUND DATA THREAD (yields, never touches an Instance) ----------
task.spawn(function()
    while alive do
        local ok, snap = pcall(function() return EggCmds.GetAreaEggSnapshot() end)
        if ok and snap and snap.Records then
            local eggs, mine = {}, nil
            for _, r in ipairs(snap.Records) do
                if r.State == "Carried" and r.CarrierUserId == LP.UserId then
                    mine = r.Uid
                end
                if r.State == "Slot" and typeof(r.BoundsCFrame) == "CFrame" then
                    eggs[#eggs+1] = {
                        uid = r.Uid, cf = r.BoundsCFrame, pos = r.BoundsCFrame.Position,
                        area = r.AreaId, cat = r.AssetCategory, nest = r.NestId,
                    }
                end
            end
            cachedEggs  = eggs
            carriedByMe = mine
        end
        task.wait(0.35)
    end
end)

-- ---------- cache readers (no yield) ----------
local function eggAllowed(e)
    local bl = blacklist[e.uid]
    if bl and (os.clock() - bl) < 10 then return false end
    return areaUnlocked(e.area)          -- locked area = instant death
end

local function currentEggs(filtered)
    local list = {}
    for _, e in ipairs(cachedEggs) do
        if not filtered or eggAllowed(e) then list[#list+1] = e end
    end
    local hp = hrp()
    if hp then
        local pos = hp.Position
        table.sort(list, function(a, b) return (a.pos - pos).Magnitude < (b.pos - pos).Magnitude end)
    end
    return list
end

-- ---------- plot / placement ----------
local plotCenterCF, plotPetPos, plotPetSize = nil, nil, nil
local function refreshPlot()
    if not PlotCmds then return end
    pcall(function()
        local pd = PlotCmds.GetPlotData()
        if pd then
            if pd.CenterPoint then plotCenterCF = pd.CenterPoint.CFrame end
            if pd.PetArea then plotPetPos = pd.PetArea.Position; plotPetSize = pd.PetArea.Size end
        end
    end)
end

-- ---------- ESP marker pool ----------
local ESP_MAX = 30
local pool = {}
for i = 1, ESP_MAX do
    local p = Instance.new("Part"); p.Anchored = true; p.CanCollide = false; p.CanQuery = false; p.Transparency = 1
    p.Size = Vector3.new(1.2,1.2,1.2); p.CFrame = CFrame.new(0,-9999,0)
    local hl = Instance.new("Highlight"); hl.FillTransparency = 0.4; hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop; hl.Enabled = false; hl.Parent = p
    local bb = Instance.new("BillboardGui"); bb.Size = UDim2.fromOffset(170,20); bb.AlwaysOnTop = true; bb.MaxDistance = 900; bb.Enabled = false; bb.Parent = p
    local tl = Instance.new("TextLabel"); tl.Size = UDim2.fromScale(1,1); tl.BackgroundTransparency = 1; tl.Font = Enum.Font.GothamBold; tl.TextSize = 12; tl.TextStrokeTransparency = 0.3; tl.Text = ""; tl.Parent = bb
    p.Parent = Workspace
    pool[i] = { part = p, hl = hl, bb = bb, tl = tl }
end

-- ---------- steal state machine ----------
local stState, stTimer, stEgg, stTarget, stReturn = "idle", 0, nil, nil, nil
local stEnter, stTries = 0, 0
local wantSteal = false          -- set by the E keybind, consumed by Heartbeat
local grabs, deaths, fails = 0, 0, 0
local L = { h = 0, q = 0, c = 0 }
local function net(ep) task.spawn(function() pcall(function() Network.Invoke(ep) end) end) end

local function goto_(state, now, delay)
    stState = state
    stEnter = now
    stTimer = now + (delay or 0)
end

-- carry result, written by the request thread (plain values only)
local carryPending, carryOk, carryErr = false, nil, nil

local function requestCarry(e)
    carryPending, carryOk, carryErr = true, nil, nil
    task.spawn(function()
        local ok, res, err = pcall(function()
            local key = nil
            if SlotId and SlotId.IsFirstAreaUid(e.uid) then
                key = SlotId.BuildSlotKey(e.area, e.nest)
            end
            return EggCmds.RequestCarryAreaEgg(e.uid, key)
        end)
        if ok then carryOk, carryErr = res, err else carryOk, carryErr = false, tostring(res) end
        carryPending = false
    end)
end

-- one instant hop, no intermediate positions -> nothing to clip through
local function warpTo(hp, cf)
    hp.AssemblyLinearVelocity  = Vector3.zero
    hp.AssemblyAngularVelocity = Vector3.zero
    hp.CFrame = cf
end

-- Drop a CFrame onto the floor beneath it. Warping to a raw CFrame leaves the
-- character hovering and it burns about a second falling before it can act
-- again; landing it on the ground removes that dead time.
local RP = RaycastParams.new()
RP.FilterType = Enum.RaycastFilterType.Exclude
local function groundCF(cf)
    if typeof(cf) ~= "CFrame" then return cf end
    local char = LP.Character
    RP.FilterDescendantsInstances = char and { char } or {}
    local ok, res = pcall(function()
        return Workspace:Raycast(cf.Position + Vector3.new(0, 6, 0), Vector3.new(0, -250, 0), RP)
    end)
    if ok and res then
        local hu = hum()
        local lift = (hu and hu.HipHeight or 2) + 0.15
        return CFrame.new(res.Position + Vector3.new(0, lift, 0)) * (cf - cf.Position)
    end
    return cf
end

local function warpGrounded(hp, cf)
    warpTo(hp, groundCF(cf))
    local hu = hum()
    if hu then pcall(function() hu:ChangeState(Enum.HumanoidStateType.Landed) end) end
end

-- ---------- GUI ----------
local hui = (typeof(gethui) == "function") and gethui() or game:GetService("CoreGui")
local sg = Instance.new("ScreenGui"); sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true; sg.Parent = hui
local m = Instance.new("Frame"); m.Size = UDim2.fromOffset(292,368); m.Position = UDim2.fromOffset(40,80)
m.BackgroundColor3 = Color3.fromRGB(18,18,24); m.BorderSizePixel = 0; m.Active = true; m.Parent = sg
Instance.new("UICorner", m).CornerRadius = UDim.new(0,10)
local sk = Instance.new("UIStroke", m); sk.Color = GD; sk.Thickness = 1.5
local bar = Instance.new("Frame"); bar.Size = UDim2.new(1,0,0,32); bar.BackgroundColor3 = Color3.fromRGB(28,28,38); bar.BorderSizePixel = 0; bar.Parent = m
Instance.new("UICorner", bar).CornerRadius = UDim.new(0,10)
local tt = Instance.new("TextLabel"); tt.Size = UDim2.new(1,-12,1,0); tt.Position = UDim2.fromOffset(12,0)
tt.BackgroundTransparency = 1; tt.Font = Enum.Font.GothamBold; tt.TextSize = 14; tt.TextColor3 = GD
tt.TextXAlignment = Enum.TextXAlignment.Left; tt.Text = "POTATO - STEAL AN EGG v5"; tt.Parent = bar
local lf = Instance.new("Frame"); lf.Size = UDim2.new(1,-16,1,-44); lf.Position = UDim2.fromOffset(8,38); lf.BackgroundTransparency = 1; lf.Parent = m
local ly = Instance.new("UIListLayout", lf); ly.Padding = UDim.new(0,5)
local od = 0

od = od + 1
local stat = Instance.new("TextLabel"); stat.Size = UDim2.new(1,0,0,34); stat.BackgroundColor3 = Color3.fromRGB(26,26,34)
stat.BorderSizePixel = 0; stat.Font = Enum.Font.Gotham; stat.TextSize = 11; stat.TextColor3 = W
stat.TextXAlignment = Enum.TextXAlignment.Left; stat.TextYAlignment = Enum.TextYAlignment.Center
stat.LayoutOrder = od; stat.Text = "  ready"; stat.Parent = lf
Instance.new("UICorner", stat).CornerRadius = UDim.new(0,6)
Instance.new("UIPadding", stat).PaddingLeft = UDim.new(0,8)

od = od + 1
local dBtn = Instance.new("TextButton")
dBtn.Size = UDim2.new(1,0,0,30); dBtn.BackgroundColor3 = Color3.fromRGB(30,34,48); dBtn.BorderSizePixel = 0
dBtn.Font = Enum.Font.GothamBold; dBtn.TextSize = 12; dBtn.TextColor3 = Color3.fromRGB(150,190,255)
dBtn.LayoutOrder = od; dBtn.Parent = lf
Instance.new("UICorner", dBtn).CornerRadius = UDim.new(0,6)
local function dPaint()
    local t = DL()
    dBtn.Text = "Grab Delay: " .. t.name .. "   (hold " .. t.hold .. "s)"
end
dPaint()
dBtn.MouseButton1Click:Connect(function()
    dIdx = dIdx % #DELAYS + 1
    dPaint()
end)

local function tg(key, txt, hint)
    od = od + 1
    local h = Instance.new("Frame"); h.Size = UDim2.new(1,0,0,38); h.BackgroundColor3 = Color3.fromRGB(26,26,34)
    h.BorderSizePixel = 0; h.LayoutOrder = od; h.Parent = lf
    Instance.new("UICorner", h).CornerRadius = UDim.new(0,6)
    local b = Instance.new("TextButton"); b.Size = UDim2.new(1,-30,0,22); b.Position = UDim2.fromOffset(10,2)
    b.BackgroundTransparency = 1; b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.TextColor3 = W
    b.TextXAlignment = Enum.TextXAlignment.Left; b.Text = txt; b.Parent = h
    local dt = Instance.new("Frame"); dt.Size = UDim2.fromOffset(11,11); dt.Position = UDim2.new(1,-22,0,6)
    dt.BorderSizePixel = 0; dt.Parent = h
    Instance.new("UICorner", dt).CornerRadius = UDim.new(1,0)
    local hl = Instance.new("TextLabel"); hl.Size = UDim2.new(1,-16,0,12); hl.Position = UDim2.fromOffset(10,23)
    hl.BackgroundTransparency = 1; hl.Font = Enum.Font.Gotham; hl.TextSize = 10
    hl.TextColor3 = Color3.fromRGB(150,150,160); hl.TextXAlignment = Enum.TextXAlignment.Left
    hl.Text = hint; hl.Parent = h
    local function pt() dt.BackgroundColor3 = S[key] and G or R end
    pt()
    b.MouseButton1Click:Connect(function()
        S[key] = not S[key]; pt()
        if key == "Insta" then
            stState = "idle"; stEgg = nil; wantSteal = false; stEnter = os.clock()
            if S.Insta then refreshPlot() end
        end
    end)
end
tg("Insta",     "Insta Steal",     "press E - nearest egg straight into your hand")
tg("ESP",       "Egg ESP",         "green open / red locked area")
tg("Hatch",     "Auto Hatch",      "hatches your ready placed eggs")
tg("EquipBest", "Auto Equip Best", "keeps your best pets equipped")
tg("Claim",     "Auto Claim",      "index / gifts / offline / group")

do
    od = od + 1
    local DISCORD = "https://discord.gg/SgBZtPnTkd"
    local b = Instance.new("TextButton"); b.Size = UDim2.new(1,0,0,28); b.BackgroundColor3 = Color3.fromRGB(38,42,70)
    b.BorderSizePixel = 0; b.Font = Enum.Font.GothamBold; b.TextSize = 13; b.TextColor3 = Color3.fromRGB(150,175,255)
    b.TextXAlignment = Enum.TextXAlignment.Left; b.LayoutOrder = od; b.Parent = lf
    Instance.new("UICorner", b).CornerRadius = UDim.new(0,6)
    Instance.new("UIPadding", b).PaddingLeft = UDim.new(0,10)
    b.Text = "Discord - Copy Invite"
    b.MouseButton1Click:Connect(function()
        local copy = (setclipboard) or (toclipboard) or (writeclipboard) or (syn and syn.write_clipboard)
        local ok = copy ~= nil and pcall(copy, DISCORD)
        b.Text = ok and "Copied! discord.gg/SgBZtPnTkd" or "discord.gg/SgBZtPnTkd"
        task.delay(2.5, function() if b and b.Parent then b.Text = "Discord - Copy Invite" end end)
    end)
end

do
    local dg, ds, sp
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then
            dg = true; ds = i.Position; sp = m.Position
            i.Changed:Connect(function()
                if i.UserInputState == Enum.UserInputState.End then dg = false end
            end)
        end
    end)
    UIS.InputChanged:Connect(function(i)
        if dg and i.UserInputType == Enum.UserInputType.MouseMovement then
            local d = i.Position - ds
            m.Position = UDim2.fromOffset(sp.X.Offset + d.X, sp.Y.Offset + d.Y)
        end
    end)
end

LP.CharacterAdded:Connect(function()
    stState = "idle"; stEgg = nil; wantSteal = false; stEnter = os.clock()
end)

-- ---------- HEARTBEAT: every Instance touch happens here, never yields ----------
local wasDead, plotAt, spAt = false, 0, 0
RunS.Heartbeat:Connect(function()
    if not alive then return end
    local now = os.clock()

    if now - plotAt > 5 then plotAt = now; refreshPlot() end
    if now - spAt > 1 and SPP then
        spAt = now
        pcall(function() curSP = SPP.GetSpeedPower() or curSP end)
    end

    local hp, hu = hrp(), hum()
    if hp then pcall(function() hp:SetAttribute("KillPartIgnore", true) end) end

    -- death / respawn recovery
    local dead = (hu == nil) or (hu.Health <= 0)
    if dead and not wasDead then
        wasDead = true; deaths = deaths + 1
        stEgg = nil; wantSteal = false; goto_("idle", now)
    elseif not dead and wasDead then
        wasDead = false
        goto_("idle", now)
    end

    -- watchdog: no step may take longer than 8s
    if stState ~= "idle" and (now - stEnter) > 8 then
        if stEgg then blacklist[stEgg.uid] = now end
        stEgg = nil; fails = fails + 1
        if stReturn and hp then warpGrounded(hp, stReturn) end
        goto_("idle", now)
    end

    do
        local open, locked = 0, 0
        for _, e in ipairs(cachedEggs) do
            if areaUnlocked(e.area) then open = open + 1 else locked = locked + 1 end
        end
        local note = ""
        if carryOk == false and type(carryErr) == "string" then note = "  <" .. carryErr .. ">" end
        stat.Text = string.format("  SpeedPower %s    open %d / locked %d\n  %s%s    got %d    died %d    failed %d",
            shortNum(curSP), open, locked, stState, note, grabs, deaths, fails)
    end

    -- ESP
    if S.ESP then
        local list = currentEggs(false)
        for i, e in ipairs(pool) do
            local r = list[i]
            if r then
                e.part.CFrame = r.cf
                local A  = AREA[r.area]
                local ok = areaUnlocked(r.area)
                local col = ok and G or R
                e.hl.FillColor = col; e.hl.OutlineColor = col; e.tl.TextColor3 = col
                if ok then
                    e.tl.Text = tostring(r.cat or "Egg") .. "  (" .. tostring(r.area) .. ")"
                else
                    e.tl.Text = tostring(r.area) .. "  LOCKED " .. shortNum(A and A.reqSP)
                end
                e.hl.Enabled = true; e.bb.Enabled = true
            else
                e.hl.Enabled = false; e.bb.Enabled = false
            end
        end
    elseif pool[1].hl.Enabled then
        for _, e in ipairs(pool) do e.hl.Enabled = false; e.bb.Enabled = false end
    end

    -- INSTA STEAL: E -> TP onto the egg -> hold -> carry -> TP back where you were
    if S.Insta and not dead and hp then
        if stState == "idle" then
            if wantSteal then
                wantSteal = false
                local pick = currentEggs(true)[1]
                if pick then
                    stEgg    = pick
                    stTries  = 0
                    stReturn = hp.CFrame                     -- come back to exactly here
                    stTarget = pick.cf + Vector3.new(0, 3, 0)
                    warpTo(hp, stTarget)                     -- INSTANT teleport in
                    goto_("grab", now, DL().hold)
                else
                    carryOk, carryErr = false, "no reachable egg"
                end
            end

        elseif stState == "grab" then
            warpTo(hp, stTarget)                             -- hold still on the egg
            if now >= stTimer then
                if stEgg then requestCarry(stEgg) end
                goto_("confirm", now, 2.5)
            end

        elseif stState == "confirm" then
            warpTo(hp, stTarget)
            if stEgg and carriedByMe == stEgg.uid then
                grabs = grabs + 1
                if stReturn then warpGrounded(hp, stReturn) end   -- instant hop back
                stEgg = nil
                goto_("idle", now)

            elseif (not carryPending and carryOk == false) or now >= stTimer then
                -- Usually "Get closer to the egg": we asked before our position
                -- replicated. Sit longer and retry the same egg.
                stTries = stTries + 1
                if stEgg and stTries < 3 then
                    goto_("grab", now, DL().hold + 0.35 * stTries)
                else
                    if stEgg then blacklist[stEgg.uid] = now end
                    stEgg = nil; fails = fails + 1
                    if stReturn then warpGrounded(hp, stReturn) end
                    goto_("idle", now)
                end
            end
        end
    else
        stState = "idle"; wantSteal = false
    end

    -- network-only autos (never touch an Instance)
    if S.Hatch and (now - L.h) >= 2 then
        L.h = now
        task.spawn(function()
            local ok, recs = pcall(function() return EggCmds.GetOwnerRuntimeRecords(LP.UserId) end)
            if ok and type(recs) == "table" then
                for uid, rec in pairs(recs) do
                    local rd = false
                    pcall(function() rd = EggCmds.IsLocalEggReady(uid) end)
                    if rec.Placement ~= nil and rd then
                        local st = pcall(function() return EggCmds.RequestHatchEgg(uid) end)
                        if st then
                            task.wait(0.15)
                            pcall(function() EggCmds.RequestCompleteHatchEgg(uid) end)
                        end
                    end
                end
            end
        end)
    end
    if S.EquipBest and (now - L.q) >= 3 then L.q = now; net(NM.Backpack.EQUIP_BEST) end
    if S.Claim and (now - L.c) >= 5 then
        L.c = now
        net(NM.Index.REQUEST_CLAIM_ALL); net(NM.FreeGifts.REQUEST_CLAIM)
        net(NM.OfflineAssets.REQUEST_REDEEM); net(NM.GroupReward.CLAIM_REWARD)
    end
end)

local function u()
    alive = false
    for k in pairs(S) do S[k] = false end
    for _, e in ipairs(pool) do pcall(function() e.part:Destroy() end) end
    pcall(function() sg:Destroy() end)
    getgenv().__POTATO_EGG = nil
end

UIS.InputBegan:Connect(function(i, gp)
    if gp then return end                       -- ignore while typing in chat
    if i.KeyCode == Enum.KeyCode.End then u(); return end
    if i.KeyCode == STEAL_KEY and S.Insta and stState == "idle" then
        wantSteal = true                        -- consumed by the Heartbeat above
    end
end)

getgenv().__POTATO_EGG = { S = S, u = u, AREA = AREA }
warn("[POTATO STEAL AN EGG v5] loaded - toggle Insta Steal, then press E. Unload: End.")
