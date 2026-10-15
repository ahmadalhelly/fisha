// Host test of the hub's MQTT publish queue. The code under test is pasted verbatim from mttl_hub.ino (mqtt_extract.inc).
#include "Arduino.h"
#include <pthread.h>
#include <mutex>
#include <condition_variable>
#include <deque>
#include <vector>
#include <string>
#include <atomic>
#include <cstdio>
#include <cassert>
#include <unistd.h>
#include <random>
#include <thread>

// ---- realloc hook used by the real WString.cpp: lets a test make String allocations fail (out of heap)
thread_local int failAllocs = 0;   // per thread, so one producer's fake out-of-memory never hits the other
extern "C" void* test_realloc(void* p, size_t n) { if (failAllocs > 0) { failAllocs--; return nullptr; } return realloc(p, n); }

// ---- FreeRTOS mocks
typedef int BaseType_t;
#define pdTRUE 1
#define pdFALSE 0
#define pdPASS 1
#define portMAX_DELAY 0xffffffffu
struct Q { std::mutex m; std::condition_variable cv; std::deque<std::vector<char>> d; size_t cap, sz; };
typedef Q* QueueHandle_t;
std::atomic<bool> stopWorker{false};
QueueHandle_t xQueueCreate(size_t n, size_t sz) { auto q = new Q; q->cap = n; q->sz = sz; return q; }
BaseType_t xQueueSend(QueueHandle_t q, const void* it, unsigned) {
  std::lock_guard<std::mutex> l(q->m);
  if (q->d.size() >= q->cap) return pdFALSE;
  q->d.emplace_back((const char*)it, (const char*)it + q->sz); q->cv.notify_all(); return pdTRUE;
}
BaseType_t xQueueReceive(QueueHandle_t q, void* it, unsigned) {
  std::unique_lock<std::mutex> l(q->m);
  for (;;) {
    if (!q->d.empty()) { memcpy(it, q->d.front().data(), q->sz); q->d.pop_front(); q->cv.notify_all(); return pdTRUE; }
    if (stopWorker) { l.unlock(); pthread_exit(nullptr); }
    q->cv.wait_for(l, std::chrono::milliseconds(5));
  }
}
size_t qLen(QueueHandle_t q) { std::lock_guard<std::mutex> l(q->m); return q->d.size(); }
typedef std::mutex* SemaphoreHandle_t;
SemaphoreHandle_t xSemaphoreCreateMutex() { return new std::mutex; }
BaseType_t xSemaphoreTake(SemaphoreHandle_t s, unsigned) { s->lock(); return pdTRUE; }
BaseType_t xSemaphoreGive(SemaphoreHandle_t s) { s->unlock(); return pdTRUE; }
typedef std::mutex portMUX_TYPE;
#define portMUX_INITIALIZER_UNLOCKED {}
#define portENTER_CRITICAL(x) (x)->lock()
#define portEXIT_CRITICAL(x) (x)->unlock()
pthread_t workerTh;
BaseType_t xTaskCreatePinnedToCore(void (*f)(void*), const char*, int, void* a, int, void*, int) {
  pthread_create(&workerTh, nullptr, (void* (*)(void*))(void*)f, a); return pdPASS;
}
struct SubT { SubT(const char*) {} };

// ---- esp-mqtt mock: records what the worker hands to the client
struct Client { std::atomic<bool> destroyed{false}; };
typedef Client* esp_mqtt_client_handle_t;
Client* volatile mqtt = nullptr;
volatile bool mqttUp = false;
struct Pub { std::string topic, data; int qos, retain; };
std::mutex pubM; std::vector<Pub> pubs;
std::atomic<bool> gate{false};          // true = client "stuck" (slow server); worker waits inside enqueue
std::atomic<int> enqDelayUs{0};
int esp_mqtt_client_enqueue(esp_mqtt_client_handle_t c, const char* t, const char* d, int len, int qos, int retain, bool store) {
  if (!c || c->destroyed) { fprintf(stderr, "FAIL: enqueue on destroyed/null client\n"); abort(); }
  if (!t || !d) { fprintf(stderr, "FAIL: null topic/data\n"); abort(); }
  if ((int)strlen(d) != len) { fprintf(stderr, "FAIL: len mismatch %d vs %zu\n", len, strlen(d)); abort(); }
  while (gate) usleep(200);
  if (enqDelayUs) usleep(enqDelayUs);
  std::lock_guard<std::mutex> l(pubM); pubs.push_back({t, std::string(d, len), qos, retain}); return 1;
}

