// Fisha hub: the on/off log of every outlet. Part of mttl_hub.ino, included in order from there.
// ---------- outlet cycle log (kept on the hub, about 30 days) ----------
// One record per finished cycle (the outlet went on, then off): when, how long, how much energy and what started it. Two
// files on the flash filesystem take turns (each holds OLOG_PER_FILE records); when one is full the other is emptied and
// used, so the log never grows past 2 x OLOG_PER_FILE records and no write needs more than a record of memory.
#define OLOG_PER_FILE 750
struct OLogRec {
  uint32_t on, off;      // epoch seconds (UTC)
  uint32_t wh;           // energy used in the cycle, Wh
  uint8_t mac[6];
  uint8_t outlet;        // 1..4
  uint8_t src;           // 0 = the strip's own button, 1 = a command from the hub (app, schedule, rule, timer)
};
static_assert(sizeof(OLogRec) == 20, "OLogRec must be 20 bytes");

// what is running now, per strip slot and outlet
struct OLogOpen { bool on = false; uint32_t since = 0, wh0 = 0, whLast = 0; uint8_t src = 0; };
OLogOpen olOpen[MAX_STRIPS][4];
uint8_t olFile = 0;                                    // the file being appended to
bool olPicked = false;
const char* olPath(uint8_t i) { return i ? "/olog1.bin" : "/olog0.bin"; }

bool olMac(const String& mac, uint8_t out[6]) {   // "88D0390B1ABA" or "88:D0:39:0B:1A:BA"
  int n = 0, hi = -1;
  for (unsigned i = 0; i < mac.length() && n < 6; i++) {
    char c = mac[i];
    int v = (c >= '0' && c <= '9') ? c - '0' : (c >= 'a' && c <= 'f') ? c - 'a' + 10 : (c >= 'A' && c <= 'F') ? c - 'A' + 10 : -1;
    if (v < 0) continue;
    if (hi < 0) hi = v;
    else { out[n++] = (uint8_t)(hi * 16 + v); hi = -1; }
  }
  return n == 6;
}

// the end time of the last record of a file (0 = empty or missing)
static uint32_t olLastOff(uint8_t i) {
  if (!fsOk || !LittleFS.exists(olPath(i))) return 0;
  File f = LittleFS.open(olPath(i), "r");
  if (!f || f.size() < sizeof(OLogRec)) { if (f) f.close(); return 0; }
  f.seek(f.size() / sizeof(OLogRec) * sizeof(OLogRec) - sizeof(OLogRec));
  OLogRec r = {};
  uint32_t off = f.read((uint8_t*)&r, sizeof r) == sizeof r ? r.off : 0;
  f.close();
  return off;
}
// after a restart: keep appending to the file that holds the newest cycle
static void olPick() {
  if (olPicked || !fsOk) return;
  olPicked = true;
  olFile = olLastOff(1) > olLastOff(0) ? 1 : 0;
}

void olAppend(const OLogRec& r) {
  if (!fsOk) return;
  olPick();
  File f = LittleFS.open(olPath(olFile), "a");
  if (!f) return;
  if (f.size() >= OLOG_PER_FILE * sizeof(OLogRec)) {   // full: switch to the other file and start it empty
    f.close();
    olFile ^= 1;
    LittleFS.remove(olPath(olFile));
    f = LittleFS.open(olPath(olFile), "a");
    if (!f) return;
  }
  f.write((const uint8_t*)&r, sizeof r);
  f.close();
}

