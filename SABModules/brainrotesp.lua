-- ==================================================
-- Brainrot ESP Module — Drawing-based
-- Steal A Brainrot | Clean visual ESP for brainrots
-- API: Init(), Start(), Stop(), SetName(b), SetSkeleton(b),
--      SetTracers(b), SetMoney(b),
--      SetMostExpensive(b), GetBest()
-- ==================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LOCAL_PLAYER = Players.LocalPlayer
local Camera = Workspace.CurrentCamera
local V2 = Vector2.new
local C3 = Color3.fromRGB
local CF = CFrame.new

-- Safe requires
local sharedFolder, datasFolder, packagesFolder
pcall(function() sharedFolder = ReplicatedStorage:WaitForChild("Shared", 5) end)
pcall(function() datasFolder = ReplicatedStorage:WaitForChild("Datas", 5) end)
pcall(function() packagesFolder = ReplicatedStorage:WaitForChild("Packages", 5) end)

local Synchronizer, AnimalsDataModule, AnimalsSharedModule, MutationsDataModule, TraitsDataModule, GameDataModule
pcall(function() Synchronizer = require(packagesFolder:WaitForChild("Synchronizer", 3)) end)
pcall(function() AnimalsDataModule = require(datasFolder:WaitForChild("Animals", 3)) end)
pcall(function() AnimalsSharedModule = require(sharedFolder:WaitForChild("Animals", 3)) end)
pcall(function() MutationsDataModule = require(datasFolder:WaitForChild("Mutations", 3)) end)
pcall(function() TraitsDataModule = require(datasFolder:WaitForChild("Traits", 3)) end)
pcall(function() GameDataModule = require(datasFolder:WaitForChild("Game", 3)) end)

AnimalsDataModule = AnimalsDataModule or {}
MutationsDataModule = MutationsDataModule or {}
TraitsDataModule = TraitsDataModule or {}
GameDataModule = GameDataModule or {}

-- ==================== HELPERS ====================
local function safeCall(fn, ...)
    local ok, r = pcall(fn, ...)
    return ok and r or nil
end

local function formatNumber(v)
    v = tonumber(v) or 0
    if v >= 1e12 then return string.format("%.1fT", v/1e12)
    elseif v >= 1e9 then return string.format("%.1fB", v/1e9)
    elseif v >= 1e6 then return string.format("%.1fM", v/1e6)
    elseif v >= 1e3 then return string.format("%.0fK", v/1e3) end
    return tostring(math.floor(v))
end

local function sanitizeKey(v)
    if v == nil then return nil end
    if typeof(v) == "string" then
        local t = v:gsub("^%s+",""):gsub("%s+$","")
        return t ~= "" and t:lower() or nil
    elseif typeof(v) == "number" then return tostring(v):lower() end
    return nil
end

local function w2s(p)
    local v, on = Camera:WorldToViewportPoint(p)
    return V2(v.X, v.Y), on, v.Z
end

-- Lookup tables
local animalsLookup = {}
for k, e in pairs(AnimalsDataModule) do
    if typeof(k) == "string" then animalsLookup[k:lower()] = e end
    if e and e.DisplayName then animalsLookup[e.DisplayName:lower()] = e end
end

local mutationMultipliers = {}
for n, d in pairs(MutationsDataModule) do
    mutationMultipliers[n] = 1 + (d.Modifier or 0)
end

-- ==================== COLORS ====================
local COLORS = {
    highlight = C3(50, 180, 255),  -- Cyan blue
    name     = C3(255, 255, 255), -- White
    money    = C3(80, 255, 120),  -- Green
    tracer   = C3(50, 180, 255),  -- Cyan blue
    bestAccent = C3(255, 200, 50),-- Gold
    bestName = C3(255, 220, 80),  -- Gold text
    bestMoney= C3(255, 180, 50),  -- Gold money
}

