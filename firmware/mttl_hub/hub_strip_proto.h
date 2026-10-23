// Fisha hub: strip protocol, timers, schedules. Part of mttl_hub.ino, included in order from there.
// ---------- strip protocol ----------
// up:getinfo:<ch>:<runtime>;<relay>;<state>;<flagA>;<flagB>;<power mW>;<energy hex Wh>;<prev>;<config>;<status>;<event>;<temp>  x4
void keepRestore(Strip& s, int ch) {
  s.cmdAt[ch - 1] = millis();
  sendLine(s, "up:onoff:" + String(ch) + ":on");
  if (!s.keepEvAt[ch - 1] || millis() - s.keepEvAt[ch - 1] > 60000) {
    s.keepEvAt[ch - 1] = millis() ? millis() : 1;
    addEvent("lock", s.mac, ch, "keep_on");
  }
}

bool tryParseInfo(int i) {
  Strip& s = strips[i];
  std::vector<String> t = split(s.pendingInfo.substring(11), ':');
  Outlet tmp[4];
  bool seen[4] = {false, false, false, false};
  for (size_t j = 0; j + 1 < t.size(); j += 2) {
    int ch = t[j].toInt();
    std::vector<String> f = split(t[j + 1], ';');
    if (f.size() < 12 || ch < 1 || ch > 4 || !isHex(f[6])) continue;
    Outlet& o = tmp[ch - 1];
    o.on = f[1].equalsIgnoreCase("on");
    o.powerW = f[5].toInt() / 1000.0f;
    o.energyWh = strtoul(f[6].c_str(), nullptr, 16);
    o.tempC = f[11].toInt();
    seen[ch - 1] = true;
  }
  if (!(seen[0] && seen[1] && seen[2] && seen[3])) {
    if (s.pendingInfo.length() > 2048) s.pendingInfo = "";
    return false;
  }
  uint32_t now = millis();
  float total = 0;
  for (int k = 0; k < 4; k++) {
    if (tmp[k].on) total += tmp[k].powerW;
    // a change the hub did not ask for in the last 8 s came from the strip's own buttons
    if (s.gotInfo && tmp[k].on != s.o[k].on && now - s.cmdAt[k] > 8000 && !(s.lockMask & (1 << k))) {
      s.cmdAt[k] = now;
      addEvent("button", s.mac, k + 1, tmp[k].on ? "on" : "off");
    }
    bool was = s.gotInfo ? s.o[k].on : false;
    if (tmp[k].on && !was && s.autoOffMin[k]) s.autoOffAt[k] = now + (uint32_t)s.autoOffMin[k] * 60000UL;
    if (!tmp[k].on) s.autoOffAt[k] = 0;
    s.o[k] = tmp[k];
  }
  s.gotInfo = true;
  s.pendingInfo = "";
  s.infoSeq++;
  s.infoOn = 0;
  for (int k = 0; k < 4; k++) if (s.o[k].on) s.infoOn |= 1 << k;
  for (int k = 0; k < 4; k++) {                  // keep always on (wins over the child lock)
    uint8_t bit = 1 << k;
    if (!(s.keepMask & bit)) continue;
    if (s.o[k].on) { s.keepHold &= ~bit; continue; }
    if (!(s.keepHold & bit)) keepRestore(s, k + 1);
  }
  for (int k = 0; k < 4; k++) {                  // child lock: keep a locked outlet where it belongs
    if (!(s.lockMask & (1 << k)) || (s.keepMask & (1 << k))) continue;
    bool want = s.lockState & (1 << k);
    if (s.o[k].on != want) sendLine(s, "up:onoff:" + String(k + 1) + ":" + (want ? "on" : "off"));
  }
  energyUpdate(i);
  peakUpdate(i, total);
  evalStrip(i);
  liveDirty = true;                              // numbers only; anything else that changed sets stateDirty itself
  return true;
}

