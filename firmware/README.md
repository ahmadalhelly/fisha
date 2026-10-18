# Fisha hub firmware

Source: `mttl_hub/mttl_hub.ino` plus the `mttl_hub/hub_*.h` parts it includes in order (CI builds this folder). `hub_protos.h` holds the function prototypes that the Arduino/PlatformIO builder used to generate by itself; when a function is added to or removed from a part, regenerate it (see below). Host tests read the code through `tests/flatten.py`.

## Changelog

### Code split into parts (no behaviour change)
- `mttl_hub.ino` (version, libraries, configuration, includes) + 14 parts `hub_data.h` ... `hub_wifi.h`, cut only at the old section banners. Text order is unchanged, so static initialisation order is unchanged.
- Proof: the code and data sections of the built firmware (`.iram0.text`, `.flash.text`, `.dram0.data`, `.flash.appdesc`) are byte-identical to the build of the single file; the only difference in the whole image is the build time string. The host tests pass unchanged through `tests/flatten.py`.
- Why: one 5300-line file was hard to review. Prototypes: PlatformIO only auto-generates them for functions written in the `.ino` itself, so they are now explicit in `hub_protos.h`.
- Regenerating `hub_protos.h`: `python3 firmware/tools/gen_protos.py` (it runs the PlatformIO prototype regex over the flattened source; `--check` tells if the file is out of date).

### 1.0.4 (not built or flashed yet)
- Diagnostics: the failed-allocation backtrace is 14 frames deep (was 8; `/api/heapdiag` buffer 2300 bytes) so it reaches the code that sends; `wifi_move` shows the last line each non-answering strip sent (`last_rx`). Why: the 1.0.3 data stopped inside lwip `tcp_write` and the strips answer nothing to `up:connect`.
- Child lock and the strip's own master button: the hub now sends the locked outlets back to their saved state the moment the master-button event arrives, instead of after the next `getinfo` answer. Expected effect: the glitch of a locked outlet switching for about half a second gets much shorter. It cannot be removed completely, the strip switches the relay itself. Not verified on a device.

