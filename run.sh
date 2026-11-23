#!/usr/bin/env bash
# =============================================================================
#  SpotX for macOS (Apple Silicon / Intel)
#  A port of SpotX (originally for Windows/PowerShell) to macOS Bash.
#
#  Patches the Spotify desktop client to:
#   - Block all banner, video, and audio ads
#   - Optionally hide podcasts / episodes / audiobooks from home
#   - Optionally block Spotify automatic updates
#   - Disable analytics / sentry reporting
#   - Apply experimental feature overrides
#
#  Usage:
#    bash run.sh [OPTIONS]
#
#  Options:
#    -h, --help                Show this help message and exit
#    --premium                 Install without ad-blocking (for Premium users)
#    --podcasts-off            Hide podcasts/episodes/audiobooks from home
#    --adsections-off          Hide ad-like sections from home
#    --block-update            Block Spotify automatic updates
#    --no-shortcut             Do not create a desktop alias
#    --start-spotify           Launch Spotify after patching
#    --lyrics-block            Disable native lyrics
#    --exp-spotify             Use only Spotify experimental flags (minimal overrides)
#    --new-theme               Force new theme (new left/right sidebars)
#    --no-pause                Skip the "Press Enter to exit" pause
#    --spotify-path <path>     Custom path to Spotify.app (default: auto-detect)
#    --custom-patches <path>   Path to a local patches.json (default: download)
#    --mirror                  Use github.io mirror instead of raw.githubusercontent
#    --version <ver>           Force a specific Spotify version check (informational)
#    --lyrics-stat <color>     Static colour for lyrics (e.g. spotify, blue, etc.)
#    --devtools                Enable developer tools in the patched client
#    --cache-limit <mb>        Set max cache limit (500-20000 MB)
#    --restore, --uninstall    Restore Spotify from backup
#
#  Requirements:
#    - macOS 11+ (Big Sur or later), Apple Silicon or Intel
#    - Spotify desktop app installed (not from Mac App Store)
#    - curl, unzip, zip, python3, codesign (pre-installed on modern macOS)
#
#  Disclaimer:
#    SpotX is provided for evaluation/educational purposes only.
#    Use at your own risk.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || echo "")"

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

info()  { echo -e "${CYAN}[INFO]${RESET}  $*"; }
ok()    { echo -e "${GREEN}[OK]${RESET}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${RESET}  $*"; }
err()   { echo -e "${RED}[ERROR]${RESET} $*" >&2; }
die()   { err "$*"; exit 1; }

# ---------------------------------------------------------------------------
# Default option values
# ---------------------------------------------------------------------------
OPT_PREMIUM=false
OPT_PODCASTS_OFF=false
OPT_ADSECTIONS_OFF=false
OPT_BLOCK_UPDATE=false
OPT_NO_SHORTCUT=false
OPT_START_SPOTIFY=false
OPT_LYRICS_BLOCK=false
OPT_EXP_SPOTIFY=false
OPT_NEW_THEME=false
OPT_NO_PAUSE=false
OPT_DEVTOOLS=false
OPT_MIRROR=false
OPT_RESTORE=false
OPT_SPOTIFY_PATH=""
OPT_CUSTOM_PATCHES=""
OPT_VERSION=""
OPT_LYRICS_STAT=""
OPT_CACHE_LIMIT=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
usage() {
    sed -n '/^#  Usage:/,/^# ====/p' "$0" | head -n -1 | sed 's/^#  \?//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)            usage ;;
        --premium)            OPT_PREMIUM=true ;;
        --podcasts-off)       OPT_PODCASTS_OFF=true ;;
        --adsections-off)     OPT_ADSECTIONS_OFF=true ;;
        --block-update)       OPT_BLOCK_UPDATE=true ;;
        --no-shortcut)        OPT_NO_SHORTCUT=true ;;
        --start-spotify)      OPT_START_SPOTIFY=true ;;
        --lyrics-block)       OPT_LYRICS_BLOCK=true ;;
        --exp-spotify)        OPT_EXP_SPOTIFY=true ;;
        --new-theme)          OPT_NEW_THEME=true ;;
        --no-pause)           OPT_NO_PAUSE=true ;;
        --devtools)           OPT_DEVTOOLS=true ;;
        --mirror)             OPT_MIRROR=true ;;
        --restore|--uninstall) OPT_RESTORE=true ;;
        --spotify-path)       OPT_SPOTIFY_PATH="$2"; shift ;;
        --custom-patches)     OPT_CUSTOM_PATCHES="$2"; shift ;;
        --version)            OPT_VERSION="$2"; shift ;;
        --lyrics-stat)        OPT_LYRICS_STAT="$2"; shift ;;
        --cache-limit)        OPT_CACHE_LIMIT="$2"; shift ;;
        *) warn "Unknown option: $1" ;;
    esac
    shift
done

# ---------------------------------------------------------------------------
# Architecture detection
# ---------------------------------------------------------------------------
ARCH=$(uname -m)
case "$ARCH" in
    arm64)   ARCH_LABEL="Apple Silicon (arm64)" ;;
    x86_64)  ARCH_LABEL="Intel (x86_64)" ;;
    *)       die "Unsupported architecture: $ARCH" ;;
esac

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗"
echo -e "║          SpotX for macOS – Ad Patcher               ║"
echo -e "╚══════════════════════════════════════════════════════╝${RESET}"
echo -e "  Platform : ${CYAN}macOS – ${ARCH_LABEL}${RESET}"
echo ""