#include "mqtt_extract.inc"

// ---- helpers
int fails = 0;
#define CHECK(c, msg) do { if (!(c)) { printf("  FAIL: %s (line %d)\n", msg, __LINE__); fails++; } } while (0)
void drain() { for (int i = 0; i < 4000 && (qLen(mqttOutQ) || mqttOutBytes); i++) usleep(500); usleep(2000); }
void reset() { drain(); std::lock_guard<std::mutex> l(pubM); pubs.clear(); mqttOutDropped = 0; }
String oomString() {                     // what userStateJson returns when the heap runs out mid-build
  String a = "{\"hub_fw\":\"2.15.32\",\"hub\":\"";
  failAllocs = 1000;
  String j = a + String("80F3DA40F674") + "\",\"time_ok\":true,\"lip\":\"192.168.1.100\",\"devices\":[ ... a long state that needs a new buffer ... ]}";
  failAllocs = 0;
  return j;
}

int main() { setvbuf(stdout, nullptr, _IONBF, 0);
  Client cl; mqtt = &cl; mqttUp = true;
  mqttOutInit();

  printf("T1 empty literal \"\" (retained clear) goes out as an empty message\n");
  reset();
  mqttPub("mttl/H/u/5/state", "", 1, true); drain();
  CHECK(pubs.size() == 1 && pubs[0].data.empty() && pubs[0].retain == 1 && pubs[0].qos == 1, "empty message published");
  CHECK(mqttOutDropped == 0, "nothing dropped");

  printf("T2 out-of-memory String (null buffer) is dropped, not sent, no crash\n");
  reset();
  String bad = oomString();
  CHECK(bad.c_str() == nullptr && bad.length() == 0, "OOM String really has a null buffer (reproduces 2.15.30 input)");
  mqttPub("mttl/H/u/5/state", bad, 0, true); drain();
  CHECK(pubs.empty(), "nothing published (would wipe retained user state)");
  CHECK(mqttOutDropped == 1, "counted as dropped");
  CHECK(mqttOutBytes == 0, "byte counter 0");

  printf("T3 normal messages arrive intact and in order\n");
  reset();
  for (int i = 0; i < 30; i++) { String p = "{\"n\":" + String(i) + "}"; mqttPub("t/" + String(i), p, i & 1, i & 2); }
  drain();
  bool ok = pubs.size() == 30;
  for (int i = 0; ok && i < 30; i++) ok = pubs[i].topic == "t/" + std::to_string(i) && pubs[i].data == "{\"n\":" + std::to_string(i) + "}" && pubs[i].qos == (i & 1) && pubs[i].retain == ((i & 2) ? 1 : 0);
  CHECK(ok, "30 messages intact, ordered, qos/retain kept");

  printf("T4 stuck server: retained copies capped at 6 KB, events/acks keep room up to 8 KB\n");
  reset(); gate = true;
  std::string k3(3000, 'x');
  mqttPub("s", "warm", 0, false); usleep(20000);       // worker now stuck inside enqueue with this one
  CHECK(mqttOutBytes == 4, "only the in-flight 4 bytes counted");
  int accS = 0; for (int i = 0; i < 4; i++) { uint32_t d = mqttOutDropped; mqttPub("state", String(k3.c_str()), 0, true); if (mqttOutDropped == d) accS++; }
  CHECK(accS == 2, "2 x 3000 B retained accepted, rest dropped");
  int accE = 0; std::string e200(200, 'e');
  for (int i = 0; i < 20; i++) { uint32_t d = mqttOutDropped; mqttPub("ev", String(e200.c_str()), 1, false); if (mqttOutDropped == d) accE++; }
  CHECK(accE == 10, "events fill the remaining room to 8 KB (10 x 200 B)");
  CHECK(mqttOutBytes <= 8192, "never above 8 KB");
  gate = false; drain();
  CHECK(mqttOutBytes == 0, "byte counter back to 0 after drain");
  CHECK((int)pubs.size() == 1 + accS + accE, "everything accepted was delivered");

  printf("T5 one state bigger than the cap still goes out when nothing is waiting\n");
  reset();
  std::string big(14000, 'b');
  mqttPub("state", String(big.c_str()), 0, true); drain();
  CHECK(pubs.size() == 1 && pubs[0].data.size() == 14000, "14 KB state delivered");

  printf("T6 queue full (48) drops instead of blocking\n");
  reset(); gate = true;
  mqttPub("w", "w", 0, false); usleep(20000);
  int acc = 0; for (int i = 0; i < 60; i++) { uint32_t d = mqttOutDropped; mqttPub("q", "x", 1, false); if (mqttOutDropped == d) acc++; }
  CHECK(acc == 48, "exactly 48 queued");
  gate = false; drain();
  CHECK(mqttOutBytes == 0 && (int)pubs.size() == 49, "all queued delivered");

  printf("T7 offline: nothing queued\n");
  reset(); mqttUp = false;
  mqttPub("x", "y", 1, false); drain();
  CHECK(pubs.empty() && mqttOutDropped == 0 && qLen(mqttOutQ) == 0, "skipped while offline");
  mqttUp = true;

  printf("T8 stress: 2 producers + restart thread (lock, destroy, new client) + random worker delays\n");
  reset(); enqDelayUs = 0;
  std::atomic<long> sent{0}; std::atomic<bool> run{true};
  auto prod = [&](int id) {
    std::mt19937 r(id);
    for (int i = 0; i < 40000; i++) {
      int sz = r() % 900; bool ret = r() % 3 == 0;
      String p = sz ? String(std::string(sz, 'a' + id).c_str()) : String("");
      if (r() % 50 == 0) p = oomString();
      mqttPub("p/" + String(id), p, r() % 2, ret); sent++;
      if (r() % 500 == 0) usleep(r() % 3000);
    }
  };
  std::vector<Client*> old;
  std::thread rest([&] {
    std::mt19937 r(9);
    while (run) {
      usleep(2000 + r() % 4000);
      mqttLock();                                 // as mqttRestart: stop+destroy under the lock
      Client* o = mqtt; o->destroyed = true; mqtt = nullptr; mqttUp = false;
      mqttUnlock();
      old.push_back(o);
      usleep(r() % 1000);
      mqtt = new Client; mqttUp = true;            // mqttStart outside the lock
    }
  });
  std::thread delays([&] { std::mt19937 r(3); while (run) { enqDelayUs = r() % 4 == 0 ? r() % 2000 : 0; usleep(3000); } enqDelayUs = 0; });
  std::thread a(prod, 0), b(prod, 1); a.join(); b.join();
  run = false; rest.join(); delays.join();
  drain();
  CHECK(mqttOutBytes == 0, "byte counter back to 0");
  bool content = true;
  for (auto& p : pubs) { char c = p.topic == "p/0" ? 'a' : 'b'; for (char x : p.data) if (x != c) { if (content) printf("  bad: topic=%s len=%zu data=%.60s\n", p.topic.c_str(), p.data.size(), p.data.c_str()); content = false; break; } }
  CHECK(content, "no corrupted payloads");
  printf("  sent %ld, delivered %zu, dropped %u, restarts %zu\n", (long)sent, pubs.size(), mqttOutDropped, old.size());
  for (auto o : old) if (o != &cl) delete o;

  stopWorker = true; pthread_join(workerTh, nullptr);
  delete (Client*)mqtt;
  printf(fails ? "\n%d FAILED\n" : "\nALL PASSED\n", fails);
  return fails ? 1 : 0;
}