// the answer to up:power_report:<ch>:vol (mV) or :current (mA), told apart by what was asked (moved out of handleLine so the host test can run it)
void handlePowerReport(Strip& s, const String& line) {
  std::vector<String> f = split(line.substring(16), ':');
  // the answer to a :current request (mA). It is told apart from a voltage (mV, >= 50000) by what was asked, and
  // a value in mV range is never taken as a voltage here: a strip that answered :current in another unit would
  // otherwise look like an under-voltage and cut its outlets.
  if (s.pwrKind == 2 && f.size() == 2 && f[0].toInt() == s.pwrCh) {
    s.pwrKind = 0;
    bool num = f[1].length() > 0 && f[1].length() <= 6;
    for (unsigned c = 0; num && c < f[1].length(); c++) if (f[1][c] < '0' || f[1][c] > '9') num = false;
    long mA = num ? f[1].toInt() : -1;
    if (mA >= 50000) { if (++s.curBadN >= 3) { s.curBad = true; for (int q = 0; q < 4; q++) { s.curAt[q] = 0; s.preAt[q] = 0; } } }
    else if (mA >= 0 && mA <= 20000 && s.pwrCh >= 1 && s.pwrCh <= 4) {
      int k = s.pwrCh - 1;
      s.curBadN = 0;
      s.preA[k] = s.curA[k]; s.preAt[k] = s.curAt[k];   // the protections need two readings in a row
      s.curA[k] = mA / 1000.0f;
      s.curPw[k] = s.o[k].powerW;
      s.curAt[k] = millis() | 1;
      liveDirty = true;                      // numbers only
    }
    return;
  }
  if (f.size() == 2 && f[1].toInt() >= 50000) {
    if (s.pwrKind == 1) s.pwrKind = 0;
    s.voltage = f[1].toInt() / 1000.0f;
    if ((s.voltage < 200 || s.voltage > 250) && (!s.voltEventAt || millis() - s.voltEventAt > 600000)) {
      s.voltEventAt = millis();
      addEvent("voltage", s.mac, 0, String(s.voltage, 0) + " V");
    }
    voltCheck(s);
  }
}

