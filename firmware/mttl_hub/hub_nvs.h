// Fisha hub: NVS storage, known strips, removed strips. Part of mttl_hub.ino, included in order from there.
// ---------- NVS ----------
void saveLocks(Strip& s) {
  cfg.putUChar(("l" + s.mac).c_str(), s.lockMask);
  cfg.putUChar(("s" + s.mac).c_str(), s.lockState);
}
// the energy/peak history (~2.4 KB per strip, rewritten every few minutes) lives in files on the unused
// SPIFFS partition (LittleFS), not in NVS: it filled NVS (500/630 entries) and saves started to fail.
bool fsOk = false;
bool fileSave(const String& path, const void* d, size_t n) {
  if (!fsOk) return false;
  SubT st("fs_save");
  String tmp = path + ".t";
  File f = LittleFS.open(tmp, "w");
  if (!f) return false;
  size_t w = f.write((const uint8_t*)d, n);
  f.close();
  if (w != n) { LittleFS.remove(tmp); return false; }
  LittleFS.remove(path);
  return LittleFS.rename(tmp, path);
}
bool fileLoad(const String& path, void* d, size_t n) {
  if (!fsOk || !LittleFS.exists(path)) return false;
  File f = LittleFS.open(path, "r");
  if (!f) return false;
  bool ok = f.size() == n && f.read((uint8_t*)d, n) == n;
  f.close();
  return ok;
}
// file first; NVS only as a fallback when the file system is not available
void saveBlob(const String& key, const void* d, size_t n) {
  if (fileSave("/" + key, d, n)) { if (cfg.isKey(key.c_str())) cfg.remove(key.c_str()); }
  else cfg.putBytes(key.c_str(), d, n);
}
// loads from the file, or from NVS once (old data), moving it to a file and freeing the NVS entries
bool loadBlob(const String& key, void* d, size_t n) {
  if (fileLoad("/" + key, d, n)) return true;
  if (cfg.getBytesLength(key.c_str()) != n) return false;
  cfg.getBytes(key.c_str(), d, n);
  if (fileSave("/" + key, d, n)) cfg.remove(key.c_str());
  return true;
}
// full log in a temporary buffer (caller hands it to elogPut or deletes it). null = no memory right now, or the
// file is there but could not be read (never overwritten then). The running day in RAM wins over the file.
ELog* elogGet(int i) {
  ELog* el = new (std::nothrow) ELog();
  if (!el) return nullptr;
  String key = "e" + strips[i].mac;
  if (!loadBlob(key, el, sizeof(ELog)) || el->magic != 0xE1E1) {
    if (fsOk && LittleFS.exists("/" + key)) { delete el; return nullptr; }
    memset(el, 0, sizeof(ELog));
    el->magic = 0xE1E1;
    for (int d = 0; d < ELOG_DAYS; d++) el->dayOf[d] = -1;
  }
  const ElogHead& h = elogs[i];
  if (h.magic == 0xE1E1) { el->day = h.day; memcpy(el->base, h.base, sizeof el->base); }
  return el;
}
void elogPut(int i, ELog* el) {
  ElogHead& h = elogs[i];
  h.magic = 0xE1E1; h.day = el->day; memcpy(h.base, el->base, sizeof h.base);
  saveBlob("e" + strips[i].mac, el, sizeof(ELog));
  delete el;
}
PeakLog* peakGet(int i) {
  PeakLog* pl = new (std::nothrow) PeakLog();
  if (!pl) return nullptr;
  String key = "k" + strips[i].mac;
  if (!loadBlob(key, pl, sizeof(PeakLog)) || pl->magic != 0xBEA7) {
    if (fsOk && LittleFS.exists("/" + key)) { delete pl; return nullptr; }
    memset(pl, 0, sizeof(PeakLog));
    pl->magic = 0xBEA7;
    for (int d = 0; d < ELOG_DAYS; d++) pl->dayOf[d] = -1;
  }
  const PeakHead& h = peaks[i];
  if (h.magic == 0xBEA7) { pl->day = h.day; pl->today = h.today; }
  return pl;
}
void peakPut(int i, PeakLog* pl) {
  PeakHead& h = peaks[i];
  h.magic = 0xBEA7; h.day = pl->day; h.today = pl->today;
  saveBlob("k" + strips[i].mac, pl, sizeof(PeakLog));
  peakSavedAt[i] = millis();
  delete pl;
}
// RAM copy of the running day, read once when the strip comes online (retried on its next report when memory is short)
bool histHeads(int i) {
  if (elogs[i].magic != 0xE1E1) {
    ELog* el = elogGet(i);
    if (!el) return false;
    ElogHead& h = elogs[i];
    h.magic = 0xE1E1; h.day = el->day; memcpy(h.base, el->base, sizeof h.base);
    delete el;
  }
  if (peaks[i].magic != 0xBEA7) {
    PeakLog* pl = peakGet(i);
    if (!pl) return false;
    PeakHead& h = peaks[i];
    h.magic = 0xBEA7; h.day = pl->day; h.today = pl->today;
    delete pl;
    peakSavedAt[i] = millis();
  }
  return true;
}

