#!/usr/bin/env bash
# Build is done by the workflow. This script boots the newest iPhone Pro
# simulator, records startup and scroll frame stats, and screenshots the
# main screens.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${APP_PATH:-}"
OUT="${OUT_DIR:-$ROOT/simulator-output}"
LABEL="${PERF_LABEL:-baseline}"
mkdir -p "$OUT/screenshots" "$OUT/perf"

if [[ -z "$APP" || ! -d "$APP" ]]; then
  APP="$(find "$ROOT/build/Build/Products" -type d -name 'PiliPlus.app' -path '*iphonesimulator*' | head -1)"
fi
if [[ -z "$APP" || ! -d "$APP" ]]; then
  echo "PiliPlus.app was not found" >&2
  exit 1
fi

python3 - "$OUT/device.txt" <<'PY'
import json, re, subprocess, sys
out = sys.argv[1]
data = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))
best = None
best_score = None
for runtime, devices in data.get("devices", {}).items():
    match = re.search(r"iOS-(\d+)-(\d+)", runtime)
    if not match:
        continue
    version = (int(match.group(1)), int(match.group(2)))
    for device in devices:
        if not device.get("isAvailable", True):
            continue
        name = device["name"]
        if name == "iPhone 18 Pro":
            score = (2, version, 18)
        else:
            numbered = re.fullmatch(r"iPhone (\d+) Pro", name)
            if not numbered:
                continue
            score = (1, version, int(numbered.group(1)))
        if best_score is None or score > best_score:
            best_score = score
            best = (name, device["udid"], runtime, version)
if best is None:
    raise SystemExit("No iPhone Pro simulator is installed")
name, udid, runtime, version = best
open(out, "w").write(f"{name}\n{udid}\n{runtime}\niOS {version[0]}.{version[1]}\n")
print(f"Selected simulator: {name} iOS {version[0]}.{version[1]} {udid}")
PY

NAME="$(sed -n '1p' "$OUT/device.txt")"
UDID="$(sed -n '2p' "$OUT/device.txt")"
echo "Booting $NAME ($UDID)"
xcrun simctl boot "$UDID" || true
xcrun simctl bootstatus "$UDID" -b
open -a Simulator --args -CurrentDeviceUDID "$UDID" || true
# iOS 26 posts "Ready for Apple Intelligence" once the model catalog is ready.
# The follow-up daemon records this date and does not post again.
suppress_apple_intelligence() {
  local stamp
  stamp="$(date -u +"%Y-%m-%d %H:%M:%S +0000")"
  xcrun simctl spawn "$UDID" defaults write \
    com.apple.generativeexperiences.corefollowup \
    DateOfLastAppleIntelligenceReadinessCFU -date "$stamp" || true
  xcrun simctl spawn "$UDID" launchctl kickstart -k "user/$(id -u)/com.apple.followupd" || true
}
suppress_apple_intelligence
sleep 2
xcrun simctl status_bar "$UDID" override \
  --time "9:41" \
  --batteryState charged \
  --batteryLevel 100 \
  --cellularMode active \
  --cellularBars 4 \
  --wifiBars 3 \
  --operatorName "" || true

xcrun simctl install "$UDID" "$APP"
BUNDLE="com.syiar.piliplus"

container() {
  xcrun simctl get_app_container "$UDID" "$BUNDLE" data
}

run_perf() {
  local mode="$1"
  local dest="$2"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  local dir
  dir="$(container)"
  rm -f "$dir/Documents/perf.json" "$dest.log" "$dest.err"
  xcrun simctl launch --terminate-running-process \
    --stdout="$dest.log" --stderr="$dest.err" \
    "$UDID" "$BUNDLE" "$mode" -perfLabel "$LABEL"
  local found=0
  for _ in $(seq 1 90); do
    if [[ -f "$dir/Documents/perf.json" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  if [[ "$found" -ne 1 ]]; then
    echo "missing perf.json for $mode" | tee "$dest.missing"
    tail -n 120 "$dest.log" || true
    tail -n 120 "$dest.err" || true
    return 1
  fi
  # The app exits on its own; give the atomic write a moment to settle.
  sleep 0.4
  cp "$dir/Documents/perf.json" "$dest.json"
  echo "saved $dest.json"
}

echo "Cold start samples"
for i in 1 2 3; do
  run_perf -perfStartup "$OUT/perf/startup-$i"
done

echo "Scroll sample and screen recording"
# Record the scripted feed scroll. simctl finalizes the mp4 on SIGINT.
SCROLL_VIDEO="$OUT/scroll-feed.mp4"
xcrun simctl io "$UDID" recordVideo --codec=h264 --mask=ignored --force "$SCROLL_VIDEO" \
  >"$OUT/perf/record.log" 2>&1 &
RECORD_PID=$!
sleep 1
set +e
run_perf -perfScroll "$OUT/perf/scroll"
SCROLL_STATUS=$?
set -e
sleep 0.6
kill -INT "$RECORD_PID" 2>/dev/null || true
for _ in $(seq 1 20); do
  if [[ -f "$SCROLL_VIDEO" ]]; then
    break
  fi
  sleep 0.5
done
wait "$RECORD_PID" 2>/dev/null || true
if [[ ! -f "$SCROLL_VIDEO" ]]; then
  echo "recordVideo did not produce $SCROLL_VIDEO" | tee "$OUT/perf/record.missing"
  tail -n 40 "$OUT/perf/record.log" || true
  exit 1
fi
ls -lh "$SCROLL_VIDEO"
if [[ "$SCROLL_STATUS" -ne 0 ]]; then
  exit "$SCROLL_STATUS"
fi

echo "Screenshots on $NAME"
suppress_apple_intelligence
for screen in home dynamics mine search settings video login playback; do
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen "$screen" -perfLabel "$LABEL"
  if [[ "$screen" == "login" ]]; then sleep 20
  elif [[ "$screen" == "playback" ]]; then sleep 45
  else sleep 12
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/${screen}.png"
  echo "saved ${screen}.png"
done

echo "Done. Output in $OUT"
ls -la "$OUT/screenshots" "$OUT/perf"
