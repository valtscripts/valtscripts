--[[==============================================================
    🐣 VALT — CHICKEN FARM AUTO  (Place 137233438285284)
    claim eggs • deposit • collect cash • upgrade /sec • merge
    buy chickens (x1/x5/x25/x100) • auto rebirth • auto lucky block
    Run in executor. Panel top-left. Unload: Delete key.
================================================================]]--
if getgenv().__POTATO_FARM then getgenv().__POTATO_FARM.unload() end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local RS         = game:GetService("ReplicatedStorage")
local Workspace  = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer

local Paper = require(RS:WaitForChild("Paper"))
local Net   = Paper.Network
local function stat(n) local ok,v=pcall(function() return Paper.Stats.GetValue(n) end); return ok and v or nil end

local WHITE=Color3.fromRGB(255,255,255); local GREEN=Color3.fromRGB(70,220,120)
local RED=Color3.fromRGB(255,80,80); local GOLD=Color3.fromRGB(255,200,60)

--------------------------------------------------------------------
-- STATE
--------------------------------------------------------------------
local F = {
    ClaimEggs   = true,
    Deposit     = true,
    CollectCash = true,
    UpgradePS   = false,
    Merge       = false,
    BuyChickens = false,
    BuyAmount   = 1,
    Rebirth     = false,   -- resets progress; default OFF
    LuckyBlock  = false,   -- needs a lucky block equipped
}
local last = { egg=0, buy=0, dep=0, cash=0, up=0, rb=0, luck=0, merge=0 }

local function getHRP()
    local c = LocalPlayer.Character
    return c and (c:FindFirstChild("HumanoidRootPart") or c.PrimaryPart)
end

--------------------------------------------------------------------
-- ACTION LOOP
--------------------------------------------------------------------
local hasFTI = type(firetouchinterest) == "function"
local runConn = RunService.Heartbeat:Connect(function()
    local now = os.clock()

    -- AUTO CLAIM EGGS (touch each egg against the character -> game collects it)
    if F.ClaimEggs and hasFTI and (now - last.egg) >= 0.08 then
        last.egg = now
        local hrp = getHRP()
        local folder = Workspace:FindFirstChild("Eggs")
        if hrp and folder then
            for _, egg in ipairs(folder:GetChildren()) do
                local touchPart = egg:FindFirstChild("Part") or egg:FindFirstChild("Hitbox") or egg.PrimaryPart
                if touchPart then
                    pcall(function()
                        firetouchinterest(touchPart, hrp, 0)
                        firetouchinterest(touchPart, hrp, 1)
                    end)
                end
            end
        end
    end

    -- AUTO DEPOSIT EGGS
    if F.Deposit and (now - last.dep) >= 0.4 then
        last.dep = now
        pcall(function() Net.InvokeServer("Deposit Eggs") end)
    end

    -- AUTO COLLECT CASH
    if F.CollectCash and (now - last.cash) >= 0.4 then
        last.cash = now
        pcall(function() Net.InvokeServer("Collect Cash") end)
    end

    -- AUTO MERGE CHICKENS
    if F.Merge and (now - last.merge) >= 0.5 then
        last.merge = now
        pcall(function() Net.InvokeServer("Merge Chickens") end)
    end

    -- AUTO BUY CHICKENS
    if F.BuyChickens and (now - last.buy) >= 0.35 then
        last.buy = now
        pcall(function() Net.InvokeServer("Buy Chickens", F.BuyAmount) end)
    end

    -- AUTO UPGRADE PER SECOND
    if F.UpgradePS and (now - last.up) >= 0.5 then
        last.up = now
        pcall(function() Net.InvokeServer("Upgrade Process Level") end)
    end

    -- AUTO REBIRTH (server rejects if not eligible)
    if F.Rebirth and (now - last.rb) >= 2.5 then
        last.rb = now
        pcall(function() Net.InvokeServer("Rebirth") end)
    end

    -- AUTO LUCKY BLOCK (open + instant claim, only if one is equipped)
    if F.LuckyBlock and (now - last.luck) >= 0.6 then
        last.luck = now
        if (stat("EquippedLuckyBlock") or 0) ~= 0 then
            pcall(function()
                Net.InvokeServer("Open Lucky Block")
                Net.FireServer("Claim Opened Chicken")
            end)
        end
    end
end)

