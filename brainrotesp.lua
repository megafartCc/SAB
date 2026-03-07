-- ==================================================
-- Brainrot ESP Module for Steal A Brainrot
-- Tracks animal podiums on plots, shows income/gen
-- API: Init(), Start(), Stop(), SetMostExpensive(bool), GetBest()
-- ==================================================

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local LOCAL_PLAYER = Players.LocalPlayer

-- Safe requires
local sharedFolder = pcall(function() return ReplicatedStorage:WaitForChild("Shared", 5) end) and ReplicatedStorage:FindFirstChild("Shared")
local datasFolder = pcall(function() return ReplicatedStorage:WaitForChild("Datas", 5) end) and ReplicatedStorage:FindFirstChild("Datas")
local packagesFolder = pcall(function() return ReplicatedStorage:WaitForChild("Packages", 5) end) and ReplicatedStorage:FindFirstChild("Packages")

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

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)
    return ok and result or nil
end

local function formatNumber(value)
    value = tonumber(value) or 0
    if value >= 1e12 then return string.format("%.1fT", value / 1e12)
    elseif value >= 1e9 then return string.format("%.1fB", value / 1e9)
    elseif value >= 1e6 then return string.format("%.1fM", value / 1e6)
    elseif value >= 1e3 then return string.format("%.0fK", value / 1e3) end
    return tostring(math.floor(value))
end

local function sanitizeKey(value)
    if value == nil then return nil end
    if typeof(value) == "string" then
        local t = value:gsub("^%s+", ""):gsub("%s+$", "")
        return t ~= "" and t:lower() or nil
    elseif typeof(value) == "number" then return tostring(value):lower() end
    return nil
end

-- Build lookup
local animalsLookup = {}
for key, entry in pairs(AnimalsDataModule) do
    if typeof(key) == "string" then animalsLookup[key:lower()] = entry end
    if entry and entry.DisplayName then animalsLookup[entry.DisplayName:lower()] = entry end
end

local mutationMultipliers = {}
for name, data in pairs(MutationsDataModule) do
    mutationMultipliers[name] = 1 + (data.Modifier or 0)
end

-- State
local state = {
    enabled = false,
    mostExpensiveOnly = false,
    tracked = {},
    knownStands = {},
    standConns = {},
    connections = {},
    podiumsConns = {},
    baseConns = {},
    boundPlots = nil,
    queue = {},
    queueSet = {},
    forceSet = {},
    queueHead = 1,
    queueTail = 0,
    refreshList = {},
    refreshIndex = 1,
    refreshAccumulator = 0,
    refreshInterval = 3,
    refreshBatch = 6,
    standUpdateInterval = 2,
    queueBudget = 6,
    frameBudget = 0.003,
    bestDirty = false,
    lastBestRefresh = 0,
    accentColor = Color3.fromRGB(50, 130, 250),
    frameColor = Color3.fromRGB(16, 18, 24),
    textColor = Color3.fromRGB(230, 235, 240),
    baseChannelCache = {},
    bestMeta = nil,
    beam = nil,
    beamAttachment0 = nil,
}

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

local function destroyBeam()
    if state.beam then state.beam:Destroy(); state.beam = nil end
    if state.beamAttachment0 then state.beamAttachment0:Destroy(); state.beamAttachment0 = nil end
end

local function updatePlayerAttachment()
    local char = LOCAL_PLAYER and LOCAL_PLAYER.Character
    local hrp = char and char:FindFirstChild("HumanoidRootPart")
    if not hrp then
        if state.beamAttachment0 then state.beamAttachment0:Destroy(); state.beamAttachment0 = nil end
        return
    end
    if state.beamAttachment0 and state.beamAttachment0.Parent == hrp then return end
    if state.beamAttachment0 then state.beamAttachment0:Destroy(); state.beamAttachment0 = nil end
    local att = Instance.new("Attachment")
    att.Name = "BrainrotESPPivot"
    att.Parent = hrp
    state.beamAttachment0 = att
    if state.beam then state.beam.Attachment0 = att end
end

