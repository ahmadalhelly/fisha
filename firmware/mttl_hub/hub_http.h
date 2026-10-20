// Fisha hub: HTTP, browser update, strip firmware flashing, strip updates. Part of mttl_hub.ino, included in order from there.
// ---------- HTTP ----------
int apiUserIdx = -1;

bool authorized() {
  webUri = web.uri() + " " + web.client().remoteIP().toString();
  apiUserIdx = -1;
  apiSrc = 0;
  String tok = web.header("X-Token");
  String uid = web.header("X-User");
  if (!tok.length()) tok = web.arg("t");
  if (!uid.length()) uid = web.arg("u");

  // 1. Shared users local access
  for (int i = 0; i < userCount; i++) {
    if (!users[i].id[0] || !strlen(users[i].pw)) continue;
    if (web.authenticate(users[i].id, users[i].pw)) {
      apiUserIdx = i;
      apiSrc = 2;
      return true;
    }
    if ((!uid.length() || uid == users[i].id) && tok == users[i].pw) {
      apiUserIdx = i;
      apiSrc = 2;
      return true;
    }
  }

  // 2. Owner check. once the hub is locked only an owner phone's key (or, in a browser, admin + the update
  // password) gets in; before that it stays open as it always was.
  if (ownerCount) {
    if (isOwnerKey(tok)) return true;
    if (otaPassOk()) return true;
    return strlen(API_TOKEN) && (tok == API_TOKEN || web.authenticate("hub", API_TOKEN));
  }
  if (!strlen(API_TOKEN)) return true;
  if (tok == API_TOKEN) return true;
  if (web.authenticate("hub", API_TOKEN)) return true;

  return false;
}

bool guard() {
  if (authorized()) return true;
  web.sendHeader("WWW-Authenticate", "Basic realm=\"mttl-hub\"");
  web.send(401, "application/json", "{\"ok\":false,\"error\":\"unauthorized\"}");
  return false;
}

