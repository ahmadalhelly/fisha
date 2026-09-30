# Protocols

## Strip setup AP (TONLY_TAP_xxxxxxx, password LGU_xxxxxxx) — TCP 192.168.1.1:30300, CRLF lines
- `up:ip:<hub-ip>` → `up:ip:ip_ok`
- `up:connect:<ssid>:<password>` → `up:connect:connect_ok` (no `:` allowed in SSID/password)

## Strip ⇄ hub — TCP 10086 (the strip dials the hub), CRLF lines
| Dir | Frame |
|---|---|
| strip→hub | `up:bootinfo:lgutap;<mac>;<mac>;<fw>;connect` |
| hub→strip | `up:getinfo:all` (poll, also keepalive) |
| strip→hub | `up:getinfo:<ch>:<runtime>;<relay on/off>;<state>;<flagA on/off>;<flagB on/off>;<power mW>;<energy hex Wh>;<prev hex>;<config hex>;<status>;<event hex>;<temp °C>` ×4 |
| hub→strip | `up:onoff:<1-4>:on|off` (no channel 0 — loop 1..4 for "all") |
| strip→hub | `up:onoff:<n>:on|off` ack, `up:event:onoff:<0-4>:on|off` physical button |
| hub→strip | `up:power_report:1:vol` → `up:power_report:<ch>:<mV>` |
| hub→strip | `up:query:wifirssi` → `up:query:<rssi>` |

Observed on fw 0.1.54-1.0.105: only channels 1–4 (USB ports are not switchable); flagA/flagB read `on` with no load, so they are protection-enabled flags, not alarms; temperature is per outlet.

## Hub HTTP — port 8080
- `GET /api/state`, `POST /api/onoff {"mac","outlet":0-4,"on"}`, `GET /api/health`, `GET /api/raw?cmd=up:...` (debug)

## Hub ⇄ cloud — MQTT over TLS
Base topic `mttl/<HUB_ID>/` (HUB_ID = ESP32 MAC, no colons)
- `status` retained `online|offline` (LWT) · `info` retained `{"hub","fw","ip","web_port"}` · `state` retained (= /api/state)
- `cmd` ← `{"id","mac","outlet","on"}` or `{"id","action":"refresh"}` · `cmd/ack` → `{"id","ok","error"}`