if LOCAL_PLAYER then
    LOCAL_PLAYER.CharacterAdded:Connect(function() task.wait(0.25); updatePlayerAttachment() end)
    LOCAL_PLAYER.CharacterRemoving:Connect(function() updatePlayerAttachment() end)
end

local function ensureBeam()
    if state.beam then return end
    state.beam = Instance.new("Beam")
    state.beam.Name = "BrainrotESPLaser"
    state.beam.Width0 = 0.1; state.beam.Width1 = 0.1
    state.beam.LightEmission = 0.4
    state.beam.Color = ColorSequence.new(state.accentColor)
    state.beam.Transparency = NumberSequence.new(0.1)
    state.beam.FaceCamera = true; state.beam.Enabled = false
    state.beam.Parent = Workspace
    updatePlayerAttachment()
end

local function computeBestMeta()
    local best, bestIncome = nil, -math.huge
    for _, meta in pairs(state.tracked) do
        local inc = meta.income or 0
        if inc > bestIncome then bestIncome = inc; best = meta end
    end
    state.bestMeta = best
    return best
end

local function setBeamTarget(meta)
    if not state.mostExpensiveOnly or not state.enabled then
        if state.beam then state.beam.Enabled = false end
        return
    end
    ensureBeam(); updatePlayerAttachment()
    if state.beam and state.beamAttachment0 and meta and meta.targetAttachment then
        state.beam.Attachment0 = state.beamAttachment0
        state.beam.Attachment1 = meta.targetAttachment
        state.beam.Enabled = true
    elseif state.beam then state.beam.Enabled = false end
end

local function setVisualVisibility(meta, visible)
    if meta.highlight then meta.highlight.Enabled = visible end
    if meta.billboard then meta.billboard.Enabled = visible end
end

local function refreshMostExpensiveVisibility()
    local best = computeBestMeta()
    if not state.mostExpensiveOnly then
        for _, meta in pairs(state.tracked) do setVisualVisibility(meta, state.enabled) end
        setBeamTarget(nil); return
    end
    for _, meta in pairs(state.tracked) do
        setVisualVisibility(meta, best and meta == best and state.enabled)
    end
    setBeamTarget(best)
end

-- Trait/mutation helpers
local function normalizeTraits(traits)
    if typeof(traits) == "table" then
        if traits[1] then return traits end
        local list = {}
        for _, v in pairs(traits) do table.insert(list, v) end
        return list
    end
    if typeof(traits) == "string" and traits ~= "" then
        local parsed = safeCall(function() return HttpService:JSONDecode(traits) end)
        if typeof(parsed) == "table" then return normalizeTraits(parsed) end
        return { traits }
    end
    return nil
end

local function readMutation(container)
    if not container then return nil end
    local val = container:GetAttribute("Mutation") or container:GetAttribute("Mut")
    if val ~= nil then return val end
    local child = container:FindFirstChild("Mutation") or container:FindFirstChild("Mut")
    return child and child.Value or nil
end

local function readTraits(container)
    if not container then return nil end
    local traits = normalizeTraits(container:GetAttribute("Traits"))
    if traits then return traits end
    local collected = {}
    for i = 1, 4 do
        local key = "Trait" .. i
        local val = container:GetAttribute(key)
        if val then table.insert(collected, val) else
            local child = container:FindFirstChild(key)
            if child and child.Value then table.insert(collected, child.Value) end
        end
    end
    return #collected > 0 and collected or nil
end

local function getMutationAndTraitsFromModel(model)
    if not model then return nil, nil end
    local mutation = readMutation(model)
    local traits = readTraits(model)
    if not mutation then
        local folder = model:FindFirstChild("MutationFolder") or model:FindFirstChild("Mutations")
        if folder then
            for _, child in ipairs(folder:GetChildren()) do
                if child:IsA("StringValue") and child.Value ~= "" then mutation = child.Value; break end
            end
        end
    end
    if not traits then
        local tFolder = model:FindFirstChild("Traits") or model:FindFirstChild("TraitsFolder")
        if tFolder then
            local list = {}
            for _, child in ipairs(tFolder:GetChildren()) do
                if child:IsA("StringValue") and child.Value ~= "" then table.insert(list, child.Value) end
            end
            if #list > 0 then traits = list end
        end
    end
    return mutation, normalizeTraits(traits)