// the state goes out without blocking. A phone that stops reading (screen off, app paused) could hold
// the whole hub inside the web send for seconds, and every strip was then dropped as "socket stuck".
void webJsonNB(const String& body) {
  NetworkClient& c = web.client();
  String h = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: " + String(body.length()) +
             "\r\nConnection: close\r\n\r\n";
  SubT st("web_send");
  if (!sendStr(c, h, 300) || !sendStr(c, body, 1500)) { webSlow++; c.stop(); }
}
void stateBadDiag(uint32_t gotLen);
// streamed piece by piece (see stateStream), so no Content-Length: the body ends when the hub closes the link
void handleState() {
  if (!guard()) return;
  const HubUser* u = (apiSrc == 2 && apiUserIdx >= 0 && apiUserIdx < userCount) ? &users[apiUserIdx] : nullptr;
  NetworkClient& c = web.client();
  SubT st("web_send");
  uint32_t t0 = millis();                       // 1.5 s for the whole body, as before (not per piece)
  bool ok = sendStr(c, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nConnection: close\r\n\r\n", 300) &&
            stateStream(u, [&](const String& p) { uint32_t used = millis() - t0; return used < 1800 && sendStr(c, p, 1800 - used); });
  if (!ok) webSlow++;
  c.stop();
}

int sseCount();
extern uint32_t sseOpened, sseCut, sseGone, sseCutAt, sseStateLen, sseStateMax, stateBadN, stateBadAt;
extern char stateBadBuf[];
extern volatile uint32_t allocFailN, allocFailAt, allocFailSize, allocFailCaps, allocFailFree, allocFailLargest, allocFailMaxSize;
extern const char* volatile allocFailFn;
extern const char* volatile allocFailTask;
extern portMUX_TYPE allocSiteMux;
// how full the settings storage is (a full NVS silently loses saves)
String nvsStatsJson() {
  nvs_stats_t st;
  if (nvs_get_stats(NULL, &st) != ESP_OK) return "";
  return ",\"nvs_used\":" + String(st.used_entries) + ",\"nvs_free\":" + String(st.free_entries) + ",\"nvs_total\":" + String(st.total_entries);
}

void handleHealth() {
  int n = 0;
  for (int i = 0; i < MAX_STRIPS; i++) if (strips[i].used && strips[i].identified) n++;
  web.send(200, "application/json", "{\"status\":\"ok\",\"fw\":\"" + String(FW_VERSION) + "\",\"hub\":\"" + hubId + "\",\"mqtt\":" +
           (mqttUp ? "true" : "false") + ",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"strips\":" + String(n) +
           ",\"uptime_s\":" + String(millis() / 1000) + ",\"lock\":" + (ownerCount ? "true" : "false") + ",\"heap\":" + String(ESP.getFreeHeap()) + ",\"max_alloc\":" + String(ESP.getMaxAllocHeap()) +
           ",\"heap_min\":" + String(ESP.getMinFreeHeap()) + ",\"mqtt_drop\":" + String(mqttOutDropped) + ",\"sse\":" + String(sseCount()) + ",\"sse_open\":" + String(sseOpened) +
           ",\"sse_cut\":" + String(sseCut) + ",\"sse_cut_ago_s\":" + (sseCut ? String((millis() - sseCutAt) / 1000) : String("-1")) +
           ",\"sse_gone\":" + String(sseGone) + ",\"state_len\":" + String(sseStateLen) + ",\"state_max\":" + String(sseStateMax) +
           ",\"state_bad\":" + String(stateBadN) + ",\"state_bad_ago_s\":" + (stateBadN ? String((millis() - stateBadAt) / 1000) : String("-1")) +
           ",\"state_bad_info\":\"" + String(stateBadBuf) + "\"" +
           ",\"alloc_fail\":" + String(allocFailN) + ",\"alloc_fail_ago_s\":" + (allocFailN ? String((millis() - allocFailAt) / 1000) : String("-1")) +
           ",\"alloc_fail_size\":" + String(allocFailSize) + ",\"alloc_fail_max_size\":" + String(allocFailMaxSize) +
           ",\"alloc_fail_caps\":\"" + String(allocFailCaps, HEX) + "\",\"alloc_fail_free\":" + String(allocFailFree) +
           ",\"alloc_fail_largest\":" + String(allocFailLargest) + ",\"alloc_fail_fn\":\"" + String((const char*)allocFailFn) + "\",\"alloc_fail_task\":\"" + String((const char*)allocFailTask) + "\"" +
           // "heap"/"max_alloc"/"heap_min" count IRAM too, which Strings and network buffers can't use; these are the real numbers
           ",\"max_strips\":" + String(MAX_STRIPS) + ",\"sockets\":" + String(CONFIG_LWIP_MAX_SOCKETS) +
           ",\"heap8\":" + String(heap_caps_get_free_size(MALLOC_CAP_8BIT)) + ",\"heap8_max\":" + String(heap_caps_get_largest_free_block(MALLOC_CAP_8BIT)) +
           ",\"heap8_min\":" + String(heap_caps_get_minimum_free_size(MALLOC_CAP_8BIT)) +
           ",\"wifi_drops\":" + String(wifiDiscCount) + ",\"wifi_reason\":" + String(wifiLastReason) +
           ",\"stall_max_ms\":" + String(stallMaxMs) + ",\"stall_where\":\"" + String(stallWhere) + "\",\"stall_sub\":\"" + String(subWorstWhere) + " " + String(subWorst) + " ms\",\"web_slow\":" + String(webSlow) + ",\"wifi_move\":\"" + jsonEsc(wifiMoveInfo) + "\"" + nvsStatsJson() + ",\"fs\":" + (fsOk ? "true" : "false") +
           ",\"reset\":\"" + resetText() + "\",\"job\":" + String((int)exJob.state) + ",\"wifi_rssi\":" + String(WiFi.RSSI()) + "}");
}

// the call sites of the refused memory requests (see hub_allocsites.h), in a fixed buffer so the answer itself needs no allocation.
// Each pc is a code address: addr2line -pfiaC -e firmware.elf <pc...> gives the function and line.
void handleHeapDiag() {
  if (!guard()) return;
  static char buf[2300];
  AllocSite snap[ALLOC_SITES];
  uint32_t other, now = millis();
  portENTER_CRITICAL(&allocSiteMux);
  memcpy(snap, allocSites, sizeof snap);
  other = allocSiteOther;
  portEXIT_CRITICAL(&allocSiteMux);
  int n = snprintf(buf, sizeof buf, "{\"alloc_fail\":%u,\"other\":%u,\"heap8\":%u,\"heap8_max\":%u,\"sites\":[",
                   (unsigned)allocFailN, (unsigned)other, (unsigned)heap_caps_get_free_size(MALLOC_CAP_8BIT),
                   (unsigned)heap_caps_get_largest_free_block(MALLOC_CAP_8BIT));
  bool first = true;
  for (int i = 0; i < ALLOC_SITES; i++) {
    if (!snap[i].key) continue;
    if (n > (int)sizeof buf - 340) break;
    n += snprintf(buf + n, sizeof buf - n, "%s{\"n\":%u,\"size\":%u,\"task\":\"%s\",\"ago_s\":%u,\"pc\":[", first ? "" : ",",
                  (unsigned)snap[i].n, (unsigned)snap[i].size, snap[i].task, (unsigned)((now - snap[i].last) / 1000));
    first = false;
    for (uint8_t k = 0; k < snap[i].depth; k++) n += snprintf(buf + n, sizeof buf - n, "%s\"0x%08x\"", k ? "," : "", (unsigned)snap[i].pc[k]);
    n += snprintf(buf + n, sizeof buf - n, "]}");
  }
  n += snprintf(buf + n, sizeof buf - n, "]}");
  if (n >= (int)sizeof buf) n = sizeof buf - 1;
  NetworkClient& c = web.client();
  char h[120];
  int hn = snprintf(h, sizeof h, "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: %d\r\nConnection: close\r\n\r\n", n);
  if (!sendNB(c, h, hn, 300) || !sendNB(c, buf, n, 1500)) { webSlow++; c.stop(); }
}

// optional &mac=<strip MAC> sends to that strip (404 if it is not connected); without it, to the first strip as before
void handleRaw() {
  if (!guard()) return;
  if (apiSrc == 2) { web.send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden\"}"); return; }
  String cmd = web.arg("cmd");
  cmd.trim();
  String mac = web.arg("mac");
  mac.trim();
  int i = mac.length() ? findStrip(mac) : firstStrip();
  if (!cmd.startsWith("up:") || (i < 0 && !mac.length())) { web.send(400, "application/json", "{\"ok\":false}"); return; }
  if (i < 0) { web.send(404, "application/json", "{\"ok\":false,\"error\":\"no such strip\"}"); return; }
  sendLine(strips[i], cmd);
  pumpFor(1500);
  web.send(200, "application/json", "{\"sent\":\"" + jsonEsc(cmd) + "\",\"mac\":\"" + jsonEsc(strips[i].mac) + "\",\"last_rx\":\"" + jsonEsc(strips[i].lastLine) + "\"}");
}

