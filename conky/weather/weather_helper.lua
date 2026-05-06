#!/usr/bin/env lua
-- weather_helper.lua — Conky weather panel display logic

local HOME         = os.getenv("HOME")
local ICON_DIR     = HOME .. "/.config/conky/weather/icons"
local FETCH_SCRIPT = HOME .. "/.config/conky/weather/weather_fetch.py"
local CONFIG_FILE  = HOME .. "/.config/conky/weather/config"
local CACHE_FILE   = "/tmp/conky_weather/data.json"

-- Pixel heights (GE Inspira pixelsize=18, matching main panel)
local LINE_H       = 21    -- one text line height
local HEADER_H     = 29    -- font7-header + template newline overhead

-- Calibration: adjust these if images appear mis-aligned with text
local CURRENT_DRIFT  =  8   -- nudge current-conditions icon Y (positive = down)
local FORECAST_DRIFT =  8   -- nudge forecast icons Y

-- Y tracker for absolute image placement (set by conky_init_weather_y)
local _weather_y = 0

-- Cached weather data and config (populated by draw hook)
local _wdata = nil
local _wcfg  = { ICON_SIZE_CURRENT = 96, ICON_SIZE_FORECAST = 64, TIME_FORMAT = "12h" }

local function read_wcfg()
    local cfg = { ICON_SIZE_CURRENT = 96, ICON_SIZE_FORECAST = 64, TIME_FORMAT = "12h" }
    local f = io.open(CONFIG_FILE)
    if not f then return cfg end
    for line in f:lines() do
        local k, v = line:match("^([A-Z_]+)=(.*)$")
        if k and v ~= nil then cfg[k] = v end
    end
    f:close()
    cfg.ICON_SIZE_CURRENT  = tonumber(cfg.ICON_SIZE_CURRENT)  or 96
    cfg.ICON_SIZE_FORECAST = tonumber(cfg.ICON_SIZE_FORECAST) or 64
    return cfg
end

function conky_init_weather_y(start_y)
    _weather_y = tonumber(start_y) or 0
    return ""
end

local function load_cache()
    local f = io.open(CACHE_FILE)
    if not f then return end
    local raw = f:read("*all"); f:close()
    if raw == "" then return end
    local ok, data = pcall(require("json").decode, raw)
    if ok and type(data) == "table" then _wdata = data end
end

function conky_weather_startup()
    _wcfg = read_wcfg()
    load_cache()
end

-- Called by lua_draw_hook_post every frame: runs async fetch, reads cache.
function conky_weather_main()
    if not conky_window then return end
    os.execute("python3 " .. FETCH_SCRIPT .. " &")
    _wcfg = read_wcfg()
    load_cache()
end

-- 16-point compass from wind degrees
local function wind_dir(deg)
    local dirs = {"N","NNE","NE","ENE","E","ESE","SE","SSE",
                  "S","SSW","SW","WSW","W","WNW","NW","NNW"}
    return dirs[math.floor(((tonumber(deg) or 0) + 11.25) / 22.5) % 16 + 1]
end

local WMO_ICONS = {
    [0] ={"clear-day",               "clear-night"},
    [1] ={"partly-cloudy-day",       "partly-cloudy-night"},
    [2] ={"partly-cloudy-day",       "partly-cloudy-night"},
    [3] ={"overcast-day",            "overcast-night"},
    [45]={"fog-day",                 "fog-night"},
    [48]={"fog-day",                 "fog-night"},
    [51]={"partly-cloudy-day-drizzle","partly-cloudy-night-drizzle"},
    [53]={"drizzle",                 "drizzle"},
    [55]={"drizzle",                 "drizzle"},
    [56]={"sleet",                   "sleet"},
    [57]={"sleet",                   "sleet"},
    [61]={"partly-cloudy-day-rain",  "partly-cloudy-night-rain"},
    [63]={"rain",                    "rain"},
    [65]={"rain",                    "rain"},
    [66]={"sleet",                   "sleet"},
    [67]={"sleet",                   "sleet"},
    [71]={"partly-cloudy-day-snow",  "partly-cloudy-night-snow"},
    [73]={"snow",                    "snow"},
    [75]={"snow",                    "snow"},
    [77]={"snow",                    "snow"},
    [80]={"partly-cloudy-day-rain",  "partly-cloudy-night-rain"},
    [81]={"rain",                    "rain"},
    [82]={"thunderstorms-day-rain",  "thunderstorms-night-rain"},
    [85]={"partly-cloudy-day-snow",  "partly-cloudy-night-snow"},
    [86]={"snow",                    "snow"},
    [95]={"thunderstorms-day",       "thunderstorms-night"},
    [96]={"thunderstorms-day-rain",  "thunderstorms-night-rain"},
    [99]={"thunderstorms-day-rain",  "thunderstorms-night-rain"},
}

