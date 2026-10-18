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

capture_playback() {
  local dir proof advanced=0 first="" cur="" err=""
  dir="$(container)"
  proof="$dir/Documents/playback-proof.json"
  rm -f "$proof" "$OUT/screenshots/playback.png" "$OUT/screenshots/playback-failed.png"
  : > "$OUT/perf/playback.log"
  : > "$OUT/perf/playback.err"
  xcrun simctl launch --terminate-running-process \
    --stdout="$OUT/perf/playback.log" --stderr="$OUT/perf/playback.err" \
    "$UDID" "$BUNDLE" -screen playback -perfLabel "$LABEL"
  for _ in $(seq 1 100); do
    if [[ -f "$proof" ]]; then
      cur="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("seconds", 0))' "$proof")"
      err="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("error", ""))' "$proof")"
      echo "playback proof seconds=$cur error=${err:-none}"
      if [[ -z "$err" ]]; then
        if [[ -z "$first" ]]; then
          first="$cur"
        elif python3 -c 'import sys; sys.exit(0 if float(sys.argv[2]) - float(sys.argv[1]) >= 0.8 else 1)' "$first" "$cur"; then
          advanced=1
          break
        fi
      fi
    fi
    sleep 1
  done
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/playback-a.png"
  sleep 0.9
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/playback-b.png"
  if [[ -f "$proof" ]]; then
    cp "$proof" "$OUT/perf/playback-proof.json"
    echo "proof file:"
    cat "$OUT/perf/playback-proof.json"
    echo
  fi
  if [[ "$advanced" -ne 1 ]]; then
    cp "$OUT/screenshots/playback-b.png" "$OUT/screenshots/playback-failed.png"
    if [[ ! -f "$proof" ]]; then
      echo "playback proof was not written" >&2
    fi
    echo "playback clock did not advance by 0.8s" >&2
    tail -n 40 "$OUT/perf/playback.log" || true
    tail -n 40 "$OUT/perf/playback.err" || true
    return 1
  fi
  if ! python3 - "$OUT/screenshots/playback-a.png" "$OUT/screenshots/playback-b.png" <<'PY'
import struct, sys, zlib

def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a png")
    pos = 8
    width = height = color = None
    idat = b""
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, _comp, _filt, inter = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or inter != 0 or color not in (2, 6):
                raise SystemExit(f"unsupported png {width}x{height} depth={depth} color={color} inter={inter}")
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
    raw = zlib.decompress(idat)
    bpp = 4 if color == 6 else 3
    stride = width * bpp
    rows = []
    index = 0
    prev = bytearray(stride)
    for _ in range(height):
        filt = raw[index]
        index += 1
        row = bytearray(raw[index:index + stride])
        index += stride
        for x in range(stride):
            left = row[x - bpp] if x >= bpp else 0
            up = prev[x]
            ul = prev[x - bpp] if x >= bpp else 0
            if filt == 0:
                value = row[x]
            elif filt == 1:
                value = (row[x] + left) & 255
            elif filt == 2:
                value = (row[x] + up) & 255
            elif filt == 3:
                value = (row[x] + ((left + up) // 2)) & 255
            elif filt == 4:
                guess = left + up - ul
                pa, pb, pc = abs(guess - left), abs(guess - up), abs(guess - ul)
                pred = left if pa <= pb and pa <= pc else (up if pb <= pc else ul)
                value = (row[x] + pred) & 255
            else:
                raise SystemExit(f"bad png filter {filt}")
            row[x] = value
        rows.append(row)
        prev = row
    return width, height, bpp, rows

def band(rows, width, height, bpp):
    y0, y1 = int(height * 0.08), int(height * 0.32)
    return y0, y1

def stats(path):
    width, height, bpp, rows = read_png(path)
    y0, y1 = band(rows, width, height, bpp)
    total = 0.0
    squares = 0.0
    count = 0
    for y in range(y0, y1):
        row = rows[y]
        for x in range(width):
            i = x * bpp
            luma = 0.2126 * row[i] + 0.7152 * row[i + 1] + 0.0722 * row[i + 2]
            total += luma
            squares += luma * luma
            count += 1
    mean = total / count
    variance = max(0.0, squares / count - mean * mean)
    return width, height, mean, variance ** 0.5

def motion(left, right):
    aw, ah, ab, ar = read_png(left)
    bw, bh, bb, br = read_png(right)
    if (aw, ah, ab) != (bw, bh, bb):
        raise SystemExit(f"screenshot size changed {aw}x{ah} -> {bw}x{bh}")
    y0, y1 = int(ah * 0.08), int(ah * 0.32)
    total = 0.0
    count = 0
    for y in range(y0, y1):
        a = ar[y]
        b = br[y]
        for i in range(0, aw * ab, ab):
            total += abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2])
            count += 3
    return total / count

mean_a, std_a = stats(sys.argv[1])[2:]
width, height, mean_b, std_b = stats(sys.argv[2])
delta = motion(sys.argv[1], sys.argv[2])
print(f"player band {width}x{height} mean={mean_b:.2f} stddev={std_b:.2f} motion={delta:.2f} first_stddev={std_a:.2f}")
# The 412 page is near-white (mean ~254, stddev ~6.6) and does not move.
if std_b < 15 or mean_b > 245 or delta < 2.0:
    raise SystemExit("player band does not look like moving video")
PY
  then
    cp "$OUT/screenshots/playback-b.png" "$OUT/screenshots/playback-failed.png"
    echo "player band did not show moving video" >&2
    return 1
  fi
  cp "$OUT/screenshots/playback-b.png" "$OUT/screenshots/playback.png"
  echo "saved playback.png"
}

