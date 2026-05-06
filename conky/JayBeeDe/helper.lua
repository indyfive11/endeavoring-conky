#!/usr/bin/env lua

-- config management functions
local config
local cache = {
    query = {}
}
local run = {
    ttl = {}
}


function _load_config(path)
    local _env = {}
    setmetatable(_env, {
        __index = _G
    })
    local f = loadfile(path, "t", _env)
    if not f then
        return {}
    end
    assert(pcall(f))
    setmetatable(_env, nil)
    return _env
end

function conky_startup()
    local config_path = os.getenv("PWD") .. "/" .. conky_config
    print("conky: Loading config from " .. config_path .. "...")
    _load_config(config_path)
    print("conky: Script has started and is now running!")
    -- pre-generate gauge images with zeros so ${image} has files on first render
    os.execute(string.format(
        "python3 %s/.config/conky/JayBeeDe/gauge_gen.py 0 0 0 0 0 0 0 0 0 &",
        os.getenv("HOME")))
end

local function fmt_speed(kibps)
    kibps = tonumber(kibps) or 0
    if kibps >= 1048576 then
        return string.format("%.1fG", kibps / 1048576)
    elseif kibps >= 1024 then
        return string.format("%.1fM", kibps / 1024)
    else
        return string.format("%dK", math.floor(kibps))
    end
end

function conky_main()
    if not conky_window then return end
    local cpu  = conky_parse("${cpu}") or "0"
    local ram  = conky_parse("${memperc}") or "0"
    local gpu  = string.gsub(_file_read("/sys/class/drm/card1/device/gpu_busy_percent", 0) or "0", "%s+", "")
    local cputemp_raw = conky_parse("${hwmon " .. helper.config.temperature.sensor_device
                        .. " temp " .. helper.config.temperature.sensor_type .. "}") or "0"
    local cputemp_c   = tostring(math.floor(tonumber(cputemp_raw) or 0))
    local cputemp_pct = tostring(math.floor(math.min(100, (tonumber(cputemp_raw) or 0) / 90 * 100)))
    local gh = io.popen("sensors 2>/dev/null | grep -A4 'amdgpu-pci-0300' | grep 'edge'")
    local gline = gh:read("*l"); gh:close()
    local gtemp_c = gline and (string.match(gline, "%+(%d+)") or "0") or "0"
    local gtemp_pct   = tostring(math.floor(math.min(100, (tonumber(gtemp_c) or 0) / 90 * 100)))
    local pwm_raw     = _file_read("/sys/class/drm/card1/device/hwmon/hwmon5/pwm1", 0)
    local pwm_max_raw = _file_read("/sys/class/drm/card1/device/hwmon/hwmon5/pwm1_max", 0)
    local pwm         = tonumber((string.gsub(pwm_raw     or "0",   "%s+", ""))) or 0
    local pwm_max     = tonumber((string.gsub(pwm_max_raw or "255", "%s+", ""))) or 255
    local gpufan_pct  = tostring(math.floor(math.min(100, pwm / math.max(1, pwm_max) * 100)))
    local disk = conky_parse("${fs_used_perc /}") or "0"

    local cfg_net   = helper.config.network_speed or {}
    local net_iface = cfg_net.interface or "enp8s0"
    local max_kibps = (tonumber(cfg_net.max_mbps) or 1000) * 125
    local down_kib  = tonumber(conky_parse("${downspeedf " .. net_iface .. "}")) or 0
    local up_kib    = tonumber(conky_parse("${upspeedf "   .. net_iface .. "}")) or 0
    local function _net_pct(kib)
        if kib <= 0 then return "0" end
        return tostring(math.floor(math.min(100,
            math.log(kib + 1) / math.log(max_kibps + 1) * 100)))
    end
    local down_pct = _net_pct(down_kib)
    local up_pct   = _net_pct(up_kib)

    os.execute(string.format(
        "python3 %s/.config/conky/JayBeeDe/gauge_gen.py %s %s %s %s %s %s %s %s %s &",
        os.getenv("HOME"), cpu, ram, gpu,
        cputemp_pct .. ":" .. cputemp_c .. "°",
        gtemp_pct   .. ":" .. gtemp_c   .. "°",
        disk,
        down_pct .. ":" .. fmt_speed(down_kib),
        up_pct   .. ":" .. fmt_speed(up_kib),
        gpufan_pct))
end

