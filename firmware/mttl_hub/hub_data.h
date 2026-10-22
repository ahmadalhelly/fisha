// Fisha hub: types, globals and limits. Part of mttl_hub.ino, included in order from there.
// ---------- data ----------
struct Outlet { bool on = false; float powerW = 0; uint32_t energyWh = 0; int tempC = 0; };

struct ELog {                                    // per-strip daily energy history (Wh)
  uint32_t magic = 0;
  int32_t day = 0;                               // local day number of the running bucket
  uint32_t base[4] = {0, 0, 0, 0};               // counters at the start of that day
  uint32_t wh[ELOG_DAYS][4];
  int32_t dayOf[ELOG_DAYS];
};

struct PeakLog {                                 // per-strip daily highest total load (W)
  uint32_t magic = 0;
  int32_t day = 0;
  uint16_t today = 0;
  uint16_t pk[ELOG_DAYS];
  int32_t dayOf[ELOG_DAYS];
};
// RAM keeps only the running day of each log (the first fields of ELog / PeakLog); the 90-day history stays in
// its file and is read into a short-lived buffer when it changes (once a day) or the app asks for it. Frees ~2.3 KB
// of RAM per strip, which 10 strips need.
struct ElogHead { uint32_t magic = 0; int32_t day = 0; uint32_t base[4] = {0, 0, 0, 0}; };
struct PeakHead { uint32_t magic = 0; int32_t day = 0; uint16_t today = 0; };

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
  bool wifiHandoverSent = false;                 // true only when up:connect: was actually sent to this strip
  uint32_t timeSyncAt = 0;                       // millis() when up:time was last sent (0 = never)
  uint8_t cfgSyncStep = 0;                       // paced F1.0.90 sync: 1=tz, 2=time, 3=limits, 4=sched, 0=done
  uint32_t cmdAt[4] = {0, 0, 0, 0};              // when the hub last switched each outlet (to tell button presses apart)
  // real per-outlet current (up:power_report:<ch>:current answers in mA). One power_report request in flight per strip.
  float curA[4] = {0, 0, 0, 0}, curPw[4] = {0, 0, 0, 0};   // last real current (A) and the outlet's power (W) when it was read
  uint32_t curAt[4] = {0, 0, 0, 0};              // when it was read (0 = never)
  uint32_t pwrAt = 0;                            // when the pending power_report request was sent
  float preA[4] = {0,0,0,0};          // the reading before curA
  uint32_t preAt[4] = {0,0,0,0};
  uint8_t pwrKind = 0, pwrCh = 0, curNext = 0, curBadN = 0;   // pending request: 0 none · 1 voltage · 2 current (and its channel) · next outlet to ask · answers that were not mA
  bool curBad = false;                           // this strip answers :current in another unit: stop asking
};

struct Timer { bool used = false; uint32_t id = 0; char mac[13] = {0}; uint8_t outlet = 0, kind = 0, phase = 0; bool on = false;
               uint32_t at = 0, offMs = 0, onMs = 0, periodS = 0, tries = 0; };
// kind: 0 = switch on/off (once, or every periodS), 1 = reboot: off, wait, on (once, or every periodS),
//       2 = loop: on for onMs, off for offMs, forever. All kept in NVS, so they survive a hub restart.
struct TimerNV { uint32_t id; char mac[13]; uint8_t outlet, kind, on, phase; uint32_t offS, onS, periodS, dueEpoch, remainS; };
struct Known { String mac, label, olabel[4]; uint8_t lock, prot, notify, keep; uint8_t amp[4]; };