void loadStripCfg(int i) {
  Strip& s = strips[i];
  s.label = cfg.getString(("n" + s.mac).c_str(), "");
  for (int k = 0; k < 4; k++) s.olabel[k] = cfg.getString(("n" + s.mac + String(k + 1)).c_str(), "");
  s.lockMask = cfg.getUChar(("l" + s.mac).c_str(), 0);
  s.masterLock = cfg.getUChar(("ml" + s.mac).c_str(), 0) != 0;
  s.lockState = cfg.getUChar(("s" + s.mac).c_str(), 0);
  s.protMask = cfg.getUChar(("p" + s.mac).c_str(), 0);
  s.keepMask = cfg.getUChar(("q" + s.mac).c_str(), 0);
  s.notifyMask = cfg.getUChar(("m" + s.mac).c_str(), 0x1F);
  if (cfg.getBytesLength(("a" + s.mac).c_str()) == sizeof(s.autoOffMin)) cfg.getBytes(("a" + s.mac).c_str(), s.autoOffMin, sizeof(s.autoOffMin));
  else memset(s.autoOffMin, 0, sizeof(s.autoOffMin));
  if (cfg.getBytesLength(("x" + s.mac).c_str()) == sizeof(s.ampX2)) cfg.getBytes(("x" + s.mac).c_str(), s.ampX2, sizeof(s.ampX2));
  else memset(s.ampX2, 0, sizeof(s.ampX2));
  elogs[i] = ElogHead();                         // slot may have held another strip
  peaks[i] = PeakHead();
  histHeads(i);
}

void peakUpdate(int i, float watts) {
  if (!timeOk() || !histHeads(i)) return;
  PeakHead& h = peaks[i];
  int32_t today = localDay();
  if (h.day != today) {
    PeakLog* pl = peakGet(i);
    if (!pl) return;                               // no memory now: next report tries again
    if (pl->day) {
      int idx = ((pl->day % ELOG_DAYS) + ELOG_DAYS) % ELOG_DAYS;
      pl->pk[idx] = pl->today;
      pl->dayOf[idx] = pl->day;
    }
    pl->day = today;
    pl->today = 0;
    peakPut(i, pl);
  }
  uint16_t w = (uint16_t)constrain(watts, 0.0f, 65000.0f);
  if (w > h.today) {
    h.today = w;
    if (millis() - peakSavedAt[i] > 600000) {      // at most every 10 min
      PeakLog* pl = peakGet(i);
      if (pl) peakPut(i, pl);
    }
  }
}

