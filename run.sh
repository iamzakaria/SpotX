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
#
#  Requirements:
#    - macOS 11+ (Big Sur or later), Apple Silicon or Intel
#    - Spotify desktop app installed (not from Mac App Store)
#    - curl, unzip, zip, python3  (pre-installed on modern macOS)
#
#  Disclaimer:
#    SpotX is provided for evaluation/educational purposes only.
#    Use at your own risk.
# =============================================================================

set -euo pipefail

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
OPT_SPOTIFY_PATH=""
OPT_CUSTOM_PATCHES=""
OPT_VERSION=""
OPT_LYRICS_STAT=""

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
        --spotify-path)       OPT_SPOTIFY_PATH="$2"; shift ;;
        --custom-patches)     OPT_CUSTOM_PATCHES="$2"; shift ;;
        --version)            OPT_VERSION="$2"; shift ;;
        --lyrics-stat)        OPT_LYRICS_STAT="$2"; shift ;;
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
# codesign is optional; remove from missing if not critical
MISSING_DEPS=($(printf '%s\n' "${MISSING_DEPS[@]}" | grep -v codesign || true))

if [[ ${#MISSING_DEPS[@]} -gt 0 ]]; then
    die "Missing required tools: ${MISSING_DEPS[*]}"$'\n'"Install via Homebrew: brew install ${MISSING_DEPS[*]}"
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
PREFS_DIR="$HOME/Library/Application Support/Spotify"

[[ -f "$XPUI_SPA" ]] || die "xpui.spa not found at: $XPUI_SPA"$'\n'"Your Spotify installation may be corrupt. Try reinstalling Spotify."

# Read version from Info.plist
SPOTIFY_VERSION=$(defaults read "$SPOTIFY_APP/Contents/Info.plist" CFBundleShortVersionString 2>/dev/null || echo "unknown")
info "Spotify version  : ${BOLD}$SPOTIFY_VERSION${RESET}"
info "Spotify path     : $SPOTIFY_APP"
info "xpui.spa path    : $XPUI_SPA"
echo ""

# ---------------------------------------------------------------------------
# Check if already patched (backup exists)
# ---------------------------------------------------------------------------
BACKUP_SPA="${XPUI_SPA}.bak"

if [[ -f "$BACKUP_SPA" ]]; then
    warn "A backup file already exists: $BACKUP_SPA"
    warn "This suggests SpotX has been applied before."
    echo -e "  ${BOLD}Options:${RESET}"
    echo -e "    ${GREEN}y${RESET} – Re-apply the patch (restore from backup first)"
    echo -e "    ${YELLOW}n${RESET} – Skip (exit without changes)"
    if [[ "${OPT_NO_PAUSE:-false}" == "false" ]]; then
        read -r -p "  Proceed? [y/n]: " REPATCH_CHOICE
        echo ""
        case "$REPATCH_CHOICE" in
            [Yy]) info "Restoring from backup before re-patching …"
                  cp "$BACKUP_SPA" "$XPUI_SPA"
                  ok "Backup restored." ;;
            *)    info "Skipped – no changes made."; exit 0 ;;
        esac
    else
        info "Auto-mode: restoring from backup and re-patching …"
        cp "$BACKUP_SPA" "$XPUI_SPA"
    fi
fi

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
# Remote base URLs
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

# ---------------------------------------------------------------------------
# Temp directory (cleaned up on exit)
# ---------------------------------------------------------------------------
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# ---------------------------------------------------------------------------
# Download helpers
# ---------------------------------------------------------------------------
spotx_download() {
    local url="$1" out="$2"
    if ! curl --silent --fail --location --max-time 30 --retry 3 --retry-delay 2 \
         --user-agent "SpotX-macOS/1.0" -o "$out" "$url"; then
        return 1
    fi
    [[ -s "$out" ]] || return 1
    return 0
}

# ---------------------------------------------------------------------------
# Load patches.json
# ---------------------------------------------------------------------------
info "Loading patches …"

if [[ -n "$OPT_CUSTOM_PATCHES" ]]; then
    [[ -f "$OPT_CUSTOM_PATCHES" ]] || die "Custom patches file not found: $OPT_CUSTOM_PATCHES"
    PATCHES_FILE="$OPT_CUSTOM_PATCHES"
    info "Using local patches.json: $PATCHES_FILE"
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

# ---------------------------------------------------------------------------
# Download optional JS/CSS helpers
# ---------------------------------------------------------------------------
info "Downloading helper files …"

CV_FILE="$TEMP_DIR/checkVersion.js"
SB_FILE="$TEMP_DIR/sectionBlock.js"
LR_FILE="$TEMP_DIR/lyricsRules.css"
LC_FILE="$TEMP_DIR/lyricsColors.css"

spotx_download "$CHECK_VERSION_URL" "$CV_FILE" && ok "checkVersion.js" || { warn "checkVersion.js unavailable – skipping"; CV_FILE=""; }

NEED_SECTION=false
$OPT_PODCASTS_OFF  && NEED_SECTION=true
$OPT_ADSECTIONS_OFF && NEED_SECTION=true

if $NEED_SECTION; then
    spotx_download "$SECTION_BLOCK_URL" "$SB_FILE" && ok "sectionBlock.js" || { warn "sectionBlock.js unavailable – skipping"; SB_FILE=""; }
else
    SB_FILE=""
fi

HAS_LYRICS_CSS=false
if [[ -n "$OPT_LYRICS_STAT" ]]; then
    if spotx_download "$LYRICS_RULES_URL" "$LR_FILE" && spotx_download "$LYRICS_COLORS_URL" "$LC_FILE"; then
        ok "Lyrics CSS files"
        HAS_LYRICS_CSS=true
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
# Back up xpui.spa
# ---------------------------------------------------------------------------
info "Backing up xpui.spa …"
cp "$XPUI_SPA" "$BACKUP_SPA"
ok "Backup saved to: $BACKUP_SPA"

# ---------------------------------------------------------------------------
# Extract xpui.spa
# ---------------------------------------------------------------------------
XPUI_DIR="$TEMP_DIR/xpui"
mkdir -p "$XPUI_DIR"
info "Extracting xpui.spa …"
unzip -q "$XPUI_SPA" -d "$XPUI_DIR" || die "Failed to extract xpui.spa"
ok "Extracted xpui.spa"

# ---------------------------------------------------------------------------
# Write Python patch engine to temp file and run it
# ---------------------------------------------------------------------------
PATCHER_SCRIPT="$TEMP_DIR/patcher.py"

cat > "$PATCHER_SCRIPT" << 'PYEOF'
#!/usr/bin/env python3
"""
SpotX macOS – Patch Engine
Applies regex-based patches from patches.json to the extracted xpui contents.
"""
import json, re, sys, os, glob, shutil

patches_file   = sys.argv[1]
xpui_dir       = sys.argv[2]
premium        = sys.argv[3] == "true"
podcasts_off   = sys.argv[4] == "true"
adsections_off = sys.argv[5] == "true"
lyrics_stat    = sys.argv[6]
devtools       = sys.argv[7] == "true"
cv_file        = sys.argv[8]   # or empty string
sb_file        = sys.argv[9]   # or empty string
lr_file        = sys.argv[10]  # or empty string
lc_file        = sys.argv[11]  # or empty string

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

def apply_patch(content, patch_obj, label=""):
    if isinstance(patch_obj, list):
        for p in patch_obj:
            content = apply_patch(content, p, label)
        return content
    if not isinstance(patch_obj, dict):
        return content
    find    = patch_obj.get("find",    "")
    replace = patch_obj.get("replace", patch_obj.get("add", ""))
    if not find:
        return content
    try:
        new_content, n = re.subn(find, replace, content, flags=re.DOTALL)
        if n > 0:
            ok(f"Patched ({n}x): {label or find[:55]!r}")
        else:
            warn(f"Pattern not found: {label or find[:55]!r}")
        return new_content
    except re.error as exc:
        warn(f"Regex error in {label!r}: {exc}")
        return content

def find_xpui_file(pattern):
    matches = glob.glob(os.path.join(xpui_dir, "**", pattern), recursive=True)
    if not matches:
        matches = glob.glob(os.path.join(xpui_dir, pattern))
    return matches

def append_to_file(fpath, text):
    if not os.path.isfile(fpath):
        return
    with open(fpath, "a", encoding="utf-8") as f:
        f.write(text)

def inject_into_index(filename, kind="js"):
    index_path = os.path.join(xpui_dir, "index.html")
    if not os.path.isfile(index_path):
        warn("index.html not found in xpui")
        return
    content = read_file(index_path)
    resource_path = f"/xpui-spotx/{filename}"
    if resource_path in content:
        return
    if kind == "js":
        tag = f'<script defer="defer" src="{resource_path}"></script>'
        insert_re = r'(<script\b)'
        if re.search(insert_re, content):
            content = re.sub(insert_re, tag + r'\1', content, count=1)
            write_file(index_path, content)
            ok(f"Injected JS: {filename}")
    elif kind == "css":
        tag = f'<link href="{resource_path}" rel="stylesheet">'
        insert_re = r'(</head>)'
        if re.search(insert_re, content, re.IGNORECASE):
            content = re.sub(insert_re, tag + r'\1', content, count=1, flags=re.IGNORECASE)
            write_file(index_path, content)
            ok(f"Injected CSS: {filename}")

# -----------------------------------------------------------------------
# Load patches.json
# -----------------------------------------------------------------------
with open(patches_file, "r", encoding="utf-8") as f:
    patches = json.load(f)

others = patches.get("others", {})
free   = patches.get("free", {})

# -----------------------------------------------------------------------
# 1) Ad-blocking patches (xpui.js / free patches)
# -----------------------------------------------------------------------
if not premium:
    info("Applying ad-block patches (free) ...")
    xpui_js_files = find_xpui_file("xpui.js")
    if not xpui_js_files:
        warn("xpui.js not found – ad patches skipped")
    else:
        for xpui_js in xpui_js_files:
            content = read_file(xpui_js)
            for key in free:
                new_content = apply_patch(content, free[key], f"free.{key}")
                if new_content != content:
                    content = new_content
            write_file(xpui_js, content)

# -----------------------------------------------------------------------
# 2) Disable Sentry error reporting
# -----------------------------------------------------------------------
info("Disabling Sentry ...")
sentry_patch = others.get("disablesentry")
if sentry_patch:
    sentry_targets = find_xpui_file("xpui.js") or find_xpui_file("vendor~xpui.js")
    for fpath in sentry_targets:
        content = read_file(fpath)
        new_content = apply_patch(content, sentry_patch, "disablesentry")
        if new_content != content:
            write_file(fpath, new_content)

# -----------------------------------------------------------------------
# 3) Forced experimental features (xpui.js)
# -----------------------------------------------------------------------
info("Applying experimental feature overrides ...")
forced_exp_patch = others.get("ForcedExp")
if forced_exp_patch:
    for fpath in find_xpui_file("xpui.js"):
        content = read_file(fpath)
        new_content = apply_patch(content, forced_exp_patch, "ForcedExp")
        if new_content != content:
            write_file(fpath, new_content)

# -----------------------------------------------------------------------
# 4) CSS patches (xpui.css)
# -----------------------------------------------------------------------
info("Applying CSS patches ...")
xpui_css_files = find_xpui_file("xpui.css")
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

if css_add and xpui_css_files:
    for fpath in xpui_css_files:
        append_to_file(fpath, f"\n/* SpotX macOS patches */\n{css_add}")
    ok("CSS patches appended")

# Fix old-theme CSS
p = others.get("fix-old-theme")
if p and xpui_css_files:
    for fpath in xpui_css_files:
        content = read_file(fpath)
        new_content = apply_patch(content, p, "fix-old-theme")
        if new_content != content:
            write_file(fpath, new_content)

# -----------------------------------------------------------------------
# 5) Hide collaborators icon (xpui-routes-playlist.js)
# -----------------------------------------------------------------------
info("Hiding collaborator icon ...")
p = others.get("hide_col_icon") or others.get("Collaborators")
if p:
    for fpath in find_xpui_file("xpui-routes-playlist.js"):
        content = read_file(fpath)
        new_content = apply_patch(content, p, "Collaborators")
        if new_content != content:
            write_file(fpath, new_content)

# -----------------------------------------------------------------------
# 6) Descriptions / modal patches (xpui-desktop-modals.js)
# -----------------------------------------------------------------------
p = others.get("discriptions")
if p:
    for fpath in find_xpui_file("xpui-desktop-modals.js"):
        content = read_file(fpath)
        new_content = apply_patch(content, p, "discriptions")
        if new_content != content:
            write_file(fpath, new_content)

# -----------------------------------------------------------------------
# 7) Developer tools (xpui-routes-desktop-settings.js)
# -----------------------------------------------------------------------
if devtools:
    info("Enabling developer tools ...")
    p = others.get("devtools")
    if p:
        for fpath in find_xpui_file("xpui-routes-desktop-settings.js"):
            content = read_file(fpath)
            new_content = apply_patch(content, p, "devtools")
            if new_content != content:
                write_file(fpath, new_content)

# -----------------------------------------------------------------------
# 8) Search / PiP fixes
# -----------------------------------------------------------------------
p = others.get("searchFixes")
if p:
    for fpath in find_xpui_file("xpui-routes-search.js"):
        content = read_file(fpath)
        new_content = apply_patch(content, p, "searchFixes")
        if new_content != content:
            write_file(fpath, new_content)

p = others.get("pipMiniPlayerRestore")
if p:
    for fpath in find_xpui_file("xpui-pip-mini-player.js"):
        content = read_file(fpath)
        new_content = apply_patch(content, p, "pipMiniPlayerRestore")
        if new_content != content:
            write_file(fpath, new_content)

# -----------------------------------------------------------------------
# 9) Inject helper scripts into index.html
# -----------------------------------------------------------------------
spotx_res_dir = os.path.join(xpui_dir, "xpui-spotx")
os.makedirs(spotx_res_dir, exist_ok=True)

if cv_file and os.path.isfile(cv_file):
    shutil.copy(cv_file, os.path.join(spotx_res_dir, "checkVersion.js"))
    inject_into_index("checkVersion.js", "js")

if sb_file and os.path.isfile(sb_file) and (podcasts_off or adsections_off):
    shutil.copy(sb_file, os.path.join(spotx_res_dir, "sectionBlock.js"))
    inject_into_index("sectionBlock.js", "js")

if lr_file and lc_file and os.path.isfile(lr_file) and os.path.isfile(lc_file) and lyrics_stat:
    shutil.copy(lr_file, os.path.join(spotx_res_dir, "lyricsRules.css"))
    shutil.copy(lc_file, os.path.join(spotx_res_dir, "lyricsColors.css"))
    inject_into_index("lyricsRules.css", "css")
    inject_into_index("lyricsColors.css", "css")

# -----------------------------------------------------------------------
# 10) HTML minification
# -----------------------------------------------------------------------
info("Minifying HTML files ...")

def minify_html(content):
    content = re.sub(r'<!--.*?-->', '', content, flags=re.DOTALL)
    content = re.sub(r'>\s+<', '><', content)
    content = re.sub(r'\s{2,}', ' ', content)
    return content.strip()

for html_name in ("licenses.html", "ui-licenses.html", "blank.html"):
    for fpath in find_xpui_file(html_name):
        try:
            content = read_file(fpath)
            minified = minify_html(content)
            if minified != content:
                write_file(fpath, minified)
                ok(f"Minified {html_name}")
        except Exception as exc:
            warn(f"Could not minify {html_name}: {exc}")

print("")
print(f"{GREEN}All patches applied successfully.{RESET}")
PYEOF

# ---------------------------------------------------------------------------
# Run the patch engine
# ---------------------------------------------------------------------------
echo ""
info "Running patch engine …"
echo ""

python3 "$PATCHER_SCRIPT" \
    "$PATCHES_FILE" \
    "$XPUI_DIR" \
    "$OPT_PREMIUM" \
    "$OPT_PODCASTS_OFF" \
    "$OPT_ADSECTIONS_OFF" \
    "$OPT_LYRICS_STAT" \
    "$OPT_DEVTOOLS" \
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
# Block auto-updates (optional – prefs level)
# ---------------------------------------------------------------------------
if $OPT_BLOCK_UPDATE; then
    info "Blocking Spotify auto-updates …"
    mkdir -p "$PREFS_DIR"
    PREFS_PATH="$PREFS_DIR/prefs"
    touch "$PREFS_PATH"
    if ! grep -q 'app.last-launched-version' "$PREFS_PATH" 2>/dev/null; then
        echo "app.last-launched-version=\"$SPOTIFY_VERSION\"" >> "$PREFS_PATH"
    fi
    # Warn about Sparkle (the macOS auto-updater framework)
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
        || warn "Ad-hoc signing failed (Spotify may still run; ignore if no issues)"
else
    warn "codesign not found – skipping re-sign (Spotify may refuse to launch on Apple Silicon)"
fi

echo ""

# ---------------------------------------------------------------------------
# Summary banner
# ---------------------------------------------------------------------------
echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════╗"
echo -e "║          SpotX macOS – Patch Complete! ✓             ║"
echo -e "╚══════════════════════════════════════════════════════╝${RESET}"
echo ""
echo -e "  ${GREEN}✔${RESET}  xpui.spa patched and repacked"
echo -e "  ${GREEN}✔${RESET}  Backup: $(basename "$BACKUP_SPA")"
if $OPT_PREMIUM; then
    echo -e "  ${YELLOW}–${RESET}  Ad-blocking: disabled (Premium mode)"
else
    echo -e "  ${GREEN}✔${RESET}  Ad-blocking: enabled"
fi
$OPT_PODCASTS_OFF    && echo -e "  ${GREEN}✔${RESET}  Podcasts / audiobooks hidden"
$OPT_ADSECTIONS_OFF  && echo -e "  ${GREEN}✔${RESET}  Ad-like home sections hidden"
$OPT_BLOCK_UPDATE    && echo -e "  ${GREEN}✔${RESET}  Auto-update blocked (prefs level)"
[[ -n "$OPT_LYRICS_STAT" ]] && echo -e "  ${GREEN}✔${RESET}  Lyrics colour: $OPT_LYRICS_STAT"
$OPT_DEVTOOLS        && echo -e "  ${GREEN}✔${RESET}  Developer tools enabled"
echo ""
echo -e "  ${CYAN}To restore:${RESET}"
echo -e "    cp \"$BACKUP_SPA\" \"$XPUI_SPA\""
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
