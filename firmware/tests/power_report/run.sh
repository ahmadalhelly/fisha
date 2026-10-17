#!/bin/sh
# Host test of the real per-outlet current: the :current / :vol answers (handlePowerReport), asking for the next outlet
# (askCurrent, pollStrips) and the validity rules (curValid, outletAmps, outletAmpsMax). The code is copied verbatim from the hub source.
# usage: CORE=<path to esp32 core, e.g. .../cores/esp32> ./run.sh
set -e
cd "$(dirname "$0")"
B=build; mkdir -p $B
cp "$CORE/WString.cpp" "$CORE/WString.h" "$CORE/stdlib_noniso.h" "$CORE/stdlib_noniso.c" $B/
python3 ../flatten.py > $B/flat.ino
python3 ../state_split/extract.py $B/flat.ino "struct Outlet" "struct Strip" > $B/types.inc
python3 ../state_split/extract.py $B/flat.ino split curValid outletAmps outletAmpsMax handlePowerReport askCurrent pollStrips > $B/code.inc
SAN="-fsanitize=address,undefined -fno-omit-frame-pointer"
g++ -std=gnu++17 -c -g $SAN -I../mqtt_queue/stub -I$B $B/WString.cpp -o $B/WString.o
gcc -c -g -I../mqtt_queue/stub -I$B $B/stdlib_noniso.c -o $B/noniso.o
gcc -c ../mqtt_queue/itoa.c -o $B/itoa.o
g++ -std=gnu++17 -g -O1 -Wall -Wno-unused-function $SAN -I../mqtt_queue/stub -I$B test.cpp $B/WString.o $B/noniso.o $B/itoa.o -o $B/test
ASAN_OPTIONS=detect_leaks=1 $B/test
