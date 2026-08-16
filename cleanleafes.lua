--[[==============================================================
    POTATO - LEAF GAME AUTOFARM   (place 100068273119174, Muffin Interactive)
    v2 - every constant below was re-measured against the live server.

      * Collect - LeafSim.collectMany(list) credits ONLY parts still parented
        to LeafSim.folder AND present in its internal id map, and it RETURNS
        the number actually banked. We use that return value, never #list, so
        a spot full of unregistered debris is detected instead of looping.
      * Bag full - collectBudget() = floor((LeafCapacity-Leaves)/LeafMult)
        minus the leaves already flying as FX, so it goes <= 0 on a nearly
        empty bag. Fullness is decided by the Leaves/LeafCapacity attributes;
        the budget is only used to size the batch.
      * Deposit - Remotes.EmptyBackpack:FireServer() pays at the nearest
        Map.Dumpsters entry, at that dumpster's PricePerLeaf attribute
        (None 0.01, Backyard 0.02, Farm 0.03). We try the richest first and
        verify the Leaves attribute actually dropped; a dumpster that does
        not pay (locked zone) is benched for 60s and we fall down the list.
      * Roam - density grid over the leaf folder, restricted to the ground
        band derived from the dumpster's own Y (keeps us out of the basement
        pile at Y~51 and off roofs). Radius and cell threshold widen in
        stages, last resort is the nearest single leaf, so bestSpot() can
        only return nil when the map genuinely has no reachable leaf.
      * Watchdog - progress = leaves banked OR cash gained. On a stall we
        roam to a NEW cluster (the old build re-parked at the dumpster,
        which is exactly where it had nothing to collect).

    One toggle runs the loop: collect -> full -> deposit -> roam. Unload: End.
================================================================]]--
if getgenv().__POTATO_LEAF then pcall(getgenv().__POTATO_LEAF.u) end

local Players   = game:GetService("Players")
local RunS      = game:GetService("RunService")
local UIS       = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local RS        = game:GetService("ReplicatedStorage")
local LP        = Players.LocalPlayer

local function tryReq(p) local ok,m = pcall(function() return require(p) end); return ok and m or nil end

local LeafSim      = tryReq(LP:WaitForChild("PlayerScripts"):WaitForChild("LeafSim"))
local UpgradeConf  = tryReq(RS:WaitForChild("UpgradeConfig"))
local Remotes      = RS:WaitForChild("Remotes")
local EmptyBackpack= Remotes:WaitForChild("EmptyBackpack")
local BuyUpgrade   = Remotes:WaitForChild("BuyUpgrade")
local BuyBagUpgrade= Remotes:FindFirstChild("BuyBagUpgrade")
local BuyToolCash  = Remotes:FindFirstChild("BuyToolCash")

if not LeafSim or typeof(LeafSim.collectMany) ~= "function" or typeof(LeafSim.folder) ~= "Instance" then
    warn("[POTATO LEAF] LeafSim not available - wrong game?")
    return
end

local W  = Color3.fromRGB(255,255,255)
local G  = Color3.fromRGB(120,220,120)
local R  = Color3.fromRGB(255,90,90)
local GD = Color3.fromRGB(230,200,90)