void handleOther() {
  webUri = web.uri() + " " + web.client().remoteIP().toString();
  if (web.method() == HTTP_POST && (web.uri() == "/api/auth/claim" || web.uri().startsWith("/api/pair/"))) return authRoute(web.uri(), web.arg("plain"));
  if (web.method() == HTTP_POST && web.uri().startsWith("/api/")) {
    if (!guard()) return;
    ApiRes r;
    if (apiSrc == 2 && apiUserIdx >= 0 && apiUserIdx < userCount) {
      r = userApi(users[apiUserIdx], web.uri(), web.arg("plain"));
    } else {
      apiSrc = 0;
      r = api(web.uri(), web.arg("plain"));
    }
    stateDirty = true;
    web.send(r.ok ? 200 : 400, "application/json", apiJson(r));
    return;
  }
  web.send(404, "application/json", "{\"ok\":false,\"error\":\"not found\"}");
}

// the built-in browser page and the web-app launcher are gone; the Fisha app is the only client.
// "/" answers with one plain line (no data), so a browser pointed at the hub's IP still gets a sane reply.
void handleRoot() { web.send(200, "text/plain; charset=utf-8", "Fisha Hub v" + String(FW_VERSION) + " - open the Fisha app"); }

// ---------- firmware update from the browser / curl (no inbound port needed on the PC) ----------
bool authorized();
bool otaPassOk() {
  if (web.authenticate("admin", secOta.c_str())) return true;
  String d = defOta();
  if (web.authenticate("admin", d.c_str())) return true;
  d.setCharAt(0, 'F');
  return web.authenticate("admin", d.c_str());
}
bool otaAuth() {
  if (otaPassOk()) return true;
  // admins and members allowed to update the hub use their phone key instead of the update password
  return authorized() && apiSrc == 2 && apiUserIdx >= 0 && apiUserIdx < userCount &&
         (users[apiUserIdx].role >= 2 || (users[apiUserIdx].rsv & P_HUBFW));
}
void handleUpdatePage() {
  if (!otaAuth()) return web.requestAuthentication();
  web.send(200, "text/html; charset=utf-8",
           "<meta name=viewport content='width=device-width,initial-scale=1'><body style='font-family:sans-serif;background:#0d1117;color:#e8edf3;padding:20px'>"
           "<h3>Fisha Hub v" + String(FW_VERSION) + " &mdash; firmware update</h3>"
           "<form method=POST action=/update enctype=multipart/form-data><input type=file name=f accept=.bin><br><br>"
           "<button style='padding:12px 20px'>Upload</button></form></body>");
}
void handleUpdateDone() {
  if (!otaAuth()) return web.requestAuthentication();
  bool ok = !Update.hasError();
  web.send(ok ? 200 : 500, "text/plain", ok ? "OK - rebooting\n" : String("FAILED: ") + Update.errorString() + "\n");
  if (ok) { delay(600); ESP.restart(); }
}
void handleUpdateUpload() {
  if (!otaAuth()) return;
  HTTPUpload& u = web.upload();
  if (u.status == UPLOAD_FILE_START) {
    Serial.printf("[ota-web] %s\n", u.filename.c_str());
    if (!Update.begin(UPDATE_SIZE_UNKNOWN)) Update.printError(Serial);
  } else if (u.status == UPLOAD_FILE_WRITE) {
    if (Update.write(u.buf, u.currentSize) != u.currentSize) Update.printError(Serial);
  } else if (u.status == UPLOAD_FILE_END) {
    if (Update.end(true)) Serial.printf("[ota-web] done %u bytes\n", u.totalSize); else Update.printError(Serial);
  } else if (u.status == UPLOAD_FILE_ABORTED) {
    Update.abort();
  }
}