capture_catalog() {
  local screen="$1"
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/home-proof.json"
  rm -f "$proof"
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen "$screen" -perfLabel "$LABEL"
  for _ in $(seq 1 45); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  if [[ "$found" -eq 1 ]]; then
    cp "$proof" "$OUT/perf/${screen}-proof.json"
    echo "proof ${screen}:"
    cat "$OUT/perf/${screen}-proof.json"
    echo
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/${screen}.png"
  echo "saved ${screen}.png"
  if [[ "$found" -ne 1 ]]; then
    echo "missing home proof for ${screen}" >&2
    return 1
  fi
  python3 - "$screen" "$OUT/perf/${screen}-proof.json" <<'PY'
import json, sys
screen, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
title = str(data.get("title", ""))
bvid = str(data.get("bvid", ""))
if screen == "home":
    ok = (
        data.get("source") == "rcmd"
        and int(data.get("page", 0)) >= 2
        and int(data.get("count", 0)) > int(data.get("firstCount", 0))
        and bvid.startswith("BV")
        and "液态玻璃" not in title
        and "fixture" not in bvid
        and 1 <= len(str(data.get("short") or "")) <= 12
        and len(str(data.get("long") or "")) >= 16
        and str(data.get("short") or "") != str(data.get("long") or "")
        and "液态玻璃" not in str(data.get("short") or "")
        and "fixture" not in str(data.get("short") or "").lower()
        and "fixture" not in str(data.get("long") or "").lower()
    )
elif screen == "rank":
    ok = int(data.get("rid", 0)) == 1 and int(data.get("count", 0)) >= 5 and bvid.startswith("BV") and "fixture" not in bvid
elif screen in ("bangumi", "cinema"):
    ok = int(data.get("count", 0)) >= 5 and int(data.get("seasonID", 0)) > 0 and title != ""
else:
    ok = False
print(f"{screen} proof {'ok' if ok else 'rejected'}")
if not ok:
    raise SystemExit(f"{screen} proof rejected")
PY
}

verify_scroll() {
  python3 - "$OUT/perf/scroll.json" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
if data.get("error"):
    raise SystemExit(f"scroll load failed: {data['error']}")
warm = data["warm"]
print(
    f"warm p95={warm['p95Ms']} p99={warm['p99Ms']} max={warm['maxMs']} "
    f"hits={data.get('imageHits')} misses={data.get('imageMisses')} prepared={data.get('preparedCovers')}"
)
if float(warm["p95Ms"]) > 20:
    raise SystemExit("warm p95 above 20 ms")
# Cards already on screen are created before the counter resets. Zero misses
# means every cover looked up during the sweep was cached; preparedCovers is
# how many of those bitmaps were decoded before the sweep started.
if int(data.get("imageMisses", 1)) != 0 or int(data.get("preparedCovers", 0)) < 8:
    raise SystemExit("cover cache did not hit")
PY
}

capture_account_proof() {
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/account-proof.json"
  rm -f "$proof"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen accountProof -perfLabel "$LABEL"
  for _ in $(seq 1 30); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  if [[ "$found" -ne 1 ]]; then
    echo "missing account request proof" >&2
    return 1
  fi
  cp "$proof" "$OUT/perf/account-proof.json"
  python3 - "$proof" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
expect = {
    "like": ("POST", "/x/web-interface/archive/like", "aid=42&csrf=jct-token&like=1", True),
    "unlike": ("POST", "/x/web-interface/archive/like", "aid=42&csrf=jct-token&like=2", True),
    "coin-2-like": ("POST", "/x/web-interface/coin/add", "aid=7&csrf=jct-token&multiply=2&select_like=1", True),
    "coin-1": ("POST", "/x/web-interface/coin/add", "aid=7&csrf=jct-token&multiply=1&select_like=0", True),
    "coin-clamp": ("POST", "/x/web-interface/coin/add", "aid=7&csrf=jct-token&multiply=1&select_like=0", True),
    "triple": ("POST", "/x/web-interface/archive/like/triple", "aid=9&csrf=jct-token", True),
    "history-delete": ("POST", "/x/v2/history/delete", "csrf=jct-token&kid=archive_100", True),
    "history-clear": ("POST", "/x/v2/history/clear", "csrf=jct-token", True),
    "history-pause": ("POST", "/x/v2/history/shadow/set", "csrf=jct-token&switch=true", True),
    "history-resume": ("POST", "/x/v2/history/shadow/set", "csrf=jct-token&switch=false", True),
    "later-add": ("POST", "/x/v2/history/toview/add", "aid=5&csrf=jct-token", True),
    "later-del": ("POST", "/x/v2/history/toview/del", "aid=5&csrf=jct-token", True),
    "later-clear": ("POST", "/x/v2/history/toview/clear", "csrf=jct-token", True),
    "fav-deal": ("POST", "/x/v3/fav/resource/deal", "add_media_ids=11%2C22&csrf=jct-token&del_media_ids=33&rid=8&type=2", True),
    "fav-add": ("POST", "/x/v3/fav/folder/add", "csrf=jct-token&privacy=0&title=%E5%AD%A6%E4%B9%A0", True),
    "history-list": ("GET", "/x/web-interface/history/cursor", "business=&max=0&ps=20&view_at=0", False),
    "history-page": ("GET", "/x/web-interface/history/cursor", "business=archive&max=900&ps=20&view_at=1600000000", False),
    "history-shadow": ("GET", "/x/v2/history/shadow", "", False),
    "later-list": ("GET", "/x/v2/history/toview", "", False),
    "fav-folders": ("GET", "/x/v3/fav/folder/created/list-all", "up_mid=99", False),
    "fav-folders-rid": ("GET", "/x/v3/fav/folder/created/list-all", "rid=8&type=2&up_mid=99", False),
    "fav-contents": ("GET", "/x/v3/fav/resource/list", "media_id=11&pn=2&ps=20", False),
}
print(f"account proof checked={data.get('checked')} ok={data.get('ok')} failures={data.get('failures')}")
if data.get("ok") is not True or data.get("failures"):
    raise SystemExit("account request proof failed")
found = {item["name"]: item for item in data.get("cases", [])}
if set(found) != set(expect):
    raise SystemExit(f"account cases {sorted(set(found) ^ set(expect))}")
for name, (method, path, body, csrf) in expect.items():
    item = found[name]
    if (item.get("method"), item.get("path"), item.get("body"), bool(item.get("csrf"))) != (method, path, body, csrf):
        raise SystemExit(f"{name} drifted: {item}")
    if csrf and "csrf=jct-token" not in item["body"]:
        raise SystemExit(f"{name} missing csrf")
    if not csrf and "csrf" in item["body"]:
        raise SystemExit(f"{name} unexpected csrf")
print(f"account request proof ok ({len(expect)} cases)")
PY
}

