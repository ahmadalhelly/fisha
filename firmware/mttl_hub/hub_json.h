// Fisha hub: JSON builders and link history. Part of mttl_hub.ino, included in order from there.
// ---------- JSON builders ----------
bool hasSched(const String& mac, int outlet) {      // outlet 0 asks for whole-strip items only
  for (int i = 0; i < schedCount; i++)
    if (scheds[i].enabled && mac.equalsIgnoreCase(scheds[i].mac) && (scheds[i].outlet == outlet || scheds[i].outlet == 0)) return true;
  return false;
}
bool hasRule(const String& mac, int outlet) {
  for (int i = 0; i < autoCount; i++)
    if (autos[i].enabled && mac.equalsIgnoreCase(autos[i].mac) && (autos[i].outlet == outlet || autos[i].outlet == 0)) return true;
  return false;
}

String stripJson(int i) {
  const Strip& s = strips[i];
  float pw = 0, en = 0;
  bool any = false;
  uint32_t now = millis();
  float vS = (!isnan(s.voltage) && s.voltage > 50) ? s.voltage : 220.0f, ampsSum = 0;
  bool anyReal = false;
  String outs = "[";
  for (int k = 0; k < 4; k++) {
    const Outlet& o = s.o[k];
    float p = o.on ? o.powerW : 0;
    pw += p; en += o.energyWh / 1000.0f; any |= o.on;
    bool real = curValid(s, k, now);
    float oa = outletAmps(s, k, vS, now);
    anyReal |= real; ampsSum += oa;
    long left = s.autoOffAt[k] ? (long)((int32_t)(s.autoOffAt[k] - now) / 1000) : -1;
    if (k) outs += ",";
    outs += "{\"n\":" + String(k + 1) + ",\"on\":" + (o.on ? "true" : "false") + ",\"power_w\":" + String(o.powerW, 2) +
            ",\"energy_kwh\":" + String(o.energyWh / 1000.0f, 3) + ",\"temp_c\":" + String(o.tempC) +
            ",\"label\":\"" + jsonEsc(s.olabel[k]) + "\",\"locked\":" + ((s.lockMask & (1 << k)) ? "true" : "false") +
            ",\"protected\":" + ((s.protMask & (1 << k)) ? "true" : "false") + ",\"keep_on\":" + ((s.keepMask & (1 << k)) ? "true" : "false") +
            ",\"amp_limit\":" + (s.ampX2[k] ? String(s.ampX2[k] * 0.5f, 1) : "0") +
            ",\"auto_off_min\":" + String(s.autoOffMin[k]) +
            ",\"auto_off_in_s\":" + String(left < 0 ? -1 : left) + ",\"sched\":" + (hasSched(s.mac, k + 1) ? "true" : "false") +
            ",\"rule\":" + (hasRule(s.mac, k + 1) ? "true" : "false") +
            ",\"current_a\":" + String(oa, 2) + ",\"cur_real\":" + (real ? "true" : "false") + "}";
  }
  outs += "]";
  return "{\"mac\":\"" + s.mac + "\",\"name\":\"MTTL " + s.mac.substring(5) + "\",\"label\":\"" + jsonEsc(s.label) +
         "\",\"model\":\"" + s.model + "\",\"fw\":\"" + s.fw + "\",\"tsync_s\":" + (s.timeSyncAt ? String((millis() - s.timeSyncAt) / 1000) : String("-1")) + ",\"ip\":\"" + s.ip + "\",\"online\":true,\"on\":" + (any ? "true" : "false") +
         ",\"power_w\":" + String(pw, 2) + ",\"energy_kwh\":" + String(en, 3) +
         ",\"voltage\":" + (isnan(s.voltage) ? String("null") : String(s.voltage, 1)) +
         ",\"current_a\":" + (anyReal ? String(ampsSum, 2) : (isnan(s.voltage) || s.voltage <= 0 ? String("0") : String(pw / s.voltage, 2))) +
         ",\"rssi\":" + (s.hasRssi ? String(s.rssi) : String("null")) + ",\"up_s\":" + String((millis() - s.connectedAt) / 1000) +
         ",\"mlock\":" + (s.masterLock ? "true" : "false") + ",\"notify\":" + String(s.notifyMask) +
         ",\"sched\":" + (hasSched(s.mac, 0) ? "true" : "false") + ",\"rule\":" + (hasRule(s.mac, 0) ? "true" : "false") + ",\"outlets\":" + outs + "}";
}

