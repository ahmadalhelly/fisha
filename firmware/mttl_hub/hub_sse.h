// Fisha hub: live push over Server-Sent Events. Part of mttl_hub.ino, included in order from there.
// ---------- live push: Server-Sent Events on :8081 ----------
struct SseClient { WiFiClient c; bool used = false, ready = false; String req; uint32_t since = 0; int userIdx = -1; };
SseClient sse[MAX_SSE];
int sseCount() { int n = 0; for (int i = 0; i < MAX_SSE; i++) n += sse[i].used && sse[i].ready; return n; }
uint32_t lastSsePush = 0, lastSseBeat = 0, lastSseFull = 0;
// diagnostics (/api/health): live streams opened, closed by the hub because the phone didn't take the data
// in time (or the send failed), closed by the phone, when the hub last closed one, and the size of the state it sends
uint32_t sseOpened = 0, sseCut = 0, sseGone = 0, sseCutAt = 0, sseStateLen = 0, sseStateMax = 0;
void sseCutNow() { sseCut++; sseCutAt = millis(); }
// diagnostics: showed every piece of the state builds fine on its own and the heap looks fine, yet the
// whole state comes out empty, so some memory request is being refused. ESP-IDF calls this whenever any allocation in
// the hub fails (Strings, network buffers, ...): it records the size asked, what was free at that instant and who asked.
// No allocation and no logging in here, only plain variables.
volatile uint32_t allocFailN = 0, allocFailAt = 0, allocFailSize = 0, allocFailCaps = 0, allocFailFree = 0, allocFailLargest = 0, allocFailMaxSize = 0;
const char* volatile allocFailFn = "";
const char* volatile allocFailTask = "";
portMUX_TYPE allocSiteMux = portMUX_INITIALIZER_UNLOCKED;
static void allocFailCb(size_t size, uint32_t caps, const char* fn) {
  allocFailN++;
  if (!xPortInIsrContext()) {   // who asked: return addresses of the calling code, kept per site (see hub_allocsites.h)
    uint32_t pc[ALLOC_BT + 2];
    uint8_t d = 0;
    esp_backtrace_frame_t f;
    esp_backtrace_get_start(&f.pc, &f.sp, &f.next_pc);
    while (d < ALLOC_BT + 2) {
      pc[d++] = allocPcFix(f.pc);
      if (!f.next_pc || !esp_backtrace_get_next_frame(&f)) break;
    }
    // esp_backtrace_get_start starts at this callback's caller: the first two frames are heap_caps_alloc_failed and the
    // heap_caps_* function above it (malloc / new frames can still follow)
    uint8_t skip = d > 2 ? 2 : 0;
    portENTER_CRITICAL(&allocSiteMux);
    allocSiteNote(size, pc + skip, d - skip, pcTaskGetName(nullptr), millis());
    portEXIT_CRITICAL(&allocSiteMux);
  }
  allocFailAt = millis();
  allocFailSize = size;
  if (size > allocFailMaxSize) allocFailMaxSize = size;
  allocFailCaps = caps;
  allocFailFn = fn ? fn : "";
  allocFailTask = pcTaskGetName(nullptr);
  allocFailFree = heap_caps_get_free_size(MALLOC_CAP_8BIT);
  allocFailLargest = heap_caps_get_largest_free_block(MALLOC_CAP_8BIT);
}
// diagnostics: on the state the hub built came out empty (state_len 0), which matches the app's "not on
// the same Wi-Fi" (an empty /api/state can't be read). When that happens, record the heap and the size of every piece of
// the state, built one by one, in a plain char buffer (no String, so the record itself can't fail) for /api/health.
uint32_t stateBadN = 0, stateBadAt = 0;
char stateBadBuf[240] = "";
void stateBadDiag(uint32_t gotLen) {
  stateBadN++;
  if (stateBadN > 1 && millis() - stateBadAt < 5000) return;   // counted; the pieces are re-measured at most every 5 s
  stateBadAt = millis();
  uint32_t fh = ESP.getFreeHeap(), ma = ESP.getMaxAllocHeap();
  int n = snprintf(stateBadBuf, sizeof stateBadBuf, "len %u heap %u max %u lip %u hub %u nvs %u prov %u err %u host %u auth %u tmr %u",
                   (unsigned)gotLen, (unsigned)fh, (unsigned)ma, (unsigned)WiFi.localIP().toString().length(), (unsigned)hubId.length(),
                   (unsigned)nvsId.length(), (unsigned)provState.length(), (unsigned)mqttErr.length(), (unsigned)mqttHost().length(),
                   (unsigned)authJson().length(), (unsigned)timersJson().length());
  for (int i = 0; i < MAX_STRIPS && n > 0 && n < (int)sizeof stateBadBuf - 12; i++)
    if (strips[i].used && strips[i].identified) n += snprintf(stateBadBuf + n, sizeof stateBadBuf - n, " s%d %u", i, (unsigned)stripJson(i).length());
  for (int k = 0; k < knownCount && n > 0 && n < (int)sizeof stateBadBuf - 12; k++)
    if (findStrip(known[k].mac) < 0) n += snprintf(stateBadBuf + n, sizeof stateBadBuf - n, " k%d %u", k, (unsigned)offlineStripJson(known[k]).length());
}