local WMO_LABELS = {
    [0]="Clear",           [1]="Mainly Clear",      [2]="Partly Cloudy",
    [3]="Overcast",        [45]="Fog",              [48]="Freezing Fog",
    [51]="Light Drizzle",  [53]="Drizzle",          [55]="Heavy Drizzle",
    [56]="Freezing Drizzle",[57]="Heavy Freezing Drizzle",
    [61]="Light Rain",     [63]="Rain",             [65]="Heavy Rain",
    [66]="Light Freezing Rain",[67]="Heavy Freezing Rain",
    [71]="Light Snow",     [73]="Snow",             [75]="Heavy Snow",
    [77]="Snow Grains",
    [80]="Light Showers",  [81]="Rain Showers",     [82]="Heavy Showers",
    [85]="Light Snow Showers",[86]="Snow Showers",
    [95]="Thunderstorm",   [96]="Thunderstorm + Hail",[99]="Thunderstorm + Hail",
}

local function wmo_icon_name(code, is_day)
    local pair = WMO_ICONS[tonumber(code)]
    if not pair then return "not-available" end
    return is_day and pair[1] or pair[2]
end

local function wmo_label(code)
    return WMO_LABELS[tonumber(code)] or ("Condition " .. tostring(code))
end

local function icon_path(name)
    local p = ICON_DIR .. "/" .. name .. ".png"
    -- fall back to not-available if icon file is missing
    local f = io.open(p)
    if f then f:close(); return p end
    return ICON_DIR .. "/not-available.png"
end

local function fmt_num(v, dec)
    if v == nil then return "?" end
    local n = tonumber(v) or 0
    if dec and dec > 0 then
        return string.format("%." .. dec .. "f", n)
    end
    return tostring(math.floor(n))
end

local MONTHS   = {"Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"}
local WEEKDAYS = {"Sun","Mon","Tue","Wed","Thu","Fri","Sat"}

-- Returns header line: "-- City  •  Mon, May 3 --"
function conky_weather_header()
    local city = "Weather"
    if _wdata and _wdata._meta then
        local c = _wdata._meta.city
        if c and c ~= "" then city = c end
    end
    local now = os.date("*t")
    local dateline = string.format("%s, %s %d",
        WEEKDAYS[now.wday], MONTHS[now.month], now.day)

    _weather_y = _weather_y + HEADER_H
    return "${font7}${color0}-- " .. city .. "  •  " .. dateline .. " --${color}"
end

