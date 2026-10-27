#!/usr/bin/env bash
# End-to-end test without the real button: emulates it with uinput (same USB IDs) and checks
# the daemon's command, keys, text and run_as handling, plus that it grabs the button.
# Run as root on a Linux box or VM with the uinput module, e.g. from a Mac:
#   ./build.sh && podman machine ssh "sudo modprobe uinput && sudo $PWD/e2e-test.sh"
set -u
cd "$(dirname "$0")"
# input_event is 16 bytes for 32-bit programs and 24 for 64-bit ones. Go by the userland, not
# uname: 32-bit Raspberry Pi OS can run a 64-bit (aarch64) kernel.
BITS=$(getconf LONG_BIT 2>/dev/null || echo 64)
case "$(uname -m)" in
  aarch64|arm64) [ "$BITS" = 64 ] && arch=arm64 || arch=armv6 ;;
  x86_64) arch=amd64 ;;
  *) arch=armv6 ;;
esac
B=${B:-$PWD/dist/bigredbutton-linux-$arch}
if [ "$BITS" = 32 ]; then ES=16; else ES=24; fi
TF=$((ES / 2 - 3)) # u2 column of the event type; code and value-low follow it
[ "$(id -u)" = 0 ] || { echo "run as root"; exit 1; }
RUN_AS_USER=${RUN_AS_USER:-$(getent passwd 1000 | cut -d: -f1)}
if [ -z "$RUN_AS_USER" ] && [ "${CREATE_TEST_USER:-}" = 1 ]; then
  useradd -m brbtest && RUN_AS_USER=brbtest && trap 'userdel -r brbtest 2>/dev/null' EXIT
fi
T=$(mktemp -d)
fails=0
check() { if eval "$2"; then echo "PASS  $1"; else echo "FAIL  $1"; fails=$((fails + 1)); fi; }
virtual_node() { grep -A5 'Name="Big Red Button (virtual)"' /proc/bus/input/devices | grep -o 'event[0-9]*' | head -1; }

echo "== command (run as root), hot-plug"
echo '{"action":"command","command":"echo pressed >> '"$T"'/presses.log"}' > "$T/cmd.json"
$B run -config "$T/cmd.json" > "$T/cmd.log" 2>&1 & D=$!
$B __emulate-button > /dev/null
$B __emulate-button > /dev/null   # unplug and plug back in
sleep 1; kill $D
check "5+5 presses ran the command" '[ "$(wc -l < "$T/presses.log")" = 10 ]'
check "daemon saw the unplug and reconnect" '[ "$(grep -c "Button connected" "$T/cmd.log")" = 2 ]'

echo "== keys: ctrl+alt+t held while pressed; button grabbed"
echo '{"action":"keys","keys":"ctrl+alt+t"}' > "$T/keys.json"
$B run -config "$T/keys.json" > "$T/keys.log" 2>&1 & D=$!
sleep 1
VN=$(virtual_node)
check "virtual keyboard exists" '[ -n "$VN" ]'
timeout 12 dd if="/dev/input/$VN" of="$T/keys.bin" bs=$ES 2>/dev/null &
$B __emulate-button > /dev/null &
E=$!
sleep 3.5
timeout 2 $B listen > "$T/listen.log" 2>&1
wait $E; sleep 1; kill $D; wait
od -An -v -w$ES -tu2 "$T/keys.bin" | awk -v t=$TF '$t == 1 { print $(t + 1), $(t + 2) }' > "$T/keys.txt"
check "first press is ctrl, alt, t down" '[ "$(head -3 "$T/keys.txt" | tr "\n" " ")" = "29 1 56 1 20 1 " ]'
check "then t, alt, ctrl up" '[ "$(sed -n 4,6p "$T/keys.txt" | tr "\n" " ")" = "20 0 56 0 29 0 " ]'
n=$(wc -l < "$T/keys.txt"); check "5 presses -> 30 key events (got $n)" "[ $n = 30 ]"
check "a second program can't grab the button" 'grep -q "another program has grabbed" "$T/listen.log"'

echo "== text"
echo '{"action":"text","text":"Hi!"}' > "$T/text.json"
$B run -config "$T/text.json" > "$T/text.log" 2>&1 & D=$!
sleep 1
VN=$(virtual_node)
timeout 7 dd if="/dev/input/$VN" of="$T/text.bin" bs=$ES 2>/dev/null &
$B __emulate-button > /dev/null
sleep 1; kill $D; wait
od -An -v -w$ES -tu2 "$T/text.bin" | awk -v t=$TF '$t == 1 { print $(t + 1), $(t + 2) }' | head -8 | tr '\n' ' ' > "$T/text.txt"
# H = shift+h(35), i = 23, ! = shift+1(2)
check "types H i ! with shift" '[ "$(cat "$T/text.txt")" = "42 1 35 1 35 0 42 0 23 1 23 0 42 1 2 1 " ]'

if [ -n "$RUN_AS_USER" ]; then
  echo "== command runs as $RUN_AS_USER"
  echo '{"action":"command","command":"id -un > '"$T"'/who.txt; echo $HOME >> '"$T"'/who.txt","run_as":"'"$RUN_AS_USER"'"}' > "$T/runas.json"
  chmod 777 "$T"
  $B test -config "$T/runas.json" > /dev/null
  check "run_as user and HOME" '[ "$(head -1 "$T/who.txt")" = "$RUN_AS_USER" ] && [ "$(tail -1 "$T/who.txt")" = "$(getent passwd "$RUN_AS_USER" | cut -d: -f6)" ]'
fi

echo "== enter: button left alone"
echo '{"action":"enter"}' > "$T/enter.json"
$B run -config "$T/enter.json" > "$T/enter.log" 2>&1 & D=$!
$B __emulate-button > /dev/null &
E=$!
sleep 3.5
timeout 2 $B listen > "$T/listen-enter.log" 2>&1
wait $E; kill $D; wait
check "enter mode doesn't grab" 'grep -q "Button connected" "$T/listen-enter.log"'

echo "== set / status"
$B -config "$T/set.json" set none > /dev/null
check "set none writes the config" 'grep -q "\"action\": \"none\"" "$T/set.json"'
check "status reports the button missing" '$B status -config "$T/set.json" | grep -q "not found"'

rm -rf "$T"
echo "failures: $fails"
exit $fails