capture_account_ui() {
  local screen="$1"
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/account-ui.json"
  rm -f "$proof"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen "$screen" -perfLabel "$LABEL"
  for _ in $(seq 1 30); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  # The fav sheet is the one animated presentation. Lists are already on screen.
  if [[ "$screen" == "favsheet" ]]; then sleep 2; else sleep 1; fi
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/${screen}.png"
  echo "saved ${screen}.png"
  if [[ "$found" -ne 1 ]]; then
    echo "missing account ui proof for ${screen}" >&2
    return 1
  fi
  cp "$proof" "$OUT/perf/${screen}-ui.json"
  python3 - "$screen" "$proof" <<'PY'
import json, sys
screen, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
print(screen, {k: data.get(k) for k in ("prompt", "rows", "folders", "sheet", "error", "titles")})
if data.get("screen") != screen:
    raise SystemExit(f"{screen} proof screen mismatch")
if data.get("error"):
    raise SystemExit(f"{screen} showed an error: {data.get('error')}")
if screen.startswith("guest"):
    ok = data.get("prompt") is True and int(data.get("rows") or 0) == 0 and int(data.get("folders") or 0) == 0
elif screen == "history":
    ok = data.get("prompt") is False and int(data.get("rows") or 0) >= 4
elif screen == "later":
    ok = data.get("prompt") is False and int(data.get("rows") or 0) >= 4
elif screen == "fav":
    ok = data.get("prompt") is False and int(data.get("folders") or 0) >= 3
elif screen == "favsheet":
    titles = data.get("titles") or []
    ok = data.get("sheet") is True and int(data.get("folders") or 0) >= 3 and "默认收藏夹" in titles and "学习" in titles
else:
    ok = False
print(f"{screen} ui {'ok' if ok else 'rejected'}")
if not ok:
    raise SystemExit(f"{screen} ui proof rejected")
PY
}

capture_social_proof() {
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/social-proof.json"
  rm -f "$proof"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen socialProof -perfLabel "$LABEL"
  for _ in $(seq 1 30); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  if [[ "$found" -ne 1 ]]; then
    echo "missing social request proof" >&2
    return 1
  fi
  cp "$proof" "$OUT/perf/social-proof.json"
  python3 - "$proof" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
expect = {
    "feed": ("GET", "/x/polymer/web-dynamic/v1/feed/all", "features=itemOpusStyle&offset=&timezone_offset=-480&type=all", False),
    "feed-video": ("GET", "/x/polymer/web-dynamic/v1/feed/all", "features=itemOpusStyle&offset=cursor&timezone_offset=-480&type=video", False),
    "reply-hot": ("GET", "/x/v2/reply", "oid=42&pn=1&ps=20&sort=1&type=1", False),
    "reply-time": ("GET", "/x/v2/reply", "oid=42&pn=2&ps=20&sort=0&type=1", False),
    "reply-thread": ("GET", "/x/v2/reply/reply", "oid=42&pn=1&ps=10&root=9&type=1", False),
    "reply-add": ("POST", "/x/v2/reply/add", "csrf=jct-token&message=%E4%BD%A0%E5%A5%BD&oid=42&plat=1&type=1", True),
    "reply-to": ("POST", "/x/v2/reply/add", "csrf=jct-token&message=%E4%BD%A0%E5%A5%BD&oid=42&parent=9&plat=1&root=9&type=1", True),
    "search-video": ("GET", "/x/web-interface/search/type", "keyword=%E5%8E%9F%E7%A5%9E&page=1&search_type=video", False),
    "search-filter": ("GET", "/x/web-interface/search/type", "duration=1&keyword=%E5%8E%9F%E7%A5%9E&order=click&page=1&search_type=video&tids=4", False),
    "search-user": ("GET", "/x/web-interface/search/type", "keyword=%E7%BD%97%E7%BF%94&page=1&search_type=bili_user", False),
    "search-bangumi": ("GET", "/x/web-interface/search/type", "keyword=%E9%AC%BC%E7%81%AD%E4%B9%8B%E5%88%83&page=1&search_type=media_bangumi", False),
    "search-live": ("GET", "/x/web-interface/search/type", "keyword=%E5%8E%9F%E7%A5%9E&page=1&search_type=live_room", False),
    "search-article": ("GET", "/x/web-interface/search/type", "keyword=%E5%8E%9F%E7%A5%9E&page=1&search_type=article", False),
}
print(f"social proof checked={data.get('checked')} ok={data.get('ok')} failures={data.get('failures')}")
if data.get("ok") is not True or data.get("failures"):
    raise SystemExit("social request proof failed")
found = {item["name"]: item for item in data.get("cases", [])}
if set(found) != set(expect):
    raise SystemExit(f"social cases {sorted(set(found) ^ set(expect))}")
for name, (method, path, body, csrf) in expect.items():
    item = found[name]
    if (item.get("method"), item.get("path"), item.get("body"), bool(item.get("csrf"))) != (method, path, body, csrf):
        raise SystemExit(f"{name} drifted: {item}")
    if csrf and "csrf=jct-token" not in item["body"]:
        raise SystemExit(f"{name} missing csrf")
    if not csrf and "csrf" in item["body"]:
        raise SystemExit(f"{name} unexpected csrf")
print(f"social request proof ok ({len(expect)} cases)")
PY
}