String timersJson() {
  String j = "[";
  bool first = true;
  uint32_t now = millis();
  for (int t = 0; t < MAX_TIMERS; t++) {
    const Timer& x = timers[t];
    if (!x.used) continue;
    if (!first) j += ",";
    first = false;
    long in = (int32_t)(x.at - now) / 1000;
    j += "{\"tid\":" + String(x.id) + ",\"mac\":\"" + String(x.mac) + "\",\"outlet\":" + String(x.outlet) +
         ",\"kind\":\"" + (x.kind == 2 ? "loop" : x.kind == 1 ? "cycle" : (x.on ? "on" : "off")) + "\",\"phase\":" + String(x.phase) +
         ",\"in_s\":" + String(in < 0 ? 0 : in) + ",\"off_s\":" + String(x.offMs / 1000) + ",\"on_s\":" + String(x.onMs / 1000) +
         ",\"repeat_s\":" + String(x.periodS) + "}";
  }
  return j + "]";
}

// room for the devices part of the state, so it is reserved once instead of growing piece by piece
// (each growth can need the old and the new copy at once). A low guess only means one more growth later.
uint32_t stateDevicesBytes(const HubUser* u) {
  uint32_t n = 0;
  for (int i = 0; i < MAX_STRIPS; i++)
    if (strips[i].used && strips[i].identified && (!u || userHas(*u, strips[i].mac))) n += 1500;
  for (int k = 0; k < knownCount; k++)
    if (findStrip(known[k].mac) < 0 && (!u || userHas(*u, known[k].mac))) n += 1100;
  return n;
}

// everything in the owner's state up to the strips ("devices":[ included)
String stateHeadJson() {
  String j = "{\"local_ip\":\"" + WiFi.localIP().toString() + "\",\"port\":" + String(STRIP_PORT) + ",\"hub_fw\":\"" + FW_VERSION +
             "\",\"hub_build\":" + String(FISHA_BUILD) + ",\"hub\":\"" + hubId + "\",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"ts\":" + String((uint32_t)time(nullptr)) +
             ",\"uptime_s\":" + String(millis() / 1000) + ",\"nvs\":\"" + nvsId + "\"" +
             ",\"provision\":{\"state\":\"" + provState + "\",\"msg\":\"" + jsonEsc(provMsg) + "\"}" +
             ",\"config\":{\"temp_max\":" + String(tempMax) + ",\"temp_protect\":" + (tempProtect ? "true" : "false") +
             ",\"v_protect\":" + (vProt ? "true" : "false") + ",\"v_restore\":" + (vRestore ? "true" : "false") +
             ",\"v_back_s\":" + String(vBackS) + ",\"v_back_lo\":" + String(vBackLo) + ",\"v_back_hi\":" + String(vBackHi) +
             ",\"v_max\":" + String(vMax) + ",\"v_min\":" + String(vMin) + ",\"w_max\":" + String((int)STRIP_MAX_W) +
             ",\"a_protect\":" + (aProt ? "true" : "false") + ",\"a_max\":" + String(aMax, 1) +
             ",\"hold_s\":" + String(protHoldS) + ",\"tz_min\":" + String(tzOffsetMin) + ",\"tz_zone\":\"" + String(tzZone) + "\",\"tz_dst\":" + (tzNowDst() ? "true" : "false") +
             ",\"ntfy\":\"" + jsonEsc(ntfyTopic) + "\",\"ntypes\":" + String(notifyTypes) + ",\"ssid\":\"" + jsonEsc(secSsid) +
             "\",\"wifi_test\":\"" + wifiTestState + "\",\"wifi_test_ssid\":\"" + jsonEsc(wifiTestMsg) + "\"}" +
             ",\"cloud\":{\"up\":" + (mqttUp ? "true" : "false") + ",\"err\":\"" + mqttErr + "\",\"has_pass\":" + (secMqtt.length() ? "true" : "false") +
             ",\"user\":\"" + jsonEsc(secMqttUser) + "\",\"host\":\"" + mqttHost() + "\"}" +
             ",\"emqx_cfg\":" + (emqxReady() ? "true" : "false") + ",\"users_n\":" + String(userCount) +
             ",\"reset\":\"" + resetText() + "\"" + ",\"auth\":" + authJson() +
             ",\"timers\":" + timersJson() + ",\"devices\":[";
  return j;
}
// the state goes out piece by piece (head, then one strip at a time, then "]}") to whatever "put" sends it to.
// With 10 strips the whole state in one String is ~13 KB, more than the hub often has free in one block; this way the
// biggest piece is the head or one strip. put returns false to stop (send failed); an empty piece also stops (no memory).
bool stateStream(const HubUser* u, const std::function<bool(const String&)>& put) {
  {
    String h = u ? userStateHeadJson(*u) : stateHeadJson();
    if (!h.length() || !put(h)) return false;
  }
  bool first = true;
  for (int i = 0; i < MAX_STRIPS; i++) {
    if (!strips[i].used || !strips[i].identified || (u && !userHas(*u, strips[i].mac))) continue;
    if (!first && !put(",")) return false;
    String d = stripJson(i);
    if (!d.length() || !put(d)) return false;
    first = false;
  }
  for (int k = 0; k < knownCount; k++) {
    if (findStrip(known[k].mac) >= 0 || (u && !userHas(*u, known[k].mac))) continue;
    if (!first && !put(",")) return false;
    String d = offlineStripJson(known[k]);
    if (!d.length() || !put(d)) return false;
    first = false;
  }
  return put("]}");
}
// the whole state in one String (MQTT, cloud "state" requests): reserved once, then filled piece by piece
String stateJsonFor(const HubUser* u) {
  String j;
  j.reserve(700 + stateDevicesBytes(u));
  if (!stateStream(u, [&](const String& p) { return j.concat(p); })) return String();
  return j;
}
String buildStateJson() { return stateJsonFor(nullptr); }