// the state goes out in three pieces straight from the one copy (it used to be copied twice more per
// phone, ~3 x the state size in RAM at once) and without blocking, so a push no longer starves the strips.
bool sseWrite(WiFiClient& c, const char* ev, const String& body) {
  String head = String("event: ") + ev + "\ndata: ";
  return sendNB(c, head.c_str(), head.length(), 80) && sendNB(c, body.c_str(), body.length(), 80) && sendNB(c, "\n\n", 2, 80);
}
void sseSend(const char* ev, const String& data) {
  SubT st("sse");
  for (int i = 0; i < MAX_SSE; i++) {
    if (!sse[i].used || !sse[i].ready) continue;
    if (!sse[i].c.connected()) { sseGone++; sse[i].c.stop(); sse[i] = SseClient(); continue; }
    if (sse[i].userIdx >= 0 && ownerOnlyEvent(data)) continue;
    if (!sseWrite(sse[i].c, ev, data)) {
      sseCutNow();
      sse[i].c.stop();
      sse[i] = SseClient();
    }
  }
}
// update mode and a parked MQTT client: every live stream is closed so its buffers are free; the app reconnects by itself
void sseShedAll() {
  for (int i = 0; i < MAX_SSE; i++) if (sse[i].used) { sse[i].c.stop(); sse[i] = SseClient(); }
}
const HubUser* sseUser(const SseClient& x) { return x.userIdx >= 0 && x.userIdx < userCount ? &users[x.userIdx] : nullptr; }
// one "state" event, streamed straight into the phone's socket a piece at a time (see stateStream)
bool sseWriteState(WiFiClient& c, const HubUser* u) {
  uint32_t t0 = millis(), len = 0;              // 250 ms for the whole event (the old three pieces had 80 ms each)
  auto put = [&](const char* p, size_t n) { uint32_t used = millis() - t0; return used < 250 && sendNB(c, p, n, 250 - used); };
  if (!put("event: state\ndata: ", 19)) return false;
  bool ok = stateStream(u, [&](const String& p) { len += p.length(); return put(p.c_str(), p.length()); }) && put("\n\n", 2);
  sseStateLen = len;
  if (len > sseStateMax) sseStateMax = len;
  return ok;
}
// between full states the phones get only the numbers that change every report, per online strip (~170 bytes
// a strip instead of ~1.2 KB): {"ts":..,"d":[{"mac":"..","v":230.1,"r":-60,"up":123,"o":[[on,W,kWh,°C,auto_off_in_s,real_A_or_-1],..]}]}
// The app merges them into the strips it got with the last "state".
String liveJson(const HubUser* u) {
  uint32_t n = 0;
  for (int i = 0; i < MAX_STRIPS; i++) n += strips[i].used && strips[i].identified && (!u || userHas(*u, strips[i].mac));
  String j;
  j.reserve(32 + 230 * n);
  j += "{\"ts\":";
  j += (uint32_t)time(nullptr);
  j += ",\"d\":[";
  bool first = true;
  uint32_t now = millis();
  for (int i = 0; i < MAX_STRIPS; i++) {
    const Strip& s = strips[i];
    if (!s.used || !s.identified || (u && !userHas(*u, s.mac))) continue;
    if (!first) j += ",";
    first = false;
    j += "{\"mac\":\"";
    j += s.mac;
    j += "\",\"v\":";
    if (isnan(s.voltage)) j += "null"; else j += String(s.voltage, 1);
    j += ",\"r\":";
    if (s.hasRssi) j += s.rssi; else j += "null";
    j += ",\"up\":";
    j += (now - s.connectedAt) / 1000;
    j += ",\"o\":[";
    for (int k = 0; k < 4; k++) {
      const Outlet& o = s.o[k];
      long left = s.autoOffAt[k] ? (long)((int32_t)(s.autoOffAt[k] - now) / 1000) : -1;
      if (k) j += ",";
      j += o.on ? "[1," : "[0,";
      j += String(o.powerW, 2);
      j += ",";
      j += String(o.energyWh / 1000.0f, 3);
      j += ",";
      j += o.tempC;
      j += ",";
      j += left < 0 ? -1L : left;
      j += ",";
      if (curValid(s, k, now)) j += String(s.curA[k], 2); else j += "-1";   // real current (A), -1 = none
      j += "]";
    }
    j += "]}";
  }
  j += "]}";
  return j;
}
// sends "live" (only numbers) or the full "state" to every phone; a phone that can't take it in time is cut
void ssePush(bool full) {
  SubT st("sse");
  String ownerLive;
  for (int i = 0; i < MAX_SSE; i++) {
    SseClient& x = sse[i];
    if (!x.used || !x.ready) continue;
    if (!x.c.connected()) { sseGone++; x.c.stop(); x = SseClient(); continue; }
    const HubUser* u = sseUser(x);
    bool ok;
    if (full) ok = sseWriteState(x.c, u);
    else if (u) { String lv = liveJson(u); ok = lv.length() > 8 && sseWrite(x.c, "live", lv); }
    else {
      if (!ownerLive.length()) ownerLive = liveJson(nullptr);
      ok = ownerLive.length() > 8 && sseWrite(x.c, "live", ownerLive);
    }
    if (!ok) { sseCutNow(); x.c.stop(); x = SseClient(); }
  }
}

