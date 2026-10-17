// Host test: real per-outlet current (see run.sh). The functions under test are copied verbatim from the hub source.
#include "Arduino.h"
#include <vector>
#include <string>
#include <cstdio>
#include <cmath>
#include <cassert>
#include <algorithm>
using std::max;

static uint32_t nowMs = 100000;
uint32_t millis() { return nowMs; }
class WiFiClient {};
const uint8_t MAX_STRIPS = 2;
const uint32_t POLL_MS = 2000;
const uint8_t DIAG_EVERY = 3;
volatile bool liveDirty = false;
volatile bool stateDirty = false;
uint32_t lastPoll = 0, pollCount = 0;

#include "types.inc"
Strip strips[MAX_STRIPS];

std::vector<std::string> sent;
void sendLine(Strip&, const String& l) { sent.push_back(l.c_str()); }
int voltChecks = 0;
void voltCheck(Strip&) { voltChecks++; }
std::vector<std::string> events;
void addEvent(const String& type, const String&, int, const String& msg) { events.push_back(std::string(type.c_str()) + ":" + msg.c_str()); }

#include "code.inc"

static int fails = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); fails++; } } while (0)

static Strip fresh() { Strip s; s.used = true; s.identified = true; s.mac = "AABBCC112233"; s.voltage = 230.0f; return s; }
static void ask(Strip& s) { sent.clear(); askCurrent(s); }