--==============================================================
-- GUI
--==============================================================
local gethuiFn = (typeof(gethui)=="function") and gethui or function() return game:GetService("CoreGui") end
local sg = Instance.new("ScreenGui")
sg.ResetOnSpawn=false; sg.IgnoreGuiInset=true
sg.ZIndexBehavior=Enum.ZIndexBehavior.Sibling; sg.Parent=gethuiFn()

local main=Instance.new("Frame")
main.Size=UDim2.fromOffset(244,432); main.Position=UDim2.fromOffset(40,100)
main.BackgroundColor3=Color3.fromRGB(22,20,16); main.BorderSizePixel=0; main.Active=true; main.Parent=sg
Instance.new("UICorner",main).CornerRadius=UDim.new(0,10)
local strk=Instance.new("UIStroke",main); strk.Color=GOLD; strk.Thickness=1.5; strk.Transparency=0.25

local bar=Instance.new("Frame"); bar.Size=UDim2.new(1,0,0,32); bar.BorderSizePixel=0
bar.BackgroundColor3=Color3.fromRGB(34,30,22); bar.Parent=main
Instance.new("UICorner",bar).CornerRadius=UDim.new(0,10)
local ttl=Instance.new("TextLabel"); ttl.Size=UDim2.new(1,-12,1,0); ttl.Position=UDim2.fromOffset(12,0)
ttl.BackgroundTransparency=1; ttl.Font=Enum.Font.GothamBold; ttl.TextSize=14; ttl.TextColor3=GOLD
ttl.TextXAlignment=Enum.TextXAlignment.Left; ttl.Text="🐣 VALT FARM"; ttl.Parent=bar

local listframe=Instance.new("Frame"); listframe.Size=UDim2.new(1,-16,1,-42); listframe.Position=UDim2.fromOffset(8,38)
listframe.BackgroundTransparency=1; listframe.Parent=main
local lay=Instance.new("UIListLayout",listframe); lay.Padding=UDim.new(0,5); lay.SortOrder=Enum.SortOrder.LayoutOrder
local ord=0; local function row() ord+=1; return ord end

local function toggle(key,text,warnCol)
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,26); b.BorderSizePixel=0
    b.BackgroundColor3=Color3.fromRGB(38,34,26); b.Font=Enum.Font.GothamMedium; b.TextSize=13
    b.TextColor3=warnCol or WHITE; b.TextXAlignment=Enum.TextXAlignment.Left; b.LayoutOrder=row(); b.Parent=listframe
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); Instance.new("UIPadding",b).PaddingLeft=UDim.new(0,10)
    local dot=Instance.new("Frame"); dot.Size=UDim2.fromOffset(11,11); dot.Position=UDim2.new(1,-22,0.5,-5.5)
    dot.BorderSizePixel=0; dot.Parent=b; Instance.new("UICorner",dot).CornerRadius=UDim.new(1,0)
    local function paint() dot.BackgroundColor3=F[key] and GREEN or RED; b.Text=text end
    paint(); b.MouseButton1Click:Connect(function() F[key]=not F[key]; paint() end)
end