end

local function calculateMultiplier(mutation, traits)
    local mults, count = {}, 0
    if mutation and mutationMultipliers[mutation] then
        table.insert(mults, mutationMultipliers[mutation]); count = count + 1
    else table.insert(mults, 1); count = count + 1 end
    if typeof(traits) == "table" then
        for _, trait in ipairs(traits) do
            local info = TraitsDataModule[trait]
            if info then table.insert(mults, 1 + (info.MultiplierModifier or 0)); count = count + 1 end
        end
    end
    if count == 0 then return 1 end
    local sum = 0
    for _, m in ipairs(mults) do sum = sum + m end
    local total = sum - (count - 1)
    return total < 1 and 1 or total
end

local function safePlayerMultiplier(owner)
    if not AnimalsSharedModule then return 1 end
    local okGame, gameShared = pcall(function() return require(sharedFolder:WaitForChild("Game")) end)
    if not okGame or not gameShared or type(gameShared.GetPlayerCashMultiplayer) ~= "function" then return 1 end
    local ok, mult = pcall(gameShared.GetPlayerCashMultiplayer, gameShared, owner)
    return ok and tonumber(mult) or 1
end

local function getAttrNumber(container, keys)
    for _, key in ipairs(keys) do
        local val = container:GetAttribute(key)
        if val then local n = tonumber(val); if n then return n end end
        local child = container:FindFirstChild(key)
        if child and child.Value then local n = tonumber(child.Value); if n then return n end end
    end
    return nil
end

local function computeGeneration(index, mutation, traits, owner)
    local entry = index and animalsLookup[sanitizeKey(index) or ""]
    if not entry then return 0 end
    local baseGen = entry.Generation or ((entry.Price or 0) * (GameDataModule.Game and GameDataModule.Game.AnimalGanerationModifier or 0))
    local mult = calculateMultiplier(mutation, traits)
    local sleepy = false
    if typeof(traits) == "table" then
        for _, t in ipairs(traits) do if t == "Sleepy" then sleepy = true; break end end
    end
    local gen = baseGen * mult
    if sleepy then gen = gen * 0.5 end
    if owner then gen = gen * safePlayerMultiplier(owner) end
    return math.max(0, math.floor(gen + 0.5))
end

local function computeIncome(index, mutation, traits, owner, stand, model, entry)
    entry = entry or (index and animalsLookup[sanitizeKey(index) or ""])
    if owner and typeof(owner) == "table" and owner.UserId then
        owner = Players:GetPlayerByUserId(owner.UserId) or owner
    end
    local modelMut, modelTraits = getMutationAndTraitsFromModel(model)
    mutation = mutation or modelMut
    traits = traits or modelTraits or readTraits(stand)
    local income = (model and getAttrNumber(model, {"IncomePerSecond","Income","Generation","Gen"}))
        or (stand and getAttrNumber(stand, {"IncomePerSecond","Income","Generation","Gen"}))
    if (not income or income == 0) and AnimalsSharedModule and AnimalsSharedModule.GetGeneration and index then
        income = safeCall(AnimalsSharedModule.GetGeneration, AnimalsSharedModule, index, mutation, traits, owner)
    end
    if (not income or income == 0) and index then income = computeGeneration(index, mutation, traits, owner) end
    if (not income or income == 0) and entry and entry.Generation then income = entry.Generation end
    return income or 0
end

-- Stand/podium discovery
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
    if base:FindFirstChild("AnimalPodiums") then return base end
    return nil
end