# ---------------------------------------------------------------------------
# Dependency check
# ---------------------------------------------------------------------------
MISSING_DEPS=()
for dep in curl unzip zip python3 codesign; do
    if ! command -v "$dep" &>/dev/null; then
        MISSING_DEPS+=("$dep")
    fi
done

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    die "Missing required tools: ${MISSING_DEPS[*]}"$'\n'"Install via Homebrew or Xcode Command Line Tools"
fi

# python3 version check (need 3.6+)
PY_VER=$(python3 -c 'import sys; print(sys.version_info.major*10+sys.version_info.minor)')
if [[ "$PY_VER" -lt 36 ]]; then
    die "Python 3.6 or later is required (found $(python3 --version))"
fi

ok "Dependencies satisfied"

# ---------------------------------------------------------------------------
# Locate Spotify.app
# ---------------------------------------------------------------------------
locate_spotify() {
    local candidates=(
        "/Applications/Spotify.app"
        "$HOME/Applications/Spotify.app"
    )
    for c in "${candidates[@]}"; do
        [[ -d "$c" ]] && { echo "$c"; return; }
    done
    return 1
}

if [[ -n "$OPT_SPOTIFY_PATH" ]]; then
    SPOTIFY_APP="$OPT_SPOTIFY_PATH"
else
    SPOTIFY_APP=$(locate_spotify) || die "Spotify.app not found.\nInstall the official Spotify desktop app from https://www.spotify.com/download/mac/\nOr specify the path with --spotify-path <path>"
fi

[[ -d "$SPOTIFY_APP" ]] || die "Spotify.app does not exist at: $SPOTIFY_APP"

# Key paths inside the bundle
SPOTIFY_RESOURCES="$SPOTIFY_APP/Contents/Resources"
XPUI_SPA="$SPOTIFY_RESOURCES/Apps/xpui.spa"
SPOTIFY_BINARY="$SPOTIFY_APP/Contents/MacOS/Spotify"
BACKUP_SPA="${XPUI_SPA}.bak"
BACKUP_BINARY="${SPOTIFY_BINARY}.bak"
PREFS_DIR="$HOME/Library/Application Support/Spotify"

[[ -f "$XPUI_SPA" || -f "$BACKUP_SPA" ]] || die "xpui.spa not found at: $XPUI_SPA"$'\n'"Your Spotify installation may be corrupt. Try reinstalling Spotify."

