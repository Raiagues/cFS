#!/usr/bin/env bash
# create_app.sh — Create a new cFS app from sample_app template
# Usage: ./create_app.sh <app_name> [hk_rate_ticks] [cmd_topic_hex] [tlm_topic_hex]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APPS_DIR="$SCRIPT_DIR/apps"
REGISTRY="$APPS_DIR/.app_registry.json"
SAMPLE_DEFS="$SCRIPT_DIR/sample_defs"

# ── Args ──────────────────────────────────────────────────────────────────────
APP_NAME="${1:-}"
HK_RATE="${2:-10}"
CMD_TOPIC_ARG="${3:-}"
TLM_TOPIC_ARG="${4:-}"

# ── Validate app_name ─────────────────────────────────────────────────────────
if [[ -z "$APP_NAME" ]]; then
    echo "Usage: $0 <app_name> [hk_rate_ticks] [cmd_topic_hex] [tlm_topic_hex]"
    echo "  Example: $0 nav_app 10 0x92 0x93"
    exit 1
fi

NAME_LEN=${#APP_NAME}
if (( NAME_LEN > 10 )); then
    echo "Error: app name '$APP_NAME' is $NAME_LEN chars, max is 10"
    exit 1
fi

if [[ ! "$APP_NAME" =~ ^[a-z][a-z0-9_]*$ ]]; then
    if [[ "$APP_NAME" =~ ^[^a-z] ]]; then
        echo "Error: app name must start with a letter"
    else
        echo "Error: app name must contain only lowercase letters, digits, underscores"
    fi
    exit 1
fi

if [[ -d "$APPS_DIR/$APP_NAME" ]]; then
    echo "Error: app '$APP_NAME' already exists at apps/$APP_NAME/"
    exit 1
fi

# ── Registry helpers ──────────────────────────────────────────────────────────
init_registry() {
    mkdir -p "$APPS_DIR"
    cat > "$REGISTRY" <<'EOF'
{
  "apps": [
    {"name": "sample_app", "cmd_topic": "0x82", "tlm_topic": "0x83"}
  ],
  "next_cmd_topic": "0x92",
  "next_tlm_topic": "0x93"
}
EOF
}

read_json_field() {
    # read_json_field <file> <field>  — naive grep-based reader, no jq dependency
    local file="$1" field="$2"
    grep "\"$field\"" "$file" | head -1 | sed 's/.*"'"$field"'": *"\([^"]*\)".*/\1/'
}

registry_topic_used() {
    # Returns the app name that uses the given topic, or empty string
    local topic="$1"
    grep "\"$topic\"" "$REGISTRY" | head -1 | \
        grep -o '"name": *"[^"]*"' | head -1 | sed 's/"name": *"\([^"]*\)"/\1/' || true
}

# ── Ensure registry exists ────────────────────────────────────────────────────
if [[ ! -f "$REGISTRY" ]]; then
    init_registry
fi

# ── Resolve topic IDs ─────────────────────────────────────────────────────────
if [[ -n "$CMD_TOPIC_ARG" ]]; then
    CMD_TOPIC="$CMD_TOPIC_ARG"
else
    CMD_TOPIC=$(read_json_field "$REGISTRY" "next_cmd_topic")
fi

if [[ -n "$TLM_TOPIC_ARG" ]]; then
    TLM_TOPIC="$TLM_TOPIC_ARG"
else
    TLM_TOPIC=$(read_json_field "$REGISTRY" "next_tlm_topic")
fi

# Normalize to lowercase hex with 0x prefix
CMD_TOPIC=$(printf "0x%02x" "$((CMD_TOPIC))")
TLM_TOPIC=$(printf "0x%02x" "$((TLM_TOPIC))")

if [[ "$CMD_TOPIC" == "$TLM_TOPIC" ]]; then
    echo "Error: cmd_topic and tlm_topic must be different values (both are $CMD_TOPIC)"
    exit 1
fi

# Check for conflicts
for TOPIC in "$CMD_TOPIC" "$TLM_TOPIC"; do
    OWNER=$(registry_topic_used "$TOPIC")
    if [[ -n "$OWNER" && "$OWNER" != "$APP_NAME" ]]; then
        echo "Error: topic ID $TOPIC already used by app '$OWNER'"
        exit 1
    fi
done

# ── Case variant helpers ──────────────────────────────────────────────────────
# Input: e.g. gps_app
# lower:   gps_app
# upper:   GPS_APP
# title:   Gps_App   (first letter of each _-word capitalised)
# pascal:  GpsApp    (PascalCase, no underscores)

to_upper() { echo "$1" | tr '[:lower:]' '[:upper:]'; }

to_title() {
    # gps_app → Gps_App
    echo "$1" | awk -F'_' '{
        result=""
        for(i=1;i<=NF;i++){
            w=substr($i,1,1)
            r=substr($i,2)
            if(w~/[a-z]/) w=toupper(w)
            result=result (i>1?"_":"") w r
        }
        print result
    }'
}

