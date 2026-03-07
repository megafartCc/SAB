local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Camera = workspace.CurrentCamera
local LP = Players.LocalPlayer
local V2 = Vector2.new
local CF = CFrame.new
local C3 = Color3.fromRGB

local M = {}
M.BoxEnabled = false
M.NameEnabled = false
M.HealthEnabled = false
M.TracersEnabled = false
M.SkeletonEnabled = false
M.TeamEnabled = false
M.HeldItemEnabled = false
M.MaxDist = 1000

local tracked = {}

local function w2s(p)
    local v, on = Camera:WorldToViewportPoint(p)
    return V2(v.X, v.Y), on, v.Z
end

local function alive(p)
    local c = p and p.Character
    if not c then return false end
    local h = c:FindFirstChildOfClass("Humanoid")
    return h and h.Health > 0
end

local function make(plr)
    if plr == LP or tracked[plr] then return end
    local d = {}
    pcall(function()
        d.box = {}
        for i = 1, 4 do
            local l = Drawing.new("Line")
            l.Visible = false
            l.Color = C3(255,255,255)
            l.Thickness = 1
            d.box[i] = l
        end

        d.tracer = Drawing.new("Line")
        d.tracer.Visible = false
        d.tracer.Color = C3(255,255,255)
        d.tracer.Thickness = 1

        d.name = Drawing.new("Text")
        d.name.Visible = false
        d.name.Color = C3(255,255,255)
        d.name.Size = 14
        d.name.Center = true
        d.name.Outline = true

        d.team = Drawing.new("Text")
        d.team.Visible = false
        d.team.Color = C3(255,255,255)
        d.team.Size = 13
        d.team.Center = false
        d.team.Outline = true

        d.hpBg = Drawing.new("Line")
        d.hpBg.Visible = false
        d.hpBg.Color = C3(0,0,0)
        d.hpBg.Thickness = 3

        d.hpFill = Drawing.new("Line")
        d.hpFill.Visible = false
        d.hpFill.Thickness = 2

        d.skel = {}
        d.skelBuilt = false

        d.heldItem = Drawing.new("Text")
        d.heldItem.Visible = false
        d.heldItem.Color = C3(255,200,0)
        d.heldItem.Size = 13
        d.heldItem.Center = true
        d.heldItem.Outline = true
    end)
    tracked[plr] = d
end

local function nuke(plr)
    local d = tracked[plr]
    if not d then return end
    pcall(function()
        for _, l in ipairs(d.box or {}) do l:Remove() end
        if d.tracer then d.tracer:Remove() end
        if d.name then d.name:Remove() end
        if d.team then d.team:Remove() end
        if d.hpBg then d.hpBg:Remove() end
        if d.hpFill then d.hpFill:Remove() end
        if d.heldItem then d.heldItem:Remove() end
        for _, l in ipairs(d.skel or {}) do l:Remove() end
    end)
    tracked[plr] = nil
end

local function buildSkel(plr)
    local d = tracked[plr]
    if not d then return end
    for _, l in ipairs(d.skel or {}) do
        pcall(function() l:Remove() end)
    end
    d.skel = {}
    d.skelBuilt = false

    local char = plr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local n = 8
    if hum.RigType == Enum.HumanoidRigType.R15 then n = 10 end

    for i = 1, n do
        local l = Drawing.new("Line")
        l.Color = C3(255,255,255)
        l.Thickness = 2
        l.Visible = false
        d.skel[i] = l
    end
    d.skelBuilt = true
end

local function hideD(d)
    pcall(function()
        for _, l in ipairs(d.box or {}) do l.Visible = false end
        if d.tracer then d.tracer.Visible = false end
        if d.name then d.name.Visible = false end
        if d.team then d.team.Visible = false end
        if d.hpBg then d.hpBg.Visible = false end
        if d.hpFill then d.hpFill.Visible = false end
        if d.heldItem then d.heldItem.Visible = false end
        for _, l in ipairs(d.skel or {}) do l.Visible = false end
    end)
end