local function amountRow()
    local holder=Instance.new("Frame"); holder.Size=UDim2.new(1,0,0,26); holder.BackgroundTransparency=1
    holder.LayoutOrder=row(); holder.Parent=listframe
    local hl=Instance.new("UIListLayout",holder); hl.FillDirection=Enum.FillDirection.Horizontal
    hl.Padding=UDim.new(0,4); hl.SortOrder=Enum.SortOrder.LayoutOrder
    local btns={}; local amounts={1,5,25,100}
    local function repaint()
        for amt,btn in pairs(btns) do
            local on=F.BuyAmount==amt
            btn.BackgroundColor3=on and GOLD or Color3.fromRGB(45,40,30)
            btn.TextColor3=on and Color3.fromRGB(30,25,15) or WHITE
        end
    end
    for i,amt in ipairs(amounts) do
        local btn=Instance.new("TextButton"); btn.Size=UDim2.new(0.25,-3,1,0); btn.BorderSizePixel=0
        btn.Font=Enum.Font.GothamBold; btn.TextSize=13; btn.Text="x"..amt; btn.LayoutOrder=i; btn.Parent=holder
        Instance.new("UICorner",btn).CornerRadius=UDim.new(0,6); btns[amt]=btn
        btn.MouseButton1Click:Connect(function() F.BuyAmount=amt; repaint() end)
    end
    repaint()
end

local function label(text)
    local l=Instance.new("TextLabel"); l.Size=UDim2.new(1,0,0,14); l.BackgroundTransparency=1
    l.Font=Enum.Font.Gotham; l.TextSize=11; l.TextColor3=Color3.fromRGB(160,150,120)
    l.TextXAlignment=Enum.TextXAlignment.Left; l.Text=text; l.LayoutOrder=row(); l.Parent=listframe
end

toggle("ClaimEggs","Auto Claim Eggs")
toggle("Deposit","Auto Deposit Eggs")
toggle("CollectCash","Auto Collect Cash")
toggle("UpgradePS","Auto Upgrade /sec")
toggle("Merge","Auto Merge Chickens")
toggle("LuckyBlock","Auto Lucky Block")
toggle("Rebirth","Auto Rebirth (resets!)", Color3.fromRGB(255,150,150))
toggle("BuyChickens","Auto Buy Chickens")
label("  Buy amount:")
amountRow()

do
    local DISCORD_INVITE = "https://discord.gg/SgBZtPnTkd"
    local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,26); b.BorderSizePixel=0
    b.BackgroundColor3=Color3.fromRGB(38,42,70); b.Font=Enum.Font.GothamBold; b.TextSize=13
    b.TextColor3=Color3.fromRGB(150,175,255); b.TextXAlignment=Enum.TextXAlignment.Left; b.LayoutOrder=row(); b.Parent=listframe
    Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); Instance.new("UIPadding",b).PaddingLeft=UDim.new(0,10)
    b.Text="💬 Discord - Copy Invite"
    b.MouseButton1Click:Connect(function()
        local copy = (setclipboard) or (toclipboard) or (writeclipboard) or (syn and syn.write_clipboard)
        local ok = copy ~= nil and pcall(copy, DISCORD_INVITE)
        b.Text = ok and "✓ Copied! discord.gg/SgBZtPnTkd" or "discord.gg/SgBZtPnTkd"
        task.delay(2.5, function() if b and b.Parent then b.Text="💬 Discord - Copy Invite" end end)
    end)
end

do
    local drag,ds,sp
    bar.InputBegan:Connect(function(i)
        if i.UserInputType==Enum.UserInputType.MouseButton1 or i.UserInputType==Enum.UserInputType.Touch then
            drag=true; ds=i.Position; sp=main.Position
            i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then drag=false end end)
        end
    end)
    UserInput.InputChanged:Connect(function(i)
        if drag and (i.UserInputType==Enum.UserInputType.MouseMovement or i.UserInputType==Enum.UserInputType.Touch) then
            local d=i.Position-ds; main.Position=UDim2.fromOffset(sp.X.Offset+d.X, sp.Y.Offset+d.Y)
        end
    end)
end

local function unload()
    for k in pairs(F) do if type(F[k])=="boolean" then F[k]=false end end
    pcall(function() runConn:Disconnect() end)
    pcall(function() sg:Destroy() end)
    getgenv().__POTATO_FARM=nil
end
UserInput.InputBegan:Connect(function(i,gpe) if not gpe and i.KeyCode==Enum.KeyCode.Delete then unload() end end)

getgenv().__POTATO_FARM={ F=F, unload=unload }
warn("[🐣 VALT FARM] loaded — claim/deposit/collect/merge/lucky/rebirth/buy. Unload: Delete key.")