// value of ?k= / &k= in a request line like "GET /events?u=..&t=.. HTTP/1.1" (no URL decoding needed: ids and tokens are plain)
String queryArg(const String& line, const char* k) {
  String key = String(k) + "=";
  int q = line.indexOf('?');
  if (q < 0) return "";
  int sp = line.indexOf(' ', q);
  String qs = line.substring(q + 1, sp < 0 ? line.length() : sp);
  int i = 0;
  while (i < (int)qs.length()) {
    int amp = qs.indexOf('&', i);
    if (amp < 0) amp = qs.length();
    if (qs.substring(i, i + key.length()) == key) return qs.substring(i + key.length(), amp);
    i = amp + 1;
  }
  return "";
}

void ssePump() {
  WiFiClient n = sseServer.accept();
  if (n) {
    int slot = -1;
    for (int i = 0; i < MAX_SSE; i++) if (!sse[i].used) { slot = i; break; }
    if (slot < 0) { sse[0].c.stop(); sse[0] = SseClient(); slot = 0; }   // replace the oldest
    sse[slot] = SseClient();
    sse[slot].c = n; sse[slot].used = true; sse[slot].since = millis();
    n.setNoDelay(true);
    n.setTimeout(150);
  }
  for (int i = 0; i < MAX_SSE; i++) {
    SseClient& x = sse[i];
    if (!x.used) continue;
    if (!x.ready) {
      while (x.c.available() && x.req.length() < 1024) x.req += (char)x.c.read();
      if (x.req.indexOf("\r\n\r\n") >= 0) {
        // a shared user is matched first (exact u=/t= values) so it gets only its own strips,
        // even when API_TOKEN is empty; before, an empty token made every SSE client the owner.
        String line0 = x.req.substring(0, x.req.indexOf('\r'));
        String qu = queryArg(line0, "u"), qt = queryArg(line0, "t");
        int matchedUser = -1;
        for (int k = 0; qt.length() && k < userCount; k++) {
          if (strlen(users[k].pw) && qt == users[k].pw && (!qu.length() || qu == users[k].id)) {
            matchedUser = k;
            break;
          }
        }
        bool owner = matchedUser < 0 && (ownerCount ? isOwnerKey(qt) || (strlen(API_TOKEN) && qt == API_TOKEN) : (!strlen(API_TOKEN) || qt == API_TOKEN));
        bool ok = owner || matchedUser >= 0;
        if (!ok || !x.req.startsWith("GET /events")) {
          sendStr(x.c, "HTTP/1.1 401 Unauthorized\r\nContent-Length: 0\r\n\r\n", 250);
          x.c.stop(); x = SseClient(); continue;
        }
        x.userIdx = matchedUser;
        // the SSE answers no longer wait on a phone that stopped reading (they could freeze the hub ~5-10 s)
        if (!sendStr(x.c, "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nCache-Control: no-cache\r\nConnection: keep-alive\r\n"
                          "Access-Control-Allow-Origin: *\r\n\r\nretry: 3000\n\n", 250)) { sseCutNow(); x.c.stop(); x = SseClient(); continue; }
        if (!sseWriteState(x.c, sseUser(x))) { sseCutNow(); x.c.stop(); x = SseClient(); continue; }
        x.ready = true;
        sseOpened++;
      } else if (millis() - x.since > 3000) { x.c.stop(); x = SseClient(); continue; }
    }
    if (x.used && !x.c.connected()) { if (x.ready) sseGone++; x.c.stop(); x = SseClient(); }
  }
  // at most one state per second to the phones (was every 250 ms). Each push builds ~4 KB and copies it into
  // every phone's socket; four times a second that used up the hub's memory ~25 refused requests a second,
  // network buffers among them) and nearly every live stream got cut.
  // a strip report only changes numbers, so it sends "live" (~170 bytes a strip); the full state goes out when
  // anything else changed (names, locks, settings, a strip came or went, ...) and every 15 s as a safety net.
  // with no 3 KB block free the push waits (the flags stay set): the network buffers come first, and the phones
  // get the state a moment later
  // (the largest-block query walks the whole heap under its lock, so it is only asked when a push is due and a phone listens)
  if ((stateDirty || liveDirty) && millis() - lastSsePush > 1000) {
    bool any = false;
    for (int i = 0; i < MAX_SSE; i++) any |= sse[i].used && sse[i].ready;
    if (any && heap_caps_get_largest_free_block(MALLOC_CAP_8BIT | MALLOC_CAP_INTERNAL) < 3072) {
      sseDefer++; lastSsePush = millis() - 750;   // look again in 250 ms
    } else {
      bool full = stateDirty || millis() - lastSseFull > 15000;
      if (stateDirty) mqttHeadDirty = true;
      stateDirty = false;
      liveDirty = false;
      lastSsePush = millis();
      if (full) lastSseFull = millis();
      if (any) ssePush(full);
    }
  }
  if (millis() - lastSseBeat > 15000) {
    lastSseBeat = millis();
    for (int i = 0; i < MAX_SSE; i++) {
      if (sse[i].used && sse[i].ready) {
        SubT st("sse_beat");
        if (!sendNB(sse[i].c, ": hb\n\n", 6, 250)) {
          sseCutNow();
          sse[i].c.stop();
          sse[i] = SseClient();
        }
      }
    }
  }
}

