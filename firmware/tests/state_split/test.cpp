// Host test for hub 2.15.38: state streamed in pieces, "live" numbers, per-strip cloud messages, 10-strip members list and
// the energy/peak history kept in files. The functions under test are copied verbatim from mttl_hub.ino (see run.sh).
#include "Arduino.h"
#include <vector>
#include <functional>
#include <memory>
#include <new>
#include <map>
#include <set>
#include <string>
#include <cstdio>
#include <ctime>
#include <cassert>
#include <algorithm>
using std::max;
#define constrain(x, lo, hi) ((x) < (lo) ? (lo) : ((x) > (hi) ? (hi) : (x)))

// ---------- stubs for what the hub code around it provides ----------
static uint32_t nowMs = 100000;
uint32_t millis() { return nowMs; }
static time_t nowEpoch = 1760000000;
static time_t test_time(time_t*) { return nowEpoch; }
#define time(p) test_time(p)
extern "C" void* test_realloc(void* p, size_t n) { return realloc(p, n); }
class WiFiClient {};
const uint8_t MAX_STRIPS = 10;
const int MAX_KNOWN = 16;
const uint8_t MAX_USERS = 10;
const int ELOG_DAYS = 90;

#include "types.inc"

Strip strips[MAX_STRIPS];
ElogHead elogs[MAX_STRIPS];
PeakHead peaks[MAX_STRIPS];
uint32_t peakSavedAt[MAX_STRIPS];
Known known[MAX_KNOWN];
int knownCount = 0;
HubUser users[MAX_USERS];
uint8_t userCount = 0;
String hubId = "HUB1";
bool mqttUp = true;
bool fsOk = true;
PubMark pubMarks[MAX_KNOWN];

std::set<std::string> schedOn;            // "MAC:outlet"
bool hasSched(const String& mac, int outlet) { return schedOn.count(std::string(mac.c_str()) + ":" + std::to_string(outlet)) > 0; }
bool hasRule(const String&, int) { return false; }
String stateHeadJson() { return "{\"hub\":\"HUB1\",\"devices\":["; }
String userStateHeadJson(const HubUser& u) { return String("{\"me\":\"") + u.id + "\",\"devices\":["; }
bool timeOkV = true;
bool timeOk() { return timeOkV; }
int32_t dayV = 20000;
int32_t localDay() { return dayV; }
void saveFailed(const char*) {}

// MQTT send queue: refuses a message that doesn't fit while something waits (like mqttPub's byte cap)
struct Pub { std::string topic, body; bool retain; };
std::vector<Pub> pubs;
uint32_t qBytes = 0, qCap = 3000;
bool mqttPub(const String& topic, const String& payload, int, bool retain) {
  if (qBytes && qBytes + payload.length() > qCap) return false;
  qBytes += payload.length();
  pubs.push_back({topic.c_str(), payload.c_str(), retain});
  return true;
}

// files (LittleFS) and NVS
std::map<std::string, std::vector<uint8_t>> files;
std::set<std::string> unreadable;
struct FsStub { bool exists(const String& p) { return files.count(p.c_str()) || unreadable.count(p.c_str()); } } LittleFS;
bool loadBlob(const String& key, void* d, size_t n) {
  std::string p = std::string("/") + key.c_str();
  if (unreadable.count(p)) return false;
  auto it = files.find(p);
  if (it == files.end() || it->second.size() != n) return false;
  memcpy(d, it->second.data(), n);
  return true;
}
int saves = 0;
void saveBlob(const String& key, const void* d, size_t n) {
  saves++;
  files[std::string("/") + key.c_str()] = std::vector<uint8_t>((const uint8_t*)d, (const uint8_t*)d + n);
}
std::map<std::string, std::vector<uint8_t>> nvs;
struct Preferences {
  std::string ns;
  bool begin(const char* n, bool) { ns = n; return true; }
  void end() {}
  size_t getBytesLength(const char* k) { auto it = nvs.find(ns + "/" + k); return it == nvs.end() ? 0 : it->second.size(); }
  size_t getBytes(const char* k, void* d, size_t n) {
    auto it = nvs.find(ns + "/" + k);
    if (it == nvs.end() || it->second.size() > n) return 0;
    memcpy(d, it->second.data(), it->second.size());
    return it->second.size();
  }
  size_t putBytes(const char* k, const void* d, size_t n) { nvs[ns + "/" + k] = std::vector<uint8_t>((const uint8_t*)d, (const uint8_t*)d + n); return n; }
};