String schedJson(const Sched& c) {
  return "{\"sid\":" + String(c.id) + ",\"mac\":\"" + String(c.mac) + "\",\"outlet\":" + String(c.outlet) + ",\"on\":" + (c.on ? "true" : "false") +
         ",\"days\":" + String(c.days) + ",\"hh\":" + String(c.hh) + ",\"mm\":" + String(c.mm) + ",\"date\":" + String(c.date) +
         ",\"enabled\":" + (c.enabled ? "true" : "false") + ",\"skip\":" + (schedSkipped(c.id) ? "true" : "false") +
         ",\"label\":\"" + jsonEsc(String(c.label)) + "\"}";
}
String autoJson(const Autom& r) {
  return "{\"aid\":" + String(r.id) + ",\"mac\":\"" + String(r.mac) + "\",\"outlet\":" + String(r.outlet) + ",\"above\":" + (r.above ? "true" : "false") +
         ",\"watts\":" + String(r.watts, 1) + ",\"hold_s\":" + String(r.holdS) + ",\"act\":" + String(r.act) +
         ",\"enabled\":" + (r.enabled ? "true" : "false") + ",\"metric\":" + String(r.metric) + ",\"limit2\":" + String(r.limit2, 0) + ",\"label\":\"" + jsonEsc(String(r.label)) + "\"}";
}
// ---------- link history per strip (the app's "network & connection" card) ----------
// Per strip and per day (7 days): seconds the hub was on Wi-Fi, seconds the strip was connected in that time, drops,
// the longest drop, and the lowest/average RSSI. Drops while the hub itself is off Wi-Fi are not counted: that is the
// hub's link, not the strip's. Kept in RAM and written to /links every 10 minutes.
const uint8_t LINK_NDAYS = 7, LINK_SLOTS = 8;
struct LinkDay { int32_t day; uint32_t hubS, upS, longS; uint16_t drops, rN; int32_t rSum; int8_t minR; uint8_t pad[3]; };
struct LinkLog { char mac[13]; uint8_t pad[3]; uint32_t lastDrop; LinkDay d[LINK_NDAYS]; };
struct LinkFile { uint32_t ver; uint32_t n; LinkLog l[LINK_SLOTS]; };
LinkFile linkF;
uint32_t linkDownAt[LINK_SLOTS];                     // epoch the strip dropped (RAM only, 0 = connected)
uint32_t linkTickAt = 0, linkSaveAt = 0;
uint32_t linkHubBlipAt = 0;                        // the hub's own Wi-Fi last dropped (strips drop with it: not counted)
bool linkDirty = false;

