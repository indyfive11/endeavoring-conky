# endeavoring-conky

A three-panel Conky desktop setup for Linux — main hardware monitor, weather
forecast, and a fans + services panel. Built around X11 (works under Xwayland on
KDE Plasma 6) with a `kdialog` GUI for adjusting position, monitor, transparency,
and edge-gap on each panel.

## Panels

| Panel | What it shows | Source |
|---|---|---|
| **Main** | CPU/GPU usage + temps, memory, disk, network up/down | `conky/JayBeeDe/` (vendored upstream, GPLv3) |
| **Weather** | Current conditions + 4-day forecast with [Basmilius Meteocons](https://github.com/basmilius/weather-icons), auto-detected location and units | `conky/weather/` |
| **System** | Fan RPMs and water/GPU temps from [CoolerControl](https://gitlab.com/coolercontrol/coolercontrol), service health checks (TCP port probes + NFS + remote API) | `conky/system/` |

The original `conky.conf` at `~/.config/conky/conky.conf` is replaced by a stub
that exits immediately — this prevents a "ghost" panel from appearing when KDE
or another launcher invokes `conky` with no `-c` flag.

## Requirements

- `conky` (X11 build) — Wayland mode is unsupported because the settings GUI uses xdotool
- `python3` (stdlib only — `urllib`, `json`)
- `lua-cjson` or another `json` Lua module loadable via `require("json")`
- `ncat` (from `nmap`) for service port probes
- `curl` for CoolerControl REST calls
- `xdotool`, `xrandr`, `xprop` for the settings GUI
- `kdialog` (KDE) for the settings GUI menus
- `rsvg-convert` (from `librsvg`) for weather icon rendering
- A running CoolerControl instance for the System panel's fan/temp data

## Install

```bash
git clone git@github.com:indyfive11/endeavoring-conky.git ~/dev/endeavoring-conky
mkdir -p ~/.config/conky ~/.config/systemd/user ~/bin

ln -s ~/dev/endeavoring-conky/conky/conky.conf            ~/.config/conky/conky.conf
ln -s ~/dev/endeavoring-conky/conky/JayBeeDe              ~/.config/conky/JayBeeDe
ln -s ~/dev/endeavoring-conky/conky/system                ~/.config/conky/system
ln -s ~/dev/endeavoring-conky/conky/weather               ~/.config/conky/weather
ln -s ~/dev/endeavoring-conky/systemd/conky.service         ~/.config/systemd/user/conky.service
ln -s ~/dev/endeavoring-conky/systemd/conky-system.service  ~/.config/systemd/user/conky-system.service
ln -s ~/dev/endeavoring-conky/systemd/conky-weather.service ~/.config/systemd/user/conky-weather.service
ln -s ~/dev/endeavoring-conky/bin/conky-settings.sh         ~/bin/conky-settings.sh

cp ~/.config/conky/system/config.example ~/.config/conky/system/config
$EDITOR ~/.config/conky/system/config           # set CC_PASS and your services

systemctl --user daemon-reload
systemctl --user enable --now conky.service conky-weather.service conky-system.service
```

The weather panel auto-detects location and units from your IP on first launch
and writes the result back to `conky/weather/config`. To override, edit that
file directly or use the settings GUI.

## Configuring

### System panel — `conky/system/config`

Sourced as bash at the top of `fans_fetch.sh` and `svc_fetch.sh`. Holds:

- `CC_HOST`, `CC_PORT`, `CC_USER`, `CC_PASS` — CoolerControl REST API
- `COMMANDER_UID`, `GPU_DEV_UID` — device UID prefixes (find via `curl -k https://localhost:11987/devices`)
- `SERVICES=("Label:port" ...)` — TCP port probes shown as Online/Offline
- `NFS_MOUNT`, `NFS_LABEL` — optional mountpoint to monitor
- `REMOTE_HOST`, `REMOTE_PORT`, `REMOTE_LABEL` — optional remote API to ping

The fan labels and section layout (two columns, three rows + pump) live in
`conky/system/system_helper.lua` near the top — edit the `FAN_LABELS` table to
name fans by what they actually cool.

### Weather panel — settings GUI

Run `~/bin/conky-settings.sh` and pick **Weather settings** for location, units,
time format, corner, monitor, icon size, and transparency.

### All panels — settings GUI

The same `conky-settings.sh` script controls position, monitor placement,
transparency (0–255 alpha), and edge-gap for all three panels. Multi-monitor
positioning math assumes a specific Xwayland HiDPI layout; the constants near
the top of the script (`SCALE`, `BASE_RIGHT`, `PRIMARY_X`) describe the primary
monitor and may need adjusting on different setups.

## Layout

```
endeavoring-conky/
├── bin/
│   └── conky-settings.sh       # kdialog GUI controller for all three panels
├── conky/
│   ├── conky.conf              # ghost-prevention stub (run-once-and-exit)
│   ├── JayBeeDe/               # main panel — vendored upstream, GPLv3
│   ├── system/
│   │   ├── conky.conf
│   │   ├── system_helper.lua   # display logic
│   │   ├── fans_fetch.sh       # CoolerControl REST → fans.json (5s cache)
│   │   ├── svc_fetch.sh        # port/NFS probes → services.json (30s cache)
│   │   └── config.example      # copy to "config" and edit
│   └── weather/
│       ├── weather.conf
│       ├── weather_helper.lua
│       ├── weather_fetch.py    # Open-Meteo → data.json + icon downloads
│       └── config              # auto-populated on first run
└── systemd/
    ├── conky.service
    ├── conky-system.service
    └── conky-weather.service
```

## Acknowledgements

The main panel under `conky/JayBeeDe/` is a vendored copy of
[JayBeeDe/conky-config](https://github.com/JayBeeDe/conky-config), used as-is
under its original GPLv3 license. The repo as a whole is GPLv3 to remain
compatible.

Weather icons are [Basmilius Meteocons](https://github.com/basmilius/weather-icons)
(MIT), downloaded on demand from jsDelivr.

## License

GPL-3.0 — see [LICENSE](LICENSE).
