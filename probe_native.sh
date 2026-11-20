#!/bin/bash
# i102897: does the NATIVE macOS surface (System Settings > Apple Account / iCloud,
# and the Messages "Sign in to iMessage" sheet) offer a "Create Apple Account" entry,
# and if so, where does it lead (native form vs embedded appleid.apple.com web page)?
# Sends nothing, creates nothing unless an entry is found (then only records what it asks).
set -u
OUT="${OUT:-$PWD/out_native}"; mkdir -p "$OUT"
L(){ echo "=== $* ===" | tee -a "$OUT/probe.log"; }
R(){ echo "--- \$ $*" | tee -a "$OUT/probe.log"; }
run(){ R "$@"; timeout 90 "$@" 2>&1 | sed 's/\r//' | head -80 | tee -a "$OUT/probe.log"; }
shot(){ local n="$1"; screencapture -x "$OUT/$n.png" >/dev/null 2>&1; if [ -x ./ocr2 ]; then ./ocr2 "$OUT/$n.png" > "$OUT/$n.ocr.txt" 2>&1; grep -h -E '^(orig|BEST)' "$OUT/$n.ocr.txt" | cut -c1-600 | head -6 | tee -a "$OUT/probe.log"; fi; }
pids(){ ./cgui list 2>/dev/null | grep -i "owner=$1" | sed -E 's/.*pid=([0-9]+).*/\1/' | sort -u; }
dumpax(){ local name="$1" pid="$2" d="${3:-8}"; ./cgui axdump "$pid" "$d" > "$OUT/ax_$name.txt" 2>&1; echo "ax_$name.txt lines=$(wc -l < "$OUT/ax_$name.txt")" | tee -a "$OUT/probe.log"; grep -n -i -E 'Create|Sign In|Sign in|Apple Account|iCloud|Not Signed|Button|Sheet|TextField|WebArea' "$OUT/ax_$name.txt" | head -40 | tee -a "$OUT/probe.log"; }

L "0. environment / local account credentials"
sw_vers; uname -m; sysctl -n hw.model 2>/dev/null; whoami; id
launchctl managername 2>/dev/null || true
echo "--- local users"; dscl . -list /Users 2>&1 | grep -v '^_' | head -20 | tee -a "$OUT/probe.log"
echo "--- auth authority (does local account have a password?)"
dscl . -read /Users/$(whoami) AuthenticationAuthority 2>&1 | head -10 | tee -a "$OUT/probe.log"
echo "--- sudo"; sudo -n true 2>&1 && echo sudo_ok || echo sudo_no
L "1. baseline apple account state"
defaults read MobileMeAccounts 2>&1 | head -30 | tee -a "$OUT/baseline_mobileme.txt" | head -20
echo "--- iCloud/AppleID prefs files"
ls -la ~/Library/Preferences/ 2>/dev/null | grep -i -E 'apple|icloud|mobileme|account' | head -20 | tee -a "$OUT/probe.log"
ls -la ~/Library/Application\ Support/ 2>/dev/null | grep -i -E 'apple|accounts' | head -10 | tee -a "$OUT/probe.log"
echo "--- any Apple account daemon state"
launchctl print gui/$(id -u) 2>/dev/null | grep -i -E 'akd|accountsd|AppleAccount|AOS' | head -20 | tee -a "$OUT/probe.log"

L "2. Messages sign-in sheet (native entry point #1)"
open -a Messages; sleep 8
open "sms://open?address=+19496788958&body=PROBE_MARKER_i102897"; sleep 8
run ./cgui list
MP=$(pids Messages | head -1); echo "Messages pid=$MP" | tee -a "$OUT/probe.log"
if [ -n "$MP" ]; then dumpax messages "$MP" 8; shot "n2_00_messages"; fi
echo "--- AX find 'Create' in Messages"
if [ -n "$MP" ]; then ./cgui axfind "$MP" "Create" 2>&1 | head -20 | tee -a "$OUT/probe.log"; fi

L "3. System Settings > Apple Account (native entry point #2)"
open "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings" 2>&1 | tee -a "$OUT/probe.log"
sleep 15
run ./cgui list
SP=$(pids "System Settings" | head -1); echo "SystemSettings pid=$SP" | tee -a "$OUT/probe.log"
if [ -n "$SP" ]; then dumpax systemsettings "$SP" 8; shot "n3_00_applepane"; fi
echo "--- AX find keywords in System Settings"
if [ -n "$SP" ]; then
  for k in Apple "Sign In" Create iCloud; do ./cgui axfind "$SP" "$k" 2>&1 | head -14 | tee -a "$OUT/probe.log"; done
fi

L "4. fallback: open System Settings generically and look for the Apple Account row"
if [ -z "$SP" ]; then
  open -b com.apple.systempreferences; sleep 14; run ./cgui list
  SP=$(pids "System Settings" | head -1); echo "SystemSettings pid=$SP (fallback)" | tee -a "$OUT/probe.log"
  if [ -n "$SP" ]; then dumpax systemsettings "$SP" 8; shot "n4_00_settings"; fi
fi

L "5. what processes appear when the native sign-in/create surface opens"
./cgui list 2>/dev/null | grep -i -E 'Apple|Setup|AOS|Account|iCloud|AuthKit|Settings' | tee -a "$OUT/probe.log"
ps -Ao pid,comm 2>/dev/null | grep -i -E 'akd|accountsd|AppleAccount|SetupAssistant|AOSUI|AuthKit' | grep -v grep | head -20 | tee -a "$OUT/probe.log"

L "6. click 'Create New Apple Account' in the Messages sheet (observation only, then record)"
if [ -n "$MP" ]; then
  ./cgui axpress "$MP" "Create New Apple Account" 2>&1 | head -10 | tee -a "$OUT/probe.log"
  sleep 12
  shot "n6_00_after_create_click"
  run ./cgui list
  # whatever app now owns the front window, dump it
  for pn in "System Settings" "Messages" "Safari" "Setup Assistant"; do
    p=$(pids "$pn" | head -1)
    if [ -n "$p" ]; then dumpax "after_create_${pn// /_}" "$p" 8; fi
  done
  ps -Ao pid,comm 2>/dev/null | grep -i -E 'akd|accountsd|AppleAccount|AuthKit|webkit' | grep -v grep | head -20 | tee -a "$OUT/probe.log"
fi

L "7. state after (did anything change / did a web page appear?)"
defaults read MobileMeAccounts 2>&1 | head -10 | tee -a "$OUT/after_mobileme.txt"
ls -la ~/Library/Messages 2>/dev/null | head -10 | tee -a "$OUT/probe.log"
echo DONE_i102897 | tee -a "$OUT/probe.log"