// ---------- strip firmware flashing (/stripfw) ----------
uint32_t stripFwWritten = 0;
bool stripFwErr = false;
bool stripFwUploadRejected = false;
volatile bool suFetchRunning = false;
static TaskHandle_t suFetchTaskHandle = nullptr;
static String suFetchUrl;
void handleStripFwPage() {
  if (!otaAuth()) return web.requestAuthentication();
  String h = "<meta name=viewport content='width=device-width,initial-scale=1'><meta charset=utf-8>"
             "<body style='font-family:sans-serif;background:#0d1117;color:#e8edf3;padding:20px'>"
             "<h3>Fisha Hub v" + String(FW_VERSION) + " &mdash; strip firmware</h3>"
             "<p>Stored .fwr: <b>" + (stripFwSize ? String(stripFwSize) + " bytes" : String("none")) + "</b>" +
             (stripFwWhy.length() ? " &mdash; refused: " + stripFwWhy : String("")) + "</p>"
             "<form method=POST action=/stripfw enctype=multipart/form-data><input type=file name=f accept=.fwr,.bin> "
             "<button style='padding:10px 16px'>1) Upload .fwr</button></form><hr>"
             "<form method=POST action=/stripfw/flash>Strip in setup mode (Wi-Fi name): "
             "<input name=ssid placeholder=TONLY_TAP_91778E8 style='padding:8px'> "
             "<button style='padding:10px 16px'>2) Flash</button></form>"
             "<p>State: <b>" + provState + "</b> " + provMsg + "</p><pre style='white-space:pre-wrap'>" + stripOtaLog + "</pre>"
             + String((provState == "running" || provState == "queued" || suRunning()) ? "<script>setTimeout(()=>location.reload(),5000)</script>" : "");
  // connected strips, updated over their normal connection (no button press)
  h += "<hr><h4>Update connected strips</h4><form method=POST action=/stripfw/live>"
       "<label><input type=checkbox onclick=\"for(const c of document.querySelectorAll('.sm'))c.checked=this.checked\"> <b>Select all</b></label><br>";
  for (int i = 0; i < MAX_STRIPS; i++) {
    const Strip& st = strips[i];
    if (!st.used || !st.identified) continue;
    h += "<label><input type=checkbox class=sm name=mac value=" + st.mac + "> " + (st.label.length() ? st.label : String("Strip")) + " &middot; " + st.mac +
         " &middot; fw " + st.fw + "</label><br>";
  }
  h += "<button style='padding:10px 16px;margin-top:8px'" + String(stripFwOk && !suRunning() ? "" : " disabled") + ">Update selected</button></form><pre>";
  for (uint8_t k = 0; k < suN; k++)
    h += suList[k].mac + "  " + suList[k].state + (suList[k].from.length() ? "  " + suList[k].from : String("")) +
         (suList[k].to.length() ? " -> " + suList[k].to : String("")) + (suList[k].msg.length() ? "  " + suList[k].msg : String("")) + "\n";
  h += "</pre></body>";
  web.send(200, "text/html; charset=utf-8", h);
}
// an MTTL-W01 .fwr is a 16-byte plain header (body length, load address 0x10006000) and a body XOR'd
// with a 16-byte key (the padding rows give it away); the last 4 decoded bytes are the sum of everything before.
bool stripFwCheck(uint32_t size, String& why) {
  const esp_partition_t* part = stripFwPart();
  uint32_t h[4];
  if (!part || size < 64 * 1024 || esp_partition_read(part, 0, h, 16) != ESP_OK) { why = "file too small"; return false; }
  if (h[1] != 0x10006000 || h[0] + 20 != size) { why = "not an MTTL-W01 firmware (header)"; return false; }
  // most common 16-byte row = the XOR key (Misra-Gries, 8 slots)
  static uint8_t cand[8][16];
  uint16_t cnt[8] = {0};
  static uint8_t buf[1024];
  uint32_t end = size - 4;
  for (uint32_t off = 16; off + 16 <= end; off += sizeof buf) {
    uint32_t n = min((uint32_t)sizeof buf, (end - off) & ~15u);
    if (!n || esp_partition_read(part, off, buf, n) != ESP_OK) break;
    for (uint32_t r = 0; r < n; r += 16) {
      int hit = -1, empty = -1;
      for (int k = 0; k < 8; k++) {
        if (cnt[k] && !memcmp(cand[k], buf + r, 16)) { hit = k; break; }
        if (!cnt[k] && empty < 0) empty = k;
      }
      if (hit >= 0) cnt[hit]++;
      else if (empty >= 0) { memcpy(cand[empty], buf + r, 16); cnt[empty] = 1; }
      else for (int k = 0; k < 8; k++) cnt[k]--;
    }
    esp_task_wdt_reset();
  }
  int best = 0;
  for (int k = 1; k < 8; k++) if (cnt[k] > cnt[best]) best = k;
  const uint8_t* key = cand[best];
  uint32_t sum = 0;
  const uint8_t* hb = (const uint8_t*)h;
  for (int i = 0; i < 16; i++) sum += hb[i];
  for (uint32_t off = 16; off < end; off += sizeof buf) {
    uint32_t n = min((uint32_t)sizeof buf, end - off);
    if (esp_partition_read(part, off, buf, n) != ESP_OK) { why = "flash read failed"; return false; }
    for (uint32_t i = 0; i < n; i++) sum += buf[i] ^ key[(off + i) & 15];
    esp_task_wdt_reset();
  }
  uint8_t t[4];
  if (esp_partition_read(part, end, t, 4) != ESP_OK) { why = "flash read failed"; return false; }
  uint32_t stored = 0;
  for (int i = 0; i < 4; i++) stored |= (uint32_t)(t[i] ^ key[(end + i) & 15]) << (8 * i);
  if (stored != sum) { why = "checksum does not match (damaged file)"; return false; }
  return true;
}
// keeps the upload (already written to the spare slot) only if it is a valid strip firmware
bool stripFwStore(String& why) {
  if (stripFwErr || !stripFwWritten) { why = "upload failed (file empty or larger than 384 KB)"; stripFwSize = 0; }
  else if (!stripFwCheck(stripFwWritten, why)) stripFwSize = 0;
  else stripFwSize = stripFwWritten;
  stripFwOk = stripFwSize > 0;
  stripFwWhy = stripFwOk ? "" : why;
  Preferences p;
  p.begin("stripfw", false);
  p.putUInt("size", stripFwSize);
  p.end();
  Serial.printf("[strip-ota] stored %u bytes%s\n", stripFwSize, stripFwOk ? "" : (" (refused: " + why + ")").c_str());
  return stripFwOk;
}
void handleStripFwDone() {
  if (!otaAuth()) return web.requestAuthentication();
  if (stripFwUploadRejected || suFetchRunning) {
    stripFwUploadRejected = false;
    web.send(409, "text/plain", "busy\n");
    return;
  }
  String why;
  if (!stripFwStore(why)) { web.send(400, "text/plain", "REFUSED: " + why + "\n"); return; }
  web.sendHeader("Location", "/stripfw");
  web.send(303, "text/plain", "OK " + String(stripFwSize) + " bytes\n");
}
void stripFwChunk(HTTPUpload& u) {
  static uint32_t erasedUpTo = 0;
  const esp_partition_t* part = stripFwPart();
  if (u.status == UPLOAD_FILE_START) {
    stripFwWritten = 0;
    erasedUpTo = 0;
    stripFwErr = !part || part->size < STRIP_FW_MAX;
    Serial.printf("[strip-ota] upload %s%s\n", u.filename.c_str(), stripFwErr ? " (no spare slot)" : "");
  } else if (u.status == UPLOAD_FILE_WRITE && !stripFwErr) {
    if (stripFwWritten + u.currentSize > STRIP_FW_MAX) { stripFwErr = true; return; }
    const uint32_t eraseTo = min(STRIP_FW_MAX, (stripFwWritten + u.currentSize + 4095u) & ~4095u);
    while (erasedUpTo < eraseTo) {
      if (!part || esp_partition_erase_range(part, erasedUpTo, 4096) != ESP_OK) { stripFwErr = true; return; }
      erasedUpTo += 4096;
      esp_task_wdt_reset();
    }
    if (esp_partition_write(part, stripFwWritten, u.buf, u.currentSize) != ESP_OK) { stripFwErr = true; return; }
    stripFwWritten += u.currentSize;
  } else if (u.status == UPLOAD_FILE_ABORTED) {
    stripFwErr = true;
  }
}
void handleStripFwUpload() {
  if (!otaAuth()) return;
  if (web.upload().status == UPLOAD_FILE_START) stripFwUploadRejected = suFetchRunning;
  if (stripFwUploadRejected) return;
  stripFwChunk(web.upload());
}
void handleStripFwFlash() {
  if (!otaAuth()) return web.requestAuthentication();
  String ssid = web.arg("ssid");
  ssid.trim();
  if (!stripFwSize) { web.send(400, "text/plain", "upload the .fwr first\n"); return; }
  if (!ssid.startsWith("TONLY_TAP_") && !ssid.startsWith("ONLY_TAP_")) { web.send(400, "text/plain", "ssid must be TONLY_TAP_...\n"); return; }
  if (provState == "running" || provState == "waiting" || provRequested || suRunning()) { web.send(409, "text/plain", "busy\n"); return; }
  stripOtaLog = "";
  provOta = true;
  provSsid = ssid;
  requestProvision();
  web.sendHeader("Location", "/stripfw");
  web.send(303, "text/plain", "started: the hub leaves the home Wi-Fi for up to 2 minutes\n");
}

