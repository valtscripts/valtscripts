--[[==============================================================
    🥔 POTATO — DIG & CLEAN AUTO  (tek GUI, hepsi içinde)
    ● Fast Dig Click  — kazarken ekrana çok hızlı sol-tık (hızlı kaz)
    ● Auto Clean      — kirli itemleri temizler
    ● Auto Best On Sale — en değerli itemleri pedestal'a koyar/swaplar
    ● Auto Sell       — envanteri gold'a satar
    ● Auto Better Items — paran yeten gear'ı alır
    Unload: End tuşu.   (Fast Click'i sadece kazarken aç.)
================================================================]]--
if getgenv().__POTATO_DC then pcall(getgenv().__POTATO_DC.unload) end

local Players=game:GetService("Players"); local RunService=game:GetService("RunService")
local UserInput=game:GetService("UserInputService"); local RS=game:GetService("ReplicatedStorage")
local Workspace=game:GetService("Workspace"); local LP=Players.LocalPlayer

local net=LP.PlayerScripts:WaitForChild("TS"):WaitForChild("network")
local ItemsNet=require(net.ItemsNetwork); local ItemsF=ItemsNet.ItemsFunctions; local ItemsEv=ItemsNet.ItemsEvents
local PedestalF=require(net.PedestalNetwork).PedestalFunctions
local SellF=require(net.SellNetwork).SellFunctions; local ShopF=require(net.ShopNetwork).ShopFunctions
local DataF=require(net.DataNetwork).DataFunctions
local ShovelCat=(require(RS.TS.constants.digging.Shovels)); ShovelCat=ShovelCat.Shovels or ShovelCat
local DetectorCat=(require(RS.TS.constants.digging.Detectors)); DetectorCat=DetectorCat.Detectors or DetectorCat
local SprayCat=require(RS.TS.constants.cleaning.SprayBottles)
local itemValueFor=require(RS.TS.constants.items.Items).itemValueFor

local W=Color3.fromRGB(255,255,255); local G=Color3.fromRGB(70,220,120); local R=Color3.fromRGB(255,80,80); local GD=Color3.fromRGB(255,190,70)
local function getData() local o,d=pcall(function() return DataF.requestDataUpdate:invoke():expect() end); return o and d or nil end
local function toSet(a) local s={}; if type(a)=="table" then for _,v in ipairs(a) do s[v]=true end end; return s end
local function vOf(id,c,k) local o,v=pcall(function() return itemValueFor(id,c,tonumber(k)) end); return o and (v or 0) or 0 end
local function click() if mouse1click then pcall(mouse1click) elseif mouse1press then pcall(mouse1press); pcall(mouse1release) end end

local S={FastClick=false,Clean=false,BestSale=false,Sell=false,Better=false}
local L={c=0,s=0,se=0,b=0}
local alive=true

-- FAST DIG CLICK: 5 clicks/frame while on
task.spawn(function()
    while alive do
        if S.FastClick then for _=1,5 do click() end RunService.Heartbeat:Wait()
        else task.wait(0.1) end
    end
end)

local function cleanDirty(g) local d=getData(); if not d then return end for _,it in pairs(d.Inventory) do if g and not g() then return end if tostring(it.dirty)=="true" then pcall(function() ItemsF.beginCleaning:invoke(it.uid):expect() end); pcall(function() ItemsEv.finishCleaning:fire(it.uid) end) end end end
local function myPlot() local hrp=LP.Character and LP.Character:FindFirstChild("HumanoidRootPart"); local pl=Workspace:FindFirstChild("Plots"); if not hrp or not pl then return nil end local b,bd; for _,p in ipairs(pl:GetChildren()) do local pp=p:FindFirstChildWhichIsA("BasePart",true); if pp then local dd=(pp.Position-hrp.Position).Magnitude; if not bd or dd<bd then bd=dd; b=p end end end return b end
local function ownedPeds(plot) local r={} for _,x in ipairs(plot:GetDescendants()) do if x.Name:find("Pedestal") and x:GetAttribute("Owned")==true and x:GetAttribute("Slot")~=nil then local u=x:GetAttribute("ItemUid"); local oc=(u~=nil and u~=""); r[#r+1]={slot=x:GetAttribute("Slot"),uid=oc and u or nil,value=oc and vOf(x:GetAttribute("ItemId"),x:GetAttribute("Condition"),x:GetAttribute("Kg")) or 0} end end return r end
local function doBestSale() local plot=myPlot(); if not plot then return end cleanDirty(function() return S.BestSale end) local d=getData(); if not d then return end local up={} for _,it in pairs(d.Inventory) do if tostring(it.dirty)=="false" and (it.pedestalSlot==nil or tostring(it.pedestalSlot)=="nil") then up[#up+1]={uid=it.uid,value=vOf(it.id,it.condition,it.kg)} end end table.sort(up,function(a,b) return a.value>b.value end) local pd=ownedPeds(plot)
    for _,p in ipairs(pd) do if not S.BestSale then return end if not p.uid and #up>0 then local bt=up[1]; local o,rr=pcall(function() return PedestalF.placeItem:invoke(p.slot,bt.uid):expect() end); if o and rr then table.remove(up,1); p.uid=bt.uid; p.value=bt.value end end end
    local g=0; while #up>0 and S.BestSale and g<25 do g+=1; local ms,mv,mi; for i,p in ipairs(pd) do if p.uid and (not mv or p.value<mv) then mv=p.value; ms=p.slot; mi=i end end if not ms or up[1].value<=mv then break end local bt=table.remove(up,1); local pu=pcall(function() return PedestalF.pickupItem:invoke(ms):expect() end); if pu then task.wait(0.05); local o,rr=pcall(function() return PedestalF.placeItem:invoke(ms,bt.uid):expect() end); if o and rr then pd[mi].uid=bt.uid; pd[mi].value=bt.value else pd[mi].uid=nil; pd[mi].value=0 end end end end
local function doSell() pcall(function() SellF.sellInventory:invoke() end) end
local function buyAff(cat,cg,ow,gold) for id,inf in pairs(cat) do if not S.Better then break end if type(inf)=="table" and type(inf.cost)=="number" and not ow[id] and inf.cost<=gold then local o,rr=pcall(function() return ShopF.buyGear:invoke(cg,id):expect() end); if o and rr then gold-=inf.cost end end end end
local function doBetter() local d=getData(); if not d then return end local gold=d.Gold or 0; buyAff(ShovelCat,"shovel",toSet(d.OwnedShovels),gold); buyAff(DetectorCat,"detector",toSet(d.OwnedDetectors),gold); buyAff(SprayCat,"spray",toSet(d.OwnedSprays),gold) end

local run=RunService.Heartbeat:Connect(function() local n=os.clock()
    if S.Clean and (n-L.c)>=0.8 then L.c=n; task.spawn(function() cleanDirty(function() return S.Clean end) end) end
    if S.BestSale and (n-L.s)>=1.0 then L.s=n; task.spawn(doBestSale) end
    if S.Sell and (n-L.se)>=1.2 then L.se=n; task.spawn(doSell) end
    if S.Better and (n-L.b)>=2.0 then L.b=n; task.spawn(doBetter) end
end)

--== GUI ==--
local hui=(typeof(gethui)=="function") and gethui() or game:GetService("CoreGui")
local sg=Instance.new("ScreenGui"); sg.ResetOnSpawn=false; sg.IgnoreGuiInset=true; sg.Parent=hui
local m=Instance.new("Frame"); m.Size=UDim2.fromOffset(288,256); m.Position=UDim2.fromOffset(40,120); m.BackgroundColor3=Color3.fromRGB(18,18,24); m.BorderSizePixel=0; m.Active=true; m.Parent=sg; Instance.new("UICorner",m).CornerRadius=UDim.new(0,10)
local st=Instance.new("UIStroke",m); st.Color=GD; st.Thickness=1.5
local bar=Instance.new("Frame"); bar.Size=UDim2.new(1,0,0,32); bar.BackgroundColor3=Color3.fromRGB(28,28,38); bar.BorderSizePixel=0; bar.Parent=m; Instance.new("UICorner",bar).CornerRadius=UDim.new(0,10)
local tt=Instance.new("TextLabel"); tt.Size=UDim2.new(1,-12,1,0); tt.Position=UDim2.fromOffset(12,0); tt.BackgroundTransparency=1; tt.Font=Enum.Font.GothamBold; tt.TextSize=14; tt.TextColor3=GD; tt.TextXAlignment=Enum.TextXAlignment.Left; tt.Text="🥔 DIG & CLEAN AUTO"; tt.Parent=bar
local lf=Instance.new("Frame"); lf.Size=UDim2.new(1,-16,1,-42); lf.Position=UDim2.fromOffset(8,38); lf.BackgroundTransparency=1; lf.Parent=m; local ly=Instance.new("UIListLayout",lf); ly.Padding=UDim.new(0,6); local od=0
local function tg(k,txt,col) od+=1; local b=Instance.new("TextButton"); b.Size=UDim2.new(1,0,0,30); b.BackgroundColor3=Color3.fromRGB(26,26,34); b.BorderSizePixel=0; b.Font=Enum.Font.GothamBold; b.TextSize=13; b.TextColor3=col or W; b.TextXAlignment=Enum.TextXAlignment.Left; b.LayoutOrder=od; b.Parent=lf; Instance.new("UICorner",b).CornerRadius=UDim.new(0,6); Instance.new("UIPadding",b).PaddingLeft=UDim.new(0,10); b.Text=txt
    local dt=Instance.new("Frame"); dt.Size=UDim2.fromOffset(11,11); dt.Position=UDim2.new(1,-22,0.5,-5); dt.BorderSizePixel=0; dt.Parent=b; Instance.new("UICorner",dt).CornerRadius=UDim.new(1,0)
    local function pt() dt.BackgroundColor3=S[k] and G or R end pt(); b.MouseButton1Click:Connect(function() S[k]=not S[k]; pt() end) end
tg("FastClick","⚡ Fast Dig Click (E)",GD); tg("Clean","Auto Clean"); tg("BestSale","Auto Best On Sale"); tg("Sell","Auto Sell"); tg("Better","Auto Better Items")
do local dg,ds,sp; bar.InputBegan:Connect(function(i) if i.UserInputType==Enum.UserInputType.MouseButton1 then dg=true; ds=i.Position; sp=m.Position; i.Changed:Connect(function() if i.UserInputState==Enum.UserInputState.End then dg=false end end) end end)
    UserInput.InputChanged:Connect(function(i) if dg and i.UserInputType==Enum.UserInputType.MouseMovement then local d=i.Position-ds; m.Position=UDim2.fromOffset(sp.X.Offset+d.X,sp.Y.Offset+d.Y) end end) end

local function unload() alive=false; for k in pairs(S) do S[k]=false end pcall(function() run:Disconnect() end); pcall(function() sg:Destroy() end); getgenv().__POTATO_DC=nil end
UserInput.InputBegan:Connect(function(i,gp) if gp then return end
    if i.KeyCode==Enum.KeyCode.E then S.FastClick=not S.FastClick; for _,b in ipairs(lf:GetChildren()) do if b:IsA("TextButton") and b.Text:find("Fast Dig") then local d=b:FindFirstChildWhichIsA("Frame"); if d then d.BackgroundColor3=S.FastClick and G or R end end end
    elseif i.KeyCode==Enum.KeyCode.End then unload() end end)
getgenv().__POTATO_DC={S=S,unload=unload}
warn("[🥔 POTATO DIG & CLEAN AUTO] loaded — tek GUI. Fast Dig Click = E. Unload = End.")