local function findBrainrotModelOnStand(stand)
    if not stand or not stand.Parent then return nil end
    for _, desc in ipairs(stand:GetDescendants()) do
        if desc:IsA("Model") then
            local root = desc:FindFirstChild("RootPart") or desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart
            if root then
                local lookup = sanitizeKey(desc.Name)
                local idxAttr = sanitizeKey(desc:GetAttribute("Index") or desc:GetAttribute("Animal") or desc:GetAttribute("Brainrot"))
                local hasIncome = desc:FindFirstChild("Income") or desc:FindFirstChild("Generation") or desc:GetAttribute("IncomePerSecond")
                if (lookup and animalsLookup[lookup]) or (idxAttr and animalsLookup[idxAttr]) or hasIncome
                    or desc:GetAttribute("Mutation") or desc:GetAttribute("Traits") then
                    return desc, root
                end
            end
        end
    end
    return nil
end

local function getStandRootPart(stand)
    local model, root = findBrainrotModelOnStand(stand)
    if model then
        root = root or model.PrimaryPart or model:FindFirstChildWhichIsA("BasePart", true)
        if root then return model, root end
    end
    local base = stand:FindFirstChild("Base")
    if base then
        local spawn = base:FindFirstChild("Spawn")
        if spawn and spawn:IsA("BasePart") then return nil, spawn end
    end
    return nil, stand.PrimaryPart or stand:FindFirstChildWhichIsA("BasePart", true)
end

local function getStandSlot(stand)
    if not stand then return nil end
    local n = tonumber(stand.Name)
    if n then return n end
    return tonumber(stand:GetAttribute("Slot") or stand:GetAttribute("Index"))
end

local function getBaseChannel(base)
    if not base then return nil end
    if state.baseChannelCache[base] then return state.baseChannelCache[base] end
    local channel = nil
    if Synchronizer then
        channel = safeCall(function() return Synchronizer:Get(base.Name) end)
            or safeCall(function() return Synchronizer:Wait(base.Name) end)
    end
    state.baseChannelCache[base] = channel
    return channel
end

local function resolveBrainrotName(stand, model, index)
    if index then
        local key = sanitizeKey(index)
        local entry = key and animalsLookup[key]
        if entry then return entry.DisplayName or index end
        return typeof(index) == "string" and index or tostring(index)
    end
    if stand then
        local attr = stand:GetAttribute("Animal") or stand:GetAttribute("Brainrot") or stand:GetAttribute("Pet")
        if attr and attr ~= "" then return attr end
    end
    if model then return model.Name end
    return "Brainrot"
end

local function buildStandBrainrotInfo(stand)
    if not stand or not stand.Parent then return nil end
    local base = getValidStandBase(stand)
    if not base then return nil end
    local channel = getBaseChannel(base)
    local slot = getStandSlot(stand)
    local animalData
    if channel and type(channel.Get) == "function" then
        local animals = channel:Get("AnimalList") or channel:Get("AnimalPodiums")
        animalData = animals and animals[slot]
    end
    local model, root = getStandRootPart(stand)
    if not root then return nil end
    local owner = channel and channel:Get("Owner")
    if isLocalOwner(owner) or isLocalOwner(base:GetAttribute("Owner"))
        or isLocalOwner(base:GetAttribute("OwnerName")) or isLocalOwner(base:GetAttribute("PlacedBy")) then
        return nil
    end
    local mutation = (animalData and (animalData.Mutation or animalData.Mut)) or readMutation(model) or readMutation(stand)
    local traits = normalizeTraits(animalData and animalData.Traits) or readTraits(model) or readTraits(stand)
    local index = animalData and (animalData.Index or animalData.Animal or animalData.Name)
        or (stand:GetAttribute("Animal") or stand:GetAttribute("Brainrot"))
        or (model and model:GetAttribute("Animal")) or (model and model.Name) or stand.Name
    local resolvedName = resolveBrainrotName(stand, model, index)
    local key = sanitizeKey(index) or sanitizeKey(resolvedName)
    local entry = key and animalsLookup[key]
    local moneyValue = computeIncome(index, mutation, traits, owner, stand, model, entry)
    if not model and moneyValue <= 0 then return nil end
    return { stand = stand, base = base, model = model, root = root, name = resolvedName, moneyValue = moneyValue }
end

