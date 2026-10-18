// Fisha hub: where the failed memory requests come from. Part of mttl_hub.ino, included in order from there.
// ---------- failed-allocation call sites (diagnostics) ----------
// allocFailCb (hub_sse.h) hands every refused request here with the return addresses of the code that asked. The same
// size from the same call chain is one site, so a table of a few entries shows which line keeps failing (the addresses
// are turned into lines with addr2line on the build's firmware.elf). Plain arrays only: no allocation, no logging.
const uint8_t ALLOC_SITES = 6, ALLOC_BT = 14;
struct AllocSite {
  uint32_t key = 0, n = 0, last = 0, size = 0;
  uint32_t pc[ALLOC_BT] = {0};
  uint8_t depth = 0;
  char task[12] = "";
};
AllocSite allocSites[ALLOC_SITES];
uint32_t allocSiteOther = 0;   // failures from sites that did not fit in the table

// Xtensa return addresses carry the call size in the top two bits; this puts them back to the real code address and
// steps back 3 bytes onto the call itself, the same as ESP-IDF's esp_cpu_process_stack_pc() for panic backtraces
uint32_t allocPcFix(uint32_t pc) { return ((pc & 0x3FFFFFFFu) | 0x40000000u) - 3; }

uint32_t allocSiteKey(uint32_t size, const uint32_t* pc, uint8_t depth) {
  uint32_t h = 2166136261u ^ size;            // FNV-1a over the size and the addresses
  h *= 16777619u;
  for (uint8_t i = 0; i < depth; i++) { h ^= pc[i]; h *= 16777619u; }
  return h ? h : 1;
}

// counts one refused request; returns the table slot used, or -1 when the table is full
int allocSiteNote(uint32_t size, const uint32_t* pc, uint8_t depth, const char* task, uint32_t now) {
  if (depth > ALLOC_BT) depth = ALLOC_BT;
  uint32_t k = allocSiteKey(size, pc, depth);
  int freeAt = -1;
  for (int i = 0; i < ALLOC_SITES; i++) {
    if (allocSites[i].key == k) { allocSites[i].n++; allocSites[i].last = now; return i; }
    if (!allocSites[i].key && freeAt < 0) freeAt = i;
  }
  if (freeAt < 0) { allocSiteOther++; return -1; }
  AllocSite& s = allocSites[freeAt];
  s.key = k; s.n = 1; s.last = now; s.size = size; s.depth = depth;
  for (uint8_t i = 0; i < depth; i++) s.pc[i] = pc[i];
  strncpy(s.task, task ? task : "", sizeof(s.task) - 1);
  s.task[sizeof(s.task) - 1] = 0;
  return freeAt;
}
