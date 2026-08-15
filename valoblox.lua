--[[==============================================================
    🥔 POTATO — VALOBLOX ALL-IN-ONE
    Modules: ESP  •  Aimbot (RMB head-lock)  •  Silent Aim  •  Triggerbot
    Place: 11746368176 (Valoblox)
    Run the whole file in your executor. Panels appear top-left.

    UNLOAD KEYS
      RightShift .. ESP
      RightCtrl  .. Aimbot
      F8         .. Silent + Trigger
      End        .. UNLOAD EVERYTHING (master)
================================================================]]--

--== master cleanup: re-running the file wipes old instances first ==--
for _, g in ipairs({ "__POTATO_ESP", "__POTATO_AIM", "__POTATO_SILENT" }) do
    if getgenv()[g] and getgenv()[g].unload then pcall(getgenv()[g].unload) end
end

local Players    = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInput  = game:GetService("UserInputService")
local Workspace  = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

local ENEMY  = Color3.fromRGB(255, 60, 60)
local FRIEND = Color3.fromRGB(60, 255, 90)
local WHITE  = Color3.fromRGB(255, 255, 255)
local BLACK  = Color3.fromRGB(0, 0, 0)
local BLUE   = Color3.fromRGB(120, 180, 255)

local gethuiFn = (typeof(gethui) == "function") and gethui or function() return game:GetService("CoreGui") end