-- Returns current-conditions block: icon image + 5 text lines
function conky_weather_current()
    local ICS    = _wcfg.ICON_SIZE_CURRENT
    local ICON_X = 15
    local TEXT_X = ICON_X + ICS + 12

    local section_y = _weather_y

    if not _wdata then
        -- placeholder until first fetch completes
        local section_h = math.max(ICS, 5 * LINE_H) + 8
        _weather_y = _weather_y + section_h
        return string.format("${image %s -p %d,%d -s %dx%d -f 0}",
            icon_path("not-available"), ICON_X, section_y + CURRENT_DRIFT, ICS, ICS)
            .. "\n${goto " .. TEXT_X .. "}Fetching weather..."
    end

    local c    = _wdata.current or {}
    local meta = _wdata._meta   or {}

    local is_day = (c.is_day == nil) and true or (c.is_day ~= 0)
    local iname  = wmo_icon_name(c.weather_code, is_day)

    local temp_u = (meta.temp_unit == "fahrenheit") and "F" or "C"
    local wind_u = meta.wind_unit or "km/h"
    local prec_u = (meta.temp_unit == "fahrenheit") and "in" or "mm"

    local line1 = string.format("%s°%s  feels %s°",
        fmt_num(c.temperature_2m), temp_u, fmt_num(c.apparent_temperature))
    local line2 = wmo_label(c.weather_code)
    local line3 = string.format("Humidity: %s%%", fmt_num(c.relative_humidity_2m))
    local line4 = string.format("Wind: %s %s %s  gusts %s",
        fmt_num(c.wind_speed_10m), wind_u,
        wind_dir(c.wind_direction_10m or 0),
        fmt_num(c.wind_gusts_10m))
    local line5 = string.format("UV: %s  •  Precip: %s %s",
        fmt_num(c.uv_index, 1), fmt_num(c.precipitation, 2), prec_u)

    local n_lines   = 5
    local text_h    = n_lines * LINE_H
    local section_h = math.max(ICS, text_h) + 8

    -- vertical offset to center text within icon height (if icon is taller)
    local voff_str = ""
    local text_top_offset = math.max(0, math.floor((ICS - text_h) / 2))
    if text_top_offset > 0 then
        voff_str = "${voffset " .. text_top_offset .. "}"
    end

    local img = string.format("${image %s -p %d,%d -s %dx%d -f 0}",
        icon_path(iname), ICON_X, section_y + CURRENT_DRIFT, ICS, ICS)

    local text = voff_str
        .. "\n${font7}${goto " .. TEXT_X .. "}" .. line1
        .. "\n${goto " .. TEXT_X .. "}${color3}" .. line2 .. "${color}"
        .. "\n${goto " .. TEXT_X .. "}" .. line3
        .. "\n${goto " .. TEXT_X .. "}" .. line4
        .. "\n${goto " .. TEXT_X .. "}" .. line5

    -- advance tracker past this section
    _weather_y = _weather_y + section_h

    return img .. text
end

-- Returns forecast block: header + 4-column day/icon/hi/lo
function conky_weather_forecast()
    if not _wdata then return "" end

    local daily  = _wdata.daily or {}
    local meta   = _wdata._meta or {}
    local IFS    = _wcfg.ICON_SIZE_FORECAST

    local codes  = daily.weather_code or {}
    local hi_arr = daily.temperature_2m_max or {}
    local lo_arr = daily.temperature_2m_min or {}
    local times  = daily.time or {}
    local n      = math.min(4, #times)
    if n == 0 then return "" end

    local temp_u = (meta.temp_unit == "fahrenheit") and "F" or "C"

    -- 4 equal columns across usable width
    local PANEL_W = 372
    local col_w   = math.floor(PANEL_W / n)

    -- icon left-edge and label center for each column
    local ix, lx = {}, {}
    for i = 1, n do
        ix[i] = (i - 1) * col_w + math.floor((col_w - IFS) / 2)
        lx[i] = (i - 1) * col_w + math.floor(col_w / 2) - 15
    end

    -- Section header
    _weather_y = _weather_y + HEADER_H
    local header = "${font9}\n${font7}${color0}-- Forecast --${color}"

    -- Day name row
    local day_row = ""
    for i = 1, n do
        local t = times[i] or ""
        local y_s, m_s, d_s = t:match("(%d+)-(%d+)-(%d+)")
        local dname = ""
        if y_s then
            local ts = os.time({year=tonumber(y_s), month=tonumber(m_s), day=tonumber(d_s), hour=12})
            dname = WEEKDAYS[os.date("*t", ts).wday]
        end
        day_row = day_row .. "${goto " .. lx[i] .. "}" .. dname
    end
    _weather_y = _weather_y + LINE_H

    -- Icons at absolute Y
    local icon_y = _weather_y + FORECAST_DRIFT
    local imgs = ""
    for i = 1, n do
        local iname = wmo_icon_name(codes[i], true)
        imgs = imgs .. string.format("${image %s -p %d,%d -s %dx%d -f 0}",
            icon_path(iname), ix[i], icon_y, IFS, IFS)
    end

    -- Hi/Lo rows: voffset skips cursor past the icon area (+5 nudge to clear icons)
    local hi_row = "${voffset " .. (IFS + 5) .. "}"
    local lo_row = ""
    for i = 1, n do
        hi_row = hi_row .. "${goto " .. lx[i] .. "}"
                        .. fmt_num(hi_arr[i]) .. "°" .. temp_u
        lo_row = lo_row .. "${goto " .. lx[i] .. "}${color3}"
                        .. fmt_num(lo_arr[i]) .. "°" .. "${color}"
    end

    _weather_y = _weather_y + IFS + LINE_H + LINE_H

    return header
        .. "\n" .. day_row
        .. imgs
        .. "\n" .. hi_row
        .. "\n" .. lo_row
end