-- ==================== STATE ====================
local S = {
    enabled = false,
    nameEnabled = false,
    highlightEnabled = false,
    highlightColor = COLORS.highlight,
    tracersEnabled = false,
    moneyEnabled = false,
    mostExpensiveOnly = false,
    tracked = {},       -- stand -> visual meta
    knownStands = {},
    standConns = {},
    connections = {},
    podiumsConns = {},
    baseConns = {},
    baseChannelCache = {},
    boundPlots = nil,
    queue = {}, queueSet = {}, forceSet = {},
    queueHead = 1, queueTail = 0,
    refreshList = {}, refreshIndex = 1,
    refreshAccumulator = 0, refreshInterval = 3, refreshBatch = 6,
    standUpdateInterval = 2, queueBudget = 6, frameBudget = 0.003,
    bestStand = nil, bestIncome = -1,
    highlightPool = {}, highlightIndex = 0,
}

-- ==================== DRAWING FACTORY ====================
local function makeDrawings()
    local d = {}

    -- Highlight instance (removed from drawings, now dynamically pooled)

    -- Name text
    d.name = Drawing.new("Text")
    d.name.Visible = false; d.name.Color = COLORS.name
    d.name.Size = 15; d.name.Center = true; d.name.Outline = true
    d.name.Font = 3 -- Plex (modern)

    -- Money/s text
    d.money = Drawing.new("Text")
    d.money.Visible = false; d.money.Color = COLORS.money
    d.money.Size = 13; d.money.Center = true; d.money.Outline = true
    d.money.Font = 3

    -- Tracer line
    d.tracer = Drawing.new("Line")
    d.tracer.Visible = false; d.tracer.Color = COLORS.tracer; d.tracer.Thickness = 1

    -- Best indicator
    d.bestTag = Drawing.new("Text")
    d.bestTag.Visible = false; d.bestTag.Color = COLORS.bestName
    d.bestTag.Size = 12; d.bestTag.Center = true; d.bestTag.Outline = true
    d.bestTag.Font = 3; d.bestTag.Text = "★ BEST ★"

    return d
end

local function destroyDrawings(d)
    if not d then return end
    pcall(function()
        if d.highlight then d.highlight:Destroy() end
        if d.name then d.name:Remove() end
        if d.money then d.money:Remove() end
        if d.tracer then d.tracer:Remove() end
        if d.bestTag then d.bestTag:Remove() end
    end)
end

local function hideDrawings(d)
    if not d then return end
    pcall(function()
        if d.highlight then d.highlight.Enabled = false end
        if d.name then d.name.Visible = false end
        if d.money then d.money.Visible = false end
        if d.tracer then d.tracer.Visible = false end
        if d.bestTag then d.bestTag.Visible = false end
    end)
end

-- ==================== INCOME CALCULATION ====================
local function normalizeTraits(traits)
    if typeof(traits) == "table" then
        if traits[1] then return traits end
        local l = {}; for _, v in pairs(traits) do table.insert(l, v) end; return l
    end
    if typeof(traits) == "string" and traits ~= "" then
        local p = safeCall(function() return HttpService:JSONDecode(traits) end)
        if typeof(p) == "table" then return normalizeTraits(p) end
        return {traits}
    end
    return nil
end

local function readMutation(c)
    if not c then return nil end
    local v = c:GetAttribute("Mutation") or c:GetAttribute("Mut")
    if v ~= nil then return v end
    local ch = c:FindFirstChild("Mutation") or c:FindFirstChild("Mut")
    return ch and ch.Value or nil
end

local function readTraits(c)
    if not c then return nil end
    local t = normalizeTraits(c:GetAttribute("Traits"))
    if t then return t end
    local col = {}
    for i = 1, 4 do
        local k = "Trait"..i
        local v = c:GetAttribute(k)
        if v then table.insert(col, v) else
            local ch = c:FindFirstChild(k)
            if ch and ch.Value then table.insert(col, ch.Value) end
        end
    end
    return #col > 0 and col or nil
end