-- Visual creation
local function createStandVisual(info)
    local adornee = info.root
    local highlight = Instance.new("Highlight")
    highlight.Name = "BrainrotESPHL"
    highlight.FillColor = state.accentColor
    highlight.FillTransparency = 0.12
    highlight.OutlineColor = Color3.new(state.accentColor.R*0.45, state.accentColor.G*0.45, state.accentColor.B*0.45)
    highlight.OutlineTransparency = 0.25
    highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    highlight.Enabled = true
    highlight.Adornee = info.model or adornee
    highlight.Parent = info.model or adornee or info.stand

    local bb = Instance.new("BillboardGui")
    bb.Name = "BrainrotESPBB"
    bb.AlwaysOnTop = true
    bb.Size = UDim2.new(0, 170, 0, 34)
    bb.StudsOffsetWorldSpace = Vector3.new(0, 5.5, 0)
    bb.MaxDistance = 1200; bb.LightInfluence = 0; bb.Enabled = true
    bb.Adornee = adornee; bb.Parent = adornee

    local frame = Instance.new("Frame")
    frame.BackgroundColor3 = state.frameColor; frame.BackgroundTransparency = 0.45
    frame.BorderSizePixel = 0; frame.Size = UDim2.new(1,0,1,0); frame.Parent = bb

    local corner = Instance.new("UICorner"); corner.CornerRadius = UDim.new(0,6); corner.Parent = frame
    local stroke = Instance.new("UIStroke")
    stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
    stroke.Thickness = 1; stroke.Color = state.accentColor; stroke.Transparency = 0.15; stroke.Parent = frame

    local nameLabel = Instance.new("TextLabel")
    nameLabel.BackgroundTransparency = 1; nameLabel.Size = UDim2.new(1,-8,0,18)
    nameLabel.Position = UDim2.new(0,4,0,3); nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextColor3 = state.textColor; nameLabel.TextStrokeTransparency = 0.4
    nameLabel.TextSize = 15; nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.TextWrapped = true; nameLabel.Parent = frame

    local rateLabel = Instance.new("TextLabel")
    rateLabel.BackgroundTransparency = 1; rateLabel.Size = UDim2.new(1,-8,0,14)
    rateLabel.Position = UDim2.new(0,4,0,20); rateLabel.Font = Enum.Font.GothamBold
    rateLabel.TextColor3 = Color3.fromRGB(255,255,255); rateLabel.TextStrokeTransparency = 0.3
    rateLabel.TextSize = 13; rateLabel.TextXAlignment = Enum.TextXAlignment.Center
    rateLabel.TextWrapped = true; rateLabel.Parent = frame

    local att = Instance.new("Attachment"); att.Name = "BrainrotESPTarget"; att.Parent = adornee

    return {
        highlight = highlight, billboard = bb, frame = frame,
        nameLabel = nameLabel, rateLabel = rateLabel,
        targetAttachment = att, currentAdornee = adornee, stand = info.stand,
    }
end

local function clearStandVisual(stand)
    local meta = state.tracked[stand]
    if not meta then return end
    if meta.highlight then meta.highlight:Destroy() end
    if meta.billboard then meta.billboard:Destroy() end
    if meta.targetAttachment then meta.targetAttachment:Destroy() end
    state.tracked[stand] = nil
    if state.bestMeta == meta then computeBestMeta() end
    state.bestDirty = true
end

local function untrackStand(stand)
    clearStandVisual(stand)
    state.knownStands[stand] = nil; state.queueSet[stand] = nil; state.forceSet[stand] = nil
    local conn = state.standConns[stand]
    if conn then safeCall(function() conn:Disconnect() end) end
    state.standConns[stand] = nil
end

local function applyStandInfo(meta, info)
    meta.income = info.moneyValue or 0; meta.root = info.root
    meta.model = info.model; meta.base = info.base
    meta.nameLabel.Text = info.name or "Brainrot"
    meta.rateLabel.Text = string.format("$%s/sec", formatNumber(meta.income))
    local adornee = info.root
    if adornee and adornee ~= meta.currentAdornee then
        meta.currentAdornee = adornee; meta.billboard.Adornee = adornee
        meta.billboard.Parent = adornee; meta.targetAttachment.Parent = adornee
    end
    local ht = info.model or adornee
    if ht then meta.highlight.Adornee = ht; meta.highlight.Parent = ht end