int main() {
  // ---- a good :current answer
  { Strip s = fresh(); s.o[1].on = true; s.o[1].powerW = 148.0f;
    ask(s);
    CHECK(sent.size() == 1 && sent[0] == "up:power_report:2:current" && s.pwrKind == 2 && s.pwrCh == 2);
    handlePowerReport(s, "up:power_report:2:722");
    CHECK(s.pwrKind == 0 && fabsf(s.curA[1] - 0.722f) < 1e-6 && s.curAt[1] != 0 && liveDirty);
    CHECK(curValid(s, 1, nowMs));
    CHECK(fabsf(outletAmps(s, 1, 230.0f, nowMs) - 0.722f) < 1e-6);                 // real current preferred
    CHECK(fabsf(outletAmpsMax(s, 1, 230.0f, nowMs) - 148.0f / 230.0f) < 1e-3 || outletAmpsMax(s, 1, 230.0f, nowMs) >= 0.722f);
    // the protections never see less than the estimate
    s.curA[1] = 0.30f;
    CHECK(fabsf(outletAmpsMax(s, 1, 230.0f, nowMs) - 148.0f / 230.0f) < 1e-4);
    s.curA[1] = 0.90f;
    CHECK(fabsf(outletAmpsMax(s, 1, 230.0f, nowMs) - 148.0f / 230.0f) < 1e-4);   // one reading alone: estimate
    s.preA[1] = 0.95f; s.preAt[1] = s.curAt[1] - 6000; CHECK(fabsf(outletAmpsMax(s, 1, 230.0f, nowMs) - 0.90f) < 1e-6);   // confirmed by the one before
    // validity: load changed a lot, too old, switched off
    s.o[1].powerW = 400.0f;  CHECK(!curValid(s, 1, nowMs));
    s.o[1].powerW = 155.0f;  CHECK(curValid(s, 1, nowMs));                          // inside 15 % + 10 W
    CHECK(!curValid(s, 1, nowMs + 45002));
    CHECK(curValid(s, 1, nowMs + 44000));
    s.o[1].on = false;       CHECK(!curValid(s, 1, nowMs)); CHECK(outletAmps(s, 1, 230.0f, nowMs) == 0 && outletAmpsMax(s, 1, 230.0f, nowMs) == 0);
  }
  // ---- no real reading: estimate, exactly W / V
  { Strip s = fresh(); s.o[0].on = true; s.o[0].powerW = 460.0f;
    CHECK(!curValid(s, 0, nowMs));
    CHECK(fabsf(outletAmps(s, 0, 230.0f, nowMs) - 2.0f) < 1e-6 && fabsf(outletAmpsMax(s, 0, 230.0f, nowMs) - 2.0f) < 1e-6);
  }
  // ---- wrong unit: a :current answer in the mV range is never a voltage; three of them stop the asking
  { Strip s = fresh(); s.o[0].on = true; s.o[0].powerW = 148.0f; s.voltage = 231.0f; voltChecks = 0;
    for (int n = 0; n < 3; n++) {
      s.pwrKind = 0; nowMs += 4000;
      ask(s); CHECK(sent.size() == 1);
      handlePowerReport(s, "up:power_report:1:148000");            // would be "148 V" if read as volts
      CHECK(s.voltage == 231.0f && voltChecks == 0 && s.curAt[0] == 0);
    }
    CHECK(s.curBad);
    s.pwrKind = 0; nowMs += 4000; ask(s); CHECK(sent.empty());      // stopped
  }
  // ---- non-numeric / out-of-range answers change nothing and free the request
  { Strip s = fresh(); s.o[0].on = true; s.o[0].powerW = 50.0f;
    ask(s); handlePowerReport(s, "up:power_report:1:abc"); CHECK(s.pwrKind == 0 && s.curAt[0] == 0 && !s.curBad);
    nowMs += 4000; ask(s); handlePowerReport(s, "up:power_report:1:"); CHECK(s.pwrKind == 0 && s.curAt[0] == 0);
    nowMs += 4000; ask(s); handlePowerReport(s, "up:power_report:1:25000"); CHECK(s.pwrKind == 0 && s.curAt[0] == 0 && !s.curBad);   // 25 A is not credible
    nowMs += 4000; ask(s); handlePowerReport(s, "up:power_report:1:-5"); CHECK(s.pwrKind == 0 && s.curAt[0] == 0);
  }
  // ---- answers for another channel while one is pending
  { Strip s = fresh(); s.o[0].on = true; s.o[0].powerW = 50.0f; s.o[2].on = true; s.o[2].powerW = 80.0f;
    ask(s);                                                         // asks channel 1
    handlePowerReport(s, "up:power_report:3:500");
    CHECK(s.pwrKind == 2 && s.curAt[2] == 0 && s.curAt[0] == 0);   // not for the pending channel: ignored
    handlePowerReport(s, "up:power_report:1:230000");              // hmm: same channel, mV range -> counts as a wrong-unit answer
    CHECK(s.pwrKind == 0 && s.curBadN == 1);
  }
  // ---- a late voltage answer while a current request for another channel is pending is still a voltage
  { Strip s = fresh(); s.o[1].on = true; s.o[1].powerW = 100.0f; voltChecks = 0;
    ask(s); CHECK(s.pwrCh == 2);
    handlePowerReport(s, "up:power_report:1:229500");
    CHECK(fabsf(s.voltage - 229.5f) < 1e-3 && voltChecks == 1 && s.pwrKind == 2);   // still waiting for channel 2
  }
  // ---- voltage requests
  { Strip s = fresh(); s.pwrKind = 1; s.pwrCh = 1; voltChecks = 0;
    handlePowerReport(s, "up:power_report:1:232000");
    CHECK(fabsf(s.voltage - 232.0f) < 1e-3 && voltChecks == 1 && s.pwrKind == 0);
    handlePowerReport(s, "up:power_report:1:700");                  // a mA-sized number with nothing pending is not a voltage
    CHECK(fabsf(s.voltage - 232.0f) < 1e-3 && voltChecks == 1);
    handlePowerReport(s, "up:power_report:garbage");                 // no second field: ignored
    CHECK(voltChecks == 1);
  }
  // ---- rotation over the outlets that are on, one request in flight, 3 s timeout
  { Strip s = fresh(); s.o[0].on = true; s.o[2].on = true; s.o[0].powerW = 10; s.o[2].powerW = 10;
    nowMs += 10000;
    ask(s); CHECK(sent.size() == 1 && sent[0] == "up:power_report:1:current");
    ask(s); CHECK(sent.empty());                                    // pending, under 3 s
    nowMs += 3001;
    ask(s); CHECK(sent.size() == 1 && sent[0] == "up:power_report:3:current");
    nowMs += 3001; ask(s); CHECK(sent.size() == 1 && sent[0] == "up:power_report:1:current");
    Strip n = fresh(); ask(n); CHECK(sent.empty());                 // nothing on: nothing asked
  }
  // ---- the poll slots: slot 0 voltage + rssi, slot 1 one current request, slot 2 nothing extra
  { for (int i = 0; i < MAX_STRIPS; i++) strips[i] = Strip();
    strips[0] = fresh(); strips[0].o[0].on = true; strips[0].o[0].powerW = 10;
    nowMs += 10000; lastPoll = 0;
    pollCount = 2; sent.clear(); pollStrips();                      // -> pollCount 3: slot 0
    CHECK(sent.size() == 3 && sent[0] == "up:getinfo:all" && sent[1] == "up:power_report:1:vol" && sent[2] == "up:query:wifirssi" && strips[0].pwrKind == 1);
    nowMs += 2000; sent.clear(); pollStrips();   // slot 1: only the state
    CHECK(sent.size() == 1 && sent[0] == "up:getinfo:all" && strips[0].pwrKind == 1);
    nowMs += 2000; sent.clear(); pollStrips();   // slot 2: the voltage answer never came, 4 s later the current is still asked
    CHECK(sent.size() == 2 && sent[1] == "up:power_report:1:current" && strips[0].pwrKind == 2);
    for (auto& l : sent) CHECK((l.size() < 6 || l.substr(l.size() - 6) != ":power"));
  }
  // ---- protections need two readings in a row; one spike never counts
  { Strip s = fresh(); s.o[0].on = true; s.o[0].powerW = 460.0f;     // estimate 2.0 A
    ask(s); handlePowerReport(s, "up:power_report:1:6000");           // spike 6 A
    CHECK(outletAmps(s, 0, 230.0f, nowMs) == 6.0f);                   // shown
    CHECK(fabsf(outletAmpsMax(s, 0, 230.0f, nowMs) - 2.0f) < 1e-4);   // but protections still see the estimate
    nowMs += 3500; s.pwrKind = 0; ask(s); handlePowerReport(s, "up:power_report:1:5800");
    CHECK(fabsf(outletAmpsMax(s, 0, 230.0f, nowMs) - 5.8f) < 1e-4);   // confirmed: the lower of the two
    nowMs += 3500; s.pwrKind = 0; ask(s); handlePowerReport(s, "up:power_report:1:2100");
    CHECK(fabsf(outletAmpsMax(s, 0, 230.0f, nowMs) - 2.1f) < 1e-4);
    nowMs += 70000; CHECK(!curValid(s, 0, nowMs));                    // old
  }
  // ---- a reading from before a 24-day wrap is not fresh again
  { Strip s = fresh(); s.o[0].on = true; s.o[0].powerW = 460.0f; s.curA[0] = 9.0f; s.curPw[0] = 460.0f; s.curAt[0] = 5001;
    CHECK(!curValid(s, 0, 5001u + 0x80000000u + 10)); CHECK(!curValid(s, 0, 5001u + 0xFFFFF000u));
    CHECK(curValid(s, 0, 5001 + 40000)); CHECK(curValid(s, 0, 4990));  // a few ms "older" now is still fine
  }
  // ---- after the third wrong-unit answer the readings are dropped
  { Strip s = fresh(); s.o[0].on = true; s.o[0].powerW = 460.0f; s.curA[0] = 9.0f; s.curPw[0] = 460.0f; s.curAt[0] = nowMs;
    for (int n = 0; n < 3; n++) { s.pwrKind = 0; nowMs += 4000; ask(s); handlePowerReport(s, "up:power_report:1:230000"); }
    CHECK(s.curBad && !curValid(s, 0, nowMs));
  }
  printf(fails ? "FAILED %d\n" : "ALL PASSED\n", fails);
  return fails != 0;
}