local function getMutTraitsModel(model)
    if not model then return nil, nil end
    local mut = readMutation(model)
    local traits = readTraits(model)
    if not mut then
        local f = model:FindFirstChild("MutationFolder") or model:FindFirstChild("Mutations")
        if f then for _, ch in ipairs(f:GetChildren()) do
            if ch:IsA("StringValue") and ch.Value ~= "" then mut = ch.Value; break end
        end end
    end
    if not traits then
        local tf = model:FindFirstChild("Traits") or model:FindFirstChild("TraitsFolder")
        if tf then local l = {}; for _, ch in ipairs(tf:GetChildren()) do
            if ch:IsA("StringValue") and ch.Value ~= "" then table.insert(l, ch.Value) end
        end; if #l > 0 then traits = l end end
    end
    return mut, normalizeTraits(traits)
end

local function calcMultiplier(mut, traits)
    local ms, c = {}, 0
    table.insert(ms, (mut and mutationMultipliers[mut]) or 1); c = c + 1
    if typeof(traits) == "table" then
        for _, t in ipairs(traits) do
            local info = TraitsDataModule[t]
            if info then table.insert(ms, 1 + (info.MultiplierModifier or 0)); c = c + 1 end
        end
    end
    if c == 0 then return 1 end
    local sum = 0; for _, m in ipairs(ms) do sum = sum + m end
    local total = sum - (c - 1); return total < 1 and 1 or total
end

local function safePlyMult(owner)
    if not AnimalsSharedModule then return 1 end
    local ok, gs = pcall(function() return require(sharedFolder:WaitForChild("Game")) end)
    if not ok or not gs or type(gs.GetPlayerCashMultiplayer) ~= "function" then return 1 end
    local o2, m = pcall(gs.GetPlayerCashMultiplayer, gs, owner)
    return o2 and tonumber(m) or 1
end

local function getAttrNum(c, keys)
    for _, k in ipairs(keys) do
        local v = c:GetAttribute(k)
        if v then local n = tonumber(v); if n then return n end end
        local ch = c:FindFirstChild(k)
        if ch and ch.Value then local n = tonumber(ch.Value); if n then return n end end
    end; return nil
end

local function computeGen(idx, mut, traits, owner)
    local e = idx and animalsLookup[sanitizeKey(idx) or ""]
    if not e then return 0 end
    local bg = e.Generation or ((e.Price or 0) * (GameDataModule.Game and GameDataModule.Game.AnimalGanerationModifier or 0))
    local m = calcMultiplier(mut, traits)
    local sleepy = false
    if typeof(traits) == "table" then for _, t in ipairs(traits) do if t == "Sleepy" then sleepy = true; break end end end
    local g = bg * m; if sleepy then g = g * 0.5 end
    if owner then g = g * safePlyMult(owner) end
    return math.max(0, math.floor(g + 0.5))
end

local function computeIncome(idx, mut, traits, owner, stand, model, entry)
    entry = entry or (idx and animalsLookup[sanitizeKey(idx) or ""])
    if owner and typeof(owner) == "table" and owner.UserId then
        owner = Players:GetPlayerByUserId(owner.UserId) or owner
    end
    local mm, mt = getMutTraitsModel(model)
    mut = mut or mm; traits = traits or mt or readTraits(stand)
    local inc = (model and getAttrNum(model, {"IncomePerSecond","Income","Generation","Gen"}))
        or (stand and getAttrNum(stand, {"IncomePerSecond","Income","Generation","Gen"}))
    if (not inc or inc == 0) and AnimalsSharedModule and AnimalsSharedModule.GetGeneration and idx then
        inc = safeCall(AnimalsSharedModule.GetGeneration, AnimalsSharedModule, idx, mut, traits, owner)
    end
    if (not inc or inc == 0) and idx then inc = computeGen(idx, mut, traits, owner) end
    if (not inc or inc == 0) and entry and entry.Generation then inc = entry.Generation end
    return inc or 0
end