// ---------- update strips over their normal hub connection ----------
// Stock 1.0.66 takes "up:ota:<host>" on the hub connection too (verified 2026-10-10): it answers ota_ok, fetches
// http://<host>/ota.bin on port 80, flashes and reboots. Same command as the setup-mode flasher, no protocol change.
// One strip at a time: wait for its GET, stream the stored .fwr without blocking the loop, wait for it to dial
// back in and compare the fw in its bootinfo. The first failure stops the run.
bool suRunning() { return suPhase != SU_IDLE; }

void suStop(bool failed, const String& msg) {
  SuItem& it = suList[suCur];
  if (failed) {
    it.state = "failed"; it.msg = msg;
    addEvent("strip_fw_fail", it.mac, 0, msg);
    for (uint8_t k = suCur + 1; k < suN; k++) if (suList[k].state == "queued") suList[k].state = "skipped";
  }
  if (suCli) suCli.stop();
  suSrv.end();
  suPhase = SU_IDLE;
  stateDirty = true;
  Serial.printf("[strip-upd] stopped%s %s\n", failed ? " (failed)" : "", msg.c_str());
}

void suNext() {
  while (suCur < suN && suList[suCur].state != "queued") suCur++;
  if (suCur >= suN || suCancel) {
    for (uint8_t k = 0; k < suN; k++) if (suList[k].state == "queued") suList[k].state = "skipped";
    suSrv.end();
    suPhase = SU_IDLE;
    stateDirty = true;
    return;
  }
  suPhase = SU_SEND;
}

