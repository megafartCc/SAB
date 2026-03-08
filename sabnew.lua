-- ==================================================
-- SAB New — Steal A Brainrot Exploit
-- ==================================================
local lp = game:GetService("Players").LocalPlayer

-- ==================================================
-- UI LIBRARY (Fatality)
-- ==================================================
local function loadRemoteUiLib()
    local baseUrl = "https://raw.githubusercontent.com/megafartCc/UiLib/main/UILibModules"
    local moduleCache = {}

    local function normalizePath(path)
        local parts = {}
        for part in string.gmatch(string.gsub(path, "\\", "/"), "[^/]+") do
            if part == ".." then
                if #parts > 0 then
                    table.remove(parts)
                end
            elseif part ~= "." and part ~= "" then
                table.insert(parts, part)
            end
        end
        return table.concat(parts, "/")
    end

    local function loadRemoteModule(path)
        local normalized = normalizePath(path)
        local cached = moduleCache[normalized]
        if cached ~= nil then
            return cached
        end

        local source = game:HttpGet(baseUrl .. "/" .. normalized)
        local chunk, err = loadstring(source)
        if not chunk then
            error(string.format("UiLib load failed for %s: %s", normalized, tostring(err)))
        end

        local exported = chunk()
        moduleCache[normalized] = exported
        return exported
    end

    local entryModule = loadRemoteModule("init.lua")

    local function moduleRequire(relativePath)
        return loadRemoteModule(relativePath)
    end

    return entryModule(moduleRequire)
end

local Library = loadRemoteUiLib()
local Window = Library:CreateWindow({
    Name = "Eps1llon",
    Expire = "never",
    ConfigName = "sab_v1",
})

-- ==================================================
-- PAGE 1: VISUALS
-- ==================================================
local VisualsMenu = Window:AddMenu({ Name = "VISUALS", Columns = 2 })

local PlayerEspSection = VisualsMenu:AddSection({ Name = "PLAYER ESP", Column = 1 })
local BrainrotEspSection = VisualsMenu:AddSection({ Name = "BRAINROT ESP", Column = 2 })

-- ==================================================
-- PLAYER ESP MODULE (from GitHub)
-- ==================================================
local ESP
pcall(function()
    ESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/megafartCc/SAB/main/espmodule.lua"))()
    pcall(ESP.Init, ESP)
end)

local function safeESP(fn, s)
    if ESP then pcall(fn, ESP, s) end
end


-- ==================================================
-- BRAINROT ESP MODULE (from GitHub)
-- ==================================================
local BrainrotESP
pcall(function()
    BrainrotESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/megafartCc/SAB/main/brainrotesp.lua"))()
    pcall(BrainrotESP.Init, BrainrotESP)
end)

-- ==================================================
-- PLAYER ESP TOGGLES
-- ==================================================
PlayerEspSection:AddToggle({ Name = "Box ESP", SaveKey = "sab_box_esp", Default = false,
    Callback = function(s) safeESP(ESP.SetBoxEsp, s) end
})
PlayerEspSection:AddToggle({ Name = "Name ESP", SaveKey = "sab_name_esp", Default = false,
    Callback = function(s) safeESP(ESP.SetNameEsp, s) end
})
PlayerEspSection:AddToggle({ Name = "Health ESP", SaveKey = "sab_health_esp", Default = false,
    Callback = function(s) safeESP(ESP.SetHealthEsp, s) end
})
PlayerEspSection:AddToggle({ Name = "Team ESP", SaveKey = "sab_team_esp", Default = false,
    Callback = function(s) safeESP(ESP.SetTeamEsp, s) end
})
PlayerEspSection:AddToggle({ Name = "Tracers", SaveKey = "sab_tracers", Default = false,
    Callback = function(s) safeESP(ESP.SetTracers, s) end
})
PlayerEspSection:AddToggle({ Name = "Skeleton ESP", SaveKey = "sab_skeleton_esp", Default = true,
    Callback = function(s) safeESP(ESP.SetSkeletonEsp, s) end
})
PlayerEspSection:AddToggle({ Name = "Held Item ESP", SaveKey = "sab_held_item_esp", Default = false,
    Callback = function(s) safeESP(ESP.SetHeldItemEsp, s) end
})