#include "code.inc"

// ---------- helpers ----------
static int fails = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL %s:%d  %s\n", __FILE__, __LINE__, #c); fails++; } } while (0)
static const char* outDir = ".";
static void save(const char* name, const String& s) {
  char p[256]; snprintf(p, sizeof p, "%s/out_%s.json", outDir, name);
  FILE* f = fopen(p, "w"); fwrite(s.c_str(), 1, s.length(), f); fclose(f);
}
static String streamed(const HubUser* u, int* pieces = nullptr) {
  String all; int n = 0;
  bool ok = stateStream(u, [&](const String& p) { all += p; n++; return true; });
  CHECK(ok);
  if (pieces) *pieces = n;
  return all;
}
static int count(const std::string& topicPart, const char* body = nullptr) {
  int n = 0;
  for (auto& p : pubs) if (p.topic.find(topicPart) != std::string::npos && (!body || p.body == body)) n++;
  return n;
}
// drains the queue between passes until nothing more goes out
static void drainAll() { for (int i = 0; i < 50; i++) { size_t before = pubs.size(); qBytes = 0; publishStrips(); if (pubs.size() == before) break; } qBytes = 0; }

static void fixture() {
  for (int i = 0; i < MAX_STRIPS; i++) strips[i] = Strip();
  Strip& a = strips[0];
  a.used = a.identified = true; a.mac = "AAAAAA000001"; a.label = "Desk \"1\""; a.fw = "F1.0.82"; a.ip = "192.168.1.20";
  a.o[0].on = true; a.o[0].powerW = 12.5f; a.o[0].energyWh = 1234; a.o[0].tempC = 35;
  a.voltage = 230.4f; a.hasRssi = true; a.rssi = -60; a.connectedAt = nowMs - 5000; a.autoOffAt[1] = nowMs + 90000;
  Strip& b = strips[3];
  b.used = b.identified = true; b.mac = "AAAAAA000002"; b.voltage = NAN; b.hasRssi = false; b.connectedAt = nowMs;
  strips[5].used = true; strips[5].mac = "AAAAAA000009";          // connected, not identified yet: never shown
  const char* km[] = {"AAAAAA000001", "AAAAAA000002", "AAAAAA000003", "AAAAAA000004"};
  knownCount = 4;
  for (int k = 0; k < 4; k++) { known[k] = Known(); known[k].mac = km[k]; known[k].notify = 0x1F; }
  known[2].label = "Kitchen";
  userCount = 2;
  memset(users, 0, sizeof users);
  strcpy(users[0].id, "u1"); users[0].all = 0; parseStrips(users[0], "aaaaaa000002, AAAAAA000003");
  strcpy(users[1].id, "u2"); users[1].all = 1;
}