-- ==================== STAND DISCOVERY ====================
local function isLocalOwner(owner)
    if not owner then return false end
    if owner == LOCAL_PLAYER then return true end
    if typeof(owner) == "Instance" and owner:IsA("Player") then return owner == LOCAL_PLAYER end
    if typeof(owner) == "string" then return LOCAL_PLAYER and owner:lower() == LOCAL_PLAYER.Name:lower() end
    if typeof(owner) == "number" then return LOCAL_PLAYER and owner == LOCAL_PLAYER.UserId end
    if typeof(owner) == "table" then
        if owner.UserId and LOCAL_PLAYER and owner.UserId == LOCAL_PLAYER.UserId then return true end
        if owner.Name and LOCAL_PLAYER and owner.Name:lower() == LOCAL_PLAYER.Name:lower() then return true end
    end
    return false
end

local function getPlotsFolder() return Workspace:FindFirstChild("Plots") end

local function getStandBase(stand)
    if not stand or not stand.Parent then return nil end
    if stand.Parent.Name == "AnimalPodiums" then return stand.Parent.Parent end
    return stand:FindFirstAncestorOfClass("Model")
end

local function getValidStandBase(stand)
    local plots = getPlotsFolder()
    local base = getStandBase(stand)
    if not base then return nil end
    if plots then
        if not base:IsDescendantOf(plots) then return nil end
        if not base:FindFirstChild("PlotSign") then return nil end
        return base
    end
    return base:FindFirstChild("AnimalPodiums") and base or nil
end

local function findBrainrotOnStand(stand)
    if not stand or not stand.Parent then return nil end
    for _, desc in ipairs(stand:GetDescendants()) do
        if desc:IsA("Model") then
            local root = desc:FindFirstChild("RootPart") or desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart
            if root then
                local lk = sanitizeKey(desc.Name)
                local ia = sanitizeKey(desc:GetAttribute("Index") or desc:GetAttribute("Animal") or desc:GetAttribute("Brainrot"))
                local hasInc = desc:FindFirstChild("Income") or desc:FindFirstChild("Generation") or desc:GetAttribute("IncomePerSecond")
                if (lk and animalsLookup[lk]) or (ia and animalsLookup[ia]) or hasInc
                    or desc:GetAttribute("Mutation") or desc:GetAttribute("Traits") then
                    return desc, root
                end
            end
        end
    end
    return nil
end

local function getStandRoot(stand)
    local model, root = findBrainrotOnStand(stand)
    if model then
        root = root or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if root then return model, root end
    end
    local base = stand:FindFirstChild("Base")
    if base then local sp = base:FindFirstChild("Spawn")
        if sp and sp:IsA("BasePart") then return nil, sp end end
    return nil, stand.PrimaryPart or stand:FindFirstChildWhichIsA("BasePart", true)
end

local function getStandSlot(stand)
    if not stand then return nil end
    local n = tonumber(stand.Name); if n then return n end
    return tonumber(stand:GetAttribute("Slot") or stand:GetAttribute("Index"))
end

local function getBaseChannel(base)
    if not base then return nil end
    if S.baseChannelCache[base] then return S.baseChannelCache[base] end
    local ch = nil
    if Synchronizer then
        ch = safeCall(function() return Synchronizer:Get(base.Name) end)
            or safeCall(function() return Synchronizer:Wait(base.Name) end)
    end
    S.baseChannelCache[base] = ch; return ch
end

local function resolveName(stand, model, idx)
    if idx then
        local k = sanitizeKey(idx); local e = k and animalsLookup[k]
        if e then return e.DisplayName or idx end
        return typeof(idx) == "string" and idx or tostring(idx)
    end
    if stand then local a = stand:GetAttribute("Animal") or stand:GetAttribute("Brainrot") or stand:GetAttribute("Pet")
        if a and a ~= "" then return a end end
    return model and model.Name or "Brainrot"
end