--------------------------------------------------------------------
-- shared GUI factory
--------------------------------------------------------------------
local function makePanel(titleText, x, strokeCol)
    local sg = Instance.new("ScreenGui")
    sg.ResetOnSpawn = false; sg.IgnoreGuiInset = true
    sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling; sg.Parent = gethuiFn()

    local main = Instance.new("Frame")
    main.Size = UDim2.fromOffset(210, 300); main.Position = UDim2.fromOffset(x, 120)
    main.BackgroundColor3 = Color3.fromRGB(20, 20, 26); main.BorderSizePixel = 0
    main.Active = true; main.Parent = sg
    Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)
    local strk = Instance.new("UIStroke", main); strk.Color = strokeCol; strk.Thickness = 1.4; strk.Transparency = 0.3

    local bar = Instance.new("Frame"); bar.Size = UDim2.new(1, 0, 0, 30); bar.BorderSizePixel = 0
    bar.BackgroundColor3 = Color3.fromRGB(30, 30, 40); bar.Parent = main
    Instance.new("UICorner", bar).CornerRadius = UDim.new(0, 8)
    local ttl = Instance.new("TextLabel"); ttl.Size = UDim2.new(1, -10, 1, 0); ttl.Position = UDim2.fromOffset(10, 0)
    ttl.BackgroundTransparency = 1; ttl.Font = Enum.Font.GothamBold; ttl.TextSize = 13; ttl.TextColor3 = WHITE
    ttl.TextXAlignment = Enum.TextXAlignment.Left; ttl.Text = titleText; ttl.Parent = bar

    local list = Instance.new("Frame"); list.Size = UDim2.new(1, -16, 1, -40); list.Position = UDim2.fromOffset(8, 36)
    list.BackgroundTransparency = 1; list.Parent = main
    local lay = Instance.new("UIListLayout", list); lay.Padding = UDim.new(0, 4); lay.SortOrder = Enum.SortOrder.LayoutOrder

    -- drag
    local drag, ds, sp
    bar.InputBegan:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 or i.UserInputType == Enum.UserInputType.Touch then
            drag = true; ds = i.Position; sp = main.Position
            i.Changed:Connect(function() if i.UserInputState == Enum.UserInputState.End then drag = false end end)
        end
    end)
    UserInput.InputChanged:Connect(function(i)
        if drag and (i.UserInputType == Enum.UserInputType.MouseMovement or i.UserInputType == Enum.UserInputType.Touch) then
            local d = i.Position - ds
            main.Position = UDim2.fromOffset(sp.X.Offset + d.X, sp.Y.Offset + d.Y)
        end
    end)

    local ord = 0
    local api = { sg = sg }
    function api.header(text)
        ord += 1
        local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, 0, 0, 16); l.BackgroundTransparency = 1
        l.Font = Enum.Font.GothamBold; l.TextSize = 11; l.TextColor3 = Color3.fromRGB(150, 150, 170)
        l.TextXAlignment = Enum.TextXAlignment.Left; l.Text = text; l.LayoutOrder = ord; l.Parent = list
    end
    function api.toggle(tbl, key, text)
        ord += 1
        local b = Instance.new("TextButton"); b.Size = UDim2.new(1, 0, 0, 22); b.BorderSizePixel = 0
        b.BackgroundColor3 = Color3.fromRGB(35, 35, 46); b.Font = Enum.Font.GothamMedium; b.TextSize = 12
        b.TextColor3 = WHITE; b.TextXAlignment = Enum.TextXAlignment.Left; b.LayoutOrder = ord; b.Parent = list
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5); Instance.new("UIPadding", b).PaddingLeft = UDim.new(0, 8)
        local dot = Instance.new("Frame"); dot.Size = UDim2.fromOffset(10, 10); dot.Position = UDim2.new(1, -20, 0.5, -5)
        dot.BorderSizePixel = 0; dot.Parent = b; Instance.new("UICorner", dot).CornerRadius = UDim.new(1, 0)
        local function paint() dot.BackgroundColor3 = tbl[key] and FRIEND or ENEMY; b.Text = text end
        paint(); b.MouseButton1Click:Connect(function() tbl[key] = not tbl[key]; paint() end)
    end
    function api.stepper(tbl, key, text, step, min, max, fmt)
        ord += 1
        local b = Instance.new("Frame"); b.Size = UDim2.new(1, 0, 0, 22); b.BorderSizePixel = 0
        b.BackgroundColor3 = Color3.fromRGB(35, 35, 46); b.LayoutOrder = ord; b.Parent = list
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5)
        local l = Instance.new("TextLabel"); l.Size = UDim2.new(1, -58, 1, 0); l.Position = UDim2.fromOffset(8, 0)
        l.BackgroundTransparency = 1; l.Font = Enum.Font.GothamMedium; l.TextSize = 12; l.TextColor3 = WHITE
        l.TextXAlignment = Enum.TextXAlignment.Left; l.Parent = b
        local function draw() l.Text = text .. ": " .. string.format(fmt, tbl[key]) end; draw()
        local function mk(sym, dx, px)
            local btn = Instance.new("TextButton"); btn.Size = UDim2.fromOffset(22, 16); btn.Position = UDim2.new(1, px, 0.5, -8)
            btn.BackgroundColor3 = Color3.fromRGB(55, 55, 70); btn.BorderSizePixel = 0; btn.Font = Enum.Font.GothamBold
            btn.TextSize = 13; btn.TextColor3 = WHITE; btn.Text = sym; btn.Parent = b
            Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)
            btn.MouseButton1Click:Connect(function() tbl[key] = math.clamp(tbl[key] + dx, min, max); draw() end)
        end
        mk("-", -step, -50); mk("+", step, -26)
    end
    function api.button(text, onClick)
        ord += 1
        local b = Instance.new("TextButton"); b.Size = UDim2.new(1, 0, 0, 22); b.BorderSizePixel = 0
        b.BackgroundColor3 = Color3.fromRGB(38, 42, 70); b.Font = Enum.Font.GothamBold; b.TextSize = 12
        b.TextColor3 = Color3.fromRGB(150, 175, 255); b.TextXAlignment = Enum.TextXAlignment.Left; b.LayoutOrder = ord; b.Parent = list
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 5); Instance.new("UIPadding", b).PaddingLeft = UDim.new(0, 8)
        b.Text = text
        b.MouseButton1Click:Connect(function() onClick(b) end)
        return b
    end
    return api
end

