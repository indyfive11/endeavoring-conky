#!/usr/bin/env python3
"""
weather_fetch.py — fetches Open-Meteo data and Basmilius Meteocons icons for Conky.
Run async from weather_helper.lua every update cycle; exits early if cache is fresh.
Icons are SVGs downloaded from jsDelivr CDN and converted to PNG via rsvg-convert.
"""
import os, sys, json, time, subprocess, tempfile
from urllib.request import urlopen, urlretrieve
from urllib.error import URLError

CONFIG_FILE = os.path.expanduser("~/.config/conky/weather/config")
ICON_DIR    = os.path.expanduser("~/.config/conky/weather/icons")
CACHE_DIR   = "/tmp/conky_weather"
CACHE_FILE  = f"{CACHE_DIR}/data.json"
CACHE_TTL   = 600  # seconds

IMPERIAL_COUNTRIES = {"US", "BS", "KY", "PW", "FM", "MH"}

ICON_SVG_CDN = "https://cdn.jsdelivr.net/gh/basmilius/weather-icons/production/fill/all/{name}.svg"

WMO_ICONS = {
    0:  ("clear-day",                  "clear-night"),
    1:  ("partly-cloudy-day",          "partly-cloudy-night"),
    2:  ("partly-cloudy-day",          "partly-cloudy-night"),
    3:  ("overcast-day",               "overcast-night"),
    45: ("fog-day",                    "fog-night"),
    48: ("fog-day",                    "fog-night"),
    51: ("partly-cloudy-day-drizzle",  "partly-cloudy-night-drizzle"),
    53: ("drizzle",                    "drizzle"),
    55: ("drizzle",                    "drizzle"),
    56: ("sleet",                      "sleet"),
    57: ("sleet",                      "sleet"),
    61: ("partly-cloudy-day-rain",     "partly-cloudy-night-rain"),
    63: ("rain",                       "rain"),
    65: ("rain",                       "rain"),
    66: ("sleet",                      "sleet"),
    67: ("sleet",                      "sleet"),
    71: ("partly-cloudy-day-snow",     "partly-cloudy-night-snow"),
    73: ("snow",                       "snow"),
    75: ("snow",                       "snow"),
    77: ("snow",                       "snow"),
    80: ("partly-cloudy-day-rain",     "partly-cloudy-night-rain"),
    81: ("rain",                       "rain"),
    82: ("thunderstorms-day-rain",     "thunderstorms-night-rain"),
    85: ("partly-cloudy-day-snow",     "partly-cloudy-night-snow"),
    86: ("snow",                       "snow"),
    95: ("thunderstorms-day",          "thunderstorms-night"),
    96: ("thunderstorms-day-rain",     "thunderstorms-night-rain"),
    99: ("thunderstorms-day-rain",     "thunderstorms-night-rain"),
}
FALLBACK_ICON = "not-available"


def read_config():
    cfg = {}
    try:
        with open(CONFIG_FILE) as f:
            for line in f:
                line = line.strip()
                if "=" in line and not line.startswith("#"):
                    k, _, v = line.partition("=")
                    cfg[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return cfg


def write_config(cfg):
    lines = []
    keys_written = set()
    try:
        with open(CONFIG_FILE) as f:
            for line in f:
                stripped = line.strip()
                if "=" in stripped and not stripped.startswith("#"):
                    k = stripped.split("=", 1)[0].strip()
                    if k in cfg:
                        lines.append(f"{k}={cfg[k]}\n")
                        keys_written.add(k)
                        continue
                lines.append(line)
    except FileNotFoundError:
        pass
    for k, v in cfg.items():
        if k not in keys_written:
            lines.append(f"{k}={v}\n")
    with open(CONFIG_FILE, "w") as f:
        f.writelines(lines)


def fetch_json(url, timeout=10):
    with urlopen(url, timeout=timeout) as r:
        return json.loads(r.read().decode())


def auto_geolocate(cfg):
    data = fetch_json("http://ip-api.com/json")
    if data.get("status") != "success":
        raise RuntimeError(f"ip-api returned: {data.get('message', 'unknown error')}")
    updates = {
        "LATITUDE":  str(data["lat"]),
        "LONGITUDE": str(data["lon"]),
        "CITY":      data.get("city", ""),
    }
    if cfg.get("UNITS_MODE", "auto") == "auto" and not cfg.get("TEMPERATURE_UNIT"):
        country = data.get("countryCode", "")
        if country in IMPERIAL_COUNTRIES:
            updates["TEMPERATURE_UNIT"] = "fahrenheit"
            updates["WIND_UNIT"] = "mph"
        else:
            updates["TEMPERATURE_UNIT"] = "celsius"
            updates["WIND_UNIT"] = "kmh"
    cfg.update(updates)
    write_config(cfg)


def wmo_icon_name(code, is_day=True):
    pair = WMO_ICONS.get(int(code), None)
    if pair is None:
        return FALLBACK_ICON
    return pair[0] if is_day else pair[1]


def ensure_icon(name):
    path = os.path.join(ICON_DIR, f"{name}.png")
    if os.path.exists(path):
        return True
    url = ICON_SVG_CDN.format(name=name)
    try:
        with tempfile.NamedTemporaryFile(suffix=".svg", delete=False) as tmp:
            svg_path = tmp.name
        urlretrieve(url, svg_path)
        subprocess.run(
            ["rsvg-convert", "-w", "256", "-h", "256", svg_path, "-o", path],
            check=True, capture_output=True
        )
        os.unlink(svg_path)
        return True
    except Exception as e:
        print(f"weather_fetch: icon failed for {name}: {e}", file=sys.stderr)
        try:
            os.unlink(svg_path)
        except Exception:
            pass
        return False


def ensure_fallback_icon():
    path = os.path.join(ICON_DIR, f"{FALLBACK_ICON}.png")
    if os.path.exists(path):
        return
    # Generate a simple gray placeholder PNG using cairo if available
    try:
        import cairo
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, 256, 256)
        cr = cairo.Context(surface)
        cr.set_source_rgba(0.4, 0.4, 0.4, 0.8)
        cr.arc(128, 128, 100, 0, 6.2832)
        cr.fill()
        cr.set_source_rgba(1, 1, 1, 0.7)
        cr.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
        cr.set_font_size(40)
        cr.move_to(68, 148)
        cr.show_text("N/A")
        surface.write_to_png(path)
    except Exception:
        pass


