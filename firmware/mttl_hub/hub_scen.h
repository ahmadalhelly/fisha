// Fisha hub: scenarios (when X happens, if Y holds, do A, otherwise do B). Part of mttl_hub.ino, included in order from there.
// ---------- scenarios ----------
// A scenario is one flat JSON object per line in /scen.txt (up to SC_MAX). Trigger "tt": 1 a reading is above/below a limit for
// a while, 2 an outlet goes on/off, 3 a time of day, 4 the power came back (hub restarted after an outage), 5 the cloud link
// is down. Conditions (all optional): a time window, days of the week, the state of one outlet. Actions are a text
// "type,mac,outlet,seconds,message;..." with type on, off, delay, cycle, lock, unlock, notify; the "else" text runs
// when the trigger fired but a condition failed. on / off / cycle go through the hub timers, so "delay" is just a later
// start and nothing here blocks the loop.
#define SC_MAX 8
struct Scen {
  bool used = false, en = false, armed = true;
  uint16_t id = 0;
  char name[24] = "";
  uint8_t tt = 0, tn = 0, tmet = 0, top = 0, thh = 0, tmm = 0, tdays = 127, cd = 127, cn = 0;
  char tmac[13] = "", cmac[13] = "";
  int32_t tv = 0;
  uint16_t th = 0;
  int8_t cfh = -1, cfm = 0, cth = 0, ctm = 0, cv = -1;
  char act[150] = "", els[110] = "";
  uint32_t since = 0;
  int8_t prevOn = -1;
  int32_t lastMin = -1;
};
Scen scens[SC_MAX];
String scenRaw[SC_MAX];                         // the JSON line of each slot, for listing
uint16_t scenNextId = 1;

ApiRes api(String path, const String& b);
static void scCopy(char* dst, size_t n, const String& s) { strlcpy(dst, s.c_str(), n); }

// strips are matched by the 12 hex digits of their MAC, with or without colons
static String scMacKey(const String& m) {
  String o;
  for (unsigned i = 0; i < m.length(); i++) if (isxdigit((unsigned char)m[i])) o += (char)toupper(m[i]);
  return o;
}

bool scenParse(const String& line, Scen& s) {
  if (!jsonHas(line, "tt")) return false;
  s = Scen();
  s.used = true;
  s.id = (uint16_t)jsonValue(line, "id").toInt();
  s.en = !jsonHas(line, "en") || jsonBool(line, "en");
  scCopy(s.name, sizeof s.name, jsonValue(line, "name"));
  s.tt = (uint8_t)jsonValue(line, "tt").toInt();
  scCopy(s.tmac, sizeof s.tmac, scMacKey(jsonValue(line, "tmac")));
  s.tn = (uint8_t)constrain((int)jsonValue(line, "tn").toInt(), 0, 4);
  s.tmet = (uint8_t)jsonValue(line, "tmet").toInt();
  s.top = (uint8_t)jsonValue(line, "top").toInt();
  s.tv = (int32_t)jsonValue(line, "tv").toInt();
  s.th = (uint16_t)constrain((int)jsonValue(line, "th").toInt(), 0, 36000);
  s.thh = (uint8_t)constrain((int)jsonValue(line, "thh").toInt(), 0, 23);
  s.tmm = (uint8_t)constrain((int)jsonValue(line, "tmm").toInt(), 0, 59);
  s.tdays = jsonHas(line, "tdays") ? (uint8_t)(jsonValue(line, "tdays").toInt() & 0x7F) : 127;
  s.cfh = jsonHas(line, "cfh") ? (int8_t)constrain((int)jsonValue(line, "cfh").toInt(), -1, 23) : -1;
  s.cfm = (int8_t)constrain((int)jsonValue(line, "cfm").toInt(), 0, 59);
  s.cth = (int8_t)constrain((int)jsonValue(line, "cth").toInt(), 0, 23);
  s.ctm = (int8_t)constrain((int)jsonValue(line, "ctm").toInt(), 0, 59);
  s.cd = jsonHas(line, "cd") ? (uint8_t)(jsonValue(line, "cd").toInt() & 0x7F) : 127;
  scCopy(s.cmac, sizeof s.cmac, scMacKey(jsonValue(line, "cmac")));
  s.cn = (uint8_t)constrain((int)jsonValue(line, "cn").toInt(), 0, 4);
  s.cv = jsonHas(line, "cv") ? (int8_t)jsonValue(line, "cv").toInt() : -1;
  scCopy(s.act, sizeof s.act, jsonValue(line, "a"));
  scCopy(s.els, sizeof s.els, jsonValue(line, "e"));
  return s.tt >= 1 && s.tt <= 5;
}