local function drawSkelR6(d, char)
    local head = char:FindFirstChild("Head")
    local torso = char:FindFirstChild("Torso")
    if not head or not torso then
        for _, l in ipairs(d.skel) do l.Visible = false end
        return
    end
    local lA = char:FindFirstChild("Left Arm")
    local rA = char:FindFirstChild("Right Arm")
    local lL = char:FindFirstChild("Left Leg")
    local rL = char:FindFirstChild("Right Leg")

    local tc = torso.CFrame
    local neck = (tc * CF(0,1,0)).Position
    local pelvis = (tc * CF(0,-1,0)).Position
    local lS = (tc * CF(-1.5,1,0)).Position
    local rS = (tc * CF(1.5,1,0)).Position
    local lH = (tc * CF(-0.5,-1,0)).Position
    local rH = (tc * CF(0.5,-1,0)).Position
    local lHand = lA and (lA.CFrame * CF(0,-1,0)).Position or lS
    local rHand = rA and (rA.CFrame * CF(0,-1,0)).Position or rS
    local lFoot = lL and (lL.CFrame * CF(0,-1,0)).Position or lH
    local rFoot = rL and (rL.CFrame * CF(0,-1,0)).Position or rH

    local j = {
        {head.Position, neck},
        {lS, rS},
        {lS, lHand},
        {rS, rHand},
        {neck, pelvis},
        {lH, rH},
        {lH, lFoot},
        {rH, rFoot},
    }
    for i, p in ipairs(j) do
        local l = d.skel[i]
        if l then
            local a, oA, zA = w2s(p[1])
            local b, oB, zB = w2s(p[2])
            if (oA or oB) and zA > 0 and zB > 0 then
                l.From = a
                l.To = b
                l.Visible = true
            else
                l.Visible = false
            end
        end
    end
end

local function drawSkelR15(d, char)
    local head = char:FindFirstChild("Head")
    local uT = char:FindFirstChild("UpperTorso")
    local lT = char:FindFirstChild("LowerTorso")
    local lUA = char:FindFirstChild("LeftUpperArm")
    local lLA = char:FindFirstChild("LeftLowerArm")
    local rUA = char:FindFirstChild("RightUpperArm")
    local rLA = char:FindFirstChild("RightLowerArm")
    local lUL = char:FindFirstChild("LeftUpperLeg")
    local lLL = char:FindFirstChild("LeftLowerLeg")
    local rUL = char:FindFirstChild("RightUpperLeg")
    local rLL = char:FindFirstChild("RightLowerLeg")

    if not head or not uT then
        for _, l in ipairs(d.skel) do l.Visible = false end
        return
    end

    local parts = {
        {head, uT}, {uT, lT},
        {uT, lUA}, {lUA, lLA},
        {uT, rUA}, {rUA, rLA},
        {lT, lUL}, {lUL, lLL},
        {lT, rUL}, {rUL, rLL},
    }
    for i, p in ipairs(parts) do
        local l = d.skel[i]
        if l then
            if p[1] and p[2] and p[1].Parent and p[2].Parent then
                local a, oA, zA = w2s(p[1].Position)
                local b, oB, zB = w2s(p[2].Position)
                if (oA or oB) and zA > 0 and zB > 0 then
                    l.From = a
                    l.To = b
                    l.Visible = true
                else
                    l.Visible = false
                end
            else
                l.Visible = false
            end
        end
    end
end