// a save that NVS refused (full) shows up in the event log instead of vanishing (once a minute per item)
void saveFailed(const char* what) {
  static uint32_t lastAt = 0;
  static String lastWhat;
  Serial.printf("[nvs] save FAILED: %s\n", what);
  if (lastWhat == what && millis() - lastAt < 60000) return;
  lastWhat = what; lastAt = millis();
  addEvent("save_fail", "", 0, what);
}
void saveScheds() {
  cfg.putUChar("schN", schedCount);
  if (!cfg.putBytes("sch", scheds, sizeof(Sched) * MAX_SCHED)) saveFailed("schedules");
  stateDirty = true;   // badges follow at once
}   // badges follow at once
void saveSkips() { cfg.putBytes("schsk", schedSkip, sizeof(schedSkip)); }
bool schedSkipped(uint32_t id) { for (int i = 0; i < MAX_SCHED; i++) if (id && schedSkip[i] == id) return true; return false; }
void setSchedSkip(uint32_t id, bool on) {
  bool changed = false;
  for (int i = 0; i < MAX_SCHED; i++) if (schedSkip[i] == id) { schedSkip[i] = 0; changed = true; }
  if (on) for (int i = 0; i < MAX_SCHED; i++) if (!schedSkip[i]) { schedSkip[i] = id; changed = true; break; }
  if (changed) saveSkips();
}
void saveAutos() {
  cfg.putUChar("autN", autoCount);
  if (!cfg.putBytes("aut", autos, sizeof(Autom) * MAX_AUTO)) saveFailed("automations");
  stateDirty = true;
}

void loadGlobals() {
  tempMax = cfg.getUChar("tmax", 80);
  tempProtect = cfg.getBool("tprot", true);
  vProt = cfg.getBool("vprot", true);
  vRestore = cfg.getBool("vrest", true);
  vMax = cfg.getUShort("vmax", 260);
  vMin = cfg.getUShort("vmin", 180);
  aProt = cfg.getBool("aprot", true);
  aMax = cfg.getFloat("amax", 16.0f);
  protHoldS = (uint8_t)constrain((int)cfg.getUChar("phold", 3), 1, 60);
  tzOffsetMin = (int16_t)constrain((int)cfg.getShort("tzmin3", 180), -720, 840);
  schedCount = 0;
  memset(schedSkip, 0, sizeof(schedSkip));
  if (cfg.getBytesLength("schsk") == sizeof(schedSkip)) cfg.getBytes("schsk", schedSkip, sizeof(schedSkip));
  if (cfg.getBytesLength("sch") == sizeof(Sched) * MAX_SCHED) {
    cfg.getBytes("sch", scheds, sizeof(Sched) * MAX_SCHED);
    schedCount = min((int)cfg.getUChar("schN", 0), (int)MAX_SCHED);
  }
  autoCount = 0;
  if (cfg.getBytesLength("aut") == sizeof(Autom) * MAX_AUTO) {
    cfg.getBytes("aut", autos, sizeof(Autom) * MAX_AUTO);
    autoCount = min((int)cfg.getUChar("autN", 0), (int)MAX_AUTO);
  } else if (cfg.getBytesLength("aut") == sizeof(Autom) * OLD_MAX_AUTO) {   // raised the cap 10 -> 40
    cfg.getBytes("aut", autos, sizeof(Autom) * OLD_MAX_AUTO);
    autoCount = min((int)cfg.getUChar("autN", 0), (int)OLD_MAX_AUTO);
    saveAutos();
  } else if (cfg.getBytesLength("aut") == sizeof(AutomV2) * OLD_MAX_AUTO) {   // migrate rules saved by ..
    static AutomV2 old[OLD_MAX_AUTO];
    cfg.getBytes("aut", old, sizeof(old));
    autoCount = min((int)cfg.getUChar("autN", 0), (int)OLD_MAX_AUTO);
    for (int i = 0; i < autoCount; i++) {
      memset(&autos[i], 0, sizeof(Autom));
      memcpy(&autos[i], &old[i], offsetof(AutomV2, metric) + 1);
      autos[i].limit2 = 70;
    }
    saveAutos();
  }
  ntfyTopic = cfg.getString("ntfy", "");
  notifyTypes = cfg.getUInt("ntypes", 0xFFFFFFFF);
  for (int i = 0; i < MAX_AUTO; i++) { autoArmed[i] = true; autoSince[i] = 0; }
}

// ---------- strips the hub has seen (shown as offline instead of disappearing) ----------
const int MAX_KNOWN = 16;
Known known[MAX_KNOWN];
int knownCount = 0;

// a rule or schedule must point at a strip the hub has seen (online now or remembered)
bool macKnown(String m) {
  m.toUpperCase();
  if (m.length() != 12) return false;
  if (findStrip(m) >= 0) return true;
  for (int i = 0; i < knownCount; i++) if (known[i].mac == m) return true;
  return false;
}