void scenLoad() {
  for (int i = 0; i < SC_MAX; i++) { scens[i] = Scen(); scenRaw[i] = ""; }
  scenNextId = 1;
  if (!fsOk || !LittleFS.exists("/scen.txt")) return;
  File f = LittleFS.open("/scen.txt", "r");
  if (!f) return;
  int n = 0;
  while (f.available() && n < SC_MAX) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (!line.length()) continue;
    if (scenParse(line, scens[n])) {
      scenRaw[n] = line;
      if (scens[n].id >= scenNextId) scenNextId = scens[n].id + 1;
      n++;
    }
  }
  f.close();
}

bool scenSaveFile() {
  String all;
  for (int i = 0; i < SC_MAX; i++) if (scens[i].used) { all += scenRaw[i]; all += "\n"; }
  if (!all.length()) { if (fsOk) LittleFS.remove("/scen.txt"); return true; }
  return fileSave("/scen.txt", all.c_str(), all.length());
}

String scenListJson() {
  String j = "{\"scens\":[";
  bool first = true;
  for (int i = 0; i < SC_MAX; i++) {
    if (!scens[i].used) continue;
    if (!first) j += ",";
    first = false;
    j += scenRaw[i];
  }
  return j + "]}";
}

// the app sends one flat JSON object; an id of 0 (or none) makes a new scenario, an existing id replaces it
ApiRes scenSave(const String& b) {
  Scen s;
  if (!scenParse(b, s)) return errRes("bad scenario");
  if (b.length() > 480) return errRes("scenario too long");
  int slot = -1;
  if (s.id) for (int i = 0; i < SC_MAX; i++) if (scens[i].used && scens[i].id == s.id) slot = i;
  if (slot < 0) for (int i = 0; i < SC_MAX; i++) if (!scens[i].used) { slot = i; break; }
  if (slot < 0) return errRes("too many scenarios");
  if (!s.id) s.id = scenNextId++;
  // the stored line carries the id the hub chose
  String line = b;
  line.trim();
  if (jsonHas(line, "id")) {
    int p = line.indexOf("\"id\"");
    int e = line.indexOf(',', p);
    if (e < 0) e = line.indexOf('}', p);
    if (p >= 0 && e > p) line = line.substring(0, p) + "\"id\":" + String(s.id) + line.substring(e);
  } else {
    line = "{\"id\":" + String(s.id) + "," + line.substring(line.indexOf('{') + 1);
  }
  scens[slot] = s;
  scenRaw[slot] = line;
  if (!scenSaveFile()) return errRes("storage full");
  stateDirty = true;
  return okRes("{\"id\":" + String(s.id) + "}");
}

ApiRes scenDelete(uint16_t id) {
  for (int i = 0; i < SC_MAX; i++) {
    if (scens[i].used && scens[i].id == id) {
      scens[i] = Scen();
      scenRaw[i] = "";
      scenSaveFile();
      stateDirty = true;
      return okRes();
    }
  }
  return errRes("no such scenario");
}

// a reading of the trigger's outlet (0 = the whole strip): W, A, degrees C or V; NAN when the strip is not connected
static float scReading(const Scen& s) {
  int idx = findStrip(String(s.tmac));
  if (idx < 0 || !strips[idx].identified) return NAN;
  const Strip& st = strips[idx];
  float w = 0;
  int t = 0;
  for (int k = 0; k < 4; k++) {
    if (s.tn && k + 1 != s.tn) continue;
    w += st.o[k].powerW;
    if (st.o[k].tempC > t) t = st.o[k].tempC;
  }
  switch (s.tmet) {
    case 0: return w;
    case 1: return (!isnan(st.voltage) && st.voltage > 50) ? w / st.voltage : NAN;
    case 2: return (float)t;
    case 3: return st.voltage;
  }
  return NAN;
}

static bool scConditions(const Scen& s, const struct tm& lt) {
  if (!(s.cd & (1 << lt.tm_wday))) return false;
  if (s.cfh >= 0) {
    int now = lt.tm_hour * 60 + lt.tm_min, from = s.cfh * 60 + s.cfm, to = s.cth * 60 + s.ctm;
    bool in = from <= to ? (now >= from && now < to) : (now >= from || now < to);   // a window may pass midnight
    if (!in) return false;
  }
  if (s.cmac[0] && s.cv >= 0 && s.cn >= 1) {
    int idx = findStrip(String(s.cmac));
    if (idx < 0 || !strips[idx].identified) return false;
    if ((int)strips[idx].o[s.cn - 1].on != s.cv) return false;
  }
  return true;
}