capture_social_ui() {
  local screen="$1"
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/social-ui.json"
  rm -f "$proof"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen "$screen" -perfLabel "$LABEL"
  local tries=45
  if [[ "$screen" == "comments" || "$screen" == search-* ]]; then tries=60; fi
  for _ in $(seq 1 "$tries"); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  sleep 1
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/${screen}.png"
  echo "saved ${screen}.png"
  if [[ "$found" -ne 1 ]]; then
    echo "missing social ui proof for ${screen}" >&2
    return 1
  fi
  cp "$proof" "$OUT/perf/${screen}-ui.json"
  python3 - "$screen" "$proof" <<'PY'
import json, sys
screen, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
print(screen, {k: data.get(k) for k in ("prompt", "rows", "count", "type", "title", "name", "error")})
if data.get("screen") != screen:
    raise SystemExit(f"{screen} proof screen mismatch")
if data.get("error"):
    raise SystemExit(f"{screen} showed an error: {data.get('error')}")
types = {
    "search-video": "video",
    "search-user": "bili_user",
    "search-bangumi": "media_bangumi",
    "search-live": "live_room",
    "search-article": "article",
}
if screen == "dynamics":
    ok = data.get("prompt") is False and int(data.get("rows") or 0) >= 4
elif screen == "guest-dynamics":
    ok = data.get("prompt") is True and int(data.get("rows") or 0) == 0
elif screen == "comments":
    ok = int(data.get("rows") or 0) >= 1 and str(data.get("message") or "") != "" and str(data.get("name") or "") != ""
elif screen in types:
    title = str(data.get("title") or "")
    ok = data.get("type") == types[screen] and int(data.get("count") or 0) >= 1 and title != "" and "fixture" not in title
else:
    ok = False
print(f"{screen} social ui {'ok' if ok else 'rejected'}")
if not ok:
    raise SystemExit(f"{screen} social ui rejected")
PY
}

capture_space_proof() {
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/space-proof.json"
  rm -f "$proof"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen spaceProof -perfLabel "$LABEL"
  for _ in $(seq 1 30); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  if [[ "$found" -ne 1 ]]; then
    echo "missing space request proof" >&2
    return 1
  fi
  cp "$proof" "$OUT/perf/space-proof.json"
  python3 - "$proof" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
expect = {
    "profile": ("GET", "/x/web-interface/card", "mid=42", False),
    "videos-new": ("GET", "/x/space/wbi/arc/search", "mid=42&order=pubdate&pn=1&ps=30", False),
    "videos-hot": ("GET", "/x/space/wbi/arc/search", "mid=42&order=click&pn=2&ps=30", False),
    "dynamics": ("GET", "/x/polymer/web-dynamic/v1/feed/space", "features=itemOpusStyle&host_mid=42&offset=&timezone_offset=-480", False),
    "folders": ("GET", "/x/v3/fav/folder/created/list-all", "up_mid=42", False),
    "bangumi": ("GET", "/x/space/bangumi/follow/list", "follow_status=0&pn=1&ps=20&type=1&vmid=42", False),
    "series": ("GET", "/x/polymer/web-space/seasons_series_list", "mid=42&page_num=1&page_size=20", False),
    "follow": ("POST", "/x/relation/modify", "act=1&csrf=jct-token&fid=42&re_src=11", True),
    "unfollow": ("POST", "/x/relation/modify", "act=2&csrf=jct-token&fid=42&re_src=11", True),
}
print(f"space proof checked={data.get('checked')} ok={data.get('ok')} failures={data.get('failures')}")
if data.get("ok") is not True or data.get("failures"):
    raise SystemExit("space request proof failed")
found = {item["name"]: item for item in data.get("cases", [])}
if set(found) != set(expect):
    raise SystemExit(f"space cases {sorted(set(found) ^ set(expect))}")
for name, (method, path, body, csrf) in expect.items():
    item = found[name]
    if (item.get("method"), item.get("path"), item.get("body"), bool(item.get("csrf"))) != (method, path, body, csrf):
        raise SystemExit(f"{name} drifted: {item}")
    if csrf and "csrf=jct-token" not in item["body"]:
        raise SystemExit(f"{name} missing csrf")
    if not csrf and "csrf" in item["body"]:
        raise SystemExit(f"{name} unexpected csrf")
print(f"space request proof ok ({len(expect)} cases)")
PY
}