struct Sched { uint32_t id; char mac[13]; uint8_t outlet, on, days, hh, mm, enabled; uint32_t date; char label[40]; };
struct AutomV2 { uint32_t id; char mac[13]; uint8_t outlet, above, act, enabled; float watts; uint16_t holdS; char label[40]; uint8_t metric; };
struct Autom { uint32_t id; char mac[13]; uint8_t outlet, above, act, enabled; float watts; uint16_t holdS; char label[40]; uint8_t metric; float limit2; };
// metric 2 = watts OR temperature: "watts" is the W limit and "limit2" the °C limit
// outlet 0 = whole strip (total W / hottest outlet) · metric 0 = power (W), 1 = temperature (°C), 3 = current (A, · "watts" holds the threshold
// act: 1 notify, 2 switch off, 3 both
struct Ev { uint32_t ts = 0; String type, mac, msg; int outlet = 0; };
struct ApiRes { bool ok; String err; String data; };
struct Note { String type, mac, msg; int outlet; };   // queued phone notification (defined early for Arduino auto-prototypes)
struct NoteMsg { char topic[68]; char title[200]; char body[160]; uint8_t high; };   // handed to the notification task
// shared users (hub-managed, EMQX built-in auth + ACL). role 0 view · 1 control · 2 admin
struct HubUser { char id[8]; char name[24]; uint8_t role, all, n, rsv; char strips[10][13]; char pw[20]; };   // 10 strips (was 6)
struct HubUserV1 { char id[8]; char name[24]; uint8_t role, all, n, rsv; char strips[6][13]; char pw[20]; };   // saved before
// HubUser.rsv holds extra permissions the owner grants on top of the role (admins have them all)
const uint8_t P_AUTO = 1, P_PROT = 2, P_SFW = 4, P_WIFI = 8, P_HUBFW = 16, P_EXPORT = 32;
struct UsersNV { uint32_t magic; uint8_t count; HubUser u[10]; };
struct UsersNVV1 { uint32_t magic; uint8_t count; HubUserV1 u[10]; };
const uint8_t USER_STRIPS = 10;                    // strips a member can be given one by one (the rest: "all strips")

Strip strips[MAX_STRIPS];
ElogHead elogs[MAX_STRIPS];
PeakHead peaks[MAX_STRIPS];
uint32_t peakSavedAt[MAX_STRIPS];
Timer timers[MAX_TIMERS];
Sched scheds[MAX_SCHED];
uint32_t schedSkip[MAX_SCHED];                    // ids whose next run is skipped once (own NVS key, Sched layout unchanged)
uint8_t schedCount = 0;
Autom autos[MAX_AUTO];
uint8_t autoCount = 0;
bool autoArmed[MAX_AUTO];
bool autoWarned[MAX_AUTO];                         // near-limit warning sent for this crossing
uint32_t autoSince[MAX_AUTO];
Ev events[MAX_EVENTS];
uint8_t evHead = 0, evCount = 0;
uint32_t nextTimerId = 1;
uint8_t tempMax = 80;
bool tempProtect = true;
// whole-strip protections
bool vProt = true, vRestore = true, aProt = true;
uint16_t vMax = 260;
uint16_t vMin = 180;                               // under-voltage limit (170..260)
float aMax = 16.0f;
uint8_t protHoldS = 3;                             // consecutive readings/seconds before protection trip (1..60, default 3)
char tzZone[16] = "";                              // time zone id from the app's list ("" = the fixed offset below)
int16_t tzOffsetMin = 180;                         // timezone offset in minutes from UTC (default +180 = Egypt UTC+3)
volatile uint32_t rebootAt = 0;

WiFiServer stripServer(STRIP_PORT);
WiFiServer stripServerAlt(STRIP_PORT_ALT);   // strips that switched to 21197 (2026-10-08)
WiFiServer sseServer(SSE_PORT);
WebServer web(WEB_PORT);
Preferences cfg;
bool webRoutesReady = false;
bool stripListenerReady = false;
bool wifiWasConnected = false;
volatile uint8_t wifiLastReason = 0;    // why the hub last lost the home Wi-Fi (ESP-IDF reason code)
volatile uint8_t wifiFirstReason = 0;   // the reason of the first drop of the current outage (later ones are often our own reconnect)
volatile uint16_t wifiReasonCnt[64] = {0};  // drops by reason code: 0..47 as is, 48..62 = codes 200..214, 63 = any other
volatile uint32_t wifiDiscCount = 0;    // home Wi-Fi disconnects since boot (outside provisioning)
volatile uint32_t wifiDiscAt = 0;       // millis() of the last of those disconnects
uint32_t stallMaxMs = 0;                // longest single loop step since boot, and which one
const char* stallWhere = "";
// the slowest blocking call inside the current loop step (named in the "stall" event) and since boot (health)
uint32_t subMax = 0, subWorst = 0;
const char* subWhere = "";
const char* subWorstWhere = "";
String webUri;                          // the request the web step was answering (named in a "web" stall)
uint32_t webSlow = 0;                   // answers cut short because the phone stopped reading
// the lowest internal RAM the loop has seen, and the step that had just run (heap8_min says how low, this says where)
size_t low8 = SIZE_MAX;
const char* low8Where = "";
uint32_t low8At = 0;
uint32_t sseDefer = 0;                  // state pushes put off because no 3 KB block was free
inline void low8Check(const char* where) {
  size_t f = heap_caps_get_free_size(MALLOC_CAP_8BIT | MALLOC_CAP_INTERNAL);
  if (f < low8) { low8 = f; low8Where = where; low8At = millis(); }
}
struct SubT {
  const char* n; uint32_t t;
  SubT(const char* n_) : n(n_), t(millis()) {}
  ~SubT() {
    low8Check(n);
    uint32_t d = millis() - t;
    if (d > subMax) { subMax = d; subWhere = n; }
    if (d > subWorst) { subWorst = d; subWorstWhere = n; }
  }
};
uint32_t lastPoll = 0, pollCount = 0;
volatile bool stateDirty = true;
volatile bool liveDirty = false;               // only report numbers changed (see ssePump)
volatile bool mqttHeadDirty = true;            // something besides numbers changed: the cloud head follows