function _sec_to_human(time)
    local days = math.floor(time / 86400)
    local hours = math.floor(math.fmod(time, 86400) / 3600)
    local minutes = math.floor(math.fmod(time, 3600) / 60)
    local seconds = math.floor(math.fmod(time, 60))
    local str = ""
    if days > 0 then
        str = str .. days .. "d "
    end
    if hours > 0 then
        str = str .. hours .. "h "
    end
    if minutes > 0 and days == 0 then
        str = str .. minutes .. "m "
    end
    if seconds > 0 and hours == 0 and days == 0 then
        str = str .. seconds .. "s "
    end
    return string.gsub(str, " $", "")
end

-- utils functions

function _file(path, mode, lines)
    mode = (mode and mode or "r")
    if mode ~= "r" and mode ~= "a" and mode ~= "w" then
        return nil
    end
    local file = io.open(path, mode)
    if not file then
        return nil
    end
    if mode == "r" then
        if lines then
            return nil
        end
        lines = {}
        for line in file:lines() do
            lines[#lines + 1] = line
        end
    else
        if not lines then
            return nil
        end
        for _, line in ipairs(lines) do
            file:write(line, "\n")
        end
    end
    file:close()
    return lines
end

function _file_read(path, idx)
    local fnret = _file(path, "r")
    if idx and fnret then
        return fnret[idx + 1]
    end
    return fnret
end

function _command(cmd, idx)
    local handle = io.popen(cmd .. " 2>/dev/null")
    -- local fnret = handle:read("*all")
    local fnret = {}
    for line in handle:lines() do
        fnret[#fnret] = line
        if idx == #fnret then
            return line
        end
    end
    handle:close()
    if #fnret == 0 then
        return nil
    end
    return fnret
end

function _currency2smbol(currency)
    local currency2smbol = {
        EUR = "€", --
        DOL = "$"
    }
    if not currency2smbol[currency] then
        return ""
    end
    return currency2smbol[currency]
end

function _round(num, decimalPlaces)
    local mult = 10 ^ (decimalPlaces or 0)
    return math.floor(num * mult + 0.5) / mult
end

function _merge(...)
    local result = {}
    local k = 1
    for _, t in ipairs {...} do
        for _, v in ipairs(t) do
            result[k] = v
            k = k + 1
        end
    end
    return result
end

function _shall_display(item, blacklist)
    for blacklist_attribute, blacklist_value in pairs(blacklist) do
        if type(item[blacklist_attribute]) == "function" then
            item[blacklist_attribute] = nil
        end
        if blacklist_value == "" then
            if not item[blacklist_attribute] and blacklist_value == "" then
                return false
            end
        elseif item[blacklist_attribute] then

            if type(item[blacklist_attribute]) == "string" and type(blacklist_value) == "string" then
                if string.match(item[blacklist_attribute], blacklist_value) then
                    return false
                end
            elseif type(item[blacklist_attribute]) == "table" and type(blacklist_value) == "table" then
                for _, blacklist_value_item in pairs(blacklist_value) do -- browse each blacklist item
                    for _, item_blacklist_attribute_item in pairs(item[blacklist_attribute]) do -- browse each item attribute sub item
                        if string.match(item_blacklist_attribute_item, blacklist_value_item) then
                            return false
                        end
                    end
                end
            end
        end
    end
    return true
end

function _add_attribute_value(table, attribute, value)
    if not table then
        return {}
    end
    for _, item in ipairs(table) do
        item[attribute] = (item.attribute and item.attribute or value)
    end
    return table
end

function _split(s, delimiter)
    delimiter = delimiter or ","
    local t = {}
    local i = 1
    for str in string.gmatch(s, "([^" .. delimiter .. "]+)") do
        t[i] = str
        i = i + 1
    end
    return t
end

-- conky display functions

-- Per-section gauge placement — calibrate GAUGE_START_Y if gauges are mis-aligned
local GAUGE_START_Y  = 110   -- Y of first section after clock block
local GAUGE_HEADER_H = 50    -- pixels per section header (font9 \n + font7 line)
local GAUGE_ROW_H    = 21    -- pixels per data row (Xft metrics for font7/18px)
local GAUGE_SIZE     = 90    -- display size of each gauge image (matches source PNG)
local GAUGE_X_START  = 15    -- leftmost X for gauges
local GAUGE_X_GAP    = 5     -- gap between gauges horizontally
local _gauge_y       = GAUGE_START_Y

local _section_gauges = {
    Hardware        = {"cpu", "ram", "cputemp"},
    GPU             = {"gpu", "gputemp", "gpufan"},
    Storage         = {"disk"},
    ["Network IPs"] = {"netdown", "netup"},
    ["Network Routes"] = {"netdown", "netup"},
}

-- Clock above Hardware leaves text cursor ~48px below GAUGE_START_Y.
-- drift = cursor_correction + centering_preference, recalculated for new section order:
-- tracker over-advances 17px/section vs actual cursor; positions are 0-indexed after clock.
-- System=pos0 (no gauges), Hardware=pos1, GPU=pos2, Storage=pos3
local _section_cursor_drift = {
    Hardware           =  20,
    GPU                = -10,
    Storage            = -38,
    ["Network IPs"]    = -62,
    ["Network Routes"] = -95,
}

-- Absolute Y overrides for gauges that cannot be centered within their section.
local _section_gauge_gy_abs = {}

function conky_init_gauge_y(start_y)
    _gauge_y = tonumber(start_y) or GAUGE_START_Y
    return ""
end

function _table_format(items)
    local str_output = ""
    for _, item in ipairs(items) do
        str_output = str_output .. "\n${font7}${alignr}${color0}" .. item.key .. ":${color}  " .. item.value
    end
    return str_output
end

function _get_header(title)
    return "${font9}\n${font7}${color0}-- " .. title .. " --${color}"
end

function conky_display(title, ...)
    local fnrets = {}
    local title_extra = {}
    for _, word in pairs({...}) do
        local fn = _G["conky_" .. word]
        if type(fn) == "function" then
            local fnret = fn()
            if fnret and #fnret and #fnret > 0 then
                fnrets = _merge(fnrets, fnret)
            elseif fnret and fnret.key and fnret.value then
                fnrets[#fnrets + 1] = fnret
            end
        else
            title_extra[#title_extra + 1] = word
        end
    end
    if #title_extra > 0 then
        title = title .. " " .. table.concat(title_extra, " ")
    end

    local nrows = #fnrets
    local section_start_y = _gauge_y
    local section_height = GAUGE_HEADER_H + nrows * GAUGE_ROW_H
    _gauge_y = _gauge_y + (nrows > 0 and section_height or 0)

    if nrows == 0 then return "" end

    -- Emit gauge image commands centered vertically within the section.
    local gauge_cmds = ""
    local gauges = _section_gauges[title] or {}
    if #gauges > 0 then
        local gy = _section_gauge_gy_abs[title]
        if not gy then
            local drift = _section_cursor_drift[title] or 0
            gy = math.floor(section_start_y + drift + (section_height - GAUGE_SIZE) / 2)
        end
        for i, gname in ipairs(gauges) do
            local gx = GAUGE_X_START + (i - 1) * (GAUGE_SIZE + GAUGE_X_GAP)
            gauge_cmds = gauge_cmds .. string.format(
                "${image /tmp/conky_gauges/%s.png -p %d,%d -s %dx%d -f 5}",
                gname, gx, gy, GAUGE_SIZE, GAUGE_SIZE)
        end
    end

    return gauge_cmds .. _get_header(title) .. _table_format(fnrets)
end

function _debug_dump(o)
    if type(o) == "table" then
        local s = "{ "
        for k, v in pairs(o) do
            if type(k) ~= "number" then
                k = "\"" .. k .. "\""
            end
            s = s .. "[" .. k .. "] = " .. _debug_dump(v) .. ","
        end
        return s .. "} "
    else
        return tostring(o)
    end
end

function conky_network_ip4()   return conky_network_ip(4)   end
function conky_network_routes4() return conky_network_routes(4) end

-- conky system informations functions

function conky_uptime()
    local json = require("json")
    local current_timestamp = os.time(os.date("*t"))

    local fnret = _file_read("/proc/uptime", 0)
    if not fnret then
        return conky_parse("$uptime")
    end
    local uptime_sec, _ = string.gsub(fnret, "%..*", "")
    uptime_sec = tonumber(uptime_sec)

    fnret = _command("journalctl -u sleep.target MESSAGE=\"Stopped target Sleep.\" -o json -n 1 --no-pager", 0)
    if not fnret then
        return conky_parse("$uptime")
    end
    if type(fnret) == "string" then
        fnret = json.decode(fnret)
    end
    local awake_timestamp = fnret["_SOURCE_REALTIME_TIMESTAMP"]
    if not awake_timestamp then
        return _sec_to_human(uptime_sec)
    else
        awake_timestamp = math.ceil((tonumber(awake_timestamp) / 1000000) - 0.5)
    end
    local awake_sec = current_timestamp - awake_timestamp

    if awake_sec < uptime_sec then
        return _sec_to_human(awake_sec)
    end
    return _sec_to_human(uptime_sec)
end

function conky_storage_partitions()
    local storage = {}
    local json = require("json")
    local fnret = _command("lsblk -J -n -p -l -x MOUNTPOINT -O | jq -cM", 0)
    if not fnret then
        return nil
    end
    if type(fnret) == "string" then
        fnret = json.decode(fnret)
    end
    if not fnret.blockdevices then
        return nil
    end
    for _, item in pairs(fnret.blockdevices) do
        if _shall_display(item, helper.config.storage.black_list) == true then
            if item.fstype == "swap" then
                item.mountpoint = "swap"
                item.fsused = string.gsub(conky_parse("$swap"), " ", "")
                item.size = string.gsub(conky_parse("$swapmax"), " ", "")
                item["fsuse%"] = conky_parse("$swapperc") .. "%"
            end
            if type(item.fssize) == "function" then
                item.fssize = item.size
            end
            item.mountpoint = string.gsub(item.mountpoint, os.getenv("HOME"), "~")
            storage[#storage + 1] = {
                key = item.mountpoint,
                value = item.fstype .. " " .. item.type .. ", " .. item.fsused .. " / " .. item.fssize .. " (" .. item["fsuse%"] .. ")"
            }
        end
    end
    return storage
end

function conky_storage_raid()
    local storage = {}
    local json = require("json")
    local lines = _file_read("/proc/mdstat")
    if not lines then return storage end
    for _, line in ipairs(lines) do
        local columns = _split(line, " ")
        if columns[1] and string.match(columns[1], "^md[0-9]+$") and columns[2] and columns[2] == ":" and columns[3] and columns[4] then
            storage[#storage + 1] = {
                key = columns[1],
                value = columns[4] .. ", " .. columns[3]
            }
        elseif columns[2] and columns[2] == "blocks" and columns[3] and columns[3] == "super" and columns[6] then
            local status = "error"
            if columns[6] == "[UU]" then
                status = "ok"
            end
            storage[#storage].value = storage[#storage].value .. ", " .. status
        end
    end
    return storage
end

function conky_memory()
    return {
        key = "RAM",
        value = "${mem} / ${memmax}"
    }
end

function conky_cpu()
    local cpu_usage = conky_parse("${cpu}")
    local suffix = "   "
    if tonumber(cpu_usage) and tonumber(cpu_usage) < 100 then
        suffix = suffix .. " "
    end
    if tonumber(cpu_usage) and tonumber(cpu_usage) < 10 then
        suffix = suffix .. " "
    end
    return {
        key = "CPU",
        value = cpu_usage .. " %" .. suffix .. "@${freq_g} GHz"
    }
end

function conky_temperature()
    if not io.open("/sys/class/hwmon/hwmon" .. helper.config.temperature.sensor_device .. "/temp" .. helper.config.temperature.sensor_type .. "_input", "r") then
        print("conky_temperature: wrong sensor device (" .. helper.config.temperature.sensor_device .. ") and/or sensor type (" .. helper.config.temperature.sensor_type .. "). Trying to fix...")
        local fnret = _command("ls /sys/class/hwmon/hwmon*/temp*_input -1", 0)
        if fnret then
            fnret = string.gsub(fnret, "^/sys/class/hwmon/hwmon([0-9]+)/temp([0-9]+)_input$", "%1,%2")
        end
        if not fnret then
            return nil
        end
        helper.config.temperature.sensor_device = _split(fnret)[1]
        helper.config.temperature.sensor_type = _split(fnret)[2]
        print("conky_temperature: sensor device and sensor type configuration fixed to respective values " .. helper.config.temperature.sensor_device .. " and " .. helper.config.temperature.sensor_type)
    end
    return {
        key = "Temp",
        value = "${hwmon " .. helper.config.temperature.sensor_device .. " temp " .. helper.config.temperature.sensor_type .. "} °C"
    }
end

function conky_gpu()
    local usage_raw = _file_read("/sys/class/drm/card1/device/gpu_busy_percent", 0)
    local usage = (usage_raw and string.gsub(usage_raw, "%s+", "") or "?")

    local handle = io.popen("sensors 2>/dev/null | grep -A4 'amdgpu-pci-0300' | grep 'edge'")
    local temp_line = handle:read("*l")
    handle:close()
    local temp = "?"
    if temp_line then
        temp = string.match(temp_line, "%+(%d+%.%d+)") or string.match(temp_line, "%+(%d+)")
        if temp then temp = string.match(temp, "^%d+") end
    end

    local fan_raw = _file_read("/sys/class/drm/card1/device/hwmon/hwmon5/fan1_input", 0)
    local fan = (fan_raw and string.gsub(fan_raw, "%s+", "") or "?")

    local vram_used_raw  = _file_read("/sys/class/drm/card1/device/mem_info_vram_used", 0)
    local vram_total_raw = _file_read("/sys/class/drm/card1/device/mem_info_vram_total", 0)
    local vram = "?"
    if vram_used_raw and vram_total_raw then
        local used  = math.floor(tonumber(vram_used_raw)  / 1048576)
        local total = math.floor(tonumber(vram_total_raw) / 1048576)
        vram = used .. " / " .. total .. " MB"
    end

    return {
        {key = "Usage",  value = usage .. " %"},
        {key = "Temp",   value = (temp or "?") .. " C"},
        {key = "Fan",    value = fan .. " RPM"},
        {key = "VRAM",   value = vram},
    }
end


function conky_boot()
    if not cache.boot then
        print("conky_boot: Loading to cache...")
        local fnret = _command("test -d /sys/firmware/efi 2>&1 > /dev/null; echo $?", 0)
        local boot_type = "legacy"
        if fnret == "0" then
            boot_type = "uefi"
        end
        local tpm_type = "no TPM"
        fnret = _command("test -c /dev/" .. helper.config.boot.tpm_device .. " 2>&1 > /dev/null; echo $?", 0)
        if fnret == "0" then
            tpm_type = "TPM"
        end
        cache.boot = {
            key = "Boot",
            value = boot_type .. " (" .. tpm_type .. ")"
        }
    end
    return cache.boot
end

function conky_version_bios()
    if not cache.version_bios then
        print("conky_version_bios: Loading to cache...")
        local fnret = _file_read("/sys/devices/virtual/dmi/id/bios_version", 0)
        cache.version_bios = {
            key = "Bios",
            value = fnret
        }
    end
    return cache.version_bios
end

function conky_version_os()
    if not cache.version_os then
        print("conky_version_os: Loading to cache...")
        local fnret = _command("lsb_release -ds", 0)
        if not fnret then
            return nil
        end
        cache.version_os = {
            key = "OS",
            value = fnret
        }
    end
    return cache.version_os
end

function conky_version_kernel()
    if not cache.version_kernel then
        print("conky_version_kernel: Loading to cache...")
        cache.version_kernel = {
            key = "Kern",
            value = string.gsub(conky_parse("$kernel"), "-generic$", "")
        }
    end
    return cache.version_kernel
end

function conky_power()
    local label = "Battery"
    if not io.open("/proc/acpi/battery/" .. helper.config.power.battery, "r") and not io.open("/sys/class/power_supply/" .. helper.config.power.battery, "r") then
        return conky_boot() -- not a laptop or no battery connected for the moment, let's fall back to something else
    end
    local battery_percent = conky_parse("${battery_percent}")
    local acpi_ac_adapter = conky_parse("${acpiacadapter}")
    if acpi_ac_adapter == "on-line" and battery_percent ~= "100" then
        return {
            key = label,
            value = battery_percent .. "% (Charging)"
        }
    elseif acpi_ac_adapter == "on-line" and battery_percent == "100" then
        return {
            key = label,
            value = "Charged"
        }
    elseif acpi_ac_adapter ~= "on-line" and battery_percent ~= "0" then
        return {
            key = label,
            value = battery_percent .. "% (Discharging)"
        }
    elseif acpi_ac_adapter ~= "on-line" and battery_percent == "0" then
        return {
            key = label,
            value = "Error"
        }
    end
    return {
        key = label,
        value = "N/A"
    }
end

function conky_arch()
    if not cache.arch then
        print("conky_arch: Loading to cache...")
        local fnret = _command("arch", 0)
        if not fnret then
            return nil
        end
        cache.arch = {
            key = "Arch",
            value = fnret
        }
    end
    return cache.arch
end

function conky_version_gs()
    if not cache.version_gs then
        print("conky_version_gs: Loading to cache...")
        local fnret = _command("plasmashell --version", 0)
        if not fnret then
            return nil
        end
        local version = string.gsub(fnret, "plasmashell ", "")
        local session_type = os.getenv("XDG_SESSION_TYPE") or "unknown"
        cache.version_gs = {
            key = "Plasma",
            value = version .. "  (" .. session_type .. ")"
        }
    end
    return cache.version_gs
end

function conky_network_ip(version)
    local family = (version and "inet" .. (version == 6 and version or "") or "inet")
    local ips = {}
    local nic_aliases = _nic_aliases()

    local json = require("json")
    local fnret = _command("ip -j address", 0)
    if not fnret then
        return nil
    end
    local net_interfaces = fnret
    if type(fnret) == "string" then
        net_interfaces = json.decode(fnret)
    end
    for k, net_interface in ipairs(net_interfaces) do
        if net_interface.operstate == "UNKNOWN" or net_interface.operstate == "UP" then
            local if_name = net_interface.ifname
            local addr_infos = net_interface.addr_info
            for k, addr_info in ipairs(addr_infos) do
                if (not version or addr_info.family == family) and _shall_display(addr_info, helper.config.network_ip.black_list) == true then
                    local ip = {}
                    ip.key = if_name
                    if addr_info.label then
                        ip.key = addr_info.label
                    end
                    if nic_aliases[ip.key] then
                        ip.key = nic_aliases[ip.key]
                    end
                    if not version and addr_info.family == "inet6" then
                        ip.version = 6
                    elseif not version then
                        ip.version = 4
                    end
                    ip.value = addr_info["local"] .. "/" .. addr_info.prefixlen
                    ips[#ips + 1] = ip
                end
            end
        end
    end

    return ips
end

function _sort_routes(a, b)
    local ametric = (a.metric and a.metric or 0)
    ametric = (ametric == "default" and ametric - 1 or ametric)
    local bmetric = (b.metric and b.metric or 0)
    bmetric = (bmetric == "default" and bmetric - 1 or bmetric)
    if ametric == bmetric then
        bmetric = (a.dst == "default" and bmetric + 1 or bmetric)
        ametric = (b.dst == "default" and ametric + 1 or ametric)
    end
    return ametric < bmetric
end

function _nic_aliases()
    local json = require("json")
    local nic_aliases = {}
    local fnretNICs = _command("ip -j link", 0)
    if not fnretNICs then
        return nic_aliases
    end
    if type(fnretNICs) == "string" then
        fnretNICs = json.decode(fnretNICs)
    end
    for _, nic in ipairs(fnretNICs) do
        local if_name = nil
        if string.match(nic.ifname, "^enx.*$") then
            if_name = "eth" .. nic.ifindex
        end
        if string.match(nic.ifname, "^wlx.*$") then
            if_name = "wlan" .. nic.ifindex
        end
        if if_name then
            nic_aliases[nic.ifname] = if_name
        end
    end
    return nic_aliases
end

function conky_network_routes(version)
    local routes = {}

    local nic_aliases = _nic_aliases()

    local json = require("json")
    local fnretRoutesv4 = _command("ip -j route", 0)
    if type(fnretRoutesv4) == "string" then
        fnretRoutesv4 = json.decode(fnretRoutesv4)
    end
    local net_routesv4 = _add_attribute_value(fnretRoutesv4, "version", 4)
    local fnretRoutesv6 = _command("ip -j -6 route", 0)
    if type(fnretRoutesv6) == "string" then
        fnretRoutesv6 = json.decode(fnretRoutesv6)
    end
    local net_routesv6 = _add_attribute_value(fnretRoutesv6, "version", 6)
    local net_routes = _merge(net_routesv4, net_routesv6)
    table.sort(net_routes, _sort_routes)
    for k, net_route in ipairs(net_routes) do
        if (not version or net_route.version == version) and _shall_display(net_route, helper.config.network_routes.black_list) == true then
            local route = {}
            route.key = net_route.dev
            if nic_aliases[route.key] then
                route.key = nic_aliases[route.key]
            end
            route.value = net_route.dst
            if route.value == "default" then
                route.value = (net_route.version == 4 and "0.0.0.0/0" or "::/0")
            end
            route.metric = (net_route.metric and net_route.metric or 0)
            if not version then
                route.version = net_route.version
            end
            routes[#routes + 1] = route
        end
    end
    return routes
end