local S = { Farm=false, BuyUpg=false, BuyBag=false, BuyRake=false, AntiAFK=false }
local alive = true
local conns = {}
local function bind(sig, fn) local c = sig:Connect(fn); conns[#conns+1] = c; return c end

local COLLECT_RADIUS = 14      -- server grasp range
local THIN_SPOT      = 10      -- fewer leaves than this in reach => roam
local GRID_CELL      = 22      -- density grid cell (studs)
local CELL_MIN       = {24, 10, 4}    -- cluster size passes, richest first
local ROAM_STAGE     = {90, 170, 320} -- radius passes; short first so it works
                                      -- the area it is in instead of criss-
                                      -- crossing the map every hop
local LOOP_TICK      = 0.40    -- unhurried: one collect pass every 0.4s
local SETTLE         = 0.35    -- pause after every warp before doing anything
local HOP_COOLDOWN   = 1.20    -- minimum seconds between roams
local BAND_LO        = 12      -- studs BELOW dumpster Y that still counts as ground
local BAND_HI        = 10      -- studs above
local STUCK_SECS     = 12      -- no leaves and no cash for this long => force roam
                               -- (generous: a sell round trip alone costs ~2s)
local CELL_COOLDOWN  = 8       -- don't re-target a cell we just farmed
local DEAD_COOLDOWN  = 25      -- cell that banked nothing is benched this long
local BATCH_MAX      = 100     -- leaves per collectMany call; a 512-leaf batch was
                               -- destroyed client-side and credited nothing
local DEPOSIT_BENCH  = 60      -- dumpster that refused to pay is benched this long

local function char() return LP.Character end
local function hrp() local c=char(); return c and c:FindFirstChild("HumanoidRootPart") end
local function cashV() return LP:GetAttribute("Cash") or 0 end
local function leavesV() return LP:GetAttribute("Leaves") or 0 end
local function capV() return LP:GetAttribute("LeafCapacity") or 25 end
local function infBag() return LP:GetAttribute("InfiniteBag") == true or LP:GetAttribute("PermInfiniteBag") == true end
local function budgetV() local ok,b = pcall(function() return LeafSim.collectBudget() end); return (ok and type(b)=="number") and b or 0 end

-- bag fullness from the authoritative attributes, NOT from collectBudget:
-- the budget subtracts leaves still flying as FX and goes negative on an empty bag.
local function bagFull()
    if infBag() then return false end
    local cap = capV()
    if cap <= 0 or cap == math.huge then return false end
    return leavesV() >= cap
end
local function roomLeft()
    if infBag() then return BATCH_MAX end
    local mult = LP:GetAttribute("LeafMult") or 1
    local room = math.floor((capV() - leavesV()) / math.max(mult, 1))
    local b = budgetV()
    if b > 0 and b < room then room = b end
    return math.max(room, 0)
end

-- ground raycast: land on floor, never inside a roof or a prop
local groundRP = RaycastParams.new()
groundRP.FilterType = Enum.RaycastFilterType.Exclude
groundRP.IgnoreWater = true
local function groundPos(pos)
    groundRP.FilterDescendantsInstances = { char(), LeafSim.folder }
    -- start JUST above the leaf: starting high up catches the roof over an
    -- indoor pile and lands us on top of the house with nothing in reach
    local hit = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), groundRP)
    if hit and hit.Position.Y <= pos.Y + 3 then return hit.Position + Vector3.new(0, 3.5, 0) end
    return nil
end
-- leaves rest ON the floor, so a leaf position is always a usable landing spot
local function landing(pos) return groundPos(pos) or (pos + Vector3.new(0, 3.5, 0)) end

local function warp(pos)
    local hp = hrp(); if not hp then return false end
    hp.AssemblyLinearVelocity = Vector3.zero
    hp.CFrame = CFrame.new(pos)
    return true
end

-- ---------- deposit targets, richest dumpster first ----------
-- PricePerLeaf is an attribute on each dumpster model (0.01 / 0.02 / 0.03).
-- Zone-locked dumpsters simply pay nothing, so we verify each deposit and
-- bench a dumpster that refuses instead of assuming which zones are unlocked.
local dumps = nil
local function dumpList()
    if dumps then return dumps end
    local df = Workspace:FindFirstChild("Map"); df = df and df:FindFirstChild("Dumpsters")
    if not df then return nil end
    local out = {}
    for _, d in ipairs(df:GetChildren()) do
        if d:IsA("Model") then
            -- the server measures range to the "Leaves" part when the model has one
            local part = d:FindFirstChild("Leaves")
            local pos
            if part and part:IsA("BasePart") then pos = part.Position
            else local ok, p = pcall(function() return d:GetPivot().Position end); pos = ok and p or nil end
            if pos then
                out[#out+1] = { model=d, pos=pos,
                    price=tonumber(d:GetAttribute("PricePerLeaf")) or 0.01,
                    rate=nil, samples=0, bench=0, fails=0 }
            end
        end
    end
    if #out == 0 then return nil end
    table.sort(out, function(a,b) return a.price > b.price end)
    dumps = out
    return dumps