--==============================================================
-- MODULE 1 : ESP
--==============================================================
do
    local S = { Enabled=true, Boxes=true, Names=true, Distance=true, HealthBar=true,
                Tracers=false, HeadDot=true, TeamCheck=true, TeamColor=true, MaxDist=2000 }

    local function newLine(th, col) local l=Drawing.new("Line"); l.Thickness=th or 1; l.Color=col or WHITE; l.Visible=false; return l end
    local function newText(sz) local t=Drawing.new("Text"); t.Size=sz or 13; t.Center=true; t.Outline=true; t.Font=2; t.Color=WHITE; t.Visible=false; return t end
    local function newSquare(th) local s=Drawing.new("Square"); s.Thickness=th or 1; s.Filled=false; s.Color=WHITE; s.Visible=false; return s end
    local function newCircle() local c=Drawing.new("Circle"); c.Thickness=1; c.NumSides=12; c.Radius=3; c.Filled=true; c.Color=WHITE; c.Visible=false; return c end

    local pool = {}
    local function build(plr)
        pool[plr] = { boxOutline=newSquare(3), box=newSquare(1), name=newText(13), dist=newText(12),
                      tracer=newLine(1), hbBg=newLine(3), hbFill=newLine(1), headDot=newCircle() }
    end
    local function destroy(plr) local b=pool[plr]; if not b then return end
        for _,o in pairs(b) do pcall(function() o:Remove() end) end; pool[plr]=nil end
    local function hideAll(b) for _,o in pairs(b) do o.Visible=false end end

    local function colorFor(plr)
        if S.TeamColor then return (plr.Team==LocalPlayer.Team) and FRIEND or ENEMY end
        return ENEMY
    end
    local function screenBox(char)
        local cf,size = char:GetBoundingBox()
        local corners = {
            Vector3.new(size.X,size.Y,size.Z),Vector3.new(-size.X,size.Y,size.Z),
            Vector3.new(size.X,-size.Y,size.Z),Vector3.new(-size.X,-size.Y,size.Z),
            Vector3.new(size.X,size.Y,-size.Z),Vector3.new(-size.X,size.Y,-size.Z),
            Vector3.new(size.X,-size.Y,-size.Z),Vector3.new(-size.X,-size.Y,-size.Z) }
        local minX,minY,maxX,maxY = math.huge,math.huge,-math.huge,-math.huge
        local front=false
        for _,c in ipairs(corners) do
            local v = Camera:WorldToViewportPoint((cf*CFrame.new(c*0.5)).Position)
            if v.Z>0 then front=true end
            if v.X<minX then minX=v.X end; if v.Y<minY then minY=v.Y end
            if v.X>maxX then maxX=v.X end; if v.Y>maxY then maxY=v.Y end
        end
        if not front then return nil end
        return minX,minY,maxX,maxY
    end

    local renderConn = RunService.RenderStepped:Connect(function()
        local vp = Camera.ViewportSize
        for plr,b in pairs(pool) do
            local ok=false
            if S.Enabled and plr.Character then
                local char=plr.Character
                local hum=char:FindFirstChildOfClass("Humanoid")
                local root=char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart
                local skip = S.TeamCheck and plr.Team==LocalPlayer.Team
                if hum and hum.Health>0 and root and not skip then
                    local dist=(Camera.CFrame.Position-root.Position).Magnitude
                    if dist<=S.MaxDist then
                        local minX,minY,maxX,maxY = screenBox(char)
                        if minX then
                            ok=true
                            local col=colorFor(plr); local w,h=maxX-minX,maxY-minY; local cx=minX+w/2
                            if S.Boxes then
                                b.boxOutline.Position=Vector2.new(minX,minY); b.boxOutline.Size=Vector2.new(w,h); b.boxOutline.Color=BLACK
                                b.box.Position=Vector2.new(minX,minY); b.box.Size=Vector2.new(w,h); b.box.Color=col
                                b.boxOutline.Visible=true; b.box.Visible=true
                            else b.boxOutline.Visible=false; b.box.Visible=false end
                            if S.Names then b.name.Text=plr.Name; b.name.Color=col; b.name.Position=Vector2.new(cx,minY-16); b.name.Visible=true
                            else b.name.Visible=false end
                            if S.Distance then b.dist.Text=string.format("[%dm]",math.floor(dist)); b.dist.Color=WHITE; b.dist.Position=Vector2.new(cx,maxY+2); b.dist.Visible=true
                            else b.dist.Visible=false end
                            if S.HealthBar then
                                local pct=math.clamp(hum.Health/hum.MaxHealth,0,1); local barX=minX-5
                                b.hbBg.From=Vector2.new(barX,minY); b.hbBg.To=Vector2.new(barX,maxY); b.hbBg.Color=BLACK; b.hbBg.Visible=true
                                b.hbFill.From=Vector2.new(barX,maxY); b.hbFill.To=Vector2.new(barX,maxY-h*pct)
                                b.hbFill.Color=Color3.fromRGB(255*(1-pct),255*pct,40); b.hbFill.Visible=true
                            else b.hbBg.Visible=false; b.hbFill.Visible=false end
                            if S.Tracers then
                                b.tracer.From=Vector2.new(vp.X/2,vp.Y); b.tracer.To=Vector2.new(cx,maxY); b.tracer.Color=col; b.tracer.Visible=true
                            else b.tracer.Visible=false end
                            if S.HeadDot then
                                local head=char:FindFirstChild("Head")
                                if head then local hp,on=Camera:WorldToViewportPoint(head.Position)
                                    if on then b.headDot.Position=Vector2.new(hp.X,hp.Y); b.headDot.Color=col; b.headDot.Visible=true
                                    else b.headDot.Visible=false end end
                            else b.headDot.Visible=false end
                        end
                    end
                end
            end
            if not ok then hideAll(b) end
        end
    end)

    for _,p in ipairs(Players:GetPlayers()) do if p~=LocalPlayer then build(p) end end
    local addConn = Players.PlayerAdded:Connect(function(p) if p~=LocalPlayer then build(p) end end)
    local remConn = Players.PlayerRemoving:Connect(destroy)

    local ui = makePanel("🥔 POTATO ESP", 24, ENEMY)
    ui.toggle(S,"Enabled","Enabled"); ui.toggle(S,"Boxes","Boxes"); ui.toggle(S,"Names","Names")
    ui.toggle(S,"Distance","Distance"); ui.toggle(S,"HealthBar","Health Bar"); ui.toggle(S,"Tracers","Tracers")
    ui.toggle(S,"HeadDot","Head Dot"); ui.toggle(S,"TeamCheck","Team Check"); ui.toggle(S,"TeamColor","Team Color")
    ui.button("💬 Discord - Copy Invite", function(b)
        local copy = (setclipboard) or (toclipboard) or (writeclipboard) or (syn and syn.write_clipboard)
        local ok = copy ~= nil and pcall(copy, "https://discord.gg/SgBZtPnTkd")
        b.Text = ok and "✓ Copied! discord.gg/SgBZtPnTkd" or "discord.gg/SgBZtPnTkd"
        task.delay(2.5, function() if b and b.Parent then b.Text = "💬 Discord - Copy Invite" end end)
    end)

    local function unload()
        pcall(function() renderConn:Disconnect() end); pcall(function() addConn:Disconnect() end)
        pcall(function() remConn:Disconnect() end)
        for plr in pairs(pool) do destroy(plr) end
        pcall(function() ui.sg:Destroy() end); getgenv().__POTATO_ESP=nil
    end
    UserInput.InputBegan:Connect(function(i,gpe) if not gpe and i.KeyCode==Enum.KeyCode.RightShift then unload() end end)
    getgenv().__POTATO_ESP = { settings=S, unload=unload }