end

local function updateStandEsp(stand)
    if not state.enabled then return end
    local meta = state.tracked[stand]
    local now = os.clock()
    if meta and meta.nextUpdateAt and now < meta.nextUpdateAt then return end
    local info = safeCall(buildStandBrainrotInfo, stand)
    if not info then clearStandVisual(stand); return end
    if not meta then meta = createStandVisual(info); state.tracked[stand] = meta end
    applyStandInfo(meta, info)
    meta.nextUpdateAt = now + state.standUpdateInterval
    state.bestDirty = true
end

local function enqueueStand(stand, force)
    if not (stand and stand.Parent) then return end
    if state.queueSet[stand] then if force then state.forceSet[stand] = true end; return end
    state.queueSet[stand] = true
    if force then state.forceSet[stand] = true end
    state.queueTail = state.queueTail + 1; state.queue[state.queueTail] = stand
end

local function dequeueStand()
    if state.queueHead > state.queueTail then return nil end
    local stand = state.queue[state.queueHead]; state.queue[state.queueHead] = nil
    state.queueHead = state.queueHead + 1
    if state.queueHead > state.queueTail then state.queueHead = 1; state.queueTail = 0 end
    return stand
end

local function trackStand(stand)
    if not (stand and stand:IsA("Model") and stand.Parent) then return end
    if state.knownStands[stand] then return end
    state.knownStands[stand] = true
    state.standConns[stand] = stand.AncestryChanged:Connect(function(_, parent)
        if not parent then untrackStand(stand) end
    end)
    enqueueStand(stand, true)
end

-- Podium/plot binding
local function unbindPodiums(podiums)
    local conns = state.podiumsConns[podiums]
    if conns then for _, c in pairs(conns) do safeCall(function() c:Disconnect() end) end end
    state.podiumsConns[podiums] = nil
    if podiums then for _, s in ipairs(podiums:GetChildren()) do if s:IsA("Model") then untrackStand(s) end end end
end

local function bindPodiums(podiums)
    if not (podiums and podiums.Parent) or state.podiumsConns[podiums] then return end
    for _, s in ipairs(podiums:GetChildren()) do if s:IsA("Model") then trackStand(s) end end
    state.podiumsConns[podiums] = {
        added = podiums.ChildAdded:Connect(function(c) if c:IsA("Model") then trackStand(c) end end),
        removed = podiums.ChildRemoved:Connect(function(c) if c:IsA("Model") then untrackStand(c) end end),
        ancestry = podiums.AncestryChanged:Connect(function(_, p) if not p then unbindPodiums(podiums) end end),
    }
end

local function unbindBase(base)
    local conns = state.baseConns[base]
    if conns then for _, c in pairs(conns) do safeCall(function() c:Disconnect() end) end end
    state.baseConns[base] = nil
    local pod = base and base:FindFirstChild("AnimalPodiums")
    if pod then unbindPodiums(pod) end
end

local function bindBase(base)
    if not (base and base.Parent) or state.baseConns[base] then return end
    state.baseConns[base] = {
        added = base.ChildAdded:Connect(function(c) if c.Name == "AnimalPodiums" then bindPodiums(c) end end),
        ancestry = base.AncestryChanged:Connect(function(_, p) if not p then unbindBase(base) end end),
    }
    local pod = base:FindFirstChild("AnimalPodiums")
    if pod then bindPodiums(pod) end
end

local function unbindPlots(plots)
    if state.connections.plotsAdd then safeCall(function() state.connections.plotsAdd:Disconnect() end); state.connections.plotsAdd = nil end
    if state.connections.plotsRem then safeCall(function() state.connections.plotsRem:Disconnect() end); state.connections.plotsRem = nil end
    for base in pairs(state.baseConns) do unbindBase(base) end
    state.boundPlots = nil