to_pascal() {
    # gps_app → GpsApp
    echo "$1" | awk -F'_' '{
        result=""
        for(i=1;i<=NF;i++){
            w=substr($i,1,1)
            r=substr($i,2)
            if(w~/[a-z]/) w=toupper(w)
            result=result w r
        }
        print result
    }'
}

APP_LOWER="$APP_NAME"
APP_UPPER=$(to_upper "$APP_NAME")
APP_TITLE=$(to_title "$APP_NAME")
APP_PASCAL=$(to_pascal "$APP_NAME")

# Strip numeric suffix from hex for use in #define values (keep full hex string)
CMD_HEX_BARE="${CMD_TOPIC#0x}"
TLM_HEX_BARE="${TLM_TOPIC#0x}"

# ── STEP 3 — Copy sample_app ──────────────────────────────────────────────────
echo "Copying apps/sample_app → apps/$APP_LOWER ..."
cp -r "$APPS_DIR/sample_app" "$APPS_DIR/$APP_LOWER"

# ── STEP 4 — Rename files and directories ────────────────────────────────────
# Work bottom-up so directory renames don't break paths
cd "$APPS_DIR/$APP_LOWER"

rename_in_tree() {
    # Rename files/dirs containing any sample_app case variant, bottom-up
    while IFS= read -r -d '' path; do
        base=$(basename "$path")
        dir=$(dirname "$path")
        newbase="$base"

        # Replace all variants (order: longest first to avoid partial matches)
        newbase="${newbase//SampleApp/$APP_PASCAL}"
        newbase="${newbase//Sample_App/$APP_TITLE}"
        newbase="${newbase//SAMPLE_APP/$APP_UPPER}"
        newbase="${newbase//sample_app/$APP_LOWER}"

        if [[ "$newbase" != "$base" ]]; then
            mv "$path" "$dir/$newbase"
        fi
    done < <(find . -depth -print0 | grep -z -i 'sample_app\|sampleapp\|sample-app')
}

rename_in_tree

cd "$SCRIPT_DIR"

# ── STEP 5 — Replace text inside all files ────────────────────────────────────
NEWAPP_DIR="$APPS_DIR/$APP_LOWER"

replace_in_files() {
    local file="$1"
    # Case variants
    sed -i \
        -e "s/SampleApp/$APP_PASCAL/g" \
        -e "s/Sample_App/$APP_TITLE/g" \
        -e "s/SAMPLE_APP/$APP_UPPER/g" \
        -e "s/sample_app/$APP_LOWER/g" \
        "$file"

    # Topic IDs — replace old hex values with new ones
    # DEFAULT_SAMPLE_APP_MISSION_CMD_TOPICID     0x82
    sed -i \
        -e "s/\(DEFAULT_${APP_UPPER}_MISSION_CMD_TOPICID[[:space:]]*\)0x82/\10x${CMD_HEX_BARE}/g" \
        -e "s/\(DEFAULT_${APP_UPPER}_MISSION_SEND_HK_TOPICID[[:space:]]*\)0x83/\10x${TLM_HEX_BARE}/g" \
        -e "s/\(DEFAULT_${APP_UPPER}_MISSION_HK_TLM_TOPICID[[:space:]]*\)0x83/\10x${TLM_HEX_BARE}/g" \
        "$file"
}

export -f replace_in_files
export APP_LOWER APP_UPPER APP_TITLE APP_PASCAL CMD_HEX_BARE TLM_HEX_BARE

# Process all text files (exclude binaries and .git)
find "$NEWAPP_DIR" -type f \
    ! -path '*/.git/*' \
    ! -name '*.pyc' \
    ! -name '*.o' \
    ! -name '*.a' \
    ! -name '*.so' \
    ! -name '*.tbl' \
    | while IFS= read -r f; do
        if file "$f" | grep -qiE 'text|ascii|empty'; then
            replace_in_files "$f"
        fi
    done

