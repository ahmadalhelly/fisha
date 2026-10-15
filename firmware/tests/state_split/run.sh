#!/bin/sh
# Host test of hub 2.15.38's split state (stream, live numbers, per-strip cloud messages), the 10-strip members list and the
# energy history kept in files, with the real ESP32 Arduino String class. The code under test is copied verbatim from the .ino.
# usage: CORE=<path to esp32 core, e.g. .../hardware/esp32/3.3.12/cores/esp32> ./run.sh
set -e
cd "$(dirname "$0")"
B=build; mkdir -p $B
cp "$CORE/WString.cpp" "$CORE/WString.h" "$CORE/stdlib_noniso.h" "$CORE/stdlib_noniso.c" $B/
INO=../../mttl_hub/mttl_hub.ino
python3 extract.py $INO "struct Outlet" "struct ELog" "struct PeakLog" "struct ElogHead" "struct PeakHead" "struct Strip" "struct Known" \
  "struct HubUser" "struct HubUserV1" "struct UsersNV" "struct UsersNVV1" "line:const uint8_t USER_STRIPS" "struct PubMark" > $B/types.inc
python3 extract.py $INO split isHex jsonEsc civilFromDays findStrip macKnown userHas parseStrips stripJson offlineStripJson \
  stateDevicesBytes stateStream stateJsonFor liveJson mqttHead sigMix sigStr stripSig pubMarksReset stripPower pubMark publishStrips \
  findUser clearUserStrips elogGet elogPut peakGet peakPut histHeads energyUpdate peakUpdate energyJson \
  "line:const uint32_t USERS_MAGIC =" "union UsersBuf" "line:static UsersBuf usersBuf" "line:const uint32_t USERS_MAGIC2" loadUsers saveUsers > $B/code.inc
SAN="-fsanitize=address,undefined -fno-omit-frame-pointer"
g++ -std=gnu++17 -c -g $SAN -I../mqtt_queue/stub -I$B $B/WString.cpp -o $B/WString.o
gcc -c -g -I../mqtt_queue/stub -I$B $B/stdlib_noniso.c -o $B/noniso.o
gcc -c ../mqtt_queue/itoa.c -o $B/itoa.o
g++ -std=gnu++17 -g -O1 -Wall -Wno-unused-function -Wno-class-memaccess $SAN -I../mqtt_queue/stub -I$B test.cpp $B/WString.o $B/noniso.o $B/itoa.o -o $B/test
ASAN_OPTIONS=detect_leaks=1 $B/test $B
python3 -c "
import json,glob,sys
n=0
for f in sorted(glob.glob('$B/out_*.json')):
    json.load(open(f)); n+=1
print('json ok:', n, 'files')
"