# Read version from Info.plist
SPOTIFY_VERSION=$(defaults read "$SPOTIFY_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "1.3.11")
if [[ -n "$OPT_VERSION" ]]; then
    SPOTIFY_VERSION="$OPT_VERSION"
fi

info "Spotify version  : ${BOLD}$SPOTIFY_VERSION${RESET}"
info "Spotify path     : $SPOTIFY_APP"
info "xpui.spa path    : $XPUI_SPA"
echo ""

# ---------------------------------------------------------------------------
# Kill Spotify if running
# ---------------------------------------------------------------------------
kill_spotify() {
    local pids
    pids=$(pgrep -x "Spotify" 2>/dev/null || true)
    if [[ -n "$pids" ]]; then
        info "Stopping Spotify …"
        kill $pids 2>/dev/null || true
        local attempts=0
        while pgrep -x "Spotify" &>/dev/null && [[ $attempts -lt 10 ]]; do
            sleep 0.5
            (( attempts++ ))
        done
        if pgrep -x "Spotify" &>/dev/null; then
            warn "Could not gracefully stop Spotify; forcing …"
            kill -9 $pids 2>/dev/null || true
        fi
        ok "Spotify stopped."
    fi
}

kill_spotify

# ---------------------------------------------------------------------------
# Restore / Uninstall action
# ---------------------------------------------------------------------------
clear_spotify_caches() {
    info "Clearing Spotify caches …"
    rm -rf "$HOME/Library/Caches/com.spotify.client/Browser/Cache" 2>/dev/null || true
    rm -rf "$HOME/Library/Caches/com.spotify.client/Data" 2>/dev/null || true
    rm -rf "$HOME/Library/Application Support/Spotify/PersistentCache" 2>/dev/null || true
    rm -f "$HOME/Library/Application Support/Spotify/ad-device-state" 2>/dev/null || true
    ok "Caches cleared."
}

if $OPT_RESTORE; then
    info "Restoring original Spotify files from backup …"
    restored=false
    if [[ -f "$BACKUP_SPA" ]]; then
        cp -f "$BACKUP_SPA" "$XPUI_SPA"
        ok "Restored xpui.spa from backup."
        restored=true
    fi
    if [[ -f "$BACKUP_BINARY" ]]; then
        cp -f "$BACKUP_BINARY" "$SPOTIFY_BINARY"
        chmod +x "$SPOTIFY_BINARY"
        ok "Restored Spotify executable from backup."
        restored=true
    fi
    if ! $restored; then
        warn "No backup files found to restore."
    fi
    clear_spotify_caches
    xattr -rd com.apple.quarantine "$SPOTIFY_APP" 2>/dev/null || true
    codesign --force --deep --sign - "$SPOTIFY_APP" 2>/dev/null && ok "Ad-hoc code signing completed" || true
    ok "Spotify restoration complete."
    exit 0
fi

# ---------------------------------------------------------------------------
# Check if already patched (backup exists)
# ---------------------------------------------------------------------------
if [[ -f "$BACKUP_SPA" ]]; then
    warn "A backup file already exists: $BACKUP_SPA"
    warn "Restoring original files before re-applying patch …"
    cp -f "$BACKUP_SPA" "$XPUI_SPA"
    if [[ -f "$BACKUP_BINARY" ]]; then
        cp -f "$BACKUP_BINARY" "$SPOTIFY_BINARY"
        chmod +x "$SPOTIFY_BINARY"
    fi
    ok "Original files restored for clean patching."
else
    info "Backing up original files …"
    cp -f "$XPUI_SPA" "$BACKUP_SPA"
    cp -f "$SPOTIFY_BINARY" "$BACKUP_BINARY"
    ok "Backups saved: $(basename "$BACKUP_SPA"), $(basename "$BACKUP_BINARY")"
fi

# ---------------------------------------------------------------------------
# Remote base URLs & Helper resolution
# ---------------------------------------------------------------------------
if [[ "$OPT_MIRROR" == "true" ]]; then
    BASE_URL="https://spotx-official.github.io/SpotX"
else
    BASE_URL="https://raw.githubusercontent.com/SpotX-Official/SpotX/refs/heads/main"
fi

PATCHES_URL="${BASE_URL}/patches/patches.json"
CHECK_VERSION_URL="${BASE_URL}/js-helper/checkVersion.js"
SECTION_BLOCK_URL="${BASE_URL}/js-helper/sectionBlock.js"
LYRICS_RULES_URL="${BASE_URL}/css-helper/lyrics-color/rules.css"
LYRICS_COLORS_URL="${BASE_URL}/css-helper/lyrics-color/colors.css"

TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

spotx_download() {
    local url="$1" out="$2"
    if ! curl --silent --fail --location --max-time 30 --retry 3 --retry-delay 2 \
         --user-agent "SpotX-macOS/1.0" -o "$out" "$url"; then
        return 1
    fi
    [[ -s "$out" ]] || return 1
    return 0
}

# Load patches.json
info "Loading patches …"
if [[ -n "$OPT_CUSTOM_PATCHES" && -f "$OPT_CUSTOM_PATCHES" ]]; then
    PATCHES_FILE="$OPT_CUSTOM_PATCHES"
    info "Using custom patches.json: $PATCHES_FILE"
elif [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/patches/patches.json" ]]; then
    PATCHES_FILE="$SCRIPT_DIR/patches/patches.json"
    info "Using local repository patches.json"
elif [[ -f "./patches/patches.json" ]]; then
    PATCHES_FILE="./patches/patches.json"
    info "Using current directory patches.json"
else
    PATCHES_FILE="$TEMP_DIR/patches.json"
    if ! spotx_download "$PATCHES_URL" "$PATCHES_FILE"; then
        die "Failed to download patches.json from: $PATCHES_URL"
    fi
    ok "Downloaded patches.json"
fi

# Validate JSON
if ! python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$PATCHES_FILE" 2>/dev/null; then
    die "patches.json is not valid JSON"
fi

# Helper files
info "Resolving helper files …"
CV_FILE="$TEMP_DIR/checkVersion.js"
SB_FILE="$TEMP_DIR/sectionBlock.js"
LR_FILE="$TEMP_DIR/lyricsRules.css"
LC_FILE="$TEMP_DIR/lyricsColors.css"

# checkVersion.js
if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/js-helper/checkVersion.js" ]]; then
    cp "$SCRIPT_DIR/js-helper/checkVersion.js" "$CV_FILE"
    ok "checkVersion.js (local)"
elif spotx_download "$CHECK_VERSION_URL" "$CV_FILE"; then
    ok "checkVersion.js (downloaded)"
else
    warn "checkVersion.js unavailable – skipping"
    CV_FILE=""
fi

# sectionBlock.js
NEED_SECTION=false
$OPT_PODCASTS_OFF  && NEED_SECTION=true
$OPT_ADSECTIONS_OFF && NEED_SECTION=true

if $NEED_SECTION; then
    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/js-helper/sectionBlock.js" ]]; then
        cp "$SCRIPT_DIR/js-helper/sectionBlock.js" "$SB_FILE"
        ok "sectionBlock.js (local)"
    elif spotx_download "$SECTION_BLOCK_URL" "$SB_FILE"; then
        ok "sectionBlock.js (downloaded)"
    else
        warn "sectionBlock.js unavailable – skipping"
        SB_FILE=""
    fi
else
    SB_FILE=""
fi

# lyrics color CSS
if [[ -n "$OPT_LYRICS_STAT" ]]; then
    if [[ -n "$SCRIPT_DIR" && -f "$SCRIPT_DIR/css-helper/lyrics-color/rules.css" && -f "$SCRIPT_DIR/css-helper/lyrics-color/colors.css" ]]; then
        cp "$SCRIPT_DIR/css-helper/lyrics-color/rules.css" "$LR_FILE"
        cp "$SCRIPT_DIR/css-helper/lyrics-color/colors.css" "$LC_FILE"
        ok "Lyrics CSS files (local)"
    elif spotx_download "$LYRICS_RULES_URL" "$LR_FILE" && spotx_download "$LYRICS_COLORS_URL" "$LC_FILE"; then
        ok "Lyrics CSS files (downloaded)"
    else
        warn "Lyrics CSS files unavailable – skipping"
        LR_FILE=""
        LC_FILE=""
    fi
else
    LR_FILE=""
    LC_FILE=""
fi

echo ""

# ---------------------------------------------------------------------------
# Extract xpui.spa
# ---------------------------------------------------------------------------
XPUI_DIR="$TEMP_DIR/xpui"
mkdir -p "$XPUI_DIR"
info "Extracting xpui.spa …"
python3 -m zipfile -e "$XPUI_SPA" "$XPUI_DIR" || die "Failed to extract xpui.spa"
ok "Extracted xpui.spa"

# ---------------------------------------------------------------------------
# Patch Engine (Python)
# ---------------------------------------------------------------------------
PATCHER_SCRIPT="$TEMP_DIR/patcher.py"

cat > "$PATCHER_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
"""
SpotX macOS – Comprehensive Patch Engine
Handles:
  1. V8 context snapshot extraction for modern Spotify (assembling xpui.js)
  2. VariousJs / product_state overrides (setting ads: '0', catalogue: 'premium', product: 'premium')
  3. Ad-block regex matching (emptyblock, banner_home, upgradeMenu, upgradeButton, mock, sentry, etc.)
  4. ForcedExp remote configuration overrides with enabled/disabled experiment flags
  5. Helper script injection (checkVersion.js, sectionBlock.js with action type, lyrics CSS)
  6. Binary patching (gabo-receiver-service -> dodo, desktop-update)
"""
import json, re, sys, os, glob, shutil

patches_file   = sys.argv[1]
xpui_dir       = sys.argv[2]
spotify_app    = sys.argv[3]
spotify_binary = sys.argv[4]
spotify_ver    = sys.argv[5]
premium        = sys.argv[6] == "true"
podcasts_off   = sys.argv[7] == "true"
adsections_off = sys.argv[8] == "true"
lyrics_stat    = sys.argv[9]
devtools       = sys.argv[10] == "true"
lyrics_block   = sys.argv[11] == "true"
exp_spotify    = sys.argv[12] == "true"
new_theme      = sys.argv[13] == "true"
block_update   = sys.argv[14] == "true"
cache_limit    = sys.argv[15]
cv_file        = sys.argv[16]   # checkVersion.js path or empty
sb_file        = sys.argv[17]   # sectionBlock.js path or empty
lr_file        = sys.argv[18]   # lyricsRules.css or empty
lc_file        = sys.argv[19]   # lyricsColors.css or empty

RESET  = "\033[0m"
GREEN  = "\033[0;32m"
YELLOW = "\033[1;33m"
CYAN   = "\033[0;36m"
RED    = "\033[0;31m"

def ok(msg):   print(f"  {GREEN}\u2714{RESET}  {msg}")
def warn(msg): print(f"  {YELLOW}\u26a0{RESET}  {msg}", file=sys.stderr)
def info(msg): print(f"  {CYAN}\u2192{RESET}  {msg}")

def read_file(path):
    with open(path, "r", encoding="utf-8", errors="replace") as f:
        return f.read()

def write_file(path, content):
    with open(path, "w", encoding="utf-8") as f:
        f.write(content)

def parse_version(v_str):
    if not v_str:
        return ()
    nums = re.findall(r'\d+', str(v_str))
    return tuple(int(x) for x in nums[:4]) if nums else ()

def version_in_range(v_target, v_fr, v_to):
    target = parse_version(v_target)
    if not target:
        return True
    if v_fr:
        fr = parse_version(v_fr)
        if target < fr:
            return False
    if v_to:
        to = parse_version(v_to)
        if target > to:
            return False
    return True

# ---------------------------------------------------------------------------
# 1. V8 context snapshot extraction & xpui.js assembly
# ---------------------------------------------------------------------------
def extract_webpack_modules(snap_path):
    if not os.path.isfile(snap_path):
        return None
    with open(snap_path, "rb") as f:
        data = f.read()
    start_marker = "var __webpack_modules__={".encode("utf-16le")
    end_marker = "//# sourceMappingURL=xpui-modules.js.map".encode("utf-16le")
    idx1 = data.find(start_marker)
    if idx1 != -1:
        idx2 = data.find(end_marker, idx1)
        if idx2 != -1:
            end_data_idx = idx2 + len(end_marker)
            return data[idx1:end_data_idx].decode("utf-16le", errors="replace")
    start_marker_u8 = b"var __webpack_modules__={"
    end_marker_u8 = b"//# sourceMappingURL=xpui-modules.js.map"
    idx1_u8 = data.find(start_marker_u8)
    if idx1_u8 != -1:
        idx2_u8 = data.find(end_marker_u8, idx1_u8)
        if idx2_u8 != -1:
            return data[idx1_u8:idx2_u8 + len(end_marker_u8)].decode("utf-8", errors="replace")
    return None

xpui_js_path = os.path.join(xpui_dir, "xpui.js")
xpui_snapshot_js_path = os.path.join(xpui_dir, "xpui-snapshot.js")
xpui_css_path = os.path.join(xpui_dir, "xpui.css")
xpui_snapshot_css_path = os.path.join(xpui_dir, "xpui-snapshot.css")
index_html_path = os.path.join(xpui_dir, "index.html")

needs_assembly = False
if not os.path.isfile(xpui_js_path):
    needs_assembly = True
else:
    existing_js = read_file(xpui_js_path)
    if "var __webpack_modules__=" not in existing_js and os.path.isfile(xpui_snapshot_js_path):
        needs_assembly = True

if needs_assembly and os.path.isfile(xpui_snapshot_js_path):
    info("Spotify V8 snapshot detected. Locating snapshot binary …")
    snap_candidates = [
        os.path.join(spotify_app, "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/v8_context_snapshot.arm64.bin"),
        os.path.join(spotify_app, "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/v8_context_snapshot.x86_64.bin"),
        os.path.join(spotify_app, "Contents/Frameworks/Chromium Embedded Framework.framework/Versions/A/Resources/v8_context_snapshot.bin"),
    ]
    snapshot_bin = None
    for cand in snap_candidates:
        if os.path.isfile(cand):
            snapshot_bin = cand
            break
    if not snapshot_bin:
        found = glob.glob(os.path.join(spotify_app, "**", "v8_context_snapshot*.bin"), recursive=True)
        if found:
            snapshot_bin = found[0]

    if snapshot_bin:
        info(f"Extracting Webpack modules from: {os.path.basename(snapshot_bin)} …")
        modules = extract_webpack_modules(snapshot_bin)
        if modules:
            snapshot_code = read_file(xpui_snapshot_js_path)
            full_js = modules + "\n" + snapshot_code
            write_file(xpui_js_path, full_js)
            write_file(xpui_snapshot_js_path, full_js)
            ok(f"Extracted {len(modules):,} chars of Webpack modules & assembled xpui.js")
        else:
            warn("Could not extract Webpack modules from snapshot binary")
    else:
        warn("v8_context_snapshot binary not found in Spotify bundle")

# Ensure both xpui.css and xpui-snapshot.css exist
if os.path.isfile(xpui_snapshot_css_path) and not os.path.isfile(xpui_css_path):
    shutil.copyfile(xpui_snapshot_css_path, xpui_css_path)
elif os.path.isfile(xpui_css_path) and not os.path.isfile(xpui_snapshot_css_path):
    shutil.copyfile(xpui_css_path, xpui_snapshot_css_path)

# Update index.html to refer to xpui.js / xpui.css
if os.path.isfile(index_html_path):
    idx_content = read_file(index_html_path)
    idx_content = idx_content.replace("/xpui-snapshot.js", "/xpui.js")
    idx_content = idx_content.replace("/xpui-snapshot.css", "/xpui.css")
    write_file(index_html_path, idx_content)

# ---------------------------------------------------------------------------
# 2. Patch helper
# ---------------------------------------------------------------------------
with open(patches_file, "r", encoding="utf-8") as f:
    patches = json.load(f)

others   = patches.get("others", {})
free     = patches.get("free", {})
var_js   = patches.get("VariousJs", {})

def apply_patch(content, patch_obj, label=""):
    if isinstance(patch_obj, list):
        for p in patch_obj:
            content = apply_patch(content, p, label)
        return content
    if not isinstance(patch_obj, dict):
        return content
    if patch_obj.get("disable") is True:
        return content

    ver_info = patch_obj.get("version")
    if isinstance(ver_info, dict):
        if not version_in_range(spotify_ver, ver_info.get("fr"), ver_info.get("to")):
            return content

    match_val = patch_obj.get("match", patch_obj.get("find", ""))
    replace_val = patch_obj.get("replace", patch_obj.get("add", ""))
    if not match_val:
        return content

    matches = match_val if isinstance(match_val, list) else [match_val]
    replaces = replace_val if isinstance(replace_val, list) else [replace_val]

    total_patched = 0
    for i in range(len(matches)):
        pat = matches[i]
        rep = replaces[i] if i < len(replaces) else replaces[0]
        try:
            new_content, n = re.subn(pat, rep, content, flags=re.DOTALL)
            if n > 0:
                total_patched += n
                content = new_content
        except re.error as exc:
            warn(f"Regex error in {label}: {exc}")

    if total_patched > 0:
        ok(f"Patched ({total_patched}x): {label}")
    return content

# ---------------------------------------------------------------------------
# 3. Apply xpui.js patches (ad-blocking, product state, ForcedExp)
# ---------------------------------------------------------------------------
info("Applying ad-blocking and product state patches to xpui.js …")
if os.path.isfile(xpui_js_path):
    xpui_content = read_file(xpui_js_path)

    # VariousJs.product_state (The core ad-block & premium status override)
    if not premium:
        p_prod = var_js.get("product_state", {})
        if p_prod and version_in_range(spotify_ver, p_prod.get("version", {}).get("fr"), p_prod.get("version", {}).get("to")):
            adds = p_prod.get("add", "")
            if cache_limit:
                try:
                    clim = max(500, min(20000, int(cache_limit)))
                    add2 = p_prod.get("add2", "").replace("{0}", str(clim))
                    adds = f"{adds},{add2}" if adds else add2
                except ValueError:
                    pass
            repl = p_prod.get("replace", "").replace("{0}", f"{{pairs:{{{adds}}}}}")
            match_pat = p_prod.get("match", "")
            xpui_content, count = re.subn(match_pat, repl, xpui_content, count=1)
            if count > 0:
                ok("Patched product_state (Premium override & ad-block)")
            else:
                warn("Pattern not found: VariousJs.product_state")

        # VariousJs UI ad and upgrade elements
        for vkey in ("banner_home", "upgradeButton", "upgradeMenu", "mock", "sentry", "disablelog", "filtertags_locale_fix", "hidemerchsidebar"):
            if vkey in var_js:
                xpui_content = apply_patch(xpui_content, var_js[vkey], f"VariousJs.{vkey}")

        # free patches (emptyblock adsEnabled=false, and legacy fallbacks)
        for fkey in free:
            xpui_content = apply_patch(xpui_content, free[fkey], f"free.{fkey}")

    # Lyrics patches
    if lyrics_block:
        if "lyrics-block" in var_js:
            xpui_content = apply_patch(xpui_content, var_js["lyrics-block"], "VariousJs.lyrics-block")
    else:
        if "lyrics-old-on" in var_js:
            xpui_content = apply_patch(xpui_content, var_js["lyrics-old-on"], "VariousJs.lyrics-old-on")

    # Developer tools
    if devtools and "dev-tools" in var_js:
        xpui_content = apply_patch(xpui_content, var_js["dev-tools"], "VariousJs.dev-tools")

    # ForcedExp (Remote configuration with comprehensive enable/disable list)
    forced_exp_patch = others.get("ForcedExp")
    if forced_exp_patch and version_in_range(spotify_ver, forced_exp_patch.get("version", {}).get("fr"), forced_exp_patch.get("version", {}).get("to")):
        enable_exp = others.get("EnableExp", {})
        disable_exp = others.get("DisableExp", {})
        custom_exp = others.get("CustomExp", {})

        en_list = [v["name"] for k, v in enable_exp.items() if isinstance(v, dict) and version_in_range(spotify_ver, v.get("version", {}).get("fr"), v.get("version", {}).get("to")) and "name" in v]
        dis_list = [v["name"] for k, v in disable_exp.items() if isinstance(v, dict) and version_in_range(spotify_ver, v.get("version", {}).get("fr"), v.get("version", {}).get("to")) and "name" in v]
        cust_list = [f"{{name:'{v['name']}',value:'{v['value']}'}}" for k, v in custom_exp.items() if isinstance(v, dict) and version_in_range(spotify_ver, v.get("version", {}).get("fr"), v.get("version", {}).get("to")) and "name" in v and "value" in v]

        if podcasts_off:
            if "HomePin" in en_list: en_list.remove("HomePin")
            if "HomePin" not in dis_list: dis_list.append("HomePin")
        if lyrics_block:
            if "Lyrics" in en_list: en_list.remove("Lyrics")
            if "Lyrics" not in dis_list: dis_list.append("Lyrics")

        en_str = "['" + "','".join(en_list) + "']"
        dis_str = "['" + "','".join(dis_list) + "']"
        cust_str = "[" + ",".join(cust_list) + "]"

        f_match = forced_exp_patch.get("match", "")
        f_repl = forced_exp_patch.get("replace", "")
        f_repl = f_repl.replace("enable:[]", f"enable:{en_str}").replace("disable:[]", f"disable:{dis_str}").replace("custom:[]", f"custom:{cust_str}")

        xpui_content, f_count = re.subn(f_match, f_repl, xpui_content, count=1)
        if f_count > 0:
            ok(f"Patched ForcedExp (enabled={len(en_list)}, disabled={len(dis_list)}, custom={len(cust_list)})")
        else:
            warn("Pattern not found: ForcedExp")

    # Sentry error reporting in xpui.js
    sentry_patch = others.get("disablesentry")
    if sentry_patch:
        xpui_content = apply_patch(xpui_content, sentry_patch, "disablesentry")

    # SpotX signature watermark
    spotx_watermark = others.get("byspotx", {}).get("add", "// Patched by SpotX")
    if spotx_watermark not in xpui_content:
        xpui_content += f"\n{spotx_watermark}\n"

    write_file(xpui_js_path, xpui_content)
    # Sync to xpui-snapshot.js as well
    if os.path.isfile(xpui_snapshot_js_path):
        write_file(xpui_snapshot_js_path, xpui_content)
else:
    warn("xpui.js not found – ad patches skipped")

# ---------------------------------------------------------------------------
# 4. Other JS chunks
# ---------------------------------------------------------------------------
info("Applying patches to secondary JS chunks …")

# Mini player
pip_file = os.path.join(xpui_dir, "xpui-pip-mini-player.js")
if os.path.isfile(pip_file) and "pipMiniPlayerRestore" in others:
    content = read_file(pip_file)
    new_c = apply_patch(content, others["pipMiniPlayerRestore"], "pipMiniPlayerRestore")
    if new_c != content: write_file(pip_file, new_c)

# Modals
modals_file = os.path.join(xpui_dir, "xpui-desktop-modals.js")
if os.path.isfile(modals_file) and "discriptions" in others:
    content = read_file(modals_file)
    new_c = apply_patch(content, others["discriptions"], "discriptions")
    if new_c != content: write_file(modals_file, new_c)

# Playlist
playlist_file = os.path.join(xpui_dir, "xpui-routes-playlist.js")
if os.path.isfile(playlist_file) and "collaboration" in others:
    content = read_file(playlist_file)
    new_c = apply_patch(content, others["collaboration"], "collaboration")
    if new_c != content: write_file(playlist_file, new_c)

# Settings devtools
settings_file = os.path.join(xpui_dir, "xpui-routes-desktop-settings.js")
if devtools and os.path.isfile(settings_file) and "dev-tools" in var_js:
    content = read_file(settings_file)
    new_c = apply_patch(content, var_js["dev-tools"], "devtools (settings)")
    if new_c != content: write_file(settings_file, new_c)

# ---------------------------------------------------------------------------
# 5. CSS patches (xpui.css and xpui-snapshot.css)
# ---------------------------------------------------------------------------
info("Applying CSS patches …")
css_add = ""
if not premium:
    for key in ("downloadquality", "downloadicon", "submenudownload"):
        p = others.get(key)
        if p and isinstance(p, dict):
            css_add += p.get("add", "")

if podcasts_off or adsections_off:
    p = others.get("block_subfeeds")
    if p and isinstance(p, dict):
        css_add += p.get("add", "")

p = others.get("fix-scrollbar")
if p and isinstance(p, dict):
    css_add += p.get("add", "")

css_targets = [f for f in (xpui_css_path, xpui_snapshot_css_path) if os.path.isfile(f)]
for cf in css_targets:
    content = read_file(cf)
    if css_add and "/* SpotX macOS patches */" not in content:
        content += f"\n/* SpotX macOS patches */\n{css_add}\n"
    if not new_theme and "fix-old-theme" in others:
        content = apply_patch(content, others["fix-old-theme"], "fix-old-theme")
    write_file(cf, content)
if css_targets:
    ok("CSS patches applied")

# ---------------------------------------------------------------------------
# 6. Helper injection into index.html
# ---------------------------------------------------------------------------
info("Injecting SpotX helpers into index.html …")
helper_dir = os.path.join(xpui_dir, "spotx-helper")
os.makedirs(helper_dir, exist_ok=True)

if os.path.isfile(index_html_path):
    index_content = read_file(index_html_path)

    # 6a. checkVersion.js
    if cv_file and os.path.isfile(cv_file):
        shutil.copyfile(cv_file, os.path.join(helper_dir, "checkVersion.js"))
        cv_tag = '<script defer="defer" src="/spotx-helper/checkVersion.js"></script>'
        if cv_tag not in index_content:
            s_idx = index_content.find("<script")
            if s_idx != -1:
                index_content = index_content[:s_idx] + cv_tag + index_content[s_idx:]
                ok("Injected checkVersion.js")

    # 6b. sectionBlock.js
    if sb_file and os.path.isfile(sb_file) and (podcasts_off or adsections_off):
        calltype = "'all'" if (podcasts_off and adsections_off) else ("'podcast'" if podcasts_off else "'section'")
        sb_code = read_file(sb_file)
        sb_code = sb_code.replace("sectionBlock(data, '')", f"sectionBlock(data, {calltype})")
        write_file(os.path.join(helper_dir, "sectionBlock.js"), sb_code)
        sb_tag = '<script defer="defer" src="/spotx-helper/sectionBlock.js"></script>'
        if sb_tag not in index_content:
            s_idx = index_content.find("<script")
            if s_idx != -1:
                index_content = index_content[:s_idx] + sb_tag + index_content[s_idx:]
                ok(f"Injected sectionBlock.js (mode: {calltype})")

    # 6c. Lyrics CSS
    if lr_file and lc_file and os.path.isfile(lr_file) and os.path.isfile(lc_file) and lyrics_stat:
        lyrics_dir = os.path.join(helper_dir, "lyrics-color")
        os.makedirs(lyrics_dir, exist_ok=True)
        shutil.copyfile(lr_file, os.path.join(lyrics_dir, "rules.css"))
        shutil.copyfile(lc_file, os.path.join(lyrics_dir, "colors.css"))
        lr_tag = '<link href="/spotx-helper/lyrics-color/rules.css" rel="stylesheet">'
        if lr_tag not in index_content:
            h_idx = index_content.lower().find("</head>")
            if h_idx != -1:
                index_content = index_content[:h_idx] + lr_tag + index_content[h_idx:]
                ok("Injected lyrics color CSS")

    write_file(index_html_path, index_content)

# ---------------------------------------------------------------------------
# 7. HTML minification
# ---------------------------------------------------------------------------
def minify_html(content):
    content = re.sub(r'<!--.*?-->', '', content, flags=re.DOTALL)
    content = re.sub(r'>\s+<', '><', content)
    content = re.sub(r'\s{2,}', ' ', content)
    return content.strip()

for html_name in ("licenses.html", "ui-licenses.html", "blank.html"):
    hf = os.path.join(xpui_dir, html_name)
    if os.path.isfile(hf):
        try:
            c = read_file(hf)
            mc = minify_html(c)
            if mc != c:
                write_file(hf, mc)
        except Exception:
            pass

# ---------------------------------------------------------------------------
# 8. Mach-O Spotify binary patching
# ---------------------------------------------------------------------------
if os.path.isfile(spotify_binary):
    info("Checking Spotify Mach-O binary for ad endpoints …")
    with open(spotify_binary, "rb") as bf:
        bin_data = bf.read()
    bin_text = bin_data.decode("latin1")
    bin_modified = False

    if not premium:
        gabo_pat = r"gabo(?=.receiver-service(?:/public|[^/]))"
        new_text, gn = re.subn(gabo_pat, "dodo", bin_text)
        if gn > 0:
            bin_text = new_text
            bin_modified = True
            ok(f"Binary patched ({gn}x): gabo-receiver-service -> dodo (ad receiver blocked)")
        else:
            info("gabo ad-receiver pattern already patched or not found")

    if block_update:
        up_pat = r"(?<=desktop-update/.)2(/update)"
        new_text, un = re.subn(up_pat, "7/update", bin_text)
        if un > 0:
            bin_text = new_text
            bin_modified = True
            ok(f"Binary patched ({un}x): desktop-update blocked")

    if bin_modified:
        with open(spotify_binary, "wb") as bf:
            bf.write(bin_text.encode("latin1"))
        os.chmod(spotify_binary, 0o755)
        ok("Spotify binary patched successfully")

print("")
print(f"{GREEN}All patches applied successfully.{RESET}")
PYEOF

# ---------------------------------------------------------------------------
# Run patch engine
# ---------------------------------------------------------------------------
info "Running patch engine …"
echo ""

python3 "$PATCHER_SCRIPT" \
    "$PATCHES_FILE" \
    "$XPUI_DIR" \
    "$SPOTIFY_APP" \
    "$SPOTIFY_BINARY" \
    "$SPOTIFY_VERSION" \
    "$OPT_PREMIUM" \
    "$OPT_PODCASTS_OFF" \
    "$OPT_ADSECTIONS_OFF" \
    "${OPT_LYRICS_STAT:-}" \
    "$OPT_DEVTOOLS" \
    "$OPT_LYRICS_BLOCK" \
    "$OPT_EXP_SPOTIFY" \
    "$OPT_NEW_THEME" \
    "$OPT_BLOCK_UPDATE" \
    "${OPT_CACHE_LIMIT:-}" \
    "${CV_FILE:-}" \
    "${SB_FILE:-}" \
    "${LR_FILE:-}" \
    "${LC_FILE:-}" \
    || die "Patch engine failed"

# ---------------------------------------------------------------------------
# Re-pack xpui.spa
# ---------------------------------------------------------------------------
echo ""
info "Repacking xpui.spa …"
rm -f "$XPUI_SPA"
(cd "$XPUI_DIR" && zip -q -r "$XPUI_SPA" .) || die "Failed to repack xpui.spa"
ok "Repacked xpui.spa → $XPUI_SPA"

# ---------------------------------------------------------------------------
# Clear Spotify caches (critical for removing cached ads and ad device tokens)
# ---------------------------------------------------------------------------
clear_spotify_caches

# ---------------------------------------------------------------------------
# Block auto-updates (prefs level)
# ---------------------------------------------------------------------------
if $OPT_BLOCK_UPDATE; then
    info "Blocking Spotify auto-updates in prefs …"
    mkdir -p "$PREFS_DIR"
    PREFS_PATH="$PREFS_DIR/prefs"
    touch "$PREFS_PATH"
    if ! grep -q 'app.last-launched-version' "$PREFS_PATH" 2>/dev/null; then
        echo "app.last-launched-version=\"$SPOTIFY_VERSION\"" >> "$PREFS_PATH"
    fi
    AU_DIR="$SPOTIFY_APP/Contents/Frameworks/Sparkle.framework"
    if [[ -d "$AU_DIR" ]]; then
        warn "Sparkle updater framework found. For full update block, remove it manually:"
        warn "  sudo rm -rf \"$AU_DIR\""
    fi
    ok "Auto-update block applied (prefs level)"
fi

# ---------------------------------------------------------------------------
# Desktop alias
# ---------------------------------------------------------------------------
if ! $OPT_NO_SHORTCUT; then
    DESKTOP="$HOME/Desktop"
    ALIAS_PATH="$DESKTOP/Spotify.app"
    if [[ -d "$DESKTOP" ]] && [[ ! -e "$ALIAS_PATH" ]]; then
        ln -s "$SPOTIFY_APP" "$ALIAS_PATH" 2>/dev/null && ok "Desktop symlink created: $ALIAS_PATH" || true
    fi
fi

# ---------------------------------------------------------------------------
# Remove Gatekeeper quarantine flag
# ---------------------------------------------------------------------------
info "Removing Gatekeeper quarantine flag …"
xattr -rd com.apple.quarantine "$SPOTIFY_APP" 2>/dev/null || true
ok "Quarantine flag cleared"

# ---------------------------------------------------------------------------
# Ad-hoc re-sign (required after modifying bundle contents on macOS)
# ---------------------------------------------------------------------------
info "Re-signing Spotify.app (ad-hoc) …"
if command -v codesign &>/dev/null; then
    codesign --force --deep --sign - "$SPOTIFY_APP" 2>/dev/null \
        && ok "Ad-hoc code signing completed" \
        || warn "Ad-hoc signing failed"
    codesign -v "$SPOTIFY_APP" 2>/dev/null \
        && ok "Code signature verified" \
        || warn "Code signature verification reported issues"
else
    warn "codesign not found – skipping re-sign"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary banner
# ---------------------------------------------------------------------------
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗"
echo -e "║          SpotX macOS – Patch Complete! ✓             ║"
echo -e "╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${GREEN}✔${RESET}  xpui.spa patched and repacked (V8 snapshot unpacked)"
echo -e "  ${GREEN}✔${RESET}  Backup: $(basename "$BACKUP_SPA")"
if $OPT_PREMIUM; then
    echo -e "  ${YELLOW}–${RESET}  Ad-blocking: disabled (Premium mode)"
else
    echo -e "  ${GREEN}✔${RESET}  Ad-blocking: enabled (audio, banner, and UI ads blocked)"
    echo -e "  ${GREEN}✔${RESET}  Binary ad-receiver: patched (gabo -> dodo)"
fi
$OPT_PODCASTS_OFF    && echo -e "  ${GREEN}✔${RESET}  Podcasts / audiobooks hidden"
$OPT_ADSECTIONS_OFF  && echo -e "  ${GREEN}✔${RESET}  Ad-like home sections hidden"
$OPT_BLOCK_UPDATE    && echo -e "  ${GREEN}✔${RESET}  Auto-update blocked"
[[ -n "$OPT_LYRICS_STAT" ]] && echo -e "  ${GREEN}✔${RESET}  Lyrics colour: $OPT_LYRICS_STAT"
$OPT_DEVTOOLS        && echo -e "  ${GREEN}✔${RESET}  Developer tools enabled"
echo ""
echo -e "  ${CYAN}To restore original Spotify:${RESET}"
echo -e "    bash run.sh --restore"
echo ""

# ---------------------------------------------------------------------------
# Start Spotify
# ---------------------------------------------------------------------------
if $OPT_START_SPOTIFY; then
    info "Launching Spotify …"
    open -a "$SPOTIFY_APP"
fi

# ---------------------------------------------------------------------------
# Pause
# ---------------------------------------------------------------------------
if ! $OPT_NO_PAUSE; then
    echo -e "  Press ${BOLD}Enter${RESET} to exit …"
    read -r
fi