capture_space_ui() {
  local screen="$1"
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/space-ui.json"
  rm -f "$proof"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen "$screen" -perfLabel "$LABEL"
  for _ in $(seq 1 70); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  sleep 2
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/${screen}.png"
  echo "saved ${screen}.png"
  if [[ "$found" -ne 1 ]]; then
    echo "missing space ui proof for ${screen}" >&2
    return 1
  fi
  cp "$proof" "$OUT/perf/${screen}-ui.json"
  python3 - "$screen" "$proof" <<'PY'
import json, sys
screen, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
print(screen, {k: data.get(k) for k in ("name", "mid", "fans", "level", "count", "title", "tab", "error", "raw", "source", "empty")})
if data.get("screen") != screen:
    raise SystemExit(f"{screen} proof screen mismatch")
name = str(data.get("name") or "")
title = str(data.get("title") or "")
error = str(data.get("error") or "")
count = int(data.get("count") or 0)
profile_ok = "罗翔" in name and int(data.get("mid") or 0) > 0 and int(data.get("fans") or 0) > 0 and int(data.get("level") or 0) >= 1
content_ok = error == "" and count >= 1 and title != "" and "fixture" not in title
# 罗翔的追番接口返回隐私，公开收藏夹列表本身是空的。这两项记真实结果。
if screen == "space-bangumi":
    ok = profile_ok and (content_ok or "隐私" in error)
elif screen == "space-fav":
    raw = data.get("raw")
    ok = profile_ok and (content_ok or (error == "" and count == 0 and raw == 0))
elif screen == "space-dynamic":
    empty = data.get("empty")
    source = data.get("source")
    real = content_ok and source == "wbi"
    quiet = error == "" and count == 0 and source == "wbi" and (
        (empty == "none" and title == "暂无动态") or (empty == "guest" and title == "登录后查看动态")
    )
    ok = profile_ok and source != "season" and (real or quiet)
else:
    ok = profile_ok and content_ok
print(f"{screen} space ui {'ok' if ok else 'rejected'}")
if not ok:
    raise SystemExit(f"{screen} space ui rejected: {error or 'empty'}")
PY
}

capture_live_proof() {
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/live-proof.json"
  rm -f "$proof"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen liveProof -perfLabel "$LABEL"
  for _ in $(seq 1 30); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  if [[ "$found" -ne 1 ]]; then
    echo "missing live request proof" >&2
    return 1
  fi
  cp "$proof" "$OUT/perf/live-proof.json"
  python3 - "$proof" <<'PY'
import json, sys
data = json.load(open(sys.argv[1]))
expect = {
    "recommend": ("GET", "/xlive/web-interface/v1/second/getUserRecommend", "page=1&page_size=30&platform=web", False),
    "area": ("GET", "/xlive/web-interface/v1/second/getList", "area_id=0&page=1&parent_area_id=9&platform=web&sort_type=", False),
    "room": ("GET", "/xlive/web-room/v1/index/getH5InfoByRoom", "room_id=42", False),
    "play": ("GET", "/xlive/web-room/v2/index/getRoomPlayInfo", "codec=0%2C1%2C2&dolby=5&format=0%2C1%2C2&panorama=1&platform=web&protocol=0%2C1&ptype=8&qn=10000&room_id=42&web_location=444.8", False),
    "danmu": ("GET", "/xlive/web-room/v1/index/getDanmuInfo", "id=42&web_location=444.8", False),
    "send": ("POST", "/msg/send", "bubble=0&color=16777215&csrf=jct-token&csrf_token=jct-token&fontsize=25&mode=1&msg=%E4%BD%A0%E5%A5%BD&rnd=1700000000&room_type=0&roomid=42", True),
}
print(f"live proof checked={data.get('checked')} ok={data.get('ok')} failures={data.get('failures')}")
if data.get("ok") is not True or data.get("failures"):
    raise SystemExit("live request proof failed")
found = {item["name"]: item for item in data.get("cases", [])}
if set(found) != set(expect):
    raise SystemExit(f"live cases {sorted(set(found) ^ set(expect))}")
for name, (method, path, body, csrf) in expect.items():
    item = found[name]
    if (item.get("method"), item.get("path"), item.get("body"), bool(item.get("csrf"))) != (method, path, body, csrf):
        raise SystemExit(f"{name} drifted: {item}")
    if csrf and "csrf=jct-token" not in item["body"]:
        raise SystemExit(f"{name} missing csrf")
    if not csrf and "csrf" in item["body"]:
        raise SystemExit(f"{name} unexpected csrf")
print(f"live request proof ok ({len(expect)} cases)")
PY
}