// MQTT
struct MqttCmd { char payload[640]; char topic[96]; };
esp_mqtt_client_handle_t mqtt = nullptr;
QueueHandle_t mqttQ = nullptr;
volatile bool mqttUp = false, mqttFreshConnect = false;
String nvsId;                                     // changes only when the saved data is erased
String hubId, tStatus, tInfo, tState, tEvent, tCmd, tAck;
char mqttClientId[32];
// why the cloud link is down, and who sent the command being handled
volatile int mqttErrKind = 0, mqttErrCode = 0, mqttErrTls = 0;   // written by the MQTT task
String mqttErr = "";                                               // "" | no_pass | auth | refused | tls | net
volatile bool mqttRestartReq = false;
uint8_t apiSrc = 0;                                                // 0 local HTTP · 1 owner MQTT · 2 shared user
const uint8_t MAX_USERS = 10;
HubUser users[MAX_USERS];
// hub lock. Owner phones hold a secret key; with no owner the hub stays open as before, so older apps keep
// working until the owner locks it from the app. A new phone asks for access and the owner approves by picking the
// number shown on that phone (one of 3), so a stranger on the Wi-Fi can't slip in by accident.
struct OwnerDev { char key[33]; char email[48]; char model[32]; uint32_t ts; };
const uint8_t MAX_OWNERS = 4, MAX_PAIRS = 3;
OwnerDev owners[MAX_OWNERS];
uint8_t ownerCount = 0;
struct PairReq { uint32_t id = 0, at = 0; uint8_t code = 0, ch[3] = {0, 0, 0}, state = 0; bool owner = false, job = false;
                 String email, model, result; };   // state: 0 free · 1 waiting for the owner · 2 approved · 3 refused
PairReq pairs[MAX_PAIRS];
uint32_t pairJobId = 0, claimLockUntil = 0, cloudTodoAt = 0;
const uint32_t CLAIM_WINDOW_MS = 600000;          // the first owner can claim only in the first 10 min after power-on
String cloudTodoId, cloudTodoPw;                   // an approved phone's server login, made in the background
uint8_t claimFails = 0;
uint8_t userCount = 0;
String exUrl, exKey, exSec, exLast;                                // EMQX management API (NVS "sec"), never returned

// provisioning
volatile bool provRequested = false;
uint32_t provAt = 0;
String provState = "idle", provMsg = "", provSsid = "", provTarget = "";   // provTarget = last 7 hex of the new strip's MAC
// strip firmware (.fwr) kept raw in the spare OTA app slot, served to a strip in setup mode
bool provOta = false;                  // this provisioning run flashes the strip instead of pointing it at the hub
uint32_t stripFwSize = 0;              // bytes of the stored .fwr (0 = none), also in NVS "stripfw"/"size"
const uint32_t STRIP_FW_MAX = 0x60000; // 384 KB; stock .fwr files are ~320 KB
String stripOtaLog = "";               // last flash run, shown on /stripfw
bool stripFwOk = false;                // the stored file passed stripFwCheck
String stripFwWhy = "";
struct SuItem { String mac, from, to, state, msg; };   // state: queued, sending, transfer, rebooting, ok, failed, skipped
SuItem suList[MAX_STRIPS];
uint8_t suN = 0, suCur = 0;
enum SuPhase : uint8_t { SU_IDLE, SU_SEND, SU_GET, SU_XFER, SU_BACK, SU_GAP };
SuPhase suPhase = SU_IDLE;
uint32_t suT0 = 0, suOff = 0, suDoneAt = 0, suReqAt = 0;
WiFiServer suSrv(80);
WiFiClient suCli;
String suReq;
bool suCancel = false;
uint8_t suBuf[1460];
uint16_t suBufLen = 0, suBufPos = 0;
bool suRunning();
const esp_partition_t* stripFwPart();