int linkIdx(const String& mac, bool create) {
  for (uint32_t i = 0; i < linkF.n; i++) if (mac.equalsIgnoreCase(linkF.l[i].mac)) return i;
  if (!create || mac.length() != 12) return -1;
  uint32_t i = linkF.n;
  if (i >= LINK_SLOTS) {                             // full: reuse the entry seen least recently
    i = 0;
    int32_t best = INT32_MAX;
    for (uint32_t k = 0; k < LINK_SLOTS; k++) {
      int32_t last = 0;
      for (int d = 0; d < LINK_NDAYS; d++) last = max(last, linkF.l[k].d[d].day);
      if (last < best) { best = last; i = k; }
    }
  } else linkF.n++;
  memset(&linkF.l[i], 0, sizeof(LinkLog));
  strlcpy(linkF.l[i].mac, mac.c_str(), sizeof linkF.l[i].mac);
  linkDownAt[i] = 0;
  linkDirty = true;
  return i;
}
LinkDay* linkToday(int i) {
  int32_t today = localDay();
  if (!today) return nullptr;
  LinkDay& d = linkF.l[i].d[((today % LINK_NDAYS) + LINK_NDAYS) % LINK_NDAYS];
  if (d.day != today) { memset(&d, 0, sizeof d); d.day = today; }
  return &d;
}
void linkLoad() {
  memset(&linkF, 0, sizeof linkF);
  if (!fileLoad("/links", &linkF, sizeof linkF) || linkF.ver != 1 || linkF.n > LINK_SLOTS) { memset(&linkF, 0, sizeof linkF); }
  linkF.ver = 1;
  memset(linkDownAt, 0, sizeof linkDownAt);
}
void linkSave() { if (fileSave("/links", &linkF, sizeof linkF)) linkDirty = false; }
void linkDrop(const String& mac) {
  if (!timeOk() || WiFi.status() != WL_CONNECTED) return;
  if (linkHubBlipAt && millis() - linkHubBlipAt < 90000) return;   // fallout of the hub's own Wi-Fi drop
  int i = linkIdx(mac, true);
  if (i < 0 || linkDownAt[i]) return;
  LinkDay* d = linkToday(i);
  if (!d) return;
  uint32_t t = (uint32_t)time(nullptr);
  linkDownAt[i] = t;
  linkF.l[i].lastDrop = t;
  d->drops++;
  linkDirty = true;
}
void linkUp(const String& mac) {
  int i = linkIdx(mac, true);
  if (i < 0 || !linkDownAt[i] || !timeOk()) { if (i >= 0) linkDownAt[i] = 0; return; }
  uint32_t dur = (uint32_t)time(nullptr) - linkDownAt[i];
  linkDownAt[i] = 0;
  LinkDay* d = linkToday(i);
  if (d && dur < 86400UL * 7 && dur > d->longS) d->longS = dur;
  linkDirty = true;
}
void linkTick() {
  uint32_t now = millis();
  if (now - linkTickAt < 10000) return;
  uint32_t dt = (now - linkTickAt) / 1000;
  linkTickAt = now;
  if (dt > 60 || !timeOk()) return;                // first tick, or the loop was held (Wi-Fi down): skip that gap
  for (uint32_t i = 0; i < linkF.n; i++) {
    String mac = linkF.l[i].mac;
    if (isBlocked(mac)) continue;
    LinkDay* d = linkToday(i);
    if (!d) return;
    d->hubS += dt;
    int idx = findStrip(mac);
    if (idx >= 0 && strips[idx].identified) {
      d->upS += dt;
      if (strips[idx].hasRssi && strips[idx].rssi < 0 && strips[idx].rssi > -127) {
        int8_t r = strips[idx].rssi;
        if (!d->rN || r < d->minR) d->minR = r;
        d->rSum += r;
        d->rN++;
      }
    }
  }
  linkDirty = true;
  if (now - linkSaveAt > 600000) { linkSaveAt = now; linkSave(); }
}
String linkJson(const String& mac) {
  int i = linkIdx(mac, false);
  int idx = findStrip(mac);
  String j = "{\"mac\":\"" + mac + "\",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"rssi\":" +
             (idx >= 0 && strips[idx].hasRssi ? String(strips[idx].rssi) : String("null")) + ",\"ip\":\"" + (idx >= 0 ? strips[idx].ip : String("")) + "\"";
  if (i < 0) return j + ",\"last_drop\":0,\"down_since\":0,\"days\":[]}";
  const LinkLog& L = linkF.l[i];
  j += ",\"last_drop\":" + String(L.lastDrop) + ",\"down_since\":" + String(linkDownAt[i]) + ",\"days\":[";
  // newest first; "day" counts days since 1970-01-01 (hub local date)
  int32_t today = localDay();
  bool first = true;
  for (int back = 0; back < LINK_NDAYS && today; back++) {
    int32_t want = today - back;
    const LinkDay& d = L.d[((want % LINK_NDAYS) + LINK_NDAYS) % LINK_NDAYS];
    if (d.day != want) continue;
    if (!first) j += ",";
    first = false;
    j += "{\"day\":" + String(d.day) + ",\"hub_s\":" + String(d.hubS) + ",\"up_s\":" + String(d.upS) + ",\"drops\":" + String((unsigned)d.drops) +
         ",\"long_s\":" + String(d.longS) + ",\"min\":" + (d.rN ? String((int)d.minR) : String("null")) +
         ",\"avg\":" + (d.rN ? String((int)lround((double)d.rSum / d.rN)) : String("null")) + "}";
  }
  return j + "]}";
}