void handleLine(int i, const String& line) {
  Strip& s = strips[i];
  s.lastLine = line;
  s.lastLine.replace("\"", "'");
  Serial.printf("[rx %s] %s\n", s.mac.length() ? s.mac.c_str() : s.ip.c_str(), line.c_str());

  if (s.pendingInfo.length() && !line.startsWith("up:")) { s.pendingInfo += line; tryParseInfo(i); return; }
  if (line.startsWith("up:bootinfo:")) {                     // <model>;<mac>;<mac>;<fw>;connect
    std::vector<String> f = split(line.substring(12), ';');
    if (f.size() < 5 || f[1].length() != 12 || !isHex(f[1])) { Serial.printf("[?] bootinfo not understood from %s: %s\n", s.ip.c_str(), line.c_str()); return; }
    String mac = f[1]; mac.toUpperCase();
    bool target = provTarget.length() && mac.endsWith(provTarget) && (provState == "waiting" || provState == "error");
    if (isBlocked(mac)) {
      if (!target) { Serial.printf("[x] %s was removed in the app, ignoring\n", mac.c_str()); s.c.stop(); s = Strip(); return; }
      setBlocked(mac, false);
    }
    for (int j = 0; j < MAX_STRIPS; j++)
      if (j != i && strips[j].used && strips[j].mac == mac) dropStrip(strips[j], "replaced");
    s.mac = mac; s.model = f[0]; s.fw = f[3]; s.identified = true; s.connectedAt = millis();
    linkUp(mac);
    loadStripCfg(i);
    refreshKnown(mac);
    Serial.printf("[*] strip %s online  model=%s fw=%s\n", mac.c_str(), s.model.c_str(), s.fw.c_str());
    // only the strip we just configured counts — every other strip re-dials after the hub rejoins Wi-Fi
    bool isTarget = provTarget.length() && mac.endsWith(provTarget);
    if (isTarget && (provState == "waiting" || (provState == "error" &&
        (provMsg == "no_dial" || provMsg == "still_setup" || provMsg == "hub_tcp_no_client")))) {
      provState = "connected";
      provMsg = mac;
      addEvent("added", mac, 0, "");
    }
    int off = offlineMacs.indexOf(mac + ",");
    if (off >= 0) { offlineMacs.remove(off, 13); addEvent("online", mac, 0, ""); }
    sendLine(s, "up:getinfo:all");
    sendChildLock(s);                                        // F1.0.82+ keeps these in its own flash: re-apply on every connect
    if (stripFwNum(s.fw) >= 90) s.cfgSyncStep = 1;           // queue paced F1.0.90 sync (tz, time, limits, offline sched)
    stateDirty = true;
    return;
  }
  if (line.startsWith("up:getinfo:")) { s.pendingInfo = line; tryParseInfo(i); return; }
  if (line.startsWith("up:power_report:")) { handlePowerReport(s, line); return; }
  if (line.indexOf("connect_ok") >= 0) {          // reply to a Wi-Fi handover or F1.0.90 config command
    s.connOk = true;
    if (wifiTestState == "moving" || s.wifiHandoverSent) {
      s.wifiHandoverSent = false;
      if (wifiTestState == "moving" && wifiOkMacs.indexOf(s.mac) < 0) wifiOkMacs += s.mac + ",";
      addEvent("wifipush", s.mac, 0, "connect_ok");
    }
    return;
  }
  if (line.startsWith("up:query:")) { s.rssi = line.substring(9).toInt(); s.hasRssi = true; return; }

  String l = line; l.toLowerCase();
  String body;
  if (l.startsWith("up:event:onoff:")) body = l.substring(15);
  else if (l.startsWith("up:onoff:")) body = l.substring(9);
  if (!body.length()) return;
  std::vector<String> f = split(body, ':');
  int ch = f.size() == 2 ? f[0].toInt() : -1;
  bool isEvent = l.startsWith("up:event:");
  if (ch >= 1 && ch <= 4) {
    bool on = (f[1] == "on");
    uint8_t kb = 1 << (ch - 1);
    if (on) s.keepHold &= ~kb;
    if ((s.keepMask & kb) && !on && !(s.keepHold & kb)) {
      s.o[ch - 1].on = false;
      keepRestore(s, ch);
      stateDirty = true;
    } else if (isEvent && (s.lockMask & (1 << (ch - 1)))) {
      bool want = s.lockState & (1 << (ch - 1));
      if (on != want) sendLine(s, "up:onoff:" + String(ch) + ":" + (want ? "on" : "off"));
      addEvent("lock", s.mac, ch, "");
    } else {
      bool changed = s.o[ch - 1].on != on;
      s.o[ch - 1].on = on;
      if (isEvent) noteCommanded(s, ch, on);
      if (isEvent && changed && millis() - s.cmdAt[ch - 1] > 8000) { s.cmdAt[ch - 1] = millis(); addEvent("button", s.mac, ch, on ? "on" : "off"); }
      stateDirty = true;
    }
  } else if (isEvent && ch == 0) {
    // the strip's own master button turns everything off while any outlet is on. With a child-locked outlet
    // left on, every press meant "all off": the hub put the locked one back and the free ones (already off) never came
    // on. So a press that switched off while every free outlet was already off is taken as "turn the free ones on".
    uint8_t freeM = 0x0F & ~s.lockMask;
    if (s.lockMask && freeM && f[1] == "off" && !(s.infoOn & freeM))
      for (int k = 0; k < 4; k++) if (freeM & (1 << k)) sendOnOffF(s, k + 1, true, false);
    sendLine(s, "up:getinfo:all");                           // master button: next poll re-applies locks
  }
}

void acceptStrips() {
  SubT st("accept");
  WiFiClient n = stripServer.accept();
  if (!n) n = stripServerAlt.accept();
  if (!n) return;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used) {
      strips[i] = Strip();
      strips[i].c = n;
      strips[i].used = true;
      strips[i].ip = n.remoteIP().toString();
      strips[i].lastRx = millis();
      n.setNoDelay(true);
      tcpKeepAlive(strips[i].c);
      Serial.printf("[+] connection from %s -> port %u\n", strips[i].ip.c_str(), strips[i].c.localPort());
      return;
    }
  }
  n.stop();
}

