# Protocols

## Strip setup AP (TONLY_TAP_xxxxxxx, password LGU_xxxxxxx) — TCP 192.168.1.1:30300, CRLF, one command per connection
- `up:ip:<hub-ip>` → `up:ip:ip_ok`
- `up:connect:<ssid>:<password>` → `up:connect:connect_ok` (no `:` allowed). No reboot command: the strip leaves setup mode by itself.

## Strip ⇄ hub — TCP 10086 (the strip dials the hub), CRLF lines
| Dir | Frame |
|---|---|
| strip→hub | `up:bootinfo:lgutap;<mac>;<mac>;<fw>;connect` |
| hub→strip | `up:getinfo:all` (poll every 3 s, also keepalive) |
| strip→hub | `up:getinfo:<ch>:<runtime>;<relay>;<state>;<flagA>;<flagB>;<power mW>;<energy hex Wh>;<prev>;<config>;<status>;<event>;<temp °C>` ×4 |
| hub→strip | `up:onoff:<1-4>:on|off` |
| strip→hub | `up:onoff:<n>:on|off` ack, `up:event:onoff:<0-4>:on|off` physical button |
| hub→strip | `up:power_report:1:vol` → `up:power_report:<ch>:<mV>` · `up:query:wifirssi` → `up:query:<rssi>` |

## Hub v2.0
- HTTP :8080 — `GET /api/state`, `GET /api/health`, `GET /api/raw?cmd=`, `POST /api/<action>` with a flat JSON body → `{"ok","error","data"}`
- Live :8081 — `GET /events` (SSE): `event: state` on every change, `event: event` for alerts, `: hb` every 15 s
- MQTT `mttl/<HUB_ID>/` — `status` (LWT), `info`, `state` (retained), `event`, `cmd` ← `{"id","path":"/api/<action>",...}`, `cmd/ack` → `{"id","ok","error","data"}`

| action | body | stored |
|---|---|---|
| onoff | mac, outlet 0-4, on | — |
| label | mac, outlet 0-4, label | NVS |
| lock / protect | mac, outlet, locked / protected | NVS |
| autooff | mac, outlet, minutes (0 = off) | NVS |
| timer | mac, outlet 0-4, kind on/off/cycle, delay_s, off_s | RAM |
| timer_cancel | tid | — |
| schedule_save / _delete, schedules | sid, mac, outlet, on, days (bit0 = Sun), hh, mm, date yyyymmdd (days = 0), enabled, label | NVS |
| automation_save / _delete, automations | aid, mac, outlet, above, watts, hold_s, act (1 log, 2 off, 3 both), enabled, label | NVS |
| events | — | RAM (last 40) |
| energy | mac → today_wh[4] + 90 daily buckets | NVS |
| config | temp_max, temp_protect | NVS |
| provision | — (state in /api/state: queued → running → waiting → connected / error: no_ap, join_failed, strip_said:…, no_dial) | — |
