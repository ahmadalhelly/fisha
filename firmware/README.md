# Fisha hub firmware

Source: `mttl_hub/mttl_hub.ino` (CI builds this folder).

## Changelog

### 2.15.20 (beta)
- No secrets in the code. The update password is random per hub and kept in NVS.
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