int main(int argc, char** argv) {
  if (argc > 1) outDir = argv[1];
  fixture();

  // T1 the streamed state is head + online strips + remembered strips + "]}", members only see theirs
  {
    String exp = stateHeadJson() + stripJson(0) + "," + stripJson(3) + "," + offlineStripJson(known[2]) + "," + offlineStripJson(known[3]) + "]}";
    int pieces = 0;
    String got = streamed(nullptr, &pieces);
    CHECK(got == exp);
    CHECK(pieces == 1 + 4 + 3 + 1);              // head, 4 strips, 3 commas, tail
    save("state_owner", got);
    CHECK(stateJsonFor(nullptr) == exp);
    String expU = userStateHeadJson(users[0]) + stripJson(3) + "," + offlineStripJson(known[2]) + "]}";
    CHECK(streamed(&users[0]) == expU);
    CHECK(stateJsonFor(&users[0]) == expU);
    save("state_u1", expU);
    // a failed send stops at once
    int calls = 0;
    CHECK(!stateStream(nullptr, [&](const String&) { return ++calls < 3; }));
    CHECK(calls == 3);
    // nothing to show: still valid
    HubUser none; memset(&none, 0, sizeof none); strcpy(none.id, "u9");
    CHECK(streamed(&none) == userStateHeadJson(none) + "]}");
  }
  // T2 live numbers
  {
    String lv = liveJson(nullptr);
    save("live_owner", lv);
    CHECK(lv.indexOf("\"mac\":\"AAAAAA000001\",\"v\":230.4,\"r\":-60,\"up\":5,") > 0);
    CHECK(lv.indexOf("[1,12.50,1.234,35,-1,-1],[0,0.00,0.000,0,90,-1]") > 0);
    CHECK(lv.indexOf("\"mac\":\"AAAAAA000002\",\"v\":null,\"r\":null,\"up\":0,") > 0);
    CHECK(lv.indexOf("AAAAAA000003") < 0 && lv.indexOf("AAAAAA000009") < 0);   // offline / not identified: not in live
    String lu = liveJson(&users[0]);
    save("live_u1", lu);
    CHECK(lu.indexOf("AAAAAA000002") > 0 && lu.indexOf("AAAAAA000001") < 0);
    HubUser none; memset(&none, 0, sizeof none);
    CHECK(liveJson(&none) == String("{\"ts\":") + String((uint32_t)nowEpoch) + ",\"d\":[]}");
  }
  // T3 cloud head: everything but the strips, plus the strip list in the same order
  {
    String h = mqttHead(nullptr);
    save("head_owner", h);
    CHECK(h == "{\"hub\":\"HUB1\",\"strips\":[\"AAAAAA000001\",\"AAAAAA000002\",\"AAAAAA000003\",\"AAAAAA000004\"]}");
    String hu = mqttHead(&users[0]);
    save("head_u1", hu);
    CHECK(hu == "{\"me\":\"u1\",\"strips\":[\"AAAAAA000002\",\"AAAAAA000003\"]}");
  }
  // T4 per-strip cloud messages: every strip once, members only theirs, a full queue just delays
  {
    pubs.clear(); qBytes = 0; pubMarksReset();
    drainAll();
    CHECK(count("HUB1/s/AAAAAA000001") == 1 && count("HUB1/s/AAAAAA000002") == 1 && count("HUB1/s/AAAAAA000003") == 1 && count("HUB1/s/AAAAAA000004") == 1);
    CHECK(count("u/u1/s/AAAAAA000002") == 1 && count("u/u1/s/AAAAAA000003") == 1);
    CHECK(count("u/u1/s/AAAAAA000001") == 0 && count("u/u1/s/AAAAAA000004") == 0);
    CHECK(count("u/u2/s/") == 4);
    CHECK(pubs.size() == 4 + 2 + 4);
    for (auto& p : pubs) CHECK(p.retain && p.body.size() > 100);
    // the body is the same strip JSON the phones get
    for (auto& p : pubs) if (p.topic == "mttl/HUB1/s/AAAAAA000001") CHECK(p.body == stripJson(0).c_str());
    // nothing changed: nothing sent
    pubs.clear(); nowMs += 1000; drainAll();
    CHECK(pubs.empty());
    // a name change: that strip only (owner + members who have it)
    strips[0].olabel[2] = "Lamp";
    pubs.clear(); nowMs += 1000; drainAll();
    CHECK(pubs.size() == 2 && count("s/AAAAAA000001") == 2);
    // load moved: not within 3 s of the last send, then yes
    strips[0].o[0].powerW = 100;
    pubs.clear(); nowMs += 2000; drainAll();
    CHECK(pubs.empty());
    pubs.clear(); nowMs += 1500; drainAll();
    CHECK(pubs.size() == 2 && count("s/AAAAAA000001") == 2);
    // a small drift: nothing until the 60 s refresh, which sends the online strips only
    strips[0].o[0].powerW = 101;
    pubs.clear(); nowMs += 5000; drainAll();
    CHECK(pubs.empty());
    pubs.clear(); nowMs += 61000; drainAll();
    CHECK(count("HUB1/s/AAAAAA000001") == 1 && count("HUB1/s/AAAAAA000002") == 1 && count("HUB1/s/AAAAAA000003") == 0);
    // a remembered strip changes (renamed in the app while offline)
    known[3].label = "Garage";
    pubs.clear(); nowMs += 1000; drainAll();
    CHECK(pubs.size() == 2 && count("s/AAAAAA000004") == 2);
    // a strip removed in the app: its retained copies are wiped (owner + every member), once
    knownCount = 3;
    pubs.clear(); nowMs += 1000; drainAll();
    CHECK(count("HUB1/s/AAAAAA000004", "") == 1 && count("u/u1/s/AAAAAA000004", "") == 1 && count("u/u2/s/AAAAAA000004", "") == 1);
    pubs.clear(); nowMs += 1000; drainAll();
    CHECK(pubs.empty());
    // a tiny queue: one message per pass, still all of them in the end, no member gets a strip it doesn't have
    qCap = 1; pubs.clear(); pubMarksReset();
    for (int i = 0; i < 50; i++) { qBytes = 0; publishStrips(); }
    CHECK(count("HUB1/s/") == 3 && count("u/u1/s/") == 2 && count("u/u2/s/") == 3);
    qCap = 3000;
    // members changed while copies were waiting: u1 removed (u2 moves to index 0), then the queue frees up
    pubs.clear(); qBytes = 999999; strips[3].label = "Desk 2"; nowMs += 1000;
    publishStrips();                                  // marks set, nothing fits
    CHECK(pubs.size() == 0 || (pubs.size() == 1));
    users[0] = users[1]; userCount = 1;               // u1 gone
    strcpy(users[1].id, "zz");
    HubUser lim; memset(&lim, 0, sizeof lim); strcpy(lim.id, "u3"); parseStrips(lim, "AAAAAA000001");
    users[1] = lim; userCount = 2;                    // a new member who has only strip 1
    qBytes = 0; drainAll();
    CHECK(count("u/u3/s/AAAAAA000002") == 0);
    CHECK(count("u/u1/") == 0);
    // a member loses strips: their copies of the others are wiped, paced through the queue
    pubs.clear(); qBytes = 0; nowMs += 1000;
    clearUserStrips(lim, false);
    CHECK(pubs.empty());                              // nothing at once
    qCap = 1;
    for (int i = 0; i < 20; i++) { qBytes = 0; publishStrips(); }
    qCap = 3000;
    CHECK(count("u/u3/s/AAAAAA000002", "") == 1 && count("u/u3/s/AAAAAA000003", "") == 1 && count("u/u3/s/AAAAAA000001", "") == 0);
    pubs.clear(); qBytes = 0; nowMs += 1000; drainAll();
    CHECK(count("u/u3/s/", "") == 0);                 // done once
    // removed member: all its copies at once
    pubs.clear(); qBytes = 0;
    clearUserStrips(lim, true);
    CHECK(count("u/u3/s/", "") == 3);
    qBytes = 0;
  }
  // T5 members: a v2.15 blob (6 strips) loads into the 10-strip layout, saves go to "list2", "list" stays for old firmware
  {
    fixture();
    nvs.clear();
    UsersNVV1 old; memset(&old, 0, sizeof old);
    old.magic = USERS_MAGIC; old.count = 2;
    strcpy(old.u[0].id, "u1"); strcpy(old.u[0].name, "Mona"); old.u[0].role = 1; old.u[0].n = 6; old.u[0].rsv = 5; strcpy(old.u[0].pw, "secretpass1");
    for (int k = 0; k < 6; k++) snprintf(old.u[0].strips[k], 13, "AAAAAA0000%02d", k % 10);
    strcpy(old.u[1].id, "u2"); old.u[1].all = 1;
    nvs["users/list"] = std::vector<uint8_t>((uint8_t*)&old, (uint8_t*)&old + sizeof old);
    userCount = 0; memset(users, 0, sizeof users);
    loadUsers();
    CHECK(userCount == 2);
    CHECK(!strcmp(users[0].name, "Mona") && users[0].role == 1 && users[0].n == 6 && users[0].rsv == 5 && !strcmp(users[0].pw, "secretpass1"));
    CHECK(!strcmp(users[0].strips[5], "AAAAAA000005") && users[0].strips[6][0] == 0);
    CHECK(users[1].all == 1);
    parseStrips(users[0], "AAAAAA000000,AAAAAA000001,AAAAAA000002,AAAAAA000003,AAAAAA000004,AAAAAA000005,AAAAAA000006,"
                          "AAAAAA000007,AAAAAA000008,AAAAAA000009,AAAAAA00000A,AAAAAA00000B");
    CHECK(users[0].n == 10);
    CHECK(userHas(users[0], "aaaaaa000009") && !userHas(users[0], "AAAAAA00000A"));
    saveUsers();
    CHECK(nvs["users/list2"].size() == sizeof(UsersNV));
    CHECK(nvs["users/list"].size() == sizeof(UsersNVV1) && !memcmp(nvs["users/list"].data(), &old, sizeof old));   // untouched
    userCount = 0; memset(users, 0, sizeof users);
    loadUsers();
    CHECK(userCount == 2 && users[0].n == 10 && !strcmp(users[0].strips[9], "AAAAAA000009"));
    // nothing saved: no members (an empty hub)
    nvs.clear(); userCount = 0; loadUsers();
    CHECK(userCount == 0);
  }
  // T6 energy / peak history: RAM keeps the running day, the file the 90 days
  {
    fixture();
    files.clear(); unreadable.clear();
    for (int k = 0; k < 4; k++) strips[0].o[k].energyWh = 1000;
    elogs[0] = ElogHead(); peaks[0] = PeakHead();
    dayV = 20000;
    energyUpdate(0);
    CHECK(elogs[0].magic == 0xE1E1 && elogs[0].day == 20000 && elogs[0].base[2] == 1000);
    CHECK(files.count("/eAAAAAA000001") && files["/eAAAAAA000001"].size() == sizeof(ELog));
    int s0 = saves;
    energyUpdate(0);                               // same day, nothing new: no file write
    CHECK(saves == s0);
    peakUpdate(0, 500);
    peakUpdate(0, 300);
    CHECK(peaks[0].today == 500);
    for (int k = 0; k < 4; k++) strips[0].o[k].energyWh = 1000 + 100 * (k + 1);
    dayV = 20001;
    energyUpdate(0);
    peakUpdate(0, 50);
    CHECK(elogs[0].day == 20001 && elogs[0].base[3] == 1400);
    String ej = energyJson(0);
    save("energy", ej);
    char want[128];
    snprintf(want, sizeof want, "{\"date\":%u,\"wh\":[100,200,300,400],\"peak_w\":500}", (unsigned)civilFromDays(20000));
    CHECK(ej.indexOf(want) > 0);
    CHECK(ej.indexOf("\"today_wh\":[0,0,0,0],\"today_peak_w\":50") > 0);
    // after a restart the head comes back from the file
    elogs[0] = ElogHead(); peaks[0] = PeakHead();
    CHECK(histHeads(0) && elogs[0].day == 20001 && elogs[0].base[0] == 1100 && peaks[0].day == 20001);
    // the counter went back (strip reset): the base follows
    strips[0].o[1].energyWh = 10;
    energyUpdate(0);
    CHECK(elogs[0].base[1] == 10);
    // a file that is there but can't be read is never overwritten
    std::vector<uint8_t> keep = files["/eAAAAAA000001"];
    unreadable.insert("/eAAAAAA000001");
    elogs[0] = ElogHead();
    dayV = 20002;
    s0 = saves;
    energyUpdate(0);
    CHECK(saves == s0 && elogs[0].magic == 0);
    CHECK(energyJson(0).length() == 0);            // the app is told "try again"
    unreadable.clear();
    CHECK(files["/eAAAAAA000001"] == keep);
    energyUpdate(0);                               // readable again: the day rolls over as usual
    CHECK(elogs[0].day == 20002);
    // clock not set: nothing happens
    timeOkV = false; elogs[0] = ElogHead(); s0 = saves;
    energyUpdate(0); peakUpdate(0, 900);
    CHECK(saves == s0);
    timeOkV = true;
  }
  printf(fails ? "%d FAILED\n" : "all passed\n", fails);
  return fails ? 1 : 0;
}
