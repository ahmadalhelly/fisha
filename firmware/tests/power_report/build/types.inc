struct Outlet { bool on = false; float powerW = 0; uint32_t energyWh = 0; int tempC = 0; };
struct Strip {
  WiFiClient c;
  bool used = false, identified = false, hasRssi = false, gotInfo = false, poked = false;
  String mac, model, fw, ip, rx, pendingInfo, lastLine;
  String label, olabel[4];
  uint8_t lockMask = 0, lockState = 0, protMask = 0, notifyMask = 0x1F;
  bool masterLock = false;                       // strip-level child lock: the strip's own master button does nothing (F1.0.82)
  uint8_t infoOn = 0;                            // outlets on in the last full report (state before a button press)
  uint8_t keepMask = 0, keepHold = 0;            // keep always on · hold = a safety cut is in force
  uint32_t keepEvAt[4] = {0, 0, 0, 0};
  uint16_t autoOffMin[4] = {0, 0, 0, 0};
  uint32_t autoOffAt[4] = {0, 0, 0, 0};
  uint32_t hotSince[4] = {0, 0, 0, 0};
  uint32_t loadEventAt = 0, voltEventAt = 0;
  uint32_t ocSince = 0, vOkSince = 0;            // over-current timer · voltage back to normal since
  uint8_t ovCount = 0, vCutMask = 0;             // consecutive high readings · outlets cut for over-voltage
  uint8_t ampX2[4] = {0, 0, 0, 0};               // per-outlet current limit in 0.5 A steps (0 = none)
  uint32_t ocoSince[4] = {0, 0, 0, 0};           // per-outlet over-current timer
  uint8_t warnA = 0, warnT = 0;                  // near-limit warning already sent (bit per outlet): current · temperature
  uint8_t tripMask = 0, tripTries[4] = {0, 0, 0, 0}; // safety cuts still waiting for the strip to report "off"
  uint32_t tripAt = 0, tripSeq = 0, olSince = 0; // last safety cut sent (time, infoSeq) · over 3500 W since
  bool dead = false;                             // a write could not go out: dropped on the next pump
  String txq;                                    // bytes still waiting to go out to the strip (same bytes, same order)
  uint32_t txSince = 0;                          // when txq started waiting
  float voltage = NAN;
  int rssi = 0;
  Outlet o[4];
  uint32_t lastRx = 0, infoSeq = 0, connectedAt = 0;
  bool connOk = false;                           // strip answered connect_ok to a network handed over on its link
  uint32_t cmdAt[4] = {0, 0, 0, 0};              // when the hub last switched each outlet (to tell button presses apart)
  // real per-outlet current (up:power_report:<ch>:current answers in mA). One power_report request in flight per strip.
  float curA[4] = {0, 0, 0, 0}, curPw[4] = {0, 0, 0, 0};   // last real current (A) and the outlet's power (W) when it was read
  uint32_t curAt[4] = {0, 0, 0, 0};              // when it was read (0 = never)
  uint32_t pwrAt = 0;                            // when the pending power_report request was sent
  uint8_t pwrKind = 0, pwrCh = 0, curNext = 0, curBadN = 0;   // pending request: 0 none · 1 voltage · 2 current (and its channel) · next outlet to ask · answers that were not mA
  bool curBad = false;                           // this strip answers :current in another unit: stop asking
};