# ── STEP 6 — Edit sample_defs files ──────────────────────────────────────────

# Helper: insert a line after the first occurrence of a pattern in a file
insert_after() {
    local file="$1"
    local pattern="$2"
    local newline="$3"
    # Use awk to insert after first match only
    awk -v pat="$pattern" -v ins="$newline" '
        !done && index($0, pat) {
            print
            print ins
            done=1
            next
        }
        { print }
    ' "$file" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# ── cpu1/install_custom.cmake ─────────────────────────────────────────────────
CPU1_CMAKE="$SAMPLE_DEFS/cpu1/install_custom.cmake"
if grep -qF "\$<TARGET_PROPERTY:${APP_LOWER},INCLUDE_DIRECTORIES>" "$CPU1_CMAKE"; then
    echo "[skip] $APP_LOWER already in cpu1/install_custom.cmake"
else
    insert_after "$CPU1_CMAKE" \
        '$<TARGET_PROPERTY:sample_app,INCLUDE_DIRECTORIES>' \
        "    \$<TARGET_PROPERTY:${APP_LOWER},INCLUDE_DIRECTORIES>"
fi

# ── cpu2/install_custom.cmake ─────────────────────────────────────────────────
CPU2_CMAKE="$SAMPLE_DEFS/cpu2/install_custom.cmake"
if [[ -f "$CPU2_CMAKE" ]]; then
    if grep -qF "\$<TARGET_PROPERTY:${APP_LOWER},INCLUDE_DIRECTORIES>" "$CPU2_CMAKE"; then
        echo "[skip] $APP_LOWER already in cpu2/install_custom.cmake"
    else
        insert_after "$CPU2_CMAKE" \
            '$<TARGET_PROPERTY:sample_app,INCLUDE_DIRECTORIES>' \
            "    \$<TARGET_PROPERTY:${APP_LOWER},INCLUDE_DIRECTORIES>"
    fi
fi

# ── generate_startup.cmake ────────────────────────────────────────────────────
GEN_CMAKE="$SAMPLE_DEFS/generate_startup.cmake"
if grep -qF "CFE_APP, ${APP_LOWER}," "$GEN_CMAKE"; then
    echo "[skip] $APP_LOWER already in generate_startup.cmake"
else
    insert_after "$GEN_CMAKE" \
        '"CFE_APP, sample_app,  SAMPLE_APP_Main,    SAMPLE_APP,   50,   32768, 0x0, 0;\n"' \
        "        \"CFE_APP, ${APP_LOWER}, ${APP_UPPER}_Main, ${APP_UPPER}, 54,   32768, 0x0, 0;\\\n\""
fi

# ── tables/sch_lab_table.c ────────────────────────────────────────────────────
SCH_TABLE="$SAMPLE_DEFS/tables/sch_lab_table.c"
if grep -qF "#include \"${APP_LOWER}_msgids.h\"" "$SCH_TABLE"; then
    echo "[skip] $APP_LOWER include already in sch_lab_table.c"
else
    insert_after "$SCH_TABLE" \
        '#include "sample_app_msgids.h"' \
        "#include \"${APP_LOWER}_msgids.h\""
fi

if grep -qF "${APP_UPPER}_SEND_HK_MID" "$SCH_TABLE"; then
    echo "[skip] ${APP_UPPER}_SEND_HK_MID already in sch_lab_table.c"
else
    insert_after "$SCH_TABLE" \
        '{CFE_SB_MSGID_WRAP_VALUE(SAMPLE_APP_SEND_HK_MID), 54, 0}, /* every 5.4 seconds */' \
        "        {CFE_SB_MSGID_WRAP_VALUE(${APP_UPPER}_SEND_HK_MID), ${HK_RATE}, 0}, /* ${APP_LOWER} HK */"
fi

# ── tables/to_lab_sub.c ───────────────────────────────────────────────────────
TO_SUB="$SAMPLE_DEFS/tables/to_lab_sub.c"
if grep -qF "#include \"${APP_LOWER}_msgids.h\"" "$TO_SUB"; then
    echo "[skip] $APP_LOWER include already in to_lab_sub.c"
else
    insert_after "$TO_SUB" \
        '#include "sample_app_msgids.h"' \
        "#include \"${APP_LOWER}_msgids.h\""
fi

if grep -qF "${APP_UPPER}_HK_TLM_MID" "$TO_SUB"; then
    echo "[skip] ${APP_UPPER}_HK_TLM_MID already in to_lab_sub.c"
else
    insert_after "$TO_SUB" \
        '{CFE_SB_MSGID_WRAP_VALUE(SAMPLE_APP_HK_TLM_MID), {0, 0}, 1},' \
        "        {CFE_SB_MSGID_WRAP_VALUE(${APP_UPPER}_HK_TLM_MID), {0, 0}, 1},"
fi

# ── targets.cmake ─────────────────────────────────────────────────────────────
TARGETS_CMAKE="$SAMPLE_DEFS/targets.cmake"

add_to_applist() {
    local var="$1"  # e.g. cpu1_APPLIST
    # Check if already present
    if grep -qP "SET\($var\b.*\b${APP_LOWER}\b" "$TARGETS_CMAKE"; then
        echo "[skip] $APP_LOWER already in $var"
        return
    fi
    # Insert after sample_app if present in that line, else after to_lab
    if grep -qP "SET\($var\b.*\bsample_app\b" "$TARGETS_CMAKE"; then
        sed -i "s/\(SET($var[^)]*\bsample_app\b\)/\1 ${APP_LOWER}/" "$TARGETS_CMAKE"
    elif grep -qP "SET\($var\b.*\bto_lab\b" "$TARGETS_CMAKE"; then
        sed -i "s/\(SET($var[^)]*\bto_lab\b\)/\1 ${APP_LOWER}/" "$TARGETS_CMAKE"
    else
        # Append at end of the SET line
        sed -i "s/\(SET($var [^)]*\))/\1 ${APP_LOWER})/" "$TARGETS_CMAKE"
    fi
}

add_to_applist "cpu1_APPLIST"
add_to_applist "cpu2_APPLIST"

# ── STEP 7 — Update registry ──────────────────────────────────────────────────
NEXT_CMD=$(read_json_field "$REGISTRY" "next_cmd_topic")
NEXT_TLM=$(read_json_field "$REGISTRY" "next_tlm_topic")

# Compute new next values (increment by 2 from the *used* values)
NEW_NEXT_CMD=$(printf "0x%02x" "$(( $(printf '%d' "$CMD_TOPIC") + 2 ))")
NEW_NEXT_TLM=$(printf "0x%02x" "$(( $(printf '%d' "$TLM_TOPIC") + 2 ))")

# Build updated JSON (pure bash + sed, no jq dependency)
TMPFILE=$(mktemp)
python3 - <<PYEOF > "$TMPFILE"
import json, sys

with open("$REGISTRY") as f:
    reg = json.load(f)

reg["apps"].append({
    "name": "$APP_LOWER",
    "cmd_topic": "$CMD_TOPIC",
    "tlm_topic": "$TLM_TOPIC"
})
reg["next_cmd_topic"] = "$NEW_NEXT_CMD"
reg["next_tlm_topic"] = "$NEW_NEXT_TLM"

print(json.dumps(reg, indent=2))
PYEOF

mv "$TMPFILE" "$REGISTRY"

# ── STEP 8 — Summary ──────────────────────────────────────────────────────────
CMD_INT=$(printf '%d' "$CMD_TOPIC")
TLM_INT=$(printf '%d' "$TLM_TOPIC")
CMD_MID=$(printf "0x%04x" "$(( 0x1800 | CMD_INT ))")
SEND_HK_MID=$(printf "0x%04x" "$(( 0x1800 | TLM_INT ))")
HK_TLM_MID=$(printf "0x%04x" "$(( 0x0800 | TLM_INT ))")
SECONDS_PER_RATE=$(awk "BEGIN { printf \"%.1f\", $HK_RATE / 10.0 }")

echo ""
echo "✓ Created: apps/${APP_LOWER}/"
echo "✓ CMD topic: ${CMD_TOPIC} → CMD_MID = 0x1800 | ${CMD_TOPIC} = ${CMD_MID}"
echo "✓ TLM topic: ${TLM_TOPIC} → SEND_HK_MID = 0x1800 | ${TLM_TOPIC} = ${SEND_HK_MID}"
echo "                          → HK_TLM_MID  = 0x0800 | ${TLM_TOPIC} = ${HK_TLM_MID}"
echo "✓ HK rate: every ${HK_RATE} ticks (every ${SECONDS_PER_RATE}s at TickRate=10)"
echo "✓ Registry updated. Next available: CMD=${NEW_NEXT_CMD}  TLM=${NEW_NEXT_TLM}"
echo "✓ Build: cd ~/Documents/TCC/cFS && make native_std.prep && make native_std.install"
