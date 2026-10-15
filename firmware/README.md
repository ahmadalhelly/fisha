# Fisha hub firmware

Source: `mttl_hub/mttl_hub.ino` (CI builds this folder).

## Changelog

### 2.15.32
- Corrected the diagnosis of the 2.15.30 crash. The crashing message was not a deliberate empty message: it was a family member's state whose building ran out of memory right after connecting to the server (an Arduino String that runs out of heap comes back empty with no buffer). 2.15.31 would have sent it as an empty retained message, which wipes that member's state on the server. Now such a message is dropped and counted in `mqtt_drop`; a real empty message still goes out.
- The send queue is 8 KB (was 16 KB) to give the heap back, and retained state copies may use only 6 KB of it, so events and command answers always keep room. One state bigger than that still goes out when nothing else is waiting. Queue length 12 -> 48 (a reconnect sends the state, each member's state and up to 12 saved events per member at once).
- Validation: host test `tests/mqtt_queue/run.sh` runs the queue code from this file, verbatim, with the real ESP32 String class under AddressSanitizer/UBSan: empty message, out-of-memory String, ordering, caps with a stuck server, full queue, offline, and a stress run (2 senders + client restarts). The same test crashes on 2.15.30 exactly like the device did and fails on 2.15.31. Not yet tested on the device.

### 2.15.31
- Fixed the crash-and-restart loop of 2.15.30 (Guru Meditation, LoadProhibited in mqttPub). An empty message (the one that clears a family member's retained state on the server) has no text buffer at all, and the new queue copied from that null pointer. Now only real bytes are copied.

### 2.15.30
- Sending to the server (MQTT) no longer runs on the main loop: messages go into a small queue and a separate task hands them to the MQTT client. Reason: when the internet or the server was slow, one send waited 19-21 s for the MQTT client (log: "mqtt_pub 20748 ms"), the whole hub froze, every strip dropped and came back again and again, and the app showed the hub as not on the same Wi-Fi.
- The queue is capped at 16 KB; anything past that is dropped (counted in /api/health as `mqtt_drop`) so a stuck server can't use up the memory.

### 2.15.29
- Strip-level child lock now locks every button on the strip (master + all 4 outlets), not only the master button. The per-outlet locks stay saved and come back when the strip lock is turned off. Reason: with the strip locked, a child could still switch the outlets from their own buttons.

### 2.15.28
- Setup from inside the app: while the hub is in setup mode (Wi-Fi `Fisha-Hub-…`, 192.168.4.1) it now answers `GET /api/setup/info` and `POST /api/setup` (Wi-Fi name + password, LAN IP, owner Gmail, optional own update password). Reason: the customer finishes setup in the app without leaving it; the old 192.168.4.1 page still works.
- First owner can claim only during the first 10 minutes after the hub powers on (`claim_window`). Reason: a hub left unclaimed can't be taken over later by anyone on the network; power-cycling the hub opens the window again.
- A hub with no saved Wi-Fi (new or erased) goes straight to setup mode at boot. Reason: no waiting on a network that doesn't exist.
- Setting up an already-owned hub again needs the owner's phone key or the update password.

### 2.15.27
- Update password: every hub accepts the fixed `fisha-<MAC>` (12 hex digits, upper case, e.g. `fisha-80F3DA40F674`), plus the owner's own password if they set one. No random password any more (it left the owner locked out). Reason: the owner must always be able to recover the hub.
- New owner-only API `ota_pass` (`cur`, `new`): reset or change the update password; an empty `new` puts the default back.
- Wi-Fi move: the hub now moves only when every strip took the new network. Otherwise it stays on the old network and hands the old one back to the strips that answered. Reason: a half-accepted move left strips on a different network than the hub, so all of them showed offline.
- Strip-level child lock: `lock` with `outlet` 0 blocks the strip's own master button (F1.0.82 `up:childlock`, bit 0). The mask is re-sent on every connect and reported as `mlock`. Reason: the app had no way to lock the physical master button.
- `energy_restore`: puts saved daily energy history back (never overwrites days the hub already has), so reports travel with sync and backups.

### 2.15.26
- Roles as the owner sets them: view sees everything, control switches outlets (not overload-protected ones), full admin also gets Wi-Fi, updates, reboot, automations and protections.
- Owner can grant extra permissions per member (automations, protections, strip updates, hub updates, Wi-Fi, export).
- Each member's Google email and photo are kept on the hub for the family page.
- Members with the hub-update permission can update the hub with their phone key.

### 2.15.25
- Changing the hub's Wi-Fi from the app hands the new network to every online strip (up:connect on the normal link, then up:reboot after connect_ok), then the hub moves.
- Strips that do not answer are logged as "wifipush" events; hold the strip button 10 s and the hub relinks it.
- Test endpoint `strip_wifi_test` sends the current network to one strip.

### 2.15.24
- Strip master button with a child-locked outlet on: a press turns the free outlets on instead of doing nothing.

### 2.15.23
- Auto-relink: the hub scans for a known strip's setup network (TONLY_TAP_...) and re-provisions it with the current Wi-Fi.
- Stock strip firmware has no automatic fallback to setup mode; the strip must be put in setup mode by holding its button 10 s.

### 2.15.22
- Strip firmware can be fetched by the hub from a direct link (`/api/stripfw/fetch`), with redirects followed.
- Automation cap raised from 10 to 40, with NVS migration.

### 2.15.21
- Web application removed from the hub (the Fisha app is the only client).

### 2.15.20 (beta)
- No secrets in the code. (Update password: see 2.15.27.)
- The hub server user defaults to `ESP_hub`. The server address and user come from the app (`cloud` command: `host`, `user`, `pass`).
- The owner sets the hub address in the app (`cloud` command: `lip`). The hub checks it is on the home network, saves it, and restarts.
- If the router does not answer on the saved address within a minute of boot, the hub goes back to 192.168.1.100.
- First owner claim needs no password. Later phones are added by pairing (`claimed` 409 otherwise).
- Setup Wi-Fi portal network is open (the fixed `fisha1234` fallback is removed).
- Build flag `WEBSERVER_MAX_HEADER_WAIT=1500` is passed by the workflow (stops 5-11 s freezes while a request header is waited for).

### 2.15.18
- Web request header wait limited to 1.5 s (build flag, see above).

### 2.15.17
- SSE header and heartbeat sent without blocking.

### 2.15.16 and earlier: see git history.

Strip firmware: `strip-fw/comMTTL-W01_F1.0.82.fwr` (stock 1.0.66 with our build changes; not built by CI).
