#!/bin/sh
# Host test of the hub's MQTT publish queue (mqttPub / mqttOutTask) with the real ESP32 Arduino String class.
# usage: CORE=<path to esp32 core, e.g. .../hardware/esp32/3.3.12/cores/esp32> ./run.sh
set -e
cd "$(dirname "$0")"
B=build; mkdir -p $B
cp "$CORE/WString.cpp" "$CORE/WString.h" "$CORE/stdlib_noniso.h" "$CORE/stdlib_noniso.c" $B/
sed -i 's/(char \*)realloc(/(char *)test_realloc(/' $B/WString.cpp          # lets the test make String allocations fail
sed -i '27a extern "C" void* test_realloc(void*, size_t);' $B/WString.cpp
python3 ../flatten.py > $B/flat.ino
awk '/^struct MqttOut/{f=1} /^String relaySignature/{f=0} f' $B/flat.ino > $B/mqtt_extract.inc   # code under test, verbatim
SAN="-fsanitize=address,undefined -fno-omit-frame-pointer"
g++ -std=gnu++17 -c -g $SAN -Istub -I$B $B/WString.cpp -o $B/WString.o
gcc -c -g -Istub -I$B $B/stdlib_noniso.c -o $B/noniso.o
gcc -c itoa.c -o $B/itoa.o
g++ -std=gnu++17 -g -O1 $SAN -Istub -I$B test.cpp $B/WString.o $B/noniso.o $B/itoa.o -o $B/test -lpthread
ASAN_OPTIONS=detect_leaks=1 $B/test
