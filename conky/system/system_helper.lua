#!/usr/bin/env lua
-- system_helper.lua — Conky system panel (fans + services)

local HOME        = os.getenv("HOME")
local FANS_SCRIPT = HOME .. "/.config/conky/system/fans_fetch.sh"
local SVC_SCRIPT  = HOME .. "/.config/conky/system/svc_fetch.sh"
local FANS_CACHE  = "/tmp/conky_system/fans.json"
local SVC_CACHE   = "/tmp/conky_system/services.json"

local _fans = nil
local _svcs = nil

-- Edit these labels to match your physical fan connections
local FAN_LABELS = {
    fan1 = "Fan 1", fan2 = "Fan 2", fan3 = "Fan 3",
    fan4 = "Fan 4", fan5 = "Fan 5", fan6 = "Fan 6",
    pump = "Pump",
}

local function load_fans()
    local f = io.open(FANS_CACHE)
    if not f then return end
    local raw = f:read("*all"); f:close()
    if raw == "" then return end
    local ok, d = pcall(require("json").decode, raw)
    if ok and type(d) == "table" then _fans = d end
end

local function load_svcs()
    local f = io.open(SVC_CACHE)
    if not f then return end
    local raw = f:read("*all"); f:close()
    if raw == "" then return end
    local ok, d = pcall(require("json").decode, raw)
    if ok and type(d) == "table" then _svcs = d end
end

function conky_system_startup()
    load_fans()
    load_svcs()
end

function conky_system_main()
    if not conky_window then return end
    os.execute("bash " .. FANS_SCRIPT .. " &")
    os.execute("bash " .. SVC_SCRIPT  .. " &")
    load_fans()
    load_svcs()
end

local function section_header(title)
    return "${color0}${hr 2}\n${font7}${color0}-- " .. title .. " --${color}"
end

function conky_system_fans()
    local lines = {}
    lines[#lines+1] = section_header("Fans & Thermal")

    if not _fans then
        lines[#lines+1] = "  Connecting to CoolerControl..."
        return table.concat(lines, "\n")
    end

    if _fans.error then
        lines[#lines+1] = "  ${color2}CoolerControl error${color}"
        return table.concat(lines, "\n")
    end

    -- Temps: water loop + GPU junction
    local water = _fans.water_temp and string.format("%.1f", _fans.water_temp) or "--"
    local gpu   = _fans.gpu_temp   and string.format("%.0f", _fans.gpu_temp)   or "--"
    lines[#lines+1] = "  Water  " .. water .. "\xc2\xb0C${goto 195}GPU  " .. gpu .. "\xc2\xb0"
    lines[#lines+1] = ""

    -- Commander ST fans indexed by name
    local fans = {}
    for _, f in ipairs(_fans.commander_fans or {}) do
        fans[f.name] = f.rpm
    end

    -- Three rows, two columns: fan1-3 left, fan4-6 right
    local pairs_list = {{"fan1","fan4"}, {"fan2","fan5"}, {"fan3","fan6"}}
    for _, pair in ipairs(pairs_list) do
        local f1, f2 = pair[1], pair[2]
        lines[#lines+1] = "  " .. (FAN_LABELS[f1] or f1) .. "${goto 85}" .. tostring(fans[f1] or 0)
            .. "${goto 195}" .. (FAN_LABELS[f2] or f2) .. "${goto 280}" .. tostring(fans[f2] or 0)
    end

    -- Pump on its own line
    lines[#lines+1] = "  " .. (FAN_LABELS["pump"] or "Pump") .. "${goto 85}" .. tostring(fans["pump"] or 0)

    -- GPU fan
    local rpm  = _fans.gpu_fan_rpm  and tostring(math.floor((_fans.gpu_fan_rpm  or 0) + 0.5)) or "--"
    local duty = _fans.gpu_fan_duty and string.format("%.0f%%", _fans.gpu_fan_duty) or "--"
    lines[#lines+1] = "  GPU fan${goto 85}" .. rpm .. " rpm  " .. duty

    return table.concat(lines, "\n")
end

function conky_system_services()
    local lines = {}
    lines[#lines+1] = section_header("Services")

    if not _svcs then
        lines[#lines+1] = "  Checking services..."
        return table.concat(lines, "\n")
    end

    for _, svc in ipairs(_svcs) do
        local is_up = (svc.status == "up")
        local dot   = is_up and "${color1}\xe2\x97\x8f${color}" or "${color2}\xe2\x97\x8f${color}"
        local word
        if svc.kind == "nfs" then
            word = is_up and "Mounted" or "Unmounted"
        else
            word = is_up and "Online" or "Offline"
        end
        lines[#lines+1] = "  " .. svc.label .. "${goto 200}" .. dot .. "  " .. word
    end

    return table.concat(lines, "\n")
end