void suTick() {
  if (suPhase == SU_IDLE) return;
  SuItem& it = suList[suCur];
  int i = findStrip(it.mac);
  switch (suPhase) {
    case SU_SEND: {
      if (i < 0) { suStop(true, "strip offline"); return; }
      it.from = strips[i].fw;
      it.state = "sending";
      suSrv.begin();                   // listening before the command: the strip dials :80 right after ota_ok
      suSrv.setNoDelay(true);
      String cmd = "up:ota:" + WiFi.localIP().toString();
      sendLine(strips[i], cmd);
      Serial.printf("[strip-upd] %s (fw %s) << %s\n", it.mac.c_str(), it.from.c_str(), cmd.c_str());
      suT0 = millis();
      suPhase = SU_GET;
      stateDirty = true;
      return;
    }
    case SU_GET: {
      if (!suCli) {
        suCli = suSrv.accept();
        if (suCli) { suReq = ""; suReqAt = millis(); }
      }
      if (suCli) {
        while (suCli.available() && suReq.length() < 512) suReq += (char)suCli.read();
        if (suReq.indexOf("\r\n\r\n") >= 0) {
          String first = suReq.substring(0, suReq.indexOf('\r'));
          Serial.printf("[strip-upd] request from %s: %s\n", suCli.remoteIP().toString().c_str(), first.c_str());
          if (first.startsWith("GET ") && first.indexOf("/ota.bin") > 0) {
            suCli.setNoDelay(true);
            suCli.print("HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: " + String(stripFwSize) +
                        "\r\nConnection: close\r\n\r\n");
            suOff = 0; suBufLen = suBufPos = 0; suT0 = millis();
            it.state = "transfer";
            suPhase = SU_XFER;
            stateDirty = true;
            return;
          }
          suCli.print("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
          suCli.stop();
        } else if (millis() - suReqAt > 5000 || !suCli.connected()) {
          suCli.stop();
        }
      }
      if (millis() - suT0 > 60000) {
        String last = i >= 0 ? strips[i].lastLine : String("");
        suStop(true, "the strip did not ask for the file" + (last.length() ? " (last: " + last + ")" : String("")));
      }
      return;
    }
    case SU_XFER: {
      const esp_partition_t* part = stripFwPart();
      uint32_t t = millis();
      while (millis() - t < 30) {
        if (suBufPos >= suBufLen) {
          if (suOff >= stripFwSize) break;
          uint32_t n = min((uint32_t)sizeof suBuf, stripFwSize - suOff);
          if (!part || esp_partition_read(part, suOff, suBuf, n) != ESP_OK) { suStop(true, "flash read failed"); return; }
          suBufLen = n; suBufPos = 0; suOff += n;
        }
        int w = sendSome(suCli, (const char*)suBuf + suBufPos, suBufLen - suBufPos, 0);
        if (w < 0) { suStop(true, "connection lost at " + String((suOff - suBufLen + suBufPos) * 100 / stripFwSize) + "%"); return; }
        if (w == 0) break;             // socket full; next loop pass
        suBufPos += w;
      }
      if (suOff >= stripFwSize && suBufPos >= suBufLen) {
        suDoneAt = millis();
        it.state = "rebooting";
        suPhase = SU_BACK;
        stateDirty = true;
        Serial.printf("[strip-upd] %s: sent %u bytes in %u s\n", it.mac.c_str(), stripFwSize, (suDoneAt - suT0) / 1000);
      } else if (millis() - suT0 > 150000) {
        suStop(true, "transfer too slow");
      }
      return;
    }
    case SU_BACK: {
      if (suCli && millis() - suDoneAt > 1500) { suCli.stop(); suSrv.end(); }
      if (i >= 0 && (int32_t)(strips[i].connectedAt - suDoneAt) > 0 && strips[i].fw.length()) {
        it.to = strips[i].fw;
        if (it.to == it.from) { suStop(true, "came back on the same version " + it.from); return; }
        it.state = "ok";
        addEvent("strip_fw", it.mac, 0, it.from + " → " + it.to);
        suT0 = millis();
        suPhase = SU_GAP;
        stateDirty = true;
      } else if (millis() - suDoneAt > 240000) {
        suStop(true, "the strip did not come back within 4 minutes");
      }
      return;
    }
    case SU_GAP:
      if (millis() - suT0 > 3000) { suCur++; suNext(); }
      return;
    default:
      return;
  }
}

// starts a run; macs = the strips to update in order. Returns "" or an error.
String suStart(const String* macs, int n) {
  if (!stripFwSize || !stripFwOk) return "no valid strip firmware stored";
  if (suRunning() || provRequested || provState == "running" || provState == "waiting") return "busy";
  if (n <= 0) return "no strip selected";
  suN = 0;
  for (int k = 0; k < n && suN < MAX_STRIPS; k++) {
    String m = macs[k]; m.trim(); m.toUpperCase();
    if (findStrip(m) < 0) return "strip " + m + " is offline";
    bool dup = false;
    for (uint8_t j = 0; j < suN; j++) dup |= suList[j].mac == m;
    if (dup) continue;
    suList[suN] = SuItem();
    suList[suN].mac = m; suList[suN].state = "queued";
    suN++;
  }
  suCur = 0; suCancel = false;
  suNext();
  return "";
}

String suJson() {
  String j = "{\"size\":" + String(stripFwSize) + ",\"valid\":" + (stripFwOk ? "true" : "false") + ",\"why\":\"" + jsonEsc(stripFwWhy) +
             "\",\"fetching\":" + (suFetchRunning ? "true" : "false") + ",\"running\":" + (suRunning() ? "true" : "false") + ",\"items\":[";
  for (uint8_t k = 0; k < suN; k++) {
    const SuItem& it = suList[k];
    int pct = it.state == "transfer" && stripFwSize ? (int)((uint64_t)suOff * 100 / stripFwSize) : (it.state == "ok" || it.state == "rebooting" ? 100 : 0);
    if (k) j += ",";
    j += "{\"mac\":\"" + it.mac + "\",\"from\":\"" + jsonEsc(it.from) + "\",\"to\":\"" + jsonEsc(it.to) + "\",\"state\":\"" + it.state +
         "\",\"msg\":\"" + jsonEsc(it.msg) + "\",\"pct\":" + String(pct) + "}";
  }
  return j + "]}";
}

// strip updates are open to admins and members the owner allowed to update strips
bool sfwOnly() {
  if (!guard()) return false;
  if (apiSrc == 2 && !(apiUserIdx >= 0 && apiUserIdx < userCount && users[apiUserIdx].all &&
                       (users[apiUserIdx].role >= 2 || (users[apiUserIdx].rsv & P_SFW)))) {
    web.send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden\"}");
    return false;
  }
  return true;
}
bool ownerOnly() {
  if (!guard()) return false;
  if (apiSrc == 2) { web.send(403, "application/json", "{\"ok\":false,\"error\":\"forbidden\"}"); return false; }
  return true;
}
void handleSuState() {
  if (!sfwOnly()) return;
  web.send(200, "application/json", suJson());
}
// body {"macs":["88D039...", ...]}
void handleSuStart() {
  if (!sfwOnly()) return;
  String b = web.arg("plain");
  String macs[MAX_STRIPS];
  int n = 0, at = b.indexOf("\"macs\"");
  int lb = at >= 0 ? b.indexOf('[', at) : -1, rb = lb >= 0 ? b.indexOf(']', lb) : -1;
  for (int q = lb; q >= 0 && q < rb && n < MAX_STRIPS;) {
    int a = b.indexOf('"', q + 1);
    if (a < 0 || a > rb) break;
    int e = b.indexOf('"', a + 1);
    if (e < 0 || e > rb) break;
    macs[n++] = b.substring(a + 1, e);
    q = e;
  }
  String err = suStart(macs, n);
  if (err.length()) { web.send(400, "application/json", "{\"ok\":false,\"error\":\"" + jsonEsc(err) + "\"}"); return; }
  web.send(200, "application/json", suJson());
}
void handleSuCancel() {
  if (!sfwOnly()) return;
  suCancel = true;                     // the strip in progress finishes; the rest are skipped
  web.send(200, "application/json", suJson());
}
bool suUploadAuth = false;
void handleSuUpload() {
  HTTPUpload& u = web.upload();
  if (u.status == UPLOAD_FILE_START) {
    suUploadAuth = authorized() && (apiSrc != 2 || (apiUserIdx >= 0 && apiUserIdx < userCount &&
        users[apiUserIdx].all && (users[apiUserIdx].role >= 2 || (users[apiUserIdx].rsv & P_SFW))));
    stripFwUploadRejected = !suUploadAuth || suRunning() || suFetchRunning;
  }
  if (stripFwUploadRejected) return;
  stripFwChunk(u);
}
void handleSuUploadDone() {
  if (!sfwOnly()) return;
  if (stripFwUploadRejected || suRunning() || suFetchRunning) {
    stripFwUploadRejected = false;
    web.send(409, "application/json", "{\"ok\":false,\"error\":\"busy\"}");
    return;
  }
  String why;
  if (!stripFwStore(why)) { web.send(400, "application/json", "{\"ok\":false,\"error\":\"" + jsonEsc(why) + "\"}"); return; }
  web.send(200, "application/json", suJson());
}
// the hub fetches the .fwr itself over HTTP(S), so the file never passes through the phone. Reuses the
// same spare slot and validation (stripFwCheck) as a phone upload — only where the bytes come from differs.
bool stripFwFetch(const String& url, String& why) {
  const esp_partition_t* part = stripFwPart();
  if (!part || part->size < STRIP_FW_MAX) { why = "no spare slot"; return false; }
  bool https = url.startsWith("https://");
  if (!https && !url.startsWith("http://")) { why = "url must start with http:// or https://"; return false; }
  WiFiClientSecure sc;
  WiFiClient pc;
  HTTPClient http;
  http.setConnectTimeout(8000);
  http.setTimeout(15000);
  // GitHub release links answer 302 to their file server; follow it.
  http.setFollowRedirects(HTTPC_STRICT_FOLLOW_REDIRECTS);
  bool ok = https ? (sc.setInsecure(), http.begin(sc, url)) : http.begin(pc, url);
  if (!ok) { why = "could not open the url"; return false; }
  int code = http.GET();
  if (code != 200) { why = "server replied " + String(code); http.end(); return false; }
  int len = http.getSize();
  if (len <= 0 || (uint32_t)len > STRIP_FW_MAX) { why = "file too big or unknown size"; http.end(); return false; }
  WiFiClient* stream = http.getStreamPtr();
  uint8_t buf[1024];
  uint32_t written = 0, erasedUpTo = 0;
  uint32_t lastByte = millis();
  while (http.connected() && written < (uint32_t)len && millis() - lastByte < 15000) {
    size_t avail = stream->available();
    if (!avail) { delay(5); esp_task_wdt_reset(); continue; }
    size_t n = stream->readBytes(buf, min(avail, sizeof buf));
    if (!n) break;
    const uint32_t eraseTo = min(STRIP_FW_MAX, (written + n + 4095u) & ~4095u);
    while (erasedUpTo < eraseTo) {
      if (esp_partition_erase_range(part, erasedUpTo, 4096) != ESP_OK) { why = "flash erase failed"; http.end(); return false; }
      erasedUpTo += 4096;
      esp_task_wdt_reset();
    }
    if (esp_partition_write(part, written, buf, n) != ESP_OK) { why = "flash write failed"; http.end(); return false; }
    written += n;
    lastByte = millis();
    esp_task_wdt_reset();
  }
  http.end();
  if (written != (uint32_t)len) { why = "download incomplete (" + String(written) + "/" + String(len) + " bytes)"; return false; }
  stripFwWritten = written;
  stripFwErr = false;
  return stripFwStore(why);
}
static void suFetchTask(void*) {
  const String url = suFetchUrl;
  String why;
  stripFwWritten = 0;
  stripFwErr = false;
  stripFwSize = 0;
  stripFwOk = false;
  stripFwWhy = "";
  Preferences p;
  p.begin("stripfw", false);
  p.putUInt("size", 0);
  p.end();

  const bool ok = stripFwFetch(url, why);
  if (!ok) {
    stripFwSize = 0;
    stripFwOk = false;
    stripFwWhy = why;
    p.begin("stripfw", false);
    p.putUInt("size", 0);
    p.end();
  }
  suFetchUrl = "";
  tlsBusy = false;
  suFetchRunning = false;
  suFetchTaskHandle = nullptr;
  vTaskDelete(nullptr);
}
void handleSuFetch() {
  if (!sfwOnly()) return;
  if (suRunning()) { web.send(409, "application/json", "{\"ok\":false,\"error\":\"busy\"}"); return; }
  if (suFetchRunning || tlsBusy) { web.send(409, "application/json", "{\"ok\":false,\"error\":\"busy\"}"); return; }
  String b = web.arg("plain");
  int at = b.indexOf("\"url\"");
  int a = at >= 0 ? b.indexOf('"', b.indexOf(':', at) + 1) : -1;
  int e = a >= 0 ? b.indexOf('"', a + 1) : -1;
  String url = a >= 0 && e > a ? b.substring(a + 1, e) : "";
  if (!url.length()) { web.send(400, "application/json", "{\"ok\":false,\"error\":\"no url\"}"); return; }
  suFetchUrl = url;
  suFetchRunning = true;
  tlsBusy = true;
  if (xTaskCreatePinnedToCore(suFetchTask, "strip_fetch", 14336, nullptr, 1, &suFetchTaskHandle, 0) != pdPASS) {
    suFetchRunning = false;
    tlsBusy = false;
    suFetchUrl = "";
    web.send(503, "application/json", "{\"ok\":false,\"error\":\"could not start download\"}");
    return;
  }
  web.send(200, "application/json", suJson());
}
// form on /stripfw: mac=...&mac=... (checkboxes)
void handleSuForm() {
  if (!otaAuth()) return web.requestAuthentication();
  String macs[MAX_STRIPS];
  int n = 0;
  for (int k = 0; k < web.args() && n < MAX_STRIPS; k++) if (web.argName(k) == "mac") macs[n++] = web.arg(k);
  String err = suStart(macs, n);
  if (err.length()) { web.send(400, "text/plain", err + "\n"); return; }
  web.sendHeader("Location", "/stripfw");
  web.send(303, "text/plain", "started\n");
}