void refreshKnown(const String& mac) {
  int k = -1;
  for (int i = 0; i < knownCount; i++) if (known[i].mac == mac) k = i;
  if (k < 0) {
    if (knownCount >= MAX_KNOWN) return;
    k = knownCount++;
    String list;
    for (int i = 0; i < knownCount; i++) { if (i) list += ","; list += (i == k ? mac : known[i].mac); }
    cfg.putString("known", list);
  }
  Known& n = known[k];
  n.mac = mac;
  n.label = cfg.getString(("n" + mac).c_str(), "");
  for (int o = 0; o < 4; o++) n.olabel[o] = cfg.getString(("n" + mac + String(o + 1)).c_str(), "");
  n.lock = cfg.getUChar(("l" + mac).c_str(), 0);
  n.prot = cfg.getUChar(("p" + mac).c_str(), 0);
  n.keep = cfg.getUChar(("q" + mac).c_str(), 0);
  n.notify = cfg.getUChar(("m" + mac).c_str(), 0x1F);
  if (cfg.getBytesLength(("x" + mac).c_str()) == sizeof(n.amp)) cfg.getBytes(("x" + mac).c_str(), n.amp, sizeof(n.amp));
  else memset(n.amp, 0, sizeof(n.amp));
}

void loadKnown() {
  knownCount = 0;
  String list = cfg.getString("known", "");
  for (const String& m : split(list, ',')) if (m.length() == 12 && knownCount < MAX_KNOWN) { known[knownCount].mac = m; knownCount++; }
  for (int i = 0; i < knownCount; i++) refreshKnown(known[i].mac);
}

void forgetKnown(const String& mac) {
  String list;
  int w = 0;
  for (int i = 0; i < knownCount; i++) {
    if (known[i].mac == mac) continue;
    known[w++] = known[i];
  }
  knownCount = w;
  for (int i = 0; i < knownCount; i++) { if (i) list += ","; list += known[i].mac; }
  cfg.putString("known", list);
}

bool hasSched(const String& mac, int outlet);
bool hasRule(const String& mac, int outlet);

String offlineStripJson(const Known& n) {
  String outs = "[";
  for (int k = 0; k < 4; k++) {
    if (k) outs += ",";
    outs += "{\"n\":" + String(k + 1) + ",\"on\":false,\"power_w\":0,\"energy_kwh\":0,\"temp_c\":0,\"label\":\"" + jsonEsc(n.olabel[k]) +
            "\",\"locked\":" + ((n.lock & (1 << k)) ? "true" : "false") + ",\"protected\":" + ((n.prot & (1 << k)) ? "true" : "false") +
            ",\"keep_on\":" + ((n.keep & (1 << k)) ? "true" : "false") +
            ",\"amp_limit\":" + (n.amp[k] ? String(n.amp[k] * 0.5f, 1) : "0") +
            ",\"auto_off_min\":0,\"auto_off_in_s\":-1,\"sched\":" + (hasSched(n.mac, k + 1) ? "true" : "false") +
            ",\"rule\":" + (hasRule(n.mac, k + 1) ? "true" : "false") + "}";
  }
  return "{\"mac\":\"" + n.mac + "\",\"label\":\"" + jsonEsc(n.label) + "\",\"fw\":\"\",\"online\":false,\"on\":false,\"power_w\":0,\"voltage\":null,\"rssi\":null,\"notify\":" +
         String(n.notify) + ",\"sched\":" + (hasSched(n.mac, 0) ? "true" : "false") + ",\"rule\":" + (hasRule(n.mac, 0) ? "true" : "false") +
         ",\"outlets\":" + outs + "]}";
}

// ---------- strips removed from the app are ignored until they are added again ----------
bool isBlocked(const String& mac) { return ("," + cfg.getString("block", "") + ",").indexOf("," + mac + ",") >= 0; }
void setBlocked(const String& mac, bool on) {
  String out;
  for (const String& m : split(cfg.getString("block", ""), ',')) {
    if (m.length() != 12 || m == mac) continue;
    if (out.length()) out += ",";
    out += m;
  }
  if (on) { if (out.length()) out += ","; out += mac; }
  cfg.putString("block", out);
}
String offlineMacs;                               // strips that dropped off, to report when they come back