void pumpStrips() {
  acceptStrips();
  for (int i = 0; i < MAX_STRIPS; i++) {
    Strip& s = strips[i];
    if (!s.used) continue;
    if (s.dead) { dropStrip(s, "socket stuck"); continue; }
    while (s.c.available()) {
      char ch = s.c.read();
      s.lastRx = millis();
      if (ch == 0 || ch == '\r') continue;
      if (ch == '\n') {
        String line = s.rx; line.trim();
        s.rx = "";
        if (line.length()) handleLine(i, line);
        if (!s.used) break;
      } else if (s.rx.length() < 4096) s.rx += ch;
      else s.rx = "";
    }
    if (!s.used) continue;
    if (s.txq.length()) flushTx(s, 0);
    if (s.dead) { dropStrip(s, "socket stuck"); continue; }
    if (!s.identified && !s.poked && millis() - s.lastRx > 6000) {   // a strip that connected but never introduced itself
      s.poked = true;
      Serial.printf("[?] %s connected but sent no bootinfo, asking it\n", s.ip.c_str());
      sendLine(s, "up:getinfo:all");
    }
    if (!s.c.connected() && !s.c.available()) dropStrip(s, "disconnected");
    else if (millis() - s.lastRx > STALE_MS) dropStrip(s, "stale");
  }
}

// asks for the real current of the next outlet that is on (one request in flight per strip; never :power, its answer is in mW)
void askCurrent(Strip& s) {
  uint32_t now = millis();
  if (s.curBad || (s.pwrKind && now - s.pwrAt < 3000)) return;
  for (int n = 0; n < 4; n++) {
    int k = (s.curNext + n) & 3;
    if (!s.o[k].on) continue;
    s.curNext = (k + 1) & 3;
    s.pwrKind = 2; s.pwrCh = k + 1; s.pwrAt = now;
    sendLine(s, "up:power_report:" + String(k + 1) + ":current");
    return;
  }
}

void sendStripLimits(Strip& s) {
  if (stripFwNum(s.fw) < 90) return;
  // every field inside the range the strip accepts (F1.0.93 puts a field outside it back to its default, one by one);
  // a protection that is off goes to the edge of its range so the strip never trips on it
  uint16_t uv = vProt ? (uint16_t)constrain((int)vMin, 100, 220) : 100;
  uint16_t ov = (uint16_t)constrain((int)vMax, 220, 280);
  uint16_t ma = aProt ? (uint16_t)constrain((int)round(aMax * 1000.0f), 500, 16500) : 16500;
  uint16_t pw = (uint16_t)constrain((int)STRIP_MAX_W, 50, 3680);
  uint8_t  tp = tempProtect ? (uint8_t)constrain((int)tempMax, 25, 95) : 95;
  uint16_t hs = (uint16_t)constrain((int)protHoldS, 1, 600);
  for (int i = 0; i < autoCount; i++) {
    const Autom& r = autos[i];
    if (!r.enabled || r.act != 1 || !r.above) continue;
    if (strlen(r.mac) && !s.mac.equalsIgnoreCase(r.mac)) continue;
    if (r.metric == 0 && r.watts >= 50.0f && (uint16_t)r.watts < pw) {
      pw = (uint16_t)r.watts;
      if (r.holdS >= 1 && r.holdS <= 600) hs = r.holdS;
    }
  }
  sendLine(s, "up:limits:" + String(uv) + ":" + String(ov) + ":" + String(ma) + ":" +
              String(pw) + ":" + String(tp) + ":" + String(hs));
}