def main():
    os.makedirs(CACHE_DIR, exist_ok=True)
    os.makedirs(ICON_DIR, exist_ok=True)

    cfg = read_config()

    # Auto-geolocate if needed
    if cfg.get("LOCATION_MODE", "auto") == "auto" and not cfg.get("LATITUDE"):
        try:
            auto_geolocate(cfg)
        except Exception as e:
            print(f"weather_fetch: geolocation failed: {e}", file=sys.stderr)
            sys.exit(1)

    # Unit detection without full geolocation (manual location, auto units)
    if cfg.get("UNITS_MODE", "auto") == "auto" and not cfg.get("TEMPERATURE_UNIT"):
        try:
            auto_geolocate(cfg)
        except Exception as e:
            print(f"weather_fetch: unit detection failed: {e}", file=sys.stderr)
            cfg["TEMPERATURE_UNIT"] = "celsius"
            cfg["WIND_UNIT"] = "kmh"
            write_config(cfg)

    lat = cfg.get("LATITUDE", "")
    lon = cfg.get("LONGITUDE", "")
    if not lat or not lon:
        print("weather_fetch: no coordinates available", file=sys.stderr)
        sys.exit(1)

    # Check cache freshness
    try:
        age = time.time() - os.path.getmtime(CACHE_FILE)
        if age < CACHE_TTL:
            sys.exit(0)
    except FileNotFoundError:
        pass

    temp_unit = cfg.get("TEMPERATURE_UNIT", "celsius")
    wind_unit = cfg.get("WIND_UNIT", "kmh")

    url = (
        f"https://api.open-meteo.com/v1/forecast"
        f"?latitude={lat}&longitude={lon}"
        f"&current=temperature_2m,apparent_temperature,relative_humidity_2m,"
        f"weather_code,wind_speed_10m,wind_direction_10m,wind_gusts_10m,"
        f"precipitation,uv_index,is_day"
        f"&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_sum"
        f"&forecast_days=4&timezone=auto"
        f"&temperature_unit={temp_unit}"
        f"&wind_speed_unit={wind_unit}"
    )

    try:
        data = fetch_json(url)
    except Exception as e:
        print(f"weather_fetch: Open-Meteo fetch failed: {e}", file=sys.stderr)
        sys.exit(1)

    # Collect needed icon names
    icon_names = set()
    current   = data.get("current", {})
    cur_code  = current.get("weather_code")
    cur_is_day = bool(current.get("is_day", 1))
    if cur_code is not None:
        icon_names.add(wmo_icon_name(cur_code, cur_is_day))

    daily = data.get("daily", {})
    for code in daily.get("weather_code", []):
        if code is not None:
            icon_names.add(wmo_icon_name(code, True))  # forecast always day variant

    # Ensure fallback exists, then download any missing icons
    ensure_fallback_icon()
    for name in icon_names:
        ensure_icon(name)

    # Augment with metadata
    data["_meta"] = {
        "city":        cfg.get("CITY", ""),
        "temp_unit":   temp_unit,
        "wind_unit":   wind_unit,
        "time_format": cfg.get("TIME_FORMAT", "12h"),
        "fetched":     int(time.time()),
    }

    tmp = CACHE_FILE + ".tmp"
    with open(tmp, "w") as f:
        json.dump(data, f)
    os.replace(tmp, CACHE_FILE)


if __name__ == "__main__":
    try:
        main()
    except Exception as e:
        print(f"weather_fetch: fatal: {e}", file=sys.stderr)
        sys.exit(1)
