#!/usr/bin/env bash
# delete_app.sh — Remove a cFS app and all its build system references
# Usage: ./delete_app.sh <app_name> [--force]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR/apps"
REGISTRY="$APPS_DIR/.app_registry.json"
SAMPLE_DEFS="$SCRIPT_DIR/sample_defs"

# ── Args ──────────────────────────────────────────────────────────────────────
APP_NAME="${1:-}"
FORCE=false
for arg in "${@:2}"; do
    [[ "$arg" == "--force" ]] && FORCE=true
done

# ── STEP 1 — Validate inputs ──────────────────────────────────────────────────
if [[ -z "$APP_NAME" ]]; then
    echo "Usage: $0 <app_name> [--force]"
    echo "  Example: $0 nav_app"
    echo "  Example: $0 nav_app --force"
    exit 1
fi

PROTECTED=(sample_app ci_lab to_lab sch_lab cf cs ds fm hk hs lc md mm sc sbn sbn_f_remap sbn_udp)
for p in "${PROTECTED[@]}"; do
    if [[ "$APP_NAME" == "$p" ]]; then
        echo "Error: '$APP_NAME' is a protected cFS app and cannot be deleted"
        exit 1
    fi
done

APP_LOWER="$APP_NAME"
APP_UPPER=$(echo "$APP_LOWER" | tr '[:lower:]' '[:upper:]')

if [[ ! -d "$APPS_DIR/$APP_LOWER" ]]; then
    echo "Error: apps/$APP_LOWER/ does not exist"
    exit 1
fi

# Check registry
IN_REGISTRY=false
if [[ -f "$REGISTRY" ]] && grep -qF "\"$APP_LOWER\"" "$REGISTRY" 2>/dev/null; then
    IN_REGISTRY=true
fi

if ! $IN_REGISTRY; then
    if $FORCE; then
        echo "Warning: '$APP_LOWER' not found in .app_registry.json — proceeding anyway (--force)"
    else
        echo "Warning: '$APP_LOWER' not found in .app_registry.json"
    fi
fi

# Read topic IDs from registry for the retired-IDs summary line
CMD_TOPIC="?"
TLM_TOPIC="?"
if $IN_REGISTRY && [[ -f "$REGISTRY" ]]; then
    TOPICS=$(python3 - "$REGISTRY" "$APP_LOWER" <<'PYEOF'
import sys, json
with open(sys.argv[1]) as f:
    reg = json.load(f)
app = next((a for a in reg.get('apps', []) if a['name'] == sys.argv[2]), None)
print(app.get('cmd_topic', '?'), app.get('tlm_topic', '?')) if app else print('? ?')
PYEOF
)
    CMD_TOPIC=$(echo "$TOPICS" | awk '{print $1}')
    TLM_TOPIC=$(echo "$TOPICS" | awk '{print $2}')
fi