// The strip keeps one schedule. It gets the weekday schedule of this strip that comes next from now, so a new one is
// not hidden behind an older one; once that one has run, the next one takes its place (stripSchedTick).
// A one-time schedule (a date, no weekdays) stays with the hub: the strip would repeat it every day.
int stripSchedPick(const Strip& s) {
  int best = -1;
  long bestIn = 0;
  struct tm lt;
  bool tOk = timeOk();
  if (tOk) { time_t now = time(nullptr); localtime_r(&now, &lt); }
  for (int i = 0; i < schedCount; i++) {
    const Sched& c = scheds[i];
    if (!c.enabled || !c.days || !s.mac.equalsIgnoreCase(c.mac)) continue;
    if (!tOk) return i;                          // no clock yet: the first one
    // minutes until its next run; one that is due now or ran a minute ago still counts, so the strip is not handed the
    // next schedule in the very minute it should act on this one
    long nowMin = lt.tm_hour * 60L + lt.tm_min - 2, in = -1;
    for (int d = 0; d < 8 && in < 0; d++) {
      if (!(c.days & (1 << ((lt.tm_wday + d) % 7)))) continue;
      long t = d * 1440L + c.hh * 60L + c.mm - nowMin;
      if (t > 0) in = t;
    }
    if (in > 0 && (best < 0 || in < bestIn)) { best = i; bestIn = in; }
  }
  return best;
}

uint32_t stripSchedKey(int i) {
  if (i < 0) return 1;                           // "none" is also something the strip was told
  const Sched& c = scheds[i];
  return ((c.id << 1) ^ ((uint32_t)c.days << 24) ^ ((uint32_t)c.hh << 16) ^ ((uint32_t)c.mm << 8) ^ ((uint32_t)c.outlet << 4) ^ (c.on ? 2U : 0U)) | 0x80000000UL;
}

void sendStripOfflineSched(Strip& s) {
  if (stripFwNum(s.fw) < 90) return;
  int i = stripSchedPick(s);
  s.schedKey = stripSchedKey(i);
  if (i < 0) { sendLine(s, "up:sched:0:0:0:0"); return; }
  const Sched& c = scheds[i];
  uint8_t days = c.days & 0x7F;                  // bit 0 = Sunday, as tm_wday (the strip uses the same bits)
  uint16_t en_ch = (1U << 8) | ((c.on ? 1U : 0U) << 7) | (c.outlet & 0x07U);
  sendLine(s, "up:sched:" + String(en_ch) + ":" + String(days) + ":" + String(c.hh) + ":" + String(c.mm));
}

// once a minute: a strip whose next schedule changed (the one it held has run, or one was added) gets the new one
void stripSchedTick() {
  static uint32_t last = 0;
  if (millis() - last < 60000) return;
  last = millis();
  for (int i = 0; i < MAX_STRIPS; i++) {
    Strip& s = strips[i];
    if (!s.used || !s.identified || stripFwNum(s.fw) < 90 || s.cfgSyncStep || s.txq.length()) continue;
    if (stripSchedKey(stripSchedPick(s)) != s.schedKey) sendStripOfflineSched(s);
  }
}

void pollStrips() {
  if (millis() - lastPoll < POLL_MS) return;
  lastPoll = millis();
  pollCount++;
  for (int i = 0; i < MAX_STRIPS; i++) {
    Strip& s = strips[i];
    if (!s.used || !s.identified) continue;
    if (stripFwNum(s.fw) >= 90 && !s.txq.length() && s.cfgSyncStep > 0) {
      if (s.cfgSyncStep == 1) {
        sendLine(s, "up:tz:" + String(tzOffsetMin));
        s.cfgSyncStep = 2;
        continue;
      } else if (s.cfgSyncStep == 2) {
        if (timeOk()) { sendLine(s, "up:time:" + String((unsigned long)time(nullptr))); s.timeSyncAt = millis(); }
        s.cfgSyncStep = 3;
        continue;
      } else if (s.cfgSyncStep == 3) {
        sendStripLimits(s);
        s.cfgSyncStep = 4;
        continue;
      } else if (s.cfgSyncStep == 4) {
        sendStripOfflineSched(s);
        s.cfgSyncStep = 0;
        continue;
      }
    }
    sendLine(s, "up:getinfo:all");
    if (pollCount % DIAG_EVERY == 0) { s.pwrKind = 1; s.pwrCh = 1; s.pwrAt = millis(); sendLine(s, "up:power_report:1:vol"); sendLine(s, "up:query:wifirssi"); }
    else if (pollCount % DIAG_EVERY == 2) askCurrent(s);
    else if (stripFwNum(s.fw) >= 90 && (pollCount % 3600 == 0 || !s.timeSyncAt) && timeOk() && !s.txq.length()) {
      sendLine(s, "up:time:" + String((unsigned long)time(nullptr)));
      s.timeSyncAt = millis();
    }
  }
}