end

--==============================================================
-- MODULE 2 : AIMBOT (hold Right Mouse -> lock head)
--==============================================================
do
    local A = { Enabled=true, FOV=120, Smooth=0.35, TeamCheck=true, VisCheck=true, Sticky=true, AimPart="Head" }

    local fov = Drawing.new("Circle"); fov.Thickness=1.5; fov.NumSides=64; fov.Filled=false
    fov.Color=WHITE; fov.Transparency=0.6; fov.Visible=false

    local function mousePos() return UserInput:GetMouseLocation() end
    local function alive(plr)
        local c=plr.Character; if not c then return nil end
        local hum=c:FindFirstChildOfClass("Humanoid"); local part=c:FindFirstChild(A.AimPart)
        if hum and hum.Health>0 and part then return c,hum,part end; return nil
    end
    local function visible(char,part)
        if not A.VisCheck then return true end
        local o=Camera.CFrame.Position
        local p=RaycastParams.new(); p.FilterType=Enum.RaycastFilterType.Exclude
        p.FilterDescendantsInstances={LocalPlayer.Character,char,Camera}
        return Workspace:Raycast(o,part.Position-o,p)==nil
    end
    local function acquire()
        local m=mousePos(); local best,bestPart,bestD=nil,nil,A.FOV
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr~=LocalPlayer and not(A.TeamCheck and plr.Team==LocalPlayer.Team) then
                local char,hum,part=alive(plr)
                if char then
                    local sp,on=Camera:WorldToViewportPoint(part.Position)
                    if on and sp.Z>0 then
                        local d=(Vector2.new(sp.X,sp.Y)-m).Magnitude
                        if d<bestD and visible(char,part) then best,bestPart,bestD=plr,part,d end
                    end
                end
            end
        end
        return best,bestPart
    end

    local locked=nil
    local aimConn = RunService.RenderStepped:Connect(function()
        fov.Radius=A.FOV; fov.Position=mousePos(); fov.Visible=A.Enabled
        if not A.Enabled then return end
        if not UserInput:IsMouseButtonPressed(Enum.UserInputType.MouseButton2) then locked=nil; fov.Color=WHITE; return end
        local targetPart
        if A.Sticky and locked then
            local char,hum,part=alive(locked)
            if char and part and not(A.TeamCheck and locked.Team==LocalPlayer.Team) then
                local sp,on=Camera:WorldToViewportPoint(part.Position)
                if on and sp.Z>0 and visible(char,part) then targetPart=part else locked=nil end
            else locked=nil end
        end
        if not targetPart then local p,part=acquire(); if p then locked,targetPart=p,part end end
        fov.Color = targetPart and ENEMY or WHITE
        if not targetPart then return end
        local camPos=Camera.CFrame.Position
        Camera.CFrame = Camera.CFrame:Lerp(CFrame.new(camPos,targetPart.Position), math.clamp(A.Smooth,0.02,1))
    end)

    local ui = makePanel("🥔 POTATO AIM", 244, ENEMY)
    ui.toggle(A,"Enabled","Enabled"); ui.stepper(A,"FOV","FOV",10,30,400,"%d")
    ui.stepper(A,"Smooth","Smooth",0.05,0.05,1,"%.2f")
    ui.toggle(A,"TeamCheck","Team Check"); ui.toggle(A,"VisCheck","Vis Check"); ui.toggle(A,"Sticky","Sticky")

    local function unload()
        pcall(function() aimConn:Disconnect() end); pcall(function() fov:Remove() end)
        pcall(function() ui.sg:Destroy() end); getgenv().__POTATO_AIM=nil
    end
    UserInput.InputBegan:Connect(function(i,gpe) if not gpe and i.KeyCode==Enum.KeyCode.RightControl then unload() end end)
    getgenv().__POTATO_AIM = { settings=A, unload=unload }