-- ==================================================
-- BRAINROT ESP TOGGLES
-- ==================================================
local function safeBR(fn, v)
    if BrainrotESP then pcall(fn, BrainrotESP, v) end
end

BrainrotEspSection:AddToggle({ Name = "Brainrot ESP", SaveKey = "sab_brainrot_esp", Default = false,
    Callback = function(s)
        if BrainrotESP then
            pcall(function()
                if s then BrainrotESP:Start() else BrainrotESP:Stop() end
            end)
        end
    end
})
BrainrotEspSection:AddToggle({ Name = "Skeleton", SaveKey = "sab_br_skel", Default = true,
    Callback = function(s) safeBR(BrainrotESP.SetSkeleton, s) end
})
BrainrotEspSection:AddToggle({ Name = "Name ESP", SaveKey = "sab_br_name", Default = false,
    Callback = function(s) safeBR(BrainrotESP.SetName, s) end
})
BrainrotEspSection:AddToggle({ Name = "Money Per/s", SaveKey = "sab_br_money", Default = false,
    Callback = function(s) safeBR(BrainrotESP.SetMoney, s) end
})
BrainrotEspSection:AddToggle({ Name = "Tracers", SaveKey = "sab_br_tracers", Default = false,
    Callback = function(s) safeBR(BrainrotESP.SetTracers, s) end
})
BrainrotEspSection:AddToggle({ Name = "Most Expensive Only", SaveKey = "sab_most_expensive", Default = false,
    Callback = function(s) safeBR(BrainrotESP.SetMostExpensive, s) end
})

-- ==================================================
-- WORLD VISUALS
-- ==================================================
local Lighting = game:GetService("Lighting")
local WorldSection = VisualsMenu:AddSection({ Name = "WORLD VISUALS", Column = 2 })

local originalLighting = {
    Ambient = Lighting.Ambient,
    OutdoorAmbient = Lighting.OutdoorAmbient,
    Brightness = Lighting.Brightness,
    FogEnd = Lighting.FogEnd,
    FogStart = Lighting.FogStart,
    ClockTime = Lighting.ClockTime,
}

WorldSection:AddToggle({ Name = "Fullbright", SaveKey = "sab_fullbright", Default = false,
    Callback = function(s)
        if s then
            Lighting.Ambient = Color3.fromRGB(255, 255, 255)
            Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
            Lighting.Brightness = 2
            Lighting.FogEnd = 1e9
            Lighting.FogStart = 1e9
            for _, v in ipairs(Lighting:GetChildren()) do
                if v:IsA("Atmosphere") or v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect") then
                    v.Enabled = false
                end
            end
        else
            Lighting.Ambient = originalLighting.Ambient
            Lighting.OutdoorAmbient = originalLighting.OutdoorAmbient
            Lighting.Brightness = originalLighting.Brightness
            Lighting.FogEnd = originalLighting.FogEnd
            Lighting.FogStart = originalLighting.FogStart
            for _, v in ipairs(Lighting:GetChildren()) do
                if v:IsA("Atmosphere") or v:IsA("BloomEffect") or v:IsA("ColorCorrectionEffect") then
                    v.Enabled = true
                end
            end
        end
    end
})

WorldSection:AddSlider({ Name = "Time of Day", SaveKey = "sab_time",
    Min = 0, Max = 24, Default = 14, Precision = 1,
    Callback = function(v)
        Lighting.ClockTime = v
    end
})

-- Deferred auto-load
task.defer(function()
    pcall(function()
        Library:LoadConfig()
    end)
end)