end

-- A dumpster only pays if its ZoneRequired matches the player's CurrentZone,
-- and CurrentZone never changes while we teleport (measured: standing ON the
-- Farm dumpster with CurrentZone="None" paid nothing). So the zone-matched set
-- is the only one worth trying - the old build benched all three and then fell
-- back to a locked one forever, which is why it stopped depositing.
local function usable(d)
    local zr = d.model:GetAttribute("ZoneRequired")
    return zr == nil or zr == "None" or zr == LP:GetAttribute("CurrentZone")
end
local function activeDump()
    local list = dumpList(); if not list then return nil end
    local now = os.clock()
    local open, valid = {}, {}
    for _, d in ipairs(list) do
        if usable(d) then
            valid[#valid+1] = d
            if now >= d.bench then open[#open+1] = d end
        end
    end
    if #valid == 0 then return list[1] end          -- nothing matches: try anyway
    if #open == 0 then
        for _, d in ipairs(valid) do d.bench = 0; d.fails = 0 end
        open = valid
    end
    -- PricePerLeaf is only a prior (the 0.03 dumpster measured 0.012), so
    -- sample each once, then keep the best measured cash-per-leaf.
    for _, d in ipairs(open) do if d.samples == 0 then return d end end
    local best = open[1]
    for _, d in ipairs(open) do if (d.rate or 0) > (best.rate or 0) then best = d end end
    return best
end

-- ground level of the farm, taken from the dumpster we are actually using
local function groundY()
    local d = activeDump()
    if d then return d.pos.Y end
    local hp = hrp(); return hp and (hp.Position.Y - 3) or 62
end

-- ---------- leaf helpers ----------
local banked = 0        -- leaves credited this session (progress signal)
local cellState = {}    -- cellKey -> { farmed=clock, dead=clock }
local function cellKey(p) return math.floor(p.X/GRID_CELL)..","..math.floor(p.Z/GRID_CELL) end

-- returns leaves actually banked (collectMany's own count), and the candidates seen
local function collectHere()
    local hp = hrp(); if not hp then return 0, 0 end
    local room = roomLeft()
    if room <= 0 then return 0, 0 end
    local budget = math.min(room, BATCH_MAX)
    local pos = hp.Position
    local near = {}
    for _, leaf in ipairs(LeafSim.folder:GetChildren()) do
        if leaf:IsA("BasePart") then
            local d = (leaf.Position - pos).Magnitude
            if d <= COLLECT_RADIUS then near[#near+1] = { part=leaf, d=d } end
        end
    end
    if #near == 0 then return 0, 0 end
    -- nearest first: if the batch is capped, spend it on the leaves in real grasp
    table.sort(near, function(a,b) return a.d < b.d end)
    local batch = {}
    for i = 1, math.min(#near, budget) do batch[i] = near[i].part end
    local ok, got = pcall(LeafSim.collectMany, batch)
    got = (ok and type(got) == "number") and got or 0
    -- got is the CLIENT's count. The server can still refuse the batch, so the
    -- caller confirms against the Leaves attribute before trusting this spot.
    return got, #batch
end

local function countNear(radius)
    local hp = hrp(); if not hp then return 0 end
    local pos = hp.Position
    local n = 0
    for _, leaf in ipairs(LeafSim.folder:GetChildren()) do
        if leaf:IsA("BasePart") and (leaf.Position - pos).Magnitude <= radius then
            n = n + 1
            if n >= THIN_SPOT then return n end
        end
    end
    return n
end

-- Densest ground-band cluster. Widens through CELL_MIN x ROAM_STAGE and finally
-- falls back to the single nearest leaf, so this returns nil only when the map
-- really has no reachable leaf left.
local function bestSpot()
    local hp = hrp(); if not hp then return nil end
    local dump = activeDump()
    local anchor = dump and dump.pos or hp.Position
    local gy = groundY()
    local yLo, yHi = gy - BAND_LO, gy + BAND_HI
    local now = os.clock()

    -- one pass over the folder builds both grids: the ground-band grid we
    -- prefer, and an unrestricted one used only when the ground band is bare
    local function build(useBand)
        local grid, nearest, nearestD = {}, nil, math.huge
        for _, leaf in ipairs(LeafSim.folder:GetChildren()) do
            if leaf:IsA("BasePart") then
                local p = leaf.Position
                if (not useBand) or (p.Y >= yLo and p.Y <= yHi) then
                    local key = cellKey(p)
                    local st = cellState[key]
                    if not (st and st.dead and now - st.dead < DEAD_COOLDOWN) then
                        local g = grid[key]
                        if not g then g = { n=0, x=0, y=p.Y, z=0, key=key, anchorD=(p-anchor).Magnitude }; grid[key] = g end
                        g.n = g.n + 1; g.x = g.x + p.X; g.z = g.z + p.Z
                        if p.Y < g.y then g.y = p.Y end     -- lowest leaf = the floor of the pile
                        local d = (p - hp.Position).Magnitude
                        if d < nearestD and d > 4 then nearestD = d; nearest = p end
                    end
                end
            end
        end
        return grid, nearest
    end

    local function pickFrom(grid)
        for _, minN in ipairs(CELL_MIN) do
            for _, radius in ipairs(ROAM_STAGE) do
                local cells = {}
                for key, g in pairs(grid) do
                    if g.n >= minN and g.anchorD <= radius then
                        local cx, cz = g.x/g.n, g.z/g.n
                        local center = Vector3.new(cx, g.y, cz)
                        local st = cellState[key]
                        local recent = (st and st.farmed and now - st.farmed < CELL_COOLDOWN) and -1e6 or 0
                        cells[#cells+1] = {
                            key = key, center = center,
                            -- distance weighted hard: work the pile you are
                            -- standing in before crossing the map
                            score = g.n - (center - hp.Position).Magnitude * 0.25 + recent,
                        }
                    end
                end
                table.sort(cells, function(a,b) return a.score > b.score end)
                for i = 1, math.min(4, #cells) do
                    local land = landing(cells[i].center)
                    -- reject a landing that sits above the pile: that is a roof
                    -- over an indoor cluster, and we would arrive with 0 in reach
                    if land.Y <= cells[i].center.Y + 8 then
                        cellState[cells[i].key] = cellState[cells[i].key] or {}
                        cellState[cells[i].key].farmed = now
                        return land, cells[i].key
                    end
                end
            end
        end
        return nil
    end

    local grid, nearest = build(true)
    local land, key = pickFrom(grid)
    if land then return land, key end

    -- ground band exhausted (map farmed down) -> allow any floor level
    local grid2, nearest2 = build(false)
    land, key = pickFrom(grid2)
    if land then return land, key end

    local fallback = nearest or nearest2
    if fallback then return landing(fallback), cellKey(fallback) end
    return nil
end

-- ---------- deposit, verified ----------
-- Measured on the live server: EmptyBackpack pays at 20 studs and refuses at 24,
-- so the sell CANNOT be fired from the farm spot. The server also ignores it
-- until the new position has replicated - and how long that takes varies per
-- server (one paid after 8 frames, another needed a settle before the fire and
-- ignored a 10-frame blink entirely). So: hop, let it settle, fire, hold, then
-- restore the exact CFrame we were farming from. The settle/hold that worked is
-- remembered, so only the first sell of a session pays the discovery cost.
local SELL_SETTLE, SELL_HOLD = 0.35, 20
local SELL_LADDER = { {0.35,20}, {0.60,45}, {1.00,90} }
local function deposit()
    local before = leavesV()
    if before <= 0 then return true end
    local d = activeDump()
    if not d then return false end
    local hp = hrp(); if not hp then return false end

    local cashBefore = cashV()
    local home = hp.CFrame
    local target = CFrame.new(landing(d.pos))
    local paid = false

    local ladder = { {SELL_SETTLE, SELL_HOLD} }
    for _, step in ipairs(SELL_LADDER) do
        if step[2] > SELL_HOLD then ladder[#ladder+1] = step end
    end

    for _, step in ipairs(ladder) do
        local settle, hold = step[1], step[2]
        hp.AssemblyLinearVelocity = Vector3.zero
        hp.CFrame = target
        task.wait(settle)                       -- let the server see us arrive
        hp.CFrame = target                      -- hold the spot against physics
        pcall(function() EmptyBackpack:FireServer() end)
        for _ = 1, hold do RunS.Heartbeat:Wait() end
        hp.CFrame = home                        -- back to the exact farm spot
        hp.AssemblyLinearVelocity = Vector3.zero

        for _ = 1, 10 do                        -- ~1s for the credit to land
            task.wait(0.10)
            if leavesV() < before then paid = true; break end
        end
        if paid then
            SELL_SETTLE, SELL_HOLD = settle, hold   -- this server's timing, kept
            break
        end
    end

    hp.CFrame = home
    if paid then
        d.fails = 0
        task.wait(0.15)                         -- let the cash tick land before measuring
        local rate = (cashV() - cashBefore) / math.max(before - leavesV(), 1)
        d.rate = d.rate and (d.rate * 0.5 + rate * 0.5) or rate
        d.samples = d.samples + 1
        if d.rate <= 0 then d.bench = os.clock() + DEPOSIT_BENCH end
        return true
    end

    -- refused (zone-locked dumpster): bench it, the next one gets the bag
    d.fails = d.fails + 1
    if d.fails >= 2 then
        d.bench = os.clock() + DEPOSIT_BENCH
        d.fails = 0
        d.samples = math.max(d.samples, 1)
    end
    return false
end

-- ---------- auto buy upgrade ----------
local function ownsTool(tk)
    if not UpgradeConf or not UpgradeConf.tools or not UpgradeConf.tools[tk] then return true end
    local oa = UpgradeConf.tools[tk].ownsAttr
    return oa == nil or LP:GetAttribute(oa) == true
end
local function cheapestUpgrade()
    if not UpgradeConf or not UpgradeConf.tools then return nil end
    local money, best = cashV(), nil
    for tk, tool in pairs(UpgradeConf.tools) do
        if ownsTool(tk) and type(tool.upgrades) == "table" then
            for un, u in pairs(tool.upgrades) do
                local lvl = LP:GetAttribute("Upg_"..tk.."_"..un) or 0
                if type(u) == "table" and u.max and lvl < u.max and u.prices then
                    local price = u.prices[lvl+1]
                    if type(price) == "number" and price <= money and (not best or price < best.price) then
                        best = { tk=tk, un=un, price=price }
                    end
                end
            end
        end
    end
    return best
end

-- ---------- roam bookkeeping ----------
local spotKey = nil
local function markDead(key)
    if not key then return end
    local st = cellState[key] or {}
    st.dead = os.clock()
    cellState[key] = st
end
-- warp to a bestSpot() result, remembering which cell we committed to
local lastHop = 0
local function goTo(pos, key)
    if not pos then return false end
    warp(pos)
    spotKey = key
    lastHop = os.clock()
    task.wait(SETTLE)          -- land, let the server see us, then collect
    return true
end
local function hopReady() return os.clock() - lastHop >= HOP_COOLDOWN end

-- ---------- state / stats ----------
local mode = "idle"
local cashStart, leafStart, startClock = cashV(), 0, os.clock()
local emptyStreak = 0

-- ================= FARM LOOP =================
local lastCash, lastProgress = cashV(), os.clock()
local prevLeaves = leavesV()
local pendingSince = nil
task.spawn(function()
    while alive do
        local okLoop, err = pcall(function()
            if not S.Farm then
                mode = "idle"; lastProgress = os.clock(); emptyStreak = 0
                return
            end
            local hp = hrp()
            if not hp then mode = "no char"; lastProgress = os.clock(); return end

            local gy = groundY()

            -- void guard: fell through the map / into the fall sequence
            if hp.Position.Y < gy - 25 then
                mode = "recover"
                local d = activeDump()
                if d then warp(landing(d.pos)) end
                task.wait(0.20)
                lastProgress = os.clock()
                return
            end

            -- Progress = leaves the SERVER credited, or cash. Deposits are rare
            -- on a 500 bag, so cash alone would trip the watchdog mid-collect.
            local money = cashV()
            if money > lastCash then lastCash = money; lastProgress = os.clock() end
            local lv = leavesV()
            if lv > prevLeaves then
                banked = banked + (lv - prevLeaves)
                lastProgress = os.clock()
                pendingSince = nil
                emptyStreak = 0
            end
            prevLeaves = lv

            -- sent a batch but the bag never grew => server refused this spot
            if pendingSince and os.clock() - pendingSince > 1.6 then
                pendingSince = nil
                markDead(spotKey or cellKey(hp.Position))
                markDead(cellKey(hp.Position))
                goTo(bestSpot())
                return
            end

            -- Leaves spawn once per zone per server (Leave_Locations, with a
            -- Completed attribute per zone) - they do NOT respawn. A drained
            -- server means rejoin, so idle quietly instead of warping forever.
            if #LeafSim.folder:GetChildren() == 0 then
                mode = "field empty - rejoin"
                if leavesV() > 0 then
                    deposit(); pendingSince = nil; prevLeaves = leavesV()
                end
                task.wait(1.0)
                lastProgress = os.clock()
                return
            end

            if bagFull() then
                mode = "sell"
                deposit()
                pendingSince = nil
                prevLeaves = leavesV()
                task.wait(0.10)
                goTo(bestSpot())
                lastProgress = os.clock()
                return
            end

            -- stalled: NOT back to the dumpster (that is the empty spot we keep
            -- landing in) - bank whatever is in the bag, then take a fresh cluster.
            if os.clock() - lastProgress > STUCK_SECS then
                mode = "unstick"
                if leavesV() > 0 then
                    deposit()
                    pendingSince = nil
                    prevLeaves = leavesV()
                end
                for k, st in pairs(cellState) do st.farmed = nil end
                markDead(spotKey)
                if not goTo(bestSpot()) then
                    local d = activeDump(); if d then warp(landing(d.pos)) end
                end
                task.wait(0.20)
                emptyStreak = 0
                lastProgress = os.clock()
                return
            end

            mode = "collect"
            local got, tried = collectHere()
            if got > 0 and not pendingSince then
                pendingSince = os.clock()       -- armed; cleared when the bag grows
            end

            -- Arrived with nothing in grasp: bad landing or a stripped cell.
            -- Bench it so bestSpot stops handing it back.
            if tried == 0 then
                emptyStreak = emptyStreak + 1
                if emptyStreak >= 2 then
                    markDead(spotKey or cellKey(hp.Position))
                    markDead(cellKey(hp.Position))
                    goTo(bestSpot())
                    emptyStreak = 0
                    return
                end
            end

            -- thinned out => next cluster, but never more often than HOP_COOLDOWN
            if countNear(COLLECT_RADIUS + 6) < THIN_SPOT and hopReady() then
                mode = "roam"
                goTo(bestSpot())
            end
        end)
        if not okLoop then mode = "err"; warn("[POTATO LEAF] "..tostring(err)) end
        task.wait(LOOP_TICK)
    end
end)

-- ================= BUY LOOP =================
task.spawn(function()
    while alive do
        pcall(function()
            if S.BuyRake and BuyToolCash and LP:GetAttribute("OwnsRake") ~= true and cashV() >= 1 then
                BuyToolCash:FireServer("Rake")
            end
            if S.BuyBag and BuyBagUpgrade then
                BuyBagUpgrade:FireServer()   -- server ignores if maxed/unaffordable
            end
            if S.BuyUpg then
                local up = cheapestUpgrade()
                if up then BuyUpgrade:FireServer(up.tk, up.un) end
            end
        end)
        task.wait(1.0)
    end
end)

-- ---------- anti afk ----------
local VirtualUser = game:GetService("VirtualUser")
bind(LP.Idled, function()
    if S.AntiAFK then
        pcall(function() VirtualUser:CaptureController(); VirtualUser:ClickButton2(Vector2.new()) end)
    end
end)

-- ---------- GUI ----------
local hui = (typeof(gethui)=="function") and gethui() or game:GetService("CoreGui")
local sg = Instance.new("ScreenGui"); sg.ResetOnSpawn=false; sg.IgnoreGuiInset=true; sg.Parent=hui
local m = Instance.new("Frame"); m.Size=UDim2.fromOffset(286,392); m.Position=UDim2.fromOffset(40,70)
m.BackgroundColor3=Color3.fromRGB(20,22,18); m.BorderSizePixel=0; m.Active=true; m.Parent=sg
Instance.new("UICorner",m).CornerRadius=UDim.new(0,10)
local sk=Instance.new("UIStroke",m); sk.Color=GD; sk.Thickness=1.5
local bar=Instance.new("Frame"); bar.Size=UDim2.new(1,0,0,32); bar.BackgroundColor3=Color3.fromRGB(30,34,24); bar.BorderSizePixel=0; bar.Parent=m
Instance.new("UICorner",bar).CornerRadius=UDim.new(0,10)
local tt=Instance.new("TextLabel"); tt.Size=UDim2.new(1,-12,1,0); tt.Position=UDim2.fromOffset(12,0)
tt.BackgroundTransparency=1; tt.Font=Enum.Font.GothamBold; tt.TextSize=14; tt.TextColor3=GD
tt.TextXAlignment=Enum.TextXAlignment.Left; tt.Text="POTATO - LEAF AUTOFARM"; tt.Parent=bar

local scroll=Instance.new("ScrollingFrame"); scroll.Size=UDim2.new(1,-16,1,-44); scroll.Position=UDim2.fromOffset(8,38)
scroll.BackgroundTransparency=1; scroll.BorderSizePixel=0; scroll.ScrollBarThickness=4; scroll.ScrollBarImageColor3=GD
scroll.CanvasSize=UDim2.new(0,0,0,0); scroll.AutomaticCanvasSize=Enum.AutomaticSize.Y; scroll.Parent=m
local ly=Instance.new("UIListLayout",scroll); ly.Padding=UDim.new(0,5)
local od=0

od=od+1
local stat=Instance.new("TextLabel"); stat.Size=UDim2.new(1,0,0,58); stat.BackgroundColor3=Color3.fromRGB(28,30,24)
stat.BorderSizePixel=0; stat.Font=Enum.Font.Gotham; stat.TextSize=11; stat.TextColor3=W
stat.TextXAlignment=Enum.TextXAlignment.Left; stat.TextYAlignment=Enum.TextYAlignment.Center
stat.LayoutOrder=od; stat.Text="  ready"; stat.Parent=scroll
Instance.new("UICorner",stat).CornerRadius=UDim.new(0,6)
Instance.new("UIPadding",stat).PaddingLeft=UDim.new(0,8)

local function section(txt)
    od=od+1
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,18); l.BackgroundTransparency=1
    l.Font=Enum.Font.GothamBold; l.TextSize=11; l.TextColor3=Color3.fromRGB(140,150,120)
    l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=txt:upper(); l.LayoutOrder=od; l.Parent=scroll
end

local function tg(key, txt, hint)
    od=od+1
    local h=Instance.new("Frame"); h.Size=UDim2.new(1,0,0,38); h.BackgroundColor3=Color3.fromRGB(28,30,24)
    h.BorderSizePixel=0; h.LayoutOrder=od; h.Parent=scroll
    Instance.new("UICorner",h).CornerRadius=UDim.new(0,6)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,-30,0,22); b.Position=UDim2.fromOffset(10,2)
    b.BackgroundTransparency=1; b.Font=Enum.Font.GothamBold; b.TextSize=13; b.TextColor3=W
    b.TextXAlignment=Enum.TextXAlignment.Left; b.Text=txt; b.Parent=h
    local dt=Instance.new("Frame"); dt.Size=UDim2.fromOffset(11,11); dt.Position=UDim2.new(1,-22,0,6)
    dt.BorderSizePixel=0; dt.Parent=h; Instance.new("UICorner",dt).CornerRadius=UDim.new(1,0)
    local hl=Instance.new("TextLabel"); hl.Size=UDim2.new(1,-16,0,12); hl.Position=UDim2.fromOffset(10,23)
    hl.BackgroundTransparency=1; hl.Font=Enum.Font.Gotham; hl.TextSize=10; hl.TextColor3=Color3.fromRGB(140,140,130)
    hl.TextXAlignment=Enum.TextXAlignment.Left; hl.Text=hint; hl.Parent=h
    local function pt() dt.BackgroundColor3 = S[key] and G or R end
    pt()
    b.MouseButton1Click:Connect(function()
        S[key] = not S[key]; pt()
        if key=="Farm" and S.Farm then
            cashStart=cashV(); leafStart=banked; startClock=os.clock()
            lastProgress=os.clock(); cellState={}
            for _, d in ipairs(dumpList() or {}) do d.bench=0; d.fails=0 end
        end
    end)
end

section("Farming")
tg("Farm", "Auto Farm", "collect + deposit + roam, all in one")

section("Auto Buy")
tg("BuyUpg", "Auto Buy Upgrades", "cheapest affordable upgrade")
tg("BuyBag", "Auto Buy Bag", "bigger bag = fewer trips")
tg("BuyRake", "Auto Buy Rake", "buys the Rake tool when affordable")

section("Misc")
tg("AntiAFK", "Anti AFK", "never get kicked for idling")

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
    l.Font=Enum.Font.Gotham; l.TextSize=10; l.TextColor3=Color3.fromRGB(120,120,110)
    l.Text="Press  End  to unload"; l.LayoutOrder=od; l.Parent=scroll
end

do
    local dg, ds, sp
    bind(bar.InputBegan, function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            dg=true; ds=i.Position; sp=m.Position
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dg=false end end)
        end
    end)
    bind(UIS.InputChanged, function(i)
        if dg and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-ds; m.Position=UDim2.fromOffset(sp.X.Offset+d.X, sp.Y.Offset+d.Y)
        end
    end)
end

-- stat updater, throttled: the old build reformatted the label every frame
local nextStat = 0
bind(RunS.Heartbeat, function()
    if not alive or os.clock() < nextStat then return end
    nextStat = os.clock() + 0.1
    local el = os.clock() - startClock
    local cpm = el > 1 and (cashV() - cashStart) / el * 60 or 0
    local lpm = el > 1 and (banked - leafStart) / el * 60 or 0
    local d = activeDump()
    local capTxt = infBag() and "inf" or tostring(capV())
    stat.Text = string.format("  Cash %.2f    Bag %d/%s\n  %s    dump %.3f/leaf %s\n  cash/min ~%.2f    leaves/min ~%.0f",
        cashV(), leavesV(), capTxt, mode,
        d and (d.rate or d.price) or 0, (d and d.rate) and "measured" or "listed", cpm, lpm)
end)

-- ---------- unload ----------
local function u()
    alive = false
    for k in pairs(S) do S[k] = false end
    for _, c in ipairs(conns) do pcall(function() c:Disconnect() end) end
    pcall(function() sg:Destroy() end)
    getgenv().__POTATO_LEAF = nil
end
bind(UIS.InputBegan, function(i, gp)
    if not gp and i.KeyCode == Enum.KeyCode.End then u() end
end)

getgenv().__POTATO_LEAF = { S = S, u = u }
warn("[POTATO LEAF AUTOFARM v2] loaded. Toggle Auto Farm. Unload: End.")