local function buildStandInfo(stand)
    if not stand or not stand.Parent then return nil end
    local base = getValidStandBase(stand); if not base then return nil end
    local channel = getBaseChannel(base)
    local slot = getStandSlot(stand)
    local animalData
    if channel and type(channel.Get) == "function" then
        local animals = channel:Get("AnimalList") or channel:Get("AnimalPodiums")
        animalData = animals and animals[slot]
    end
    local model, root = getStandRoot(stand); if not root then return nil end
    local owner = channel and channel:Get("Owner")
    if isLocalOwner(owner) or isLocalOwner(base:GetAttribute("Owner"))
        or isLocalOwner(base:GetAttribute("OwnerName")) or isLocalOwner(base:GetAttribute("PlacedBy")) then return nil end
    local mut = (animalData and (animalData.Mutation or animalData.Mut)) or readMutation(model) or readMutation(stand)
    local traits = normalizeTraits(animalData and animalData.Traits) or readTraits(model) or readTraits(stand)
    local idx = animalData and (animalData.Index or animalData.Animal or animalData.Name)
        or (stand:GetAttribute("Animal") or stand:GetAttribute("Brainrot"))
        or (model and model:GetAttribute("Animal")) or (model and model.Name) or stand.Name
    local name = resolveName(stand, model, idx)
    local k = sanitizeKey(idx) or sanitizeKey(name)
    local entry = k and animalsLookup[k]
    local income = computeIncome(idx, mut, traits, owner, stand, model, entry)
    if not model and income <= 0 then return nil end
    return { stand=stand, base=base, model=model, root=root, name=name, income=income }
end