RunService.Heartbeat:Connect(function()
    Camera = workspace.CurrentCamera
    for plr, d in pairs(tracked) do
        pcall(function()
            if not alive(plr) then
                hideD(d)
                if not Players:FindFirstChild(plr.Name) then nuke(plr) end
                return
            end

            local char = plr.Character
            local hrp = char:FindFirstChild("HumanoidRootPart")
            local hum = char:FindFirstChildOfClass("Humanoid")
            if not hrp or not hum then hideD(d) return end

            local sv, onS = Camera:WorldToViewportPoint(hrp.Position)
            if not onS then hideD(d) return end

            local me = LP.Character
            local myR = me and me:FindFirstChild("HumanoidRootPart")
            if not myR then hideD(d) return end
            local dist = (hrp.Position - myR.Position).Magnitude
            if dist > M.MaxDist then hideD(d) return end

            local tP = Camera:WorldToViewportPoint(hrp.Position + Vector3.new(0,3,0))
            local bP = Camera:WorldToViewportPoint(hrp.Position - Vector3.new(0,3,0))
            local h = math.abs(bP.Y - tP.Y)
            local w = h / 2
            local cx, cy = sv.X, sv.Y

            if M.BoxEnabled then
                d.box[1].From = V2(cx-w, cy-h/2)
                d.box[1].To = V2(cx+w, cy-h/2)
                d.box[1].Visible = true
                d.box[2].From = V2(cx-w, cy+h/2)
                d.box[2].To = V2(cx+w, cy+h/2)
                d.box[2].Visible = true
                d.box[3].From = V2(cx-w, cy-h/2)
                d.box[3].To = V2(cx-w, cy+h/2)
                d.box[3].Visible = true
                d.box[4].From = V2(cx+w, cy-h/2)
                d.box[4].To = V2(cx+w, cy+h/2)
                d.box[4].Visible = true
            else
                for i=1,4 do d.box[i].Visible = false end
            end

            if M.NameEnabled then
                d.name.Text = plr.DisplayName or plr.Name
                d.name.Position = V2(cx, cy - h/2 - 18)
                d.name.Visible = true
            else
                d.name.Visible = false
            end

            if M.TeamEnabled then
                local teamName = "No Team"
                if plr.Team then teamName = plr.Team.Name end
                d.team.Text = teamName
                d.team.Color = plr.TeamColor and plr.TeamColor.Color or C3(255,255,255)
                if M.BoxEnabled then
                    d.team.Position = V2(cx + w + 8, cy - h / 2)
                    d.team.Visible = true
                else
                    local head = char:FindFirstChild("Head") or hrp
                    local hv, hon, hz = w2s(head.Position + Vector3.new(0, 0.45, 0))
                    if hon and hz > 0 then
                        d.team.Position = V2(hv.X + 10, hv.Y - 8)
                        d.team.Visible = true
                    else
                        d.team.Visible = false
                    end
                end
            else
                d.team.Visible = false
            end

            if M.HealthEnabled then
                local hp = hum.Health / hum.MaxHealth
                local bx = cx - w - 5
                local bt = cy - h/2
                local bb = cy + h/2
                d.hpBg.From = V2(bx, bb)
                d.hpBg.To = V2(bx, bt)
                d.hpBg.Visible = true
                d.hpFill.From = V2(bx, bb)
                d.hpFill.To = V2(bx, bb - (bb-bt)*hp)
                d.hpFill.Color = C3(255,0,0):Lerp(C3(0,255,0), hp)
                d.hpFill.Visible = true
            else
                d.hpBg.Visible = false
                d.hpFill.Visible = false
            end

            if M.TracersEnabled then
                local ox = Camera.ViewportSize.X / 2
                local oy = Camera.ViewportSize.Y
                d.tracer.From = V2(ox, oy)
                d.tracer.To = V2(cx, cy + h/2)
                d.tracer.Visible = true
            else
                d.tracer.Visible = false
            end

            if M.SkeletonEnabled then
                if not d.skelBuilt then buildSkel(plr) end
                if hum.RigType == Enum.HumanoidRigType.R15 then
                    drawSkelR15(d, char)
                else
                    drawSkelR6(d, char)
                end
            else
                for _, l in ipairs(d.skel or {}) do
                    pcall(function() l.Visible = false end)
                end
            end

            if M.HeldItemEnabled then
                local tool = char:FindFirstChildWhichIsA("Tool")
                if tool then
                    d.heldItem.Text = tool.Name
                    d.heldItem.Position = V2(cx, cy + h/2 + 4)
                    d.heldItem.Visible = true
                else
                    d.heldItem.Visible = false
                end
            else
                d.heldItem.Visible = false
            end
        end)
    end
end)

local function onPlr(plr)
    if plr == LP then return end
    pcall(function()
        make(plr)
        plr.CharacterAdded:Connect(function()
            task.wait(0.5)
            pcall(buildSkel, plr)
        end)
    end)
end

for _, p in ipairs(Players:GetPlayers()) do pcall(onPlr, p) end
Players.PlayerAdded:Connect(function(p) pcall(onPlr, p) end)
Players.PlayerRemoving:Connect(function(p) pcall(nuke, p) end)

local API = {}
function API:Init() end
function API:SetBoxEsp(s) M.BoxEnabled = s end
function API:SetNameEsp(s) M.NameEnabled = s end
function API:SetHealthEsp(s) M.HealthEnabled = s end
function API:SetTracers(s) M.TracersEnabled = s end
function API:SetTeamEsp(s) M.TeamEnabled = s end
function API:SetSkeletonEsp(s)
    M.SkeletonEnabled = s
    if s then
        for p in pairs(tracked) do pcall(buildSkel, p) end
    end
end
function API:SetHeldItemEsp(s) M.HeldItemEnabled = s end
function API:SetMaxDist(v) M.MaxDist = v end
return API