end

local function bindPlots(plots)
    if not plots or state.boundPlots == plots then return end
    if state.boundPlots then unbindPlots(state.boundPlots) end
    state.boundPlots = plots
    for _, base in ipairs(plots:GetChildren()) do bindBase(base) end
    state.connections.plotsAdd = plots.ChildAdded:Connect(function(c) bindBase(c) end)
    state.connections.plotsRem = plots.ChildRemoved:Connect(function(c) unbindBase(c) end)
end

-- Main loop
local function processQueue()
    local now, start = os.clock(), os.clock()
    local budget = state.queueBudget
    while budget > 0 do
        local stand = dequeueStand()
        if not stand then break end
        state.queueSet[stand] = nil
        if state.forceSet[stand] then
            state.forceSet[stand] = nil
            local meta = state.tracked[stand]
            if meta then meta.nextUpdateAt = 0 end
        end
        if stand.Parent then updateStandEsp(stand) else untrackStand(stand) end
        budget = budget - 1
        if (os.clock() - start) > state.frameBudget then break end
    end
    if state.bestDirty and (now - (state.lastBestRefresh or 0)) >= 0.5 then
        refreshMostExpensiveVisibility()
        state.bestDirty = false; state.lastBestRefresh = now
    end
end

local function heartbeatStep(dt)
    if not state.enabled then return end
    state.refreshAccumulator = (state.refreshAccumulator or 0) + dt
    if state.refreshAccumulator >= state.refreshInterval then
        state.refreshAccumulator = 0; state.refreshList = {}
        for stand in pairs(state.knownStands) do state.refreshList[#state.refreshList+1] = stand end
        state.refreshIndex = 1
    end
    local batch = state.refreshBatch
    while batch > 0 and state.refreshIndex <= #state.refreshList do
        enqueueStand(state.refreshList[state.refreshIndex], false)
        state.refreshIndex = state.refreshIndex + 1; batch = batch - 1
    end
    processQueue()
end

-- Public API
local API = {}

function API:Init() end

function API:Start()
    if state.enabled then return end
    state.enabled = true
    state.queue = {}; state.queueSet = {}; state.forceSet = {}
    state.refreshList = {}; state.knownStands = {}
    state.queueHead = 1; state.queueTail = 0
    state.refreshIndex = 1; state.refreshAccumulator = 0
    state.bestDirty = true; state.lastBestRefresh = 0

    local plots = getPlotsFolder()
    if plots then
        bindPlots(plots)
        state.connections.wsAdd = Workspace.ChildAdded:Connect(function(c) if c.Name == "Plots" then bindPlots(c) end end)
        state.connections.wsRem = Workspace.ChildRemoved:Connect(function(c) if c == state.boundPlots then unbindPlots(c) end end)
    else
        for _, inst in ipairs(Workspace:GetDescendants()) do
            if inst.Name == "AnimalPodiums" then bindPodiums(inst) end
        end
        state.connections.descAdd = Workspace.DescendantAdded:Connect(function(inst)
            if inst.Name == "AnimalPodiums" then bindPodiums(inst) end
        end)
    end
    state.connections.heartbeat = RunService.Heartbeat:Connect(heartbeatStep)
end

function API:Stop()
    if not state.enabled then return end
    state.enabled = false
    for _, conn in pairs(state.connections) do safeCall(function() conn:Disconnect() end) end
    state.connections = {}
    unbindPlots(state.boundPlots)
    for pod in pairs(state.podiumsConns) do unbindPodiums(pod) end
    for stand in pairs(state.knownStands) do untrackStand(stand) end
    for stand in pairs(state.tracked) do clearStandVisual(stand) end
    destroyBeam(); state.bestMeta = nil
end

function API:SetMostExpensive(val)
    state.mostExpensiveOnly = val and true or false
    state.bestDirty = true
    refreshMostExpensiveVisibility()
end

function API:GetBest()
    local meta = computeBestMeta()
    if not meta then return nil end
    local target = meta.currentAdornee or meta.root
    return target and target.Parent and target or nil
end

return API