// called every loop: notices an outlet that went on or off since the last look
void outletLogTick() {
  static uint32_t last = 0;
  if (millis() - last < 1000 || !timeOk()) return;
  last = millis();
  uint32_t now = (uint32_t)time(nullptr);
  for (int i = 0; i < MAX_STRIPS; i++) {
    Strip& s = strips[i];
    if (!s.used || !s.identified) {
      for (int k = 0; k < 4; k++) {
        OLogOpen& o = olOpen[i][k];
        if (!o.on) continue;
        o.on = false;                                   // the strip left while the outlet was on: keep that cycle up to now
        OLogRec r = {};
        r.on = o.since; r.off = now;
        r.wh = o.whLast >= o.wh0 ? o.whLast - o.wh0 : 0;
        if (olMac(s.mac, r.mac) && r.off > r.on) { r.outlet = k + 1; r.src = o.src; olAppend(r); }
      }
      continue;
    }
    for (int k = 0; k < 4; k++) {
      OLogOpen& o = olOpen[i][k];
      bool on = s.o[k].on;
      if (o.on) o.whLast = s.o[k].energyWh;
      if (on && !o.on) {
        o.on = true; o.since = now; o.wh0 = s.o[k].energyWh;
        o.src = (s.cmdAt[k] && millis() - s.cmdAt[k] < 8000) ? 1 : 0;
      } else if (!on && o.on) {
        o.on = false;
        OLogRec r = {};
        r.on = o.since; r.off = now;
        r.wh = s.o[k].energyWh >= o.wh0 ? s.o[k].energyWh - o.wh0 : 0;
        if (!olMac(s.mac, r.mac)) continue;
        r.outlet = k + 1; r.src = o.src;
        if (r.off > r.on) olAppend(r);
      }
    }
  }
}

// the newest cycles of one outlet (outlet 0 = every outlet of the strip) in the last [days] days, newest first
String outletLogJson(const String& mac, int outlet, int days) {
  uint8_t m[6];
  if (!olMac(mac, m)) return "{\"cycles\":[]}";
  const int MAXN = 80;
  static OLogRec ring[MAXN];
  int cnt = 0;
  olPick();
  uint32_t from = timeOk() ? (uint32_t)time(nullptr) - (uint32_t)constrain(days, 1, 30) * 86400UL : 0;
  for (int pass = 0; pass < 2; pass++) {               // the older file first, so the ring ends with the newest
    uint8_t fi = pass == 0 ? (olFile ^ 1) : olFile;
    if (!fsOk || !LittleFS.exists(olPath(fi))) continue;
    File f = LittleFS.open(olPath(fi), "r");
    if (!f) continue;
    OLogRec buf[16];                                    // 16 records per read: one read per record would hold the loop for long
    size_t got;
    while ((got = f.read((uint8_t*)buf, sizeof buf)) >= sizeof(OLogRec)) {
      for (size_t q = 0; q < got / sizeof(OLogRec); q++) {
        const OLogRec& r = buf[q];
        if (memcmp(r.mac, m, 6) != 0 || r.off < from) continue;
        if (outlet > 0 && r.outlet != outlet) continue;
        ring[cnt % MAXN] = r;
        cnt++;
      }
    }
    f.close();
  }
  int n = cnt < MAXN ? cnt : MAXN;
  String j;
  if (!j.reserve(n * 68 + 320)) return "{\"cycles\":[]}";
  j += "{\"cycles\":[";
  bool first = true;
  for (int q = 0; q < n; q++) {                        // newest first
    const OLogRec& r = ring[(cnt - 1 - q) % MAXN];
    if (!first) j += ",";
    first = false;
    j += "{\"n\":"; j += String(r.outlet);
    j += ",\"on\":"; j += String(r.on);
    j += ",\"off\":"; j += String(r.off);
    j += ",\"wh\":"; j += String(r.wh);
    j += ",\"src\":"; j += String(r.src);
    j += "}";
  }
  // a cycle that is running now
  int idx = findStrip(mac);
  if (idx >= 0) {
    for (int k = 0; k < 4; k++) {
      if (outlet > 0 && k + 1 != outlet) continue;
      const OLogOpen& o = olOpen[idx][k];
      if (!o.on) continue;
      uint32_t wh = strips[idx].o[k].energyWh;
      j += String(first ? "" : ",") + "{\"n\":" + String(k + 1) + ",\"on\":" + String(o.since) + ",\"off\":0,\"wh\":" + String(wh >= o.wh0 ? wh - o.wh0 : 0) + ",\"src\":" + String(o.src) + "}";
      first = false;
    }
  }
  j += "],\"more\":";
  j += cnt > MAXN ? "true" : "false";
  j += "}";
  return j;
}