// ---------- timers (kept in NVS) ----------
bool timersRestored = false;
TimerNV timersNV[MAX_TIMERS];
uint8_t timersNVCount = 0;

void saveTimers() {
  static TimerNV out[MAX_TIMERS];
  uint8_t n = 0;
  uint32_t now = millis();
  uint32_t epoch = timeOk() ? (uint32_t)time(nullptr) : 0;
  for (int t = 0; t < MAX_TIMERS; t++) {
    const Timer& x = timers[t];
    if (!x.used) continue;
    TimerNV& v = out[n++];
    memset(&v, 0, sizeof v);
    v.id = x.id; memcpy(v.mac, x.mac, sizeof v.mac); v.outlet = x.outlet; v.kind = x.kind; v.on = x.on; v.phase = x.phase;
    v.offS = x.offMs / 1000; v.onS = x.onMs / 1000; v.periodS = x.periodS;
    int32_t left = (int32_t)(x.at - now) / 1000;
    v.remainS = left < 0 ? 0 : left;
    v.dueEpoch = epoch ? epoch + v.remainS : 0;
  }
  cfg.putUChar("tmN", n);
  cfg.putBytes("tm", out, sizeof(TimerNV) * MAX_TIMERS);
}

void loadTimers() {
  timersNVCount = 0;
  if (cfg.getBytesLength("tm") == sizeof(TimerNV) * MAX_TIMERS) {
    cfg.getBytes("tm", timersNV, sizeof(TimerNV) * MAX_TIMERS);
    timersNVCount = min((int)cfg.getUChar("tmN", 0), (int)MAX_TIMERS);
  }
}

// called once the clock is set (or after 30 s without internet time)
void restoreTimers() {
  if (timersRestored || (!timeOk() && millis() < 30000)) return;
  timersRestored = true;
  uint32_t now = millis();
  uint32_t epoch = timeOk() ? (uint32_t)time(nullptr) : 0;
  bool changed = false;
  for (int i = 0; i < timersNVCount && i < MAX_TIMERS; i++) {
    const TimerNV& v = timersNV[i];
    int32_t left = (epoch && v.dueEpoch) ? (int32_t)(v.dueEpoch - epoch) : (int32_t)v.remainS;
    bool repeating = v.kind == 2 || v.periodS > 0;
    if (left < 0 && !repeating && -left > 600) { addEvent("missed", v.mac, v.outlet, "timer"); changed = true; continue; }
    Timer& x = timers[i];
    x = Timer();
    x.used = true; x.id = v.id; memcpy(x.mac, v.mac, sizeof x.mac); x.outlet = v.outlet; x.kind = v.kind; x.on = v.on; x.phase = v.phase;
    x.offMs = v.offS * 1000; x.onMs = v.onS * 1000; x.periodS = v.periodS;
    x.at = now + (uint32_t)(left > 2 ? left : 2) * 1000;
    if (x.id >= nextTimerId) nextTimerId = x.id + 1;
  }
  Serial.printf("[timers] restored %d\n", timersNVCount);
  if (changed) saveTimers();
  stateDirty = true;
}

String addTimer(const String& mac, int outlet, int kind, bool on, uint32_t delayS, uint32_t offS, uint32_t onS, uint32_t periodS) {
  int idx = stripFor(mac);
  if (idx < 0) return "device offline";
  if (outlet < 0 || outlet > 4) return "bad outlet";
  if (kind == 1 && (offS < 3 || offS > 3600)) return "off time must be 3..3600 s";
  if (kind == 2 && (onS < 10 || offS < 10 || onS > 604800 || offS > 604800)) return "on/off time must be 10 s .. 7 days";
  if (periodS && (periodS < 60 || periodS > 604800)) return "repeat every 1 min .. 7 days";
  if (kind == 1 && periodS && periodS <= offS) return "repeat must be longer than the off time";
  if (delayS > 604800) return "delay too long";
  for (int t = 0; t < MAX_TIMERS; t++) {
    if (timers[t].used) continue;
    Timer& x = timers[t];
    x = Timer();
    x.used = true; x.id = nextTimerId++;
    strlcpy(x.mac, strips[idx].mac.c_str(), sizeof x.mac);
    x.outlet = outlet; x.kind = kind; x.on = on; x.offMs = offS * 1000; x.onMs = onS * 1000; x.phase = 0;
    x.periodS = kind == 2 ? 0 : periodS;
    x.at = millis() + delayS * 1000;
    saveTimers();
    stateDirty = true;
    return "";
  }
  return "too many timers";
}