end

--==============================================================
-- MODULE 3 : SILENT AIM (ScreenPointToRay hook) + TRIGGERBOT
--==============================================================
do
    local SA = { Enabled=true, FOV=90, TeamCheck=true, VisCheck=true, AimPart="Head" }
    local TB = { Enabled=true, HoldMode=false, HoldKey=Enum.KeyCode.LeftAlt, Delay=0.10, Range=3000, TeamCheck=true }

    local ring = Drawing.new("Circle"); ring.Thickness=1.5; ring.NumSides=48; ring.Filled=false
    ring.Color=BLUE; ring.Transparency=0.5; ring.Visible=false

    local function mousePos() return UserInput:GetMouseLocation() end
    local function livePart(plr)
        local c=plr.Character; if not c then return nil end
        local hum=c:FindFirstChildOfClass("Humanoid"); local part=c:FindFirstChild(SA.AimPart)
        if hum and hum.Health>0 and part then return c,part end; return nil
    end
    local function visible(char,part)
        if not SA.VisCheck then return true end
        local o=Camera.CFrame.Position
        local p=RaycastParams.new(); p.FilterType=Enum.RaycastFilterType.Exclude
        p.FilterDescendantsInstances={LocalPlayer.Character,char,Camera}
        return Workspace:Raycast(o,part.Position-o,p)==nil
    end
    local function acquire()
        local m=mousePos(); local best,bestD=nil,SA.FOV
        for _,plr in ipairs(Players:GetPlayers()) do
            if plr~=LocalPlayer and not(SA.TeamCheck and plr.Team==LocalPlayer.Team) then
                local char,part=livePart(plr)
                if char then
                    local sp,on=Camera:WorldToViewportPoint(part.Position)
                    if on and sp.Z>0 then
                        local d=(Vector2.new(sp.X,sp.Y)-m).Magnitude
                        if d<bestD and visible(char,part) then best,bestD=part,d end
                    end
                end
            end
        end
        return best
    end

    local silentTarget=nil; local lastFire=0
    local loopConn = RunService.RenderStepped:Connect(function()
        ring.Radius=SA.FOV; ring.Position=mousePos(); ring.Visible=SA.Enabled
        silentTarget = SA.Enabled and acquire() or nil
        ring.Color = silentTarget and ENEMY or BLUE
        if TB.Enabled then
            local hold=(not TB.HoldMode) or UserInput:IsKeyDown(TB.HoldKey)
            if hold then
                local o=Camera.CFrame.Position
                local p=RaycastParams.new(); p.FilterType=Enum.RaycastFilterType.Exclude
                p.FilterDescendantsInstances={LocalPlayer.Character,Camera}
                local r=Workspace:Raycast(o,Camera.CFrame.LookVector*TB.Range,p)
                if r and r.Instance then
                    local model=r.Instance:FindFirstAncestorOfClass("Model")
                    local hum=model and model:FindFirstChildOfClass("Humanoid")
                    local plr=model and Players:GetPlayerFromCharacter(model)
                    if plr and hum and hum.Health>0 and plr~=LocalPlayer and (not TB.TeamCheck or plr.Team~=LocalPlayer.Team) then
                        if (tick()-lastFire)>=TB.Delay then lastFire=tick(); pcall(function() mouse1click() end) end
                    end
                end
            end
        end
    end)

    local oldNamecall
    oldNamecall = hookmetamethod(game,"__namecall",newcclosure(function(self,...)
        local method=getnamecallmethod()
        if SA.Enabled and not checkcaller() and method=="ScreenPointToRay" and self==Camera and silentTarget then
            local camPos=Camera.CFrame.Position
            return Ray.new(camPos,(silentTarget.Position-camPos).Unit)
        end
        return oldNamecall(self,...)
    end))

    local ui = makePanel("🥔 SILENT + TRIGGER", 464, BLUE)
    ui.header("SILENT AIM"); ui.toggle(SA,"Enabled","Enabled"); ui.stepper(SA,"FOV","FOV",10,20,300,"%d")
    ui.toggle(SA,"TeamCheck","Team Check"); ui.toggle(SA,"VisCheck","Vis Check")
    ui.header("TRIGGERBOT"); ui.toggle(TB,"Enabled","Enabled"); ui.toggle(TB,"HoldMode","Hold Key (LAlt)")
    ui.stepper(TB,"Delay","Delay",0.02,0.02,0.6,"%.2f")

    local function unload()
        SA.Enabled=false; TB.Enabled=false
        pcall(function() loopConn:Disconnect() end); pcall(function() ring:Remove() end)
        pcall(function() hookmetamethod(game,"__namecall",oldNamecall) end)
        pcall(function() ui.sg:Destroy() end); getgenv().__POTATO_SILENT=nil
    end
    UserInput.InputBegan:Connect(function(i,gpe) if not gpe and i.KeyCode==Enum.KeyCode.F8 then unload() end end)
    getgenv().__POTATO_SILENT = { SA=SA, TB=TB, unload=unload }
end

--==============================================================
-- MASTER UNLOAD  (End key)
--==============================================================
UserInput.InputBegan:Connect(function(i, gpe)
    if not gpe and i.KeyCode == Enum.KeyCode.End then
        for _, g in ipairs({ "__POTATO_ESP", "__POTATO_AIM", "__POTATO_SILENT" }) do
            if getgenv()[g] and getgenv()[g].unload then pcall(getgenv()[g].unload) end
        end
        warn("[POTATO] ALL MODULES UNLOADED")
    end
end)

warn("[🥔 POTATO VALOBLOX] loaded — ESP + Aimbot + Silent + Trigger. Unload all: End key.")
