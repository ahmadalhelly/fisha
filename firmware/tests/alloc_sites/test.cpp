#include <Arduino.h>
#include <string.h>
#include <stdio.h>
#include <stdint.h>
#include "WString.h"
#include "hub_allocsites.h"
#include "code.inc"
static int bad = 0;
#define CHECK(c) do { if (!(c)) { printf("FAIL line %d: %s\n", __LINE__, #c); bad++; } } while (0)
int main() {
  uint32_t a[3] = {0x400d1000, 0x400d2000, 0x400d3000}, b[3] = {0x400d1000, 0x400d2000, 0x400d3004};
  CHECK(allocPcFix(0x800d1234u) == 0x400d1231u);           // as esp_cpu_process_stack_pc(): window bits off, minus 3
  CHECK(allocPcFix(0x400d1234u) == 0x400d1231u && allocPcFix(0xC0081000u) == 0x40080ffdu);
  int s1 = allocSiteNote(1528, a, 3, "loopTask", 100);
  int s2 = allocSiteNote(1528, a, 3, "loopTask", 200);
  CHECK(s1 == 0 && s2 == 0 && allocSites[0].n == 2 && allocSites[0].last == 200 && allocSites[0].depth == 3);
  CHECK(!strcmp(allocSites[0].task, "loopTask") && allocSites[0].size == 1528 && allocSites[0].pc[2] == 0x400d3000);
  CHECK(allocSiteNote(1528, b, 3, "loopTask", 300) == 1);   // other chain = other site
  CHECK(allocSiteNote(900, a, 3, "loopTask", 300) == 2);    // other size = other site
  CHECK(allocSiteNote(1528, a, 3, "a_very_long_task_name", 1) == 0);
  for (int i = 0; i < 20; i++) { uint32_t c[1] = {0x40000000u + (uint32_t)i}; allocSiteNote(1, c, 1, nullptr, 5); }
  CHECK(allocSiteOther > 0);
  uint32_t deep[20]; for (int i = 0; i < 20; i++) deep[i] = i;
  AllocSite z[ALLOC_SITES]; memcpy(allocSites, z, sizeof z); allocSiteOther = 0;
  int s = allocSiteNote(5, deep, 20, "t", 1);
  CHECK(s == 0 && allocSites[0].depth == ALLOC_BT);          // depth is capped, no overflow
  CHECK(allocSiteNote(5, deep, 0, "t", 1) >= 0);              // empty chain is fine
  CHECK(stripFwHasChildLock("F1.0.82") && stripFwHasChildLock("F1.0.85") && stripFwHasChildLock("F1.0.100"));
  CHECK(stripFwHasChildLock("F1.1.0") && stripFwHasChildLock("F2.0.0") && stripFwHasChildLock("F1.0.82-x"));
  CHECK(!stripFwHasChildLock("F1.0.81") && !stripFwHasChildLock("F1.0.9") && !stripFwHasChildLock("1.0.66"));
  CHECK(!stripFwHasChildLock("") && !stripFwHasChildLock("F") && !stripFwHasChildLock("F1") && !stripFwHasChildLock("F1.0") && !stripFwHasChildLock("Fx.y.z"));
  CHECK(!stripFwHasChildLock("F2") && !stripFwHasChildLock("F1.1") && !stripFwHasChildLock("F1.1."));
  CHECK(stripFwHasChildLock("F1.0.82.1") && stripFwHasChildLock("comMTTL-W01_F1.0.85") && stripFwHasChildLock("FW F1.0.85"));
  CHECK(!stripFwHasChildLock("FW F1.0.66") && stripFwHasChildLock("F1.0.99999999999") && !stripFwHasChildLock("F0.9.99999999999"));
  printf(bad ? "FAILED\n" : "alloc_sites: all passed\n");
  return bad;
}
