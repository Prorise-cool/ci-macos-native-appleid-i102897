#!/bin/bash
# i102897 round 3: press the two NATIVE "create Apple Account" entries (correct needles, poll for sheet)
# and record WHAT OPENS: native AppKit form vs embedded appleid.apple.com web page (=> same captcha wall).
# Observation only: types nothing into the form, submits nothing, creates no account.
set -u
OUT="${OUT:-$PWD/out_native3}"; mkdir -p "$OUT"
L(){ echo "=== $* ===" | tee -a "$OUT/probe.log"; }
TO(){ perl -e 'alarm shift; exec @ARGV' 60 "$@"; }
run(){ echo "--- \$ $*" | tee -a "$OUT/probe.log"; TO "$@" 2>&1 | sed 's/\r//' | head -60 | tee -a "$OUT/probe.log"; }
shot(){ local n="$1"; screencapture -x "$OUT/$n.png" >/dev/null 2>&1; [ -x ./ocr2 ] && { ./ocr2 "$OUT/$n.png" > "$OUT/$n.ocr.txt" 2>&1; grep -h -E '^(origx5|BEST)' "$OUT/$n.ocr.txt" | cut -c1-1200 | head -2 | tee -a "$OUT/probe.log"; }; }
pids(){ ./cgui list 2>/dev/null | grep -i "owner=$1" | sed -E 's/.*pid=([0-9]+).*/\1/' | sort -u; }
webprocs(){ ps -Ao pid,comm 2>/dev/null | grep -i -E 'WebContent|SafariViewService|Safari\.app/Contents/MacOS/Safari$|com.apple.WebKit' | grep -v grep | tee -a "$OUT/probe.log"; }
netall(){ echo "--- TCP of account/web procs" | tee -a "$OUT/probe.log"; for p in $(pgrep -f 'akd|AKAuthorizationRemoteViewService|WebContent|SafariViewService|appleaccountd' 2>/dev/null); do lsof -nP -p "$p" 2>/dev/null | grep -E 'TCP' | head -8; done | tee -a "$OUT/probe.log"; }
waitfor(){ # $1 pid  $2 needle  $3 max_s
  local i=0; while [ $i -lt "$3" ]; do
    if ./cgui axfind "$1" "$2" 2>/dev/null | head -1 | grep -q 'matches=[1-9]'; then echo "FOUND [$2] after ${i}s" | tee -a "$OUT/probe.log"; return 0; fi
    sleep 2; i=$((i+2)); done; echo "NOT FOUND [$2] after ${3}s" | tee -a "$OUT/probe.log"; return 1; }

L "0. env"; sw_vers -productVersion; uname -m; launchctl managername; id -u
webprocs > "$OUT/p_before.txt" 2>&1; cat "$OUT/p_before.txt" | tee -a "$OUT/probe.log"

L "1. Messages sheet -> press 'Create New Apple Account' (poll first)"
open -a Messages; sleep 5
open "sms://open?address=+19496788958&body=PROBE_MARKER_i102897_r3"; sleep 10
MP=$(pids Messages | head -1); echo "Messages pid=$MP" | tee -a "$OUT/probe.log"
if [ -n "$MP" ]; then
  if waitfor "$MP" "New Apple Account" 40; then
    ./cgui axdump "$MP" 12 > "$OUT/m_before.txt" 2>&1
    echo "--- PRESS" | tee -a "$OUT/probe.log"
    ./cgui axpress "$MP" "New Apple Account" 2>&1 | head -6 | tee -a "$OUT/probe.log"
    echo "--- waiting 20s for resulting UI"; sleep 20
    shot "m_press1"
    ./cgui axdump "$MP" 14 > "$OUT/m_after.txt" 2>&1
    echo "m_after lines=$(wc -l < "$OUT/m_after.txt")" | tee -a "$OUT/probe.log"
    echo "--- what replaced the sheet:"; grep -n -i -E 'AXSheet|AXDialog|AXWebArea|AXLink|AXTextField|AXButton|Create|Email|Name|Birthday|Country|Password|verification|code' "$OUT/m_after.txt" | head -50 | tee -a "$OUT/probe.log"
    echo "--- web roles:"; grep -c -E 'AXWebArea|AXLink|AXHTMLContent' "$OUT/m_after.txt" | tee -a "$OUT/probe.log"
  fi
fi
echo "--- web procs after Messages create-press"; webprocs; netall
echo "--- window list"; ./cgui list 2>&1 | grep -v 'Control Center\|Spotlight\|Dock\|Menubar' | head -12 | tee -a "$OUT/probe.log"

L "2. System Settings -> press CREATE_BUTTON ('Have an Account')"
open "x-apple.systempreferences:com.apple.systempreferences.AppleIDSettings"; sleep 14
SP=$(pids "System Settings" | head -1); echo "SystemSettings pid=$SP" | tee -a "$OUT/probe.log"
if [ -n "$SP" ]; then
  if waitfor "$SP" "Have an Account" 30; then
    ./cgui axdump "$SP" 12 > "$OUT/s_before.txt" 2>&1
    echo "--- PRESS" | tee -a "$OUT/probe.log"
    ./cgui axpress "$SP" "Have an Account" 2>&1 | head -6 | tee -a "$OUT/probe.log"
    echo "--- waiting 22s"; sleep 22
    shot "s_press1"
    ./cgui axdump "$SP" 14 > "$OUT/s_after.txt" 2>&1
    echo "s_after lines=$(wc -l < "$OUT/s_after.txt")" | tee -a "$OUT/probe.log"
    grep -n -i -E 'AXSheet|AXDialog|AXWebArea|AXLink|AXTextField|AXButton|Create|Email|First Name|Last Name|Birthday|Country|Password|verification|code|Continue' "$OUT/s_after.txt" | head -60 | tee -a "$OUT/probe.log"
    echo "--- web roles count:"; grep -c -E 'AXWebArea|AXLink|AXHTMLContent' "$OUT/s_after.txt" | tee -a "$OUT/probe.log"
  fi
fi
echo "--- web procs after Settings create-press"; webprocs; netall
echo "--- window list"; ./cgui list 2>&1 | grep -v 'Control Center\|Spotlight\|Dock\|Menubar' | head -14 | tee -a "$OUT/probe.log"

L "3. any embedded web content anywhere? dump every window owner's tree hunting AXWebArea"
for own in "System Settings" "Messages" "Safari"; do
  p=$(pids "$own" | head -1); [ -z "$p" ] && continue
  c=$(./cgui axdump "$p" 14 2>/dev/null | grep -c -E 'AXWebArea|AXHTMLContent|AXLink')
  echo "owner=$own pid=$p webish=$c" | tee -a "$OUT/probe.log"
done

L "4. state after (account untouched)"
defaults read MobileMeAccounts 2>&1 | head -6 | tee -a "$OUT/after_mobileme3.txt"
echo DONE_r3 | tee -a "$OUT/probe.log"