capture_live_ui() {
  local screen="$1"
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/live-ui.json"
  rm -f "$proof"
  : > "$OUT/perf/${screen}.log"
  : > "$OUT/perf/${screen}.err"
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  xcrun simctl launch --terminate-running-process \
    --stdout="$OUT/perf/${screen}.log" --stderr="$OUT/perf/${screen}.err" \
    "$UDID" "$BUNDLE" -screen "$screen" -perfLabel "$LABEL"
  for _ in $(seq 1 70); do
    if [[ -f "$proof" ]]; then
      found=1
      break
    fi
    sleep 1
  done
  sleep 2
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/${screen}.png"
  echo "saved ${screen}.png"
  if [[ "$found" -ne 1 ]]; then
    echo "missing live ui proof for ${screen}" >&2
    tail -n 40 "$OUT/perf/${screen}.log" || true
    return 1
  fi
  cp "$proof" "$OUT/perf/${screen}-ui.json"
  if ! python3 - "$screen" "$proof" <<'PY'
import json, sys
screen, path = sys.argv[1], sys.argv[2]
data = json.load(open(path))
print(screen, {k: data.get(k) for k in ("area", "count", "title", "room", "uname", "error")})
if data.get("screen") != screen:
    raise SystemExit(f"{screen} proof screen mismatch")
title = str(data.get("title") or "")
error = str(data.get("error") or "")
count = int(data.get("count") or 0)
area = "网游" if screen == "live-area" else "推荐"
ok = (
    error == ""
    and count >= 1
    and title != ""
    and "fixture" not in title
    and int(data.get("room") or 0) > 0
    and data.get("area") == area
)
print(f"{screen} live ui {'ok' if ok else 'rejected'}")
if not ok:
    raise SystemExit(f"{screen} live ui rejected: {error or 'empty'}")
PY
  then
    echo "live ui log ${screen}:" >&2
    tail -n 40 "$OUT/perf/${screen}.log" || true
    return 1
  fi
}