String eventsJson() {
  String j = "{\"events\":[";
  for (int n = 0; n < evCount; n++) {
    int idx = ((int)evHead - 1 - n + MAX_EVENTS) % MAX_EVENTS;   // newest first
    const Ev& e = events[idx];
    if (n) j += ",";
    j += "{\"ts\":" + String(e.ts) + ",\"type\":\"" + e.type + "\",\"mac\":\"" + e.mac + "\",\"outlet\":" + String(e.outlet) +
         ",\"msg\":\"" + jsonEsc(e.msg) + "\"}";
  }
  return j + "]}";
}
String energyJson(int i) {                        // "" = not enough memory right now
  const Strip& s = strips[i];
  ELog* elp = elogGet(i);
  if (!elp) return "";
  PeakLog* plp = peakGet(i);
  if (!plp) { delete elp; return ""; }
  std::unique_ptr<ELog> elHold(elp);
  std::unique_ptr<PeakLog> plHold(plp);
  const ELog& el = *elp;
  String j = "{\"mac\":\"" + s.mac + "\",\"time_ok\":" + (timeOk() ? "true" : "false") + ",\"today\":" +
             String(el.day ? civilFromDays(el.day) : 0) + ",\"today_wh\":[";
  for (int k = 0; k < 4; k++) {
    if (k) j += ",";
    uint32_t c = s.o[k].energyWh;
    j += String(el.day && c >= el.base[k] ? c - el.base[k] : 0);
  }
  const PeakLog& pl = *plp;
  j += "],\"today_peak_w\":" + String(pl.day == el.day ? pl.today : 0) + ",\"days\":[";
  bool first = true;
  for (int back = 1; back <= ELOG_DAYS; back++) {
    int32_t d = el.day - back;
    int idx = ((d % ELOG_DAYS) + ELOG_DAYS) % ELOG_DAYS;
    if (!el.day || el.dayOf[idx] != d) continue;
    if (!first) j += ",";
    first = false;
    int pk = pl.dayOf[idx] == d ? pl.pk[idx] : -1;
    j += "{\"date\":" + String(civilFromDays(d)) + ",\"wh\":[" + String(el.wh[idx][0]) + "," + String(el.wh[idx][1]) + "," +
         String(el.wh[idx][2]) + "," + String(el.wh[idx][3]) + "],\"peak_w\":" + String(pk) + "}";
  }
  return j + "]}";
}


