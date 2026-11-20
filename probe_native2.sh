#!/bin/bash
# i102897 round 2: press each NATIVE "create Apple Account" entry and record WHAT IT OPENS:
#   native AppKit form  vs  embedded appleid.apple.com web view (which would mean the same captcha wall).
# Observation only. Submits nothing, types nothing, registers nothing.
set -u
OUT="${OUT:-$PWD/out_native2}"; mkdir -p "$OUT"
L(){ echo "=== $* ===" | tee -a "$OUT/probe.log"; }
TO(){ perl -e 'alarm shift; exec @ARGV' 60 "$@"; }
run(){ echo "--- \$ $*" | tee -a "$OUT/probe.log"; TO "$@" 2>&1 | sed 's/\r//' | head -60 | tee -a "$OUT/probe.log"; }
shot(){ local n="$1"; screencapture -x "$OUT/$n.png" >/dev/null 2>&1; [ -x ./ocr2 ] && { ./ocr2 "$OUT/$n.png" > "$OUT/$n.ocr.txt" 2>&1; grep -h -E '^(origx5|BEST)' "$OUT/$n.ocr.txt" | cut -c1-900 | head -3 | tee -a "$OUT/probe.log"; }; }
pids(){ ./cgui list 2>/dev/null | grep -i "owner=$1" | sed -E 's/.*pid=([0-9]+).*/\1/' | sort -u; }
netof(){ local p="$1"; echo "--- net/lsof pid=$p $(ps -o comm= -p $p 2>/dev/null)" | tee -a "$OUT/probe.log"; lsof -nP -p "$p" 2>/dev/null | grep -E 'TCP|UDP' | head -20 | tee -a "$OUT/probe.log"; }
axweb(){ local f="$1"; echo "--- web-ish roles in $f:" | tee -a "$OUT/probe.log"; grep -n -E 'AXWebArea|AXLink|AXHTMLContent|AXDocument|AXURL|http' "$f" 2>/dev/null | head -25 | tee -a "$OUT/probe.log"; }
procsnap(){ ps -Ao pid,ppid,user,comm 2>/dev/null | grep -i -E 'AKAuthorization|AuthKit|SetupAssistant|AOSUI|Safari|WebKit|appleaccount|AppleAccountSetup|akd' | grep -v grep | tee -a "$OUT/probe.log"; }

L "0. env"
sw_vers -productVersion; uname -m; launchctl managername; id -u

L "1. BASELINE process set (so new helpers are attributable)"
procsnap > "$OUT/p_before.txt" 2>&1; cat "$OUT/p_before.txt" | tee -a "$OUT/probe.log"
echo "--- baseline network of existing AKAuthorizationRemoteViewService (if any)"
for p in $(pgrep -f AKAuthorizationRemoteViewService 2>/dev/null); do netof "$p"; done

L "2. NATIVE ENTRY #1 -> Messages 'Create New Apple Account'"
open -a Messages; sleep 6
./cgui front Messages 2>&1 | tee -a "$OUT/probe.log"
open "sms://open?address=+19496788958&body=PROBE_MARKER_i102897_r2"; sleep 8
run ./cgui list
MP=$(pids Messages | head -1); echo "Messages pid=$MP" | tee -a "$OUT/probe.log"
if [ -n "$MP" ]; then
  ./cgui axdump "$MP" 10 > "$OUT/m_before.txt" 2>&1
  echo "--- ax target:"; ./cgui axfind "$MP" "Create New Apple Account" 2>&1 | head -6 | tee -a "$OUT/probe.log"
  echo "--- PRESS" | tee -a "$OUT/probe.log"
  ./cgui axpress "$MP" "Create New Apple Account" 2>&1 | head -6 | tee -a "$OUT/probe.log"
  sleep 14
  shot "m_after_press"
  ./cgui list 2>&1 | head -20 | tee -a "$OUT/probe.log"
  ./cgui axdump "$MP" 10 > "$OUT/m_after.txt" 2>&1
  echo "m_after lines=$(wc -l < "$OUT/m_after.txt") delta_vs_before=$(diff "$OUT/m_before.txt" "$OUT/m_after.txt" | wc -l)" | tee -a "$OUT/probe.log"
  grep -n -i -E 'Create|Sign|Apple|Sheet|Dialog|WebArea|TextField|Button' "$OUT/m_after.txt" | head -40 | tee -a "$OUT/probe.log"
  axweb "$OUT/m_after.txt"
fi
echo "--- process set after Messages create-press" | tee -a "$OUT/probe.log"
procsnap | tee -a "$OUT/probe.log"
echo "--- new pids vs baseline" | tee -a "$OUT/probe.log"
comm -13 <(awk '{print $1}' "$OUT/p_before.txt"|sort -u) <(ps -Ao pid,comm | awk '{print $1}'|sort -u) | head -20 | tee -a "$OUT/probe.log"
for p in $(pgrep -f 'AKAuthorizationRemoteViewService|AppleAccount|SetupAssistant|AOSUI' 2>/dev/null); do netof "$p"; done

L "3. NATIVE ENTRY #2 -> System Settings 'Don't Have an Account?' (CREATE_BUTTON)"
open "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"; sleep 14
./cgui front "System Settings" 2>&1 | tee -a "$OUT/probe.log"
SP=$(pids "System Settings" | head -1); echo "SystemSettings pid=$SP" | tee -a "$OUT/probe.log"
if [ -n "$SP" ]; then
  ./cgui axdump "$SP" 10 > "$OUT/s_before.txt" 2>&1
  grep -n -E 'CREATE_BUTTON|USERNAME_TEXT_FIELD|LOGIN_BUTTON|FORGOT_BUTTON' "$OUT/s_before.txt" | tee -a "$OUT/probe.log"
  echo "--- PRESS Don't Have an Account?" | tee -a "$OUT/probe.log"
  ./cgui axpress "$SP" "Don't Have an Account" 2>&1 | head -8 | tee -a "$OUT/probe.log"
  sleep 16
  shot "s_after_press"
  ./cgui axdump "$SP" 12 > "$OUT/s_after.txt" 2>&1
  echo "s_after lines=$(wc -l < "$OUT/s_after.txt")" | tee -a "$OUT/probe.log"
  grep -n -i -E 'Create|Apple Account|WebArea|Link|TextField|Button|Email|verification|First Name|Last Name|Birthday' "$OUT/s_after.txt" | head -50 | tee -a "$OUT/probe.log"
  axweb "$OUT/s_after.txt"
  ./cgui list 2>&1 | head -20 | tee -a "$OUT/probe.log"
fi
echo "--- process/network after System Settings create-press" | tee -a "$OUT/probe.log"
procsnap | tee -a "$OUT/probe.log"
for p in $(pgrep -f 'AKAuthorizationRemoteViewService|AppleAccount|SetupAssistant|AOSUI|Safari' 2>/dev/null); do netof "$p"; done

L "4. did an embedded web view load a URL? (all front windows + any web roles)"
./cgui list 2>&1 | tee -a "$OUT/probe.log"
for p in $(pgrep -f 'AKAuthorizationRemoteViewService' 2>/dev/null); do
  echo "--- strings in helper for loaded url (best effort)" | tee -a "$OUT/probe.log"
  lsof -nP -p "$p" 2>/dev/null | grep -E 'TCP' | head -10 | tee -a "$OUT/probe.log"
done
echo "--- Apple ID prefs state (unchanged expected)"
defaults read MobileMeAccounts 2>&1 | head -5 | tee -a "$OUT/after_mobileme2.txt"
echo DONE_r2 | tee -a "$OUT/probe.log"