-- ==================== RENDER ====================
local function renderStand(meta)
    local d = meta.drawings
    local info = meta.info
    if not d or not info or not info.root or not info.root.Parent then hideDrawings(d); return end

    local model = info.model
    local isBest = S.mostExpensiveOnly and S.bestStand == info.stand

    -- Position from root part
    local pos = info.root.Position
    local sv, onScreen = Camera:WorldToViewportPoint(pos)
    if not onScreen then hideDrawings(d); return end

    -- Check distance
    local me = LOCAL_PLAYER.Character
    local myR = me and me:FindFirstChild("HumanoidRootPart")
    if not myR then hideDrawings(d); return end
    if (pos - myR.Position).Magnitude > 1000 then hideDrawings(d); return end

    -- If most expensive only, hide non-best
    if S.mostExpensiveOnly and not isBest then hideDrawings(d); return end

    local hlColor = isBest and COLORS.bestAccent or S.highlightColor or COLORS.highlight

    -- Find character parts on the model for skeleton + head positioning
    local head, torso, lA, rA, lL, rL
    if model then
        head = model:FindFirstChild("Head")
        torso = model:FindFirstChild("Torso") or model:FindFirstChild("UpperTorso")
        lA = model:FindFirstChild("Left Arm") or model:FindFirstChild("LeftUpperArm")
        rA = model:FindFirstChild("Right Arm") or model:FindFirstChild("RightUpperArm")
        lL = model:FindFirstChild("Left Leg") or model:FindFirstChild("LeftUpperLeg")
        rL = model:FindFirstChild("Right Leg") or model:FindFirstChild("RightUpperLeg")
    end

    -- ===== NAME ESP (above brainrot's head in world space) =====
    if S.nameEnabled then
        local nameWorldPos
        if head and head:IsA("BasePart") then
            nameWorldPos = head.Position + Vector3.new(0, 3.0, 0)
        else
            nameWorldPos = pos + Vector3.new(0, 4.5, 0)
        end
        local nameScreen, nameOn = w2s(nameWorldPos)
        if nameOn then
            d.name.Text = info.name or "Brainrot"
            d.name.Color = isBest and COLORS.bestName or COLORS.name
            d.name.Position = nameScreen
            d.name.Visible = true
        else
            d.name.Visible = false
        end
    else
        d.name.Visible = false
    end

    -- ===== BEST TAG (above name) =====
    if isBest and S.nameEnabled then
        local tagPos
        if head and head:IsA("BasePart") then
            tagPos = head.Position + Vector3.new(0, 4.0, 0)
        else
            tagPos = pos + Vector3.new(0, 5.5, 0)
        end
        local tagScreen, tagOn = w2s(tagPos)
        if tagOn then
            d.bestTag.Position = tagScreen
            d.bestTag.Visible = true
        else
            d.bestTag.Visible = false
        end
    else
        d.bestTag.Visible = false
    end

    -- ===== MONEY PER/S (below feet in world space) =====
    if S.moneyEnabled then
        local moneyWorldPos
        if torso and torso:IsA("BasePart") then
            moneyWorldPos = torso.Position - Vector3.new(0, 2.5, 0)
        else
            moneyWorldPos = pos - Vector3.new(0, 1.5, 0)
        end
        local moneyScreen, moneyOn = w2s(moneyWorldPos)
        if moneyOn then
            d.money.Text = "$" .. formatNumber(info.income) .. "/s"
            d.money.Color = isBest and COLORS.bestMoney or COLORS.money
            d.money.Position = moneyScreen
            d.money.Visible = true
        else
            d.money.Visible = false
        end
    else
        d.money.Visible = false
    end

    -- ===== TRACERS =====
    if S.tracersEnabled then
        local ox = Camera.ViewportSize.X / 2
        local oy = Camera.ViewportSize.Y
        d.tracer.From = V2(ox, oy)
        d.tracer.To = V2(sv.X, sv.Y)
        d.tracer.Color = isBest and COLORS.bestAccent or COLORS.tracer
        d.tracer.Visible = true
    else
        d.tracer.Visible = false
    end

    -- ===== HIGHLIGHT =====
    local hlAssigned = false
    if S.highlightEnabled and model and S.highlightIndex < #S.highlightPool then
        S.highlightIndex = S.highlightIndex + 1
        local hl = S.highlightPool[S.highlightIndex]
        if hl then
            hl.Adornee = model
            hl.FillColor = hlColor
            hl.Enabled = true
            hlAssigned = true
        end
    end
end

-- ==================== TRACKING ====================
local function clearStand(stand)
    local meta = S.tracked[stand]
    if not meta then return end
    destroyDrawings(meta.drawings)
    S.tracked[stand] = nil
    if S.bestStand == stand then S.bestStand = nil; S.bestIncome = -1 end
end

local function untrackStand(stand)
    clearStand(stand)
    S.knownStands[stand] = nil; S.queueSet[stand] = nil; S.forceSet[stand] = nil
    local c = S.standConns[stand]
    if c then safeCall(function() c:Disconnect() end) end
    S.standConns[stand] = nil
end

local function updateStand(stand)
    if not S.enabled then return end
    local meta = S.tracked[stand]
    local now = os.clock()
    if meta and meta.nextUpdate and now < meta.nextUpdate then return end

    local info = safeCall(buildStandInfo, stand)
    if not info then clearStand(stand); return end

    if not meta then
        meta = { drawings = makeDrawings(), info = info }
        S.tracked[stand] = meta
    else
        meta.info = info
    end
    meta.nextUpdate = now + S.standUpdateInterval

    -- Track best
    if info.income > S.bestIncome then
        S.bestStand = stand; S.bestIncome = info.income
    end
end

local function enqueue(stand, force)
    if not (stand and stand.Parent) then return end
    if S.queueSet[stand] then if force then S.forceSet[stand] = true end; return end
    S.queueSet[stand] = true; if force then S.forceSet[stand] = true end
    S.queueTail = S.queueTail + 1; S.queue[S.queueTail] = stand
end

local function dequeue()
    if S.queueHead > S.queueTail then return nil end
    local s = S.queue[S.queueHead]; S.queue[S.queueHead] = nil
    S.queueHead = S.queueHead + 1
    if S.queueHead > S.queueTail then S.queueHead = 1; S.queueTail = 0 end
    return s
end

local function trackStand(stand)
    if not (stand and stand:IsA("Model") and stand.Parent) then return end
    if S.knownStands[stand] then return end
    S.knownStands[stand] = true
    S.standConns[stand] = stand.AncestryChanged:Connect(function(_, p) if not p then untrackStand(stand) end end)
    enqueue(stand, true)
end

-- Podium/plot binding
local function unbindPodiums(pod)
    local cs = S.podiumsConns[pod]
    if cs then for _, c in pairs(cs) do safeCall(function() c:Disconnect() end) end end
    S.podiumsConns[pod] = nil
    if pod then for _, s in ipairs(pod:GetChildren()) do if s:IsA("Model") then untrackStand(s) end end end
end

local function bindPodiums(pod)
    if not (pod and pod.Parent) or S.podiumsConns[pod] then return end
    for _, s in ipairs(pod:GetChildren()) do if s:IsA("Model") then trackStand(s) end end
    S.podiumsConns[pod] = {
        a = pod.ChildAdded:Connect(function(c) if c:IsA("Model") then trackStand(c) end end),
        r = pod.ChildRemoved:Connect(function(c) if c:IsA("Model") then untrackStand(c) end end),
        d = pod.AncestryChanged:Connect(function(_,p) if not p then unbindPodiums(pod) end end),
    }
end

local function unbindBase(base)
    local cs = S.baseConns[base]
    if cs then for _, c in pairs(cs) do safeCall(function() c:Disconnect() end) end end
    S.baseConns[base] = nil
    local pod = base and base:FindFirstChild("AnimalPodiums"); if pod then unbindPodiums(pod) end
end

local function bindBase(base)
    if not (base and base.Parent) or S.baseConns[base] then return end
    S.baseConns[base] = {
        a = base.ChildAdded:Connect(function(c) if c.Name == "AnimalPodiums" then bindPodiums(c) end end),
        d = base.AncestryChanged:Connect(function(_,p) if not p then unbindBase(base) end end),
    }
    local pod = base:FindFirstChild("AnimalPodiums"); if pod then bindPodiums(pod) end
end

local function unbindPlots(plots)
    if S.connections.pa then safeCall(function() S.connections.pa:Disconnect() end); S.connections.pa = nil end
    if S.connections.pr then safeCall(function() S.connections.pr:Disconnect() end); S.connections.pr = nil end
    for b in pairs(S.baseConns) do unbindBase(b) end
    S.boundPlots = nil
end

local function bindPlots(plots)
    if not plots or S.boundPlots == plots then return end
    if S.boundPlots then unbindPlots(S.boundPlots) end
    S.boundPlots = plots
    for _, b in ipairs(plots:GetChildren()) do bindBase(b) end
    S.connections.pa = plots.ChildAdded:Connect(function(c) bindBase(c) end)
    S.connections.pr = plots.ChildRemoved:Connect(function(c) unbindBase(c) end)
end

-- Main loop
local function processQueue()
    local start = os.clock()
    local budget = S.queueBudget
    while budget > 0 do
        local stand = dequeue(); if not stand then break end
        S.queueSet[stand] = nil
        if S.forceSet[stand] then S.forceSet[stand] = nil
            local m = S.tracked[stand]; if m then m.nextUpdate = 0 end end
        if stand.Parent then updateStand(stand) else untrackStand(stand) end
        budget = budget - 1
        if (os.clock() - start) > S.frameBudget then break end
    end
end

local function recomputeBest()
    S.bestStand = nil; S.bestIncome = -1
    for stand, meta in pairs(S.tracked) do
        local inc = meta.info and meta.info.income or 0
        if inc > S.bestIncome then S.bestIncome = inc; S.bestStand = stand end
    end
end

local function heartbeat(dt)
    if not S.enabled then return end
    Camera = Workspace.CurrentCamera

    S.refreshAccumulator = (S.refreshAccumulator or 0) + dt
    if S.refreshAccumulator >= S.refreshInterval then
        S.refreshAccumulator = 0; S.refreshList = {}
        for stand in pairs(S.knownStands) do S.refreshList[#S.refreshList+1] = stand end
        S.refreshIndex = 1
        recomputeBest()
    end
    local batch = S.refreshBatch
    while batch > 0 and S.refreshIndex <= #S.refreshList do
        enqueue(S.refreshList[S.refreshIndex], false)
        S.refreshIndex = S.refreshIndex + 1; batch = batch - 1
    end
    processQueue()

    -- Render all (Throttled to run every 3rd frame to prevent Net VM Starvation)
    S.renderFrameCount = (S.renderFrameCount or 0) + 1
    if S.renderFrameCount % 3 == 0 then
        -- Reset highlights pool
        for _, hl in ipairs(S.highlightPool) do
            hl.Enabled = false
            hl.Adornee = nil
        end
        S.highlightIndex = 0

        for _, meta in pairs(S.tracked) do
            pcall(renderStand, meta)
        end
    end
end

-- ==================== API ====================
local API = {}

function API:Init() end

function API:Start()
    if S.enabled then return end
    S.enabled = true
    S.queue = {}; S.queueSet = {}; S.forceSet = {}
    S.refreshList = {}; S.knownStands = {}
    S.queueHead = 1; S.queueTail = 0
    S.refreshIndex = 1; S.refreshAccumulator = 0
    S.bestStand = nil; S.bestIncome = -1

    -- Allocate Highlight pool (max 30 to bypass Roblox limits)
    S.highlightPool = {}
    local CoreGui = game:GetService("CoreGui")
    for i = 1, 30 do
        local hl = Instance.new("Highlight")
        hl.FillTransparency = 0.5
        hl.OutlineTransparency = 0
        hl.OutlineColor = Color3.new(1, 1, 1)
        hl.FillColor = S.highlightColor or COLORS.highlight
        hl.Enabled = false
        pcall(function() hl.Parent = CoreGui end)
        table.insert(S.highlightPool, hl)
    end

    local plots = getPlotsFolder()
    if plots then
        bindPlots(plots)
        S.connections.wa = Workspace.ChildAdded:Connect(function(c) if c.Name == "Plots" then bindPlots(c) end end)
        S.connections.wr = Workspace.ChildRemoved:Connect(function(c) if c == S.boundPlots then unbindPlots(c) end end)
    else
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst.Name == "AnimalPodiums" then bindPodiums(inst) end
        end
        S.connections.da = Workspace.DescendantAdded:Connect(function(inst)
            if inst.Name == "AnimalPodiums" then bindPodiums(inst) end
        end)
    end
    S.connections.hb = RunService.Heartbeat:Connect(heartbeat)
end

function API:Stop()
    if not S.enabled then return end
    S.enabled = false
    for _, conn in pairs(S.connections) do safeCall(function() conn:Disconnect() end) end
    S.connections = {}
    unbindPlots(S.boundPlots)
    for pod in pairs(S.podiumsConns) do unbindPodiums(pod) end
    for stand in pairs(S.knownStands) do untrackStand(stand) end
    for stand in pairs(S.tracked) do clearStand(stand) end

    -- Destroy highlight pool
    for _, hl in ipairs(S.highlightPool) do
        pcall(function() hl:Destroy() end)
    end
    S.highlightPool = {}
end

function API:SetName(v) S.nameEnabled = v end
function API:SetHighlight(v) 
    S.highlightEnabled = v 
    if not v and #S.highlightPool > 0 then
        for _, hl in ipairs(S.highlightPool) do
            hl.Enabled = false
            hl.Adornee = nil
        end
    end
end
function API:SetHighlightColor(v)
    if typeof(v) == "Color3" then S.highlightColor = v end
end
function API:SetTracers(v) S.tracersEnabled = v end
function API:SetMoney(v) S.moneyEnabled = v end
function API:SetMostExpensive(v) S.mostExpensiveOnly = v and true or false; recomputeBest() end

function API:GetBest()
    if not S.bestStand then recomputeBest() end
    local meta = S.tracked[S.bestStand]
    if not meta or not meta.info then return nil end
    local t = meta.info.root
    return t and t.Parent and t or nil
end

return API