### 1.0.3 (diagnostic build, not built or flashed yet)
- Failed-memory call sites: every refused allocation now records the return addresses of the code that asked (`hub_allocsites.h`, a table of 6 sites: size, task, count, 8 addresses). `GET /api/heapdiag` lists them; turn the addresses into function and line with `addr2line -pfiaC -e firmware.elf <addr...>` (addresses are already moved back onto the call instruction, as in ESP-IDF panic backtraces). The first addresses can still be inside `malloc` / `operator new`; the caller is the first address in hub or library code. `firmware.elf` is a workflow artifact of the CI run (not attached to the release); the cleanup job deletes the artifacts of earlier runs, so download it before the next firmware build, and only the ELF of the exact build on the hub gives the right lines. Why: 1528-byte requests in `loopTask` fail thousands of times and we do not know which line asks.
- `/api/raw` takes an optional `mac=<strip MAC>`: the command goes to that strip (404 when it is not connected). Without `mac` it goes to the first strip as before. Why: to read or test one strip, e.g. the ones that refuse the Wi-Fi move.
- Child lock: the hub now sends the saved lock to strips on firmware F1.0.82 and newer (was exactly F1.0.82; needs a full `F<a>.<b>.<c>` version in the strip's bootinfo). The app still enables the child-lock switch only when the strip firmware contains `F1.0.82` (`app/lib/screens/outlet_sheet.dart`), so on F1.0.85 and later a lock set earlier is kept and re-sent, but it cannot be changed from the app until the app check is updated.
- Host test: `firmware/tests/alloc_sites`. Backtrace calls (`esp_backtrace_get_start` / `esp_backtrace_get_next_frame`) are not compiled on the host; they are verified only by the CI build and on the device.

### 1.0.2 (unreleased, not yet flashed)
- Real per-outlet current: the hub asks each outlet that is on for `up:power_report:<ch>:current` (mA), one request per 6 s poll cycle, only one request in flight per strip. `:power` is never sent (it answers in mW and would look like a voltage). New JSON: per outlet `current_a` + `cur_real`, strip `current_a`, a 6th number in each `live` outlet (A, -1 = none). Old apps ignore them.
- Why it is safe: a reading counts for 45 s and only while the outlet's watts stay within 15 % + 10 W of when it was read. Shown values and rules use it; protections use `max(W/V, lower of the last two readings)`, instant cuts use W/V only. After 3 answers that are not mA the strip is not asked again. Effect: loads with a low power factor (motors, power supplies) can reach an amp limit earlier than before, because real amps are higher than W/V.
- Wi-Fi move from the app: strips are matched by MAC (not socket slot), the confirm window is 40 s with resends (12 s apart, 3 sends, none in the last 10 s), keep-alive during the wait. On failure every strip that was sent the new network is sent the old one again (twice). `/api/health` has `wifi_move` with each strip's result; Events keep `connect_ok` / `missed`. Cause of "5 strips did not take the new network" is not confirmed on a device; if it happens again, send Events and `/api/health`.
- Host test: `firmware/tests/power_report`.

### Owner recovery (unreleased, not yet flashed by the owner's CI build)
- Owner can take the hub back on a new phone: `/api/auth/claim` accepts a phone whose email already owns the hub when the update password is also sent (`ota`). The phone gets a new key and the old key of that email is replaced.
- Wrong update passwords on that route: 5 misses lock it for 5 minutes (`wait`, HTTP 429). Other emails still get `claimed` (409).
- Source comments: version notes from 2.11 to 2.15.x moved out of the file (this changelog holds them). Code is byte-for-byte the same apart from the recovery route.
- Not verified on the device yet. Host test of the route: `firmware/tests/owner_recovery` is not in the repo; the test used during the change lived outside the repo.

### 1.0.1
- Same source and build settings as 2.15.38 (commit 633a68c). Only the version string is new, so the hub version follows the app's 1.x line.
- Left out of this build: `board_build.flash_mode = qio`, `board_build.f_flash = 80000000L`, `board_build.f_cpu = 240000000L` (present in 46c8fa1 and 1.0.0).
- Not verified: whether those three settings caused the memory drop seen on 1.0.0 (heap8_min 2576, alloc_fail 2666). Needs an A/B test.

### 1.0.0 (public launch)
- Same code as 2.15.39; the version restarts at 1.0.0 for the public launch (MAJOR.MINOR.PATCH from here on). Phones must run app 2.0.29 or newer first: its update center orders by build number, so 1.0.0 counts as newer than 2.x, and it treats a three-number 1.x hub as a current hub (older apps hide automations/schedules/energy for any hub starting with "1.").
- CI: also caches `firmware/.pio` (the rebuilt ESP32 libraries took ~13 of the 14 build minutes).

### 2.15.39
- Same code as 2.15.38; only the version changed. The 10-strip build is now the only hub build (CI `build` job compiles `platformio.ini`; the old arduino-cli 6-strip build was removed to save CI minutes). Reason: 2.15.38-10strips held on the device for 11 minutes with the app open: heap8_min 23.2 KB (was ~600 B), alloc_fail 0, sse_cut 0, state_bad 0, mqtt on, no Wi-Fi drops; only one 3.4 s stall at boot ("provision").
- Published bin names stay `fisha-hub-<v>.bin` / `-FULL-flash-0x0.bin`.
- Not measured yet: the memory cost of each extra strip (the reading had 3 strips).

### 2.15.38
- Live updates without cutting: the phones get the full state (~4 KB) only when something besides the numbers changed (names, locks, settings, a strip came or went) and every 15 s; in between, once a second, an SSE `live` event with only each online strip's numbers (`{"ts","d":[{"mac","v","r","up","o":[[on,W,kWh,°C,auto_off_in_s] x4]}]}`, ~170 B a strip). 2.15.37 still cut 36 of 37 streams: each push copied ~4 KB into every phone socket and the hub had ~17 KB of usable memory.
- The state is no longer built as one String: `stateStream` sends the head, then one strip at a time, then `]}` straight into the phone socket (SSE) or the `/api/state` answer (now without Content-Length, ends when the hub closes). With 10 strips the one String would be ~13 KB.
- Cloud (EMQX) state split: `mttl/<hub>/state` (members `.../u/<id>/state`) is a small head with `"strips":[MACs]` instead of `"devices"`; each strip is its own retained message `mttl/<hub>/s/<MAC>` (members `.../u/<id>/s/<MAC>`), sent only when that strip changed (names/locks/on-off/settings at once, load moved >10% after 3 s, else every 60 s). A full send queue only delays a copy (retried until it goes). Strips removed in the app and strips taken from a member are wiped from the server. Before: the whole state on every load change and every 30 s.
- Energy and peak history (90 days, ~2.4 KB per strip) no longer sit in RAM: RAM keeps the running day, the history is read from its file when the day rolls over or the app asks for it (same files, same layout). A file that exists but can't be read is never overwritten. Static RAM 96.8 KB -> 83.5 KB with 6 strips.
- Family members can be given up to 10 strips one by one (was 6). Saved to NVS key `list2`; the old `list` (6 strips) is read once and left untouched so an older firmware still finds its members.
- 10 strips: `MAX_STRIPS` is 10 when the firmware is built with more sockets (`CONFIG_LWIP_MAX_SOCKETS >= 26`, see `platformio.ini`); the stock Arduino build has 16 sockets (the hub uses ~13 at most), so it stays at 6 there. `platformio.ini` (pioarduino 55.03.312 = Arduino core 3.3.12, ESP32 libs rebuilt with 26 sockets and a 4 KB TLS send buffer instead of 16 KB) is built by CI job `build10` as `fisha-hub-<v>-10strips.bin` (private release only); the build stops with `#error` if those settings did not reach the code (`FISHA_REQUIRE_10`). Health shows `max_strips` and `sockets`.
- Needs app 2.0.28 (reads `live` and the split cloud state; older apps keep working locally but update the numbers only every 15 s, and see no strips over the cloud).
- Validation: compiled (stock build); new host test `tests/state_split` (real String class, ASan/UBSan, code copied verbatim from the .ino): stream = old layout piece by piece, members filtered, live/head JSON valid, per-strip publishing incl. full queue, member changes and wipes, 6->10 strips members migration, energy rollover / unreadable file. Mutations of three guarded lines are caught. MQTT queue test passing. App: flutter analyze (no new issues) + unit test for the live merge. Not yet tested on the device.

### 2.15.37
- 2.15.36 fixed the empty state (state_bad 0), but the real free memory still hits ~0 (heap8_min 360) with ~25 refused requests a second from the main loop, some of them network send buffers (caps 0x80c), and nearly every live stream to the phones gets cut (41 of 42). The state was pushed to the phones up to 4 times a second (~4 KB built + copied into every phone socket each time). Now at most once a second.
- Validation: one constant changed; the flag it reads is cleared only there; compiled. Not yet tested on the device.

### 2.15.36
- Cause of the empty state found (2.15.35 data): at the moment the state is built, the usable memory is almost gone (refused request 4128 B = the state growing; free at that instant 9.5 KB, largest piece 3.2 KB; ~2000 refusals in 5 min). The "heap 55 KB / max_alloc 36 KB" in health was misleading: those count IRAM too, which Strings and network buffers can't use. Health now also shows the real numbers: `heap8`, `heap8_max`, `heap8_min`, plus `alloc_fail_task`.
- Less memory per state: the state (owner and family) is reserved once and closed in place instead of being copied whole at the end. Host test with the real String class: the same 4.1 KB state now needs ~8.1 KB free instead of ~12.5 KB, identical text.
- MQTT receive buffer 8 KB -> 2 KB (commands are under 640 B; anything bigger was already refused). Send queue 8 KB -> 6 KB (retained state max 4.5 KB, one at a time).
- Validation: compiled; MQTT queue host test updated to the new caps and passing; builder peak measured on the computer as above. Not yet tested on the device.

### 2.15.35
- Diagnostics only. 2.15.34 showed every piece of the state builds fine on its own (strips ~1.1 KB each, heap ~55 KB free, largest block ~36 KB), yet the whole state keeps coming out empty or as just "]}", and the phone stream is cut almost every time it opens. That pattern means memory requests are being refused at that moment. The hub now registers ESP-IDF's failed-allocation callback, so any refused allocation (Strings, network buffers) is recorded in /api/health: `alloc_fail`, `alloc_fail_ago_s`, `alloc_fail_size`, `alloc_fail_max_size`, `alloc_fail_caps`, `alloc_fail_free`, `alloc_fail_largest`, `alloc_fail_fn`.
- Validation: compiled; checked in the built firmware (disassembly) that String growth goes realloc -> heap_caps_realloc_default -> heap_caps_alloc_failed -> this callback. The callback allocates nothing and only stores numbers.

### 2.15.34
- Diagnostics only. 2.15.33 showed the state the hub builds sometimes comes out EMPTY (state_len 0). That matches the app's "not on the same Wi-Fi": the app's /api/state poll gets an empty answer it can't read, and the server copy is dropped too (mqtt_drop rising). The empty result can't be explained from the code yet (a host test with the real ESP32 String class showed that running out of memory still leaves at least "]}"), so when it happens the hub now records the free heap, the largest free block and the size of every piece of the state built one by one, in /api/health: `state_bad`, `state_bad_ago_s`, `state_bad_info`. Checked on both the live stream and the app's poll.
- Validation: compiled; the record uses a fixed char buffer, worst case (largest numbers, 6 strips + 12 saved strips) tested on the computer under AddressSanitizer: 231 of 240 bytes, no overflow. Re-measured at most every 5 s.

### 2.15.33
- Diagnostics only, no behaviour change. /api/health now shows the live stream to the phones (SSE): `sse_open` streams opened, `sse_cut` streams the hub closed because the phone didn't take the data in time (or sending failed), `sse_cut_ago_s` seconds since the last one, `sse_gone` streams the phone closed, `state_len`/`state_max` size of the state the hub sends. Reason: the app keeps saying "not on the same Wi-Fi" while the hub is fine. Suspected (not proven): the state (~6-7 KB) is bigger than the hub's 5.7 KB send buffer, so a phone that answers slowly (power saving) misses the 80 ms send window and the hub closes the stream. These numbers prove or rule it out before any fix.
- Validation: reviewed every place a stream is closed; compiled; the MQTT queue host test still passes.

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