capture_live_room() {
  local dir proof advanced=0 first="" cur="" err="" dm=0 proto="" title=""
  dir="$(container)"
  proof="$dir/Documents/live-room-proof.json"
  rm -f "$proof" "$OUT/screenshots/live-room.png" "$OUT/screenshots/live-room-failed.png"
  : > "$OUT/perf/live-room.log"
  : > "$OUT/perf/live-room.err"
  xcrun simctl launch --terminate-running-process \
    --stdout="$OUT/perf/live-room.log" --stderr="$OUT/perf/live-room.err" \
    "$UDID" "$BUNDLE" -screen live-room -perfLabel "$LABEL"
  local stay_room="" stay_start=0 fresh=0 room=0 elapsed=0 deadline
  deadline=$(( $(date +%s) + 220 ))
  while [[ $(date +%s) -lt $deadline ]]; do
    if [[ -f "$proof" ]]; then
      line="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
vals=[d.get("seconds",0), d.get("error") or "", d.get("danmaku",0), d.get("fresh",0), d.get("protocol") or "", d.get("room",0), str(d.get("title") or "").replace("\t"," ")]
print("\t".join(str(v) for v in vals))' "$proof" 2>/dev/null || true)"
      if [[ -z "$line" ]]; then
        sleep 1
        continue
      fi
      IFS=$'\t' read -r cur err dm fresh proto room title <<< "$line"
      if [[ -z "$err" && "$proto" == "hls" && -n "$title" ]]; then
        if [[ "$room" != "$stay_room" ]]; then
          stay_room="$room"
          stay_start=$(date +%s)
        fi
        elapsed=$(( $(date +%s) - stay_start ))
      else
        elapsed=0
      fi
      echo "live room seconds=$cur danmaku=$dm fresh=$fresh stay=${elapsed}s protocol=${proto:-none} title=${title:-none} error=${err:-none}"
      if [[ ( -z "$err" || "$err" == "-" ) && "$proto" == "hls" && -n "$title" && "$title" != "-" ]] && python3 -c 'import sys; dm,fr,el,sec=int(float(sys.argv[1])),int(float(sys.argv[2])),int(sys.argv[3]),float(sys.argv[4]); sys.exit(0 if dm >= 20 and fr >= 1 and el >= 55 and sec >= 5 else 1)' "$dm" "$fresh" "$elapsed" "$cur"; then
        advanced=1
        break
      fi
      # A quiet room can sit under 20 lines for the whole stay. Keep going once
      # the stream is real, and leave a hard failure for silence or a blank player.
      if [[ ( -z "$err" || "$err" == "-" ) && "$proto" == "hls" && -n "$title" && "$title" != "-" ]] && python3 -c 'import sys; dm,el,sec=int(float(sys.argv[1])),int(sys.argv[2]),float(sys.argv[3]); sys.exit(0 if dm >= 1 and el >= 55 and sec >= 5 else 1)' "$dm" "$elapsed" "$cur"; then
        echo "warning: live room traffic stayed at $dm danmaku after ${elapsed}s; continuing because the HLS stream is playing" >&2
        advanced=1
        break
      fi
    fi
    sleep 1
  done
  if [[ -f "$proof" ]]; then
    cp "$proof" "$OUT/perf/live-room-proof.json"
    echo "live room proof:"
    cat "$OUT/perf/live-room-proof.json"
    echo
  fi
  if [[ "$advanced" -ne 1 && ( -z "$err" || "$err" == "-" ) && "$proto" == "hls" && -n "$title" && "$title" != "-" ]] && python3 -c 'import sys; dm,sec=int(float(sys.argv[1])),float(sys.argv[2]); sys.exit(0 if dm >= 1 and sec >= 5 else 1)' "$dm" "$cur"; then
    echo "warning: live room traffic stayed at $dm danmaku; continuing because the HLS stream is playing" >&2
    advanced=1
  fi
  if [[ "$advanced" -ne 1 ]]; then
    if [[ ! -f "$proof" ]]; then
      echo "live room proof was not written" >&2
    fi
    echo "live room did not collect any danmaku on a playing HLS stream" >&2
    xcrun simctl io "$UDID" screenshot "$OUT/screenshots/live-room-b.png" || true
    cp "$OUT/screenshots/live-room-b.png" "$OUT/screenshots/live-room-failed.png" || true
    tail -n 60 "$OUT/perf/live-room.log" || true
    tail -n 40 "$OUT/perf/live-room.err" || true
    return 1
  fi
  local moved=0
  for _ in 1 2 3; do
    xcrun simctl io "$UDID" screenshot "$OUT/screenshots/live-room-a.png"
    sleep 0.9
    xcrun simctl io "$UDID" screenshot "$OUT/screenshots/live-room-b.png"
    if python3 - "$OUT/screenshots/live-room-a.png" "$OUT/screenshots/live-room-b.png" <<'PY'
import struct, sys, zlib

def read_png(path):
    data = open(path, "rb").read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise SystemExit(f"{path} is not a png")
    pos = 8
    width = height = color = None
    idat = b""
    while pos + 8 <= len(data):
        length = struct.unpack(">I", data[pos:pos + 4])[0]
        kind = data[pos + 4:pos + 8]
        chunk = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, color, _comp, _filt, inter = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or inter != 0 or color not in (2, 6):
                raise SystemExit(f"unsupported png {width}x{height} depth={depth} color={color} inter={inter}")
        elif kind == b"IDAT":
            idat += chunk
        elif kind == b"IEND":
            break
    raw = zlib.decompress(idat)
    bpp = 4 if color == 6 else 3
    stride = width * bpp
    rows = []
    index = 0
    prev = bytearray(stride)
    for _ in range(height):
        filt = raw[index]
        index += 1
        row = bytearray(raw[index:index + stride])
        index += stride
        for x in range(stride):
            left = row[x - bpp] if x >= bpp else 0
            up = prev[x]
            ul = prev[x - bpp] if x >= bpp else 0
            if filt == 0:
                value = row[x]
            elif filt == 1:
                value = (row[x] + left) & 255
            elif filt == 2:
                value = (row[x] + up) & 255
            elif filt == 3:
                value = (row[x] + ((left + up) // 2)) & 255
            elif filt == 4:
                guess = left + up - ul
                pa, pb, pc = abs(guess - left), abs(guess - up), abs(guess - ul)
                pred = left if pa <= pb and pa <= pc else (up if pb <= pc else ul)
                value = (row[x] + pred) & 255
            else:
                raise SystemExit(f"bad png filter {filt}")
            row[x] = value
        rows.append(row)
        prev = row
    return width, height, bpp, rows

def stats(path):
    width, height, bpp, rows = read_png(path)
    # The live player is the top quarter. The 8–32% band sits on the chat list.
    y0, y1 = int(height * 0.02), int(height * 0.22)
    total = 0.0
    squares = 0.0
    count = 0
    for y in range(y0, y1):
        row = rows[y]
        for x in range(width):
            i = x * bpp
            luma = 0.2126 * row[i] + 0.7152 * row[i + 1] + 0.0722 * row[i + 2]
            total += luma
            squares += luma * luma
            count += 1
    mean = total / count
    variance = max(0.0, squares / count - mean * mean)
    return width, height, mean, variance ** 0.5

def motion(left, right):
    aw, ah, ab, ar = read_png(left)
    bw, bh, bb, br = read_png(right)
    if (aw, ah, ab) != (bw, bh, bb):
        raise SystemExit(f"screenshot size changed {aw}x{ah} -> {bw}x{bh}")
    y0, y1 = int(ah * 0.02), int(ah * 0.22)
    total = 0.0
    count = 0
    for y in range(y0, y1):
        a = ar[y]
        b = br[y]
        for i in range(0, aw * ab, ab):
            total += abs(a[i] - b[i]) + abs(a[i + 1] - b[i + 1]) + abs(a[i + 2] - b[i + 2])
            count += 3
    return total / count

mean_a, std_a = stats(sys.argv[1])[2:]
width, height, mean_b, std_b = stats(sys.argv[2])
delta = motion(sys.argv[1], sys.argv[2])
print(f"live player band {width}x{height} mean={mean_b:.2f} stddev={std_b:.2f} motion={delta:.2f} first_stddev={std_a:.2f}")
if std_b < 15 or mean_b > 245 or delta < 2.0:
    raise SystemExit("player band does not look like moving video")
PY
    then
      moved=1
      break
    fi
    echo "live player band still"
  done
  if [[ "$moved" -ne 1 ]]; then
    cp "$OUT/screenshots/live-room-b.png" "$OUT/screenshots/live-room-failed.png"
    echo "live player band did not show moving video" >&2
    return 1
  fi
  cp "$OUT/screenshots/live-room-b.png" "$OUT/screenshots/live-room.png"
  echo "saved live-room.png danmaku=$dm"
}

capture_sponsor() {
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/sponsor-proof.json"
  rm -f "$proof" "$OUT/screenshots/sponsor.png"
  : > "$OUT/perf/sponsor.log"
  : > "$OUT/perf/sponsor.err"
  xcrun simctl launch --terminate-running-process \
    --stdout="$OUT/perf/sponsor.log" --stderr="$OUT/perf/sponsor.err" \
    "$UDID" "$BUNDLE" -screen sponsor -perfLabel "$LABEL"
  for _ in $(seq 1 90); do
    if [[ -f "$proof" ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if int(d.get("count") or 0) >= 1 and d.get("skipped") is True and str(d.get("server") or "") and str(d.get("prefix") or "") and not d.get("error") else 1)' "$proof"; then
      found=1
      break
    fi
    sleep 1
  done
  if [[ -f "$proof" ]]; then
    cp "$proof" "$OUT/perf/sponsor-proof.json"
    echo "sponsor proof:"
    cat "$OUT/perf/sponsor-proof.json"
    echo
  fi
  if [[ "$found" -ne 1 ]]; then
    echo "sponsor segments were not skipped on a real video" >&2
    xcrun simctl io "$UDID" screenshot "$OUT/screenshots/sponsor.png" || true
    tail -n 40 "$OUT/perf/sponsor.log" || true
    return 1
  fi
  sleep 0.6
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/sponsor.png"
  echo "saved sponsor.png"
}

capture_sponsor_settings() {
  local dir proof found=0
  dir="$(container)"
  proof="$dir/Documents/sponsor-settings-proof.json"
  rm -f "$proof" "$OUT/screenshots/sponsor-settings.png"
  xcrun simctl launch --terminate-running-process \
    "$UDID" "$BUNDLE" -screen sponsor-settings -perfLabel "$LABEL"
  for _ in $(seq 1 40); do
    if [[ -f "$proof" ]] && python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("sponsor") == "自动跳过" and d.get("screen") == "sponsor-settings" else 1)' "$proof"; then
      found=1
      break
    fi
    sleep 1
  done
  sleep 1
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/sponsor-settings.png"
  echo "saved sponsor-settings.png"
  if [[ -f "$proof" ]]; then
    cp "$proof" "$OUT/perf/sponsor-settings-proof.json"
  fi
  if [[ "$found" -ne 1 ]]; then
    echo "sponsor settings proof missing" >&2
    return 1
  fi
}

echo "Screenshots on $NAME"
suppress_apple_intelligence
account_status=0
social_status=0
space_status=0
playback_status=0
live_status=0
sponsor_status=0
capture_account_proof || account_status=1
capture_social_proof || social_status=1
capture_space_proof || space_status=1
capture_live_proof || live_status=1
catalog_status=0
for screen in home rank bangumi cinema dynamics mine search settings video login playback history later fav favsheet guest-history guest-later guest-fav guest-dynamics search-video search-user search-bangumi search-live search-article comments space space-dynamic space-fav space-bangumi space-series live live-area live-room sponsor sponsor-settings; do
  xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1 || true
  if [[ "$screen" == "playback" ]]; then
    if ! capture_playback; then
      echo "retrying playback capture" >&2
      capture_playback || playback_status=1
    fi
    continue
  fi
  if [[ "$screen" == "home" || "$screen" == "rank" || "$screen" == "bangumi" || "$screen" == "cinema" ]]; then
    capture_catalog "$screen" || catalog_status=1
    continue
  fi
  if [[ "$screen" == "history" || "$screen" == "later" || "$screen" == "fav" || "$screen" == "favsheet" || "$screen" == "guest-history" || "$screen" == "guest-later" || "$screen" == "guest-fav" ]]; then
    capture_account_ui "$screen" || account_status=1
    continue
  fi
  if [[ "$screen" == "dynamics" || "$screen" == "guest-dynamics" || "$screen" == "comments" || "$screen" == search-* ]]; then
    capture_social_ui "$screen" || social_status=1
    continue
  fi
  if [[ "$screen" == "space" || "$screen" == space-* ]]; then
    capture_space_ui "$screen" || space_status=1
    continue
  fi
  if [[ "$screen" == "live" || "$screen" == "live-area" ]]; then
    capture_live_ui "$screen" || live_status=1
    continue
  fi
  if [[ "$screen" == "live-room" ]]; then
    if ! capture_live_room; then
      echo "retrying live room capture" >&2
      capture_live_room || live_status=1
    fi
    continue
  fi
  if [[ "$screen" == "sponsor" ]]; then
    if ! capture_sponsor; then
      echo "retrying sponsor capture" >&2
      capture_sponsor || sponsor_status=1
    fi
    continue
  fi
  if [[ "$screen" == "sponsor-settings" ]]; then
    capture_sponsor_settings || sponsor_status=1
    continue
  fi
  xcrun simctl launch --terminate-running-process "$UDID" "$BUNDLE" -screen "$screen" -perfLabel "$LABEL"
  if [[ "$screen" == "login" ]]; then sleep 20
  else sleep 12
  fi
  xcrun simctl io "$UDID" screenshot "$OUT/screenshots/${screen}.png"
  echo "saved ${screen}.png"
done

scroll_status=0
verify_scroll || scroll_status=1
if [[ "$catalog_status" -ne 0 || "$scroll_status" -ne 0 || "$account_status" -ne 0 || "$social_status" -ne 0 || "$space_status" -ne 0 || "$playback_status" -ne 0 || "$live_status" -ne 0 || "$sponsor_status" -ne 0 ]]; then
  echo "home data, playback, account lists, social surfaces, user space, live, sponsor block, or warm scroll check failed" >&2
  exit 1
fi

echo "Done. Output in $OUT"
ls -la "$OUT/screenshots" "$OUT/perf"