void tickTimers() {
  restoreTimers();
  uint32_t now = millis();
  bool changed = false;
  for (int t = 0; t < MAX_TIMERS; t++) {
    Timer& x = timers[t];
    if (!x.used || (int32_t)(now - x.at) < 0) continue;
    changed = true;
    bool repeating = x.kind == 2 || x.periodS > 0;
    int idx = findStrip(x.mac);
    if (idx < 0) {                                   // strip offline
      if (x.kind == 1 && x.phase == 1 && x.tries++ < 120) { x.at = now + 5000; continue; }   // keep trying "back on" for 10 min
      addEvent("missed", x.mac, x.outlet, "timer");
      if (!repeating) { x.used = false; continue; }
      x.tries = 0;
      x.phase = 0;
      x.at = now + (x.kind == 2 ? x.onMs + x.offMs : x.periodS * 1000);
      continue;
    }
    Strip& s = strips[idx];
    x.tries = 0;
    if (x.kind == 0) {
      sendOnOff(s, x.outlet, x.on);
      addEvent("timer", s.mac, x.outlet, x.on ? "on" : "off");
      if (x.periodS) x.at = now + x.periodS * 1000; else x.used = false;
    } else if (x.kind == 1) {
      if (x.phase == 0) {
        if (stripFwNum(s.fw) >= 90) {
          uint32_t offSec = constrain(x.offMs / 1000UL, 1UL, 3600UL);
          sendLine(s, "up:cycle:" + String(x.outlet) + ":" + String(offSec));
        } else {
          sendOnOff(s, x.outlet, false);
        }
        x.phase = 1;
        x.at = now + x.offMs;
      } else {
        sendOnOff(s, x.outlet, true);
        addEvent("cycle", s.mac, x.outlet, String(x.offMs / 1000) + " s");
        if (x.periodS) { x.phase = 0; x.at = now + x.periodS * 1000 - x.offMs; } else x.used = false;
      }
    } else {                                         // loop
      bool turnOn = x.phase == 0;
      sendOnOff(s, x.outlet, turnOn);
      x.phase = turnOn ? 1 : 0;
      x.at = now + (turnOn ? x.onMs : x.offMs);
    }
    stateDirty = true;
  }
  if (changed) saveTimers();
}

// ---------- schedules (NVS, run inside the hub) ----------
void tickSchedules() {
  static int lastMin = -1;
  struct tm t;
  if (!localNow(t) || t.tm_min == lastMin) return;
  lastMin = t.tm_min;
  uint32_t today = (uint32_t)(t.tm_year + 1900) * 10000 + (t.tm_mon + 1) * 100 + t.tm_mday;
  bool save = false;
  for (int i = 0; i < schedCount; i++) {
    Sched& c = scheds[i];
    if (!c.enabled || c.hh != t.tm_hour || c.mm != t.tm_min) continue;
    bool match = c.days ? (c.days & (1 << t.tm_wday)) : (c.date == today);
    if (!match) continue;
    if (schedSkipped(c.id)) {                      // skipped once, runs again next time
      setSchedSkip(c.id, false);
      addEvent("skipped", c.mac, c.outlet, String(c.label));
      if (!c.days) { c.enabled = 0; save = true; }
      continue;
    }
    int idx = findStrip(c.mac);
    if (idx >= 0) { sendOnOff(strips[idx], c.outlet, c.on); addEvent("schedule", c.mac, c.outlet, String(c.label)); }
    else addEvent("missed", c.mac, c.outlet, String(c.label));
    if (!c.days) { c.enabled = 0; save = true; }
  }
  if (save) saveScheds();
}