# ── STEP 2 — Confirmation prompt ──────────────────────────────────────────────
if ! $FORCE; then
    echo ""
    echo "The following will be permanently removed:"
    echo "  - apps/${APP_LOWER}/ (entire directory)"
    echo "  - Entry in apps/.app_registry.json"
    echo "  - Reference in sample_defs/cpu1/install_custom.cmake"
    echo "  - Reference in sample_defs/cpu2/install_custom.cmake"
    echo "  - Reference in sample_defs/generate_startup.cmake"
    echo "  - Reference in sample_defs/tables/sch_lab_table.c"
    echo "  - Reference in sample_defs/tables/to_lab_sub.c"
    echo "  - Entry in sample_defs/targets.cmake (cpu1_APPLIST and cpu2_APPLIST)"
    echo ""
    printf "Are you sure? (yes/no): "
    read ANSWER || true
    if [[ "${ANSWER:-}" != "yes" ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ── STEP 3 — Remove app directory ─────────────────────────────────────────────
rm -rf "$APPS_DIR/$APP_LOWER"
echo "✓ Removed: apps/$APP_LOWER/"

# ── STEP 4 — Remove from sample_defs files ────────────────────────────────────

# cpu1/install_custom.cmake — remove $<TARGET_PROPERTY:<app>,INCLUDE_DIRECTORIES> line
CPU1_CMAKE="$SAMPLE_DEFS/cpu1/install_custom.cmake"
if [[ -f "$CPU1_CMAKE" ]]; then
    sed -i "/TARGET_PROPERTY:${APP_LOWER},INCLUDE_DIRECTORIES/d" "$CPU1_CMAKE"
fi

# cpu2/install_custom.cmake — same
CPU2_CMAKE="$SAMPLE_DEFS/cpu2/install_custom.cmake"
if [[ -f "$CPU2_CMAKE" ]]; then
    sed -i "/TARGET_PROPERTY:${APP_LOWER},INCLUDE_DIRECTORIES/d" "$CPU2_CMAKE"
fi

# generate_startup.cmake — remove the "CFE_APP, <app>, ..." line
GEN_CMAKE="$SAMPLE_DEFS/generate_startup.cmake"
if [[ -f "$GEN_CMAKE" ]]; then
    sed -i "/\"CFE_APP, ${APP_LOWER},/d" "$GEN_CMAKE"
fi

# sch_lab_table.c — remove #include and {CFE_SB_MSGID_WRAP_VALUE(<APP>_SEND_HK_MID),...}
SCH_TABLE="$SAMPLE_DEFS/tables/sch_lab_table.c"
if [[ -f "$SCH_TABLE" ]]; then
    sed -i "/#include \"${APP_LOWER}_msgids/d" "$SCH_TABLE"
    sed -i "/CFE_SB_MSGID_WRAP_VALUE(${APP_UPPER}_SEND_HK_MID)/d" "$SCH_TABLE"
fi

# to_lab_sub.c — remove #include and {CFE_SB_MSGID_WRAP_VALUE(<APP>_HK_TLM_MID),...}
TO_SUB="$SAMPLE_DEFS/tables/to_lab_sub.c"
if [[ -f "$TO_SUB" ]]; then
    sed -i "/#include \"${APP_LOWER}_msgids/d" "$TO_SUB"
    sed -i "/CFE_SB_MSGID_WRAP_VALUE(${APP_UPPER}_HK_TLM_MID)/d" "$TO_SUB"
fi

# targets.cmake — remove app from SET(cpuX_APPLIST ...) lines
TARGETS_CMAKE="$SAMPLE_DEFS/targets.cmake"
if [[ -f "$TARGETS_CMAKE" ]]; then
    python3 - "$TARGETS_CMAKE" "$APP_LOWER" <<'PYEOF'
import sys, re

cmake_file = sys.argv[1]
app_lower  = sys.argv[2]

with open(cmake_file) as f:
    lines = f.readlines()

result = []
for line in lines:
    if re.match(r'\s*SET\(\w+_APPLIST\b', line):
        # Remove the app name as a whole word (with any trailing whitespace)
        line = re.sub(r'\b' + re.escape(app_lower) + r'\b\s*', '', line)
        # Collapse any double-spaces left behind
        line = re.sub(r'  +', ' ', line)
        # Fix trailing space before closing paren if app was last in list
        line = re.sub(r' \)', ')', line)
    result.append(line)

with open(cmake_file, 'w') as f:
    f.writelines(result)

print('[ok] Removed {} from targets.cmake APPLISTs'.format(app_lower))
PYEOF
fi

# ── STEP 5 — Update registry ──────────────────────────────────────────────────
if [[ -f "$REGISTRY" ]]; then
    python3 - "$REGISTRY" "$APP_LOWER" <<'PYEOF'
import sys, json

registry_file = sys.argv[1]
app_lower     = sys.argv[2]

with open(registry_file) as f:
    reg = json.load(f)

before = len(reg.get('apps', []))
reg['apps'] = [a for a in reg.get('apps', []) if a['name'] != app_lower]
after = len(reg['apps'])

with open(registry_file, 'w') as f:
    json.dump(reg, f, indent=2)
    f.write('\n')

removed = before - after
print('[ok] Registry: removed {} entr{} for {}'.format(
    removed, 'y' if removed == 1 else 'ies', app_lower))
PYEOF
fi

# ── STEP 6 — Summary ──────────────────────────────────────────────────────────
echo ""
echo "✓ Deleted: apps/${APP_LOWER}/"
echo "✓ Removed from: generate_startup.cmake, sch_lab_table.c, to_lab_sub.c,"
echo "                 targets.cmake, install_custom.cmake (cpu1+cpu2)"
echo "✓ Registry updated."
if [[ "$CMD_TOPIC" != "?" ]]; then
    echo "⚠ Topic IDs (CMD=${CMD_TOPIC} TLM=${TLM_TOPIC}) are retired and will not be reused."
fi

# ── STEP 7 — Rebuild cFS ──────────────────────────────────────────────────────
BUILD_DIR="$SCRIPT_DIR/build-native_std"
if [[ -d "$BUILD_DIR" ]]; then
    echo ""
    echo "Rebuilding cFS — removing ${APP_LOWER} from startup script..."
    rm -f "$BUILD_DIR/stamp.prep" "$BUILD_DIR/stamp.install"
    if make -C "$SCRIPT_DIR" native_std.install 2>&1; then
        echo ""
        echo "✓ Build complete. ${APP_LOWER} will no longer load on cFS start."
        echo "  Startup script: $BUILD_DIR/exe/cpu1/cf/cfe_es_startup.scr"
    else
        echo ""
        echo "ERROR: Rebuild failed. Run manually:" >&2
        echo "  cd $SCRIPT_DIR && make native_std.install" >&2
        exit 1
    fi
else
    echo "✓ Build: cd ~/Documents/TCC/cFS && make native_std.prep && make native_std.install"
fi