static void scRun(const char* text, const Scen& s) {
  String all = text;
  uint32_t acc = 0;                              // seconds of "delay" so far: later on / off / cycle start that much later
  int pos = 0;
  while (pos < (int)all.length()) {
    int e = all.indexOf(';', pos);
    if (e < 0) e = all.length();
    String item = all.substring(pos, e);
    pos = e + 1;
    String f[5];
    int fi = 0, p2 = 0;
    for (int q = 0; q < 5; q++) {
      int c = item.indexOf(',', p2);
      f[q] = c < 0 ? item.substring(p2) : item.substring(p2, c);
      if (c < 0) break;
      p2 = c + 1;
      fi++;
    }
    String type = f[0];
    String mac = scMacKey(f[1]);
    int n = f[2].toInt();
    uint32_t secs = (uint32_t)f[3].toInt();
    if (type == "delay") { acc += secs; if (acc > 86400) acc = 86400; continue; }
    if (type == "on" || type == "off") {
      String e2 = addTimer(mac, n, 0, type == "on", acc, 0, 0, 0);
      if (e2.length()) Serial.printf("[scen %u] %s\n", s.id, e2.c_str());
    } else if (type == "cycle") {
      String e2 = addTimer(mac, n, 1, false, acc, secs ? secs : 10, 0, 0);
      if (e2.length()) Serial.printf("[scen %u] %s\n", s.id, e2.c_str());
    } else if (type == "lock" || type == "unlock") {
      api("lock", "{\"mac\":\"" + mac + "\",\"outlet\":" + String(n) + ",\"locked\":" + (type == "lock" ? "true" : "false") + "}");
    } else if (type == "notify") {
      String msg = f[4].length() ? f[4] : String(s.name);
      addEvent("automation", mac, n, msg);
    }
  }
}

// every second: look at each enabled scenario's trigger; when it fires run the actions (or the else actions)
void scenTick() {
  static uint32_t last = 0;
  if (millis() - last < 1000) return;
  last = millis();
  time_t tnow = time(nullptr);
  struct tm lt;
  bool tOk = timeOk();
  if (tOk) localtime_r(&tnow, &lt); else memset(&lt, 0, sizeof lt);
  uint32_t ms = millis();
  for (int i = 0; i < SC_MAX; i++) {
    Scen& s = scens[i];
    if (!s.used || !s.en) continue;
    bool fire = false;
    switch (s.tt) {
      case 1: {
        float v = scReading(s);
        bool c = !isnan(v) && (s.top == 0 ? v < (float)s.tv : v > (float)s.tv);
        if (c) {
          if (!s.since) s.since = ms ? ms : 1;
          if (s.armed && ms - s.since >= (uint32_t)s.th * 1000UL) { fire = true; s.armed = false; }
        } else {
          s.since = 0;
          s.armed = true;
        }
        break;
      }
      case 2: {
        int idx = findStrip(String(s.tmac));
        if (idx < 0 || !strips[idx].identified || s.tn < 1) { s.prevOn = -1; break; }
        int cur = strips[idx].o[s.tn - 1].on ? 1 : 0;
        if (s.prevOn >= 0 && cur != s.prevOn && cur == (s.tv ? 1 : 0)) fire = true;
        s.prevOn = cur;
        break;
      }
      case 3:
        if (tOk && lt.tm_hour == s.thh && lt.tm_min == s.tmm && (s.tdays & (1 << lt.tm_wday)) && s.lastMin != lt.tm_hour * 60 + lt.tm_min) {
          fire = true;
          s.lastMin = lt.tm_hour * 60 + lt.tm_min;
        }
        break;
      case 4:                                      // the power came back: once, a minute after the hub started
        if (s.armed && ms > 60000 && ms < 180000) {
          s.armed = false;
          if (resetText() == "power") fire = true;
        }
        break;
      case 5:
        if (secMqtt.length() && !mqttUp && WiFi.status() == WL_CONNECTED) {
          if (!s.since) s.since = ms ? ms : 1;
          if (s.armed && ms - s.since >= (uint32_t)s.th * 1000UL) { fire = true; s.armed = false; }
        } else {
          s.since = 0;
          s.armed = true;
        }
        break;
    }
    if (!fire) continue;
    bool ok = scConditions(s, lt);
    Serial.printf("[scen %u] %s fired, conditions %s\n", s.id, s.name, ok ? "hold" : "do not hold");
    scRun(ok ? s.act : s.els, s);
  }
}
