#!/usr/bin/env bash
set -euo pipefail

# =========================
# CONFIG
# =========================
DEBUG=1                     # <-- Set to 1 to enable debug output, 0 to disable
debug_echo() {
    if [[ "$DEBUG" -eq 1 ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

OUTPUT_FILE="ids.txt"
TMP_FILE=$(mktemp)

API_URL="https://graphql.anilist.co"

DB_FILE="../anime_mappings.db"
TABLE="anime"

# =========================
# DETERMINE SEASON
# =========================
month=$(date +%-m)
year=$(date +%Y)

case $month in
    12|1|2)  SEASON="WINTER" ;;
    3|4|5)   SEASON="SPRING" ;;
    6|7|8)   SEASON="SUMMER" ;;
    9|10|11) SEASON="FALL" ;;
    *) echo "Invalid month: $month"; exit 1 ;;
esac

# AniList treats December as next year's winter
[[ $month -eq 12 ]] && year=$((year + 1))
YEAR="$year"

debug_echo "Determined season: $SEASON $YEAR (current month: $month)"

echo "Fetching anime IDs for $SEASON $YEAR..."

> "$OUTPUT_FILE"

# =========================
# FETCH FROM ANILIST
# =========================
page=1
per_page=12
has_next_page=true

while [[ "$has_next_page" == "true" ]]; do
    echo "Fetching page $page..." >&2

    query="{\"query\":\"{ Page(page:$page, perPage:$per_page) { pageInfo{ hasNextPage } media(season:$SEASON, seasonYear:$YEAR, type:ANIME) { id } } }\"}"
    debug_echo "GraphQL query: $query"

    response=$(curl -s -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -d "$query")

    if [[ "$DEBUG" -eq 1 ]]; then
        # Print a snippet of the response (first 500 chars) to avoid clutter
        debug_echo "Response snippet: ${response:0:500}..."
    fi

    ids=$(echo "$response" | jq -r '.data.Page.media[].id // empty')
    has_next_page=$(echo "$response" | jq -r '.data.Page.pageInfo.hasNextPage // false')

    debug_echo "Extracted IDs: $ids"
    debug_echo "hasNextPage = $has_next_page"

    if [[ -z "$ids" && $page -eq 1 ]]; then
        echo "No anime found for $SEASON $YEAR." >&2
        exit 0
    fi

    echo "$ids" >> "$OUTPUT_FILE"
    page=$((page + 1))
    sleep 2
done

total_ids=$(wc -l < "$OUTPUT_FILE")
echo "Fetched $total_ids AniList IDs."

debug_echo "All AniList IDs collected: $(tr '\n' ' ' < "$OUTPUT_FILE")"

# =========================
# MAP → ANIDB IDS (FAST)
# =========================
echo "Mapping AniList IDs → AniDB IDs..."

# Build comma-separated list
id_list=$(paste -sd, "$OUTPUT_FILE")
debug_echo "Comma-separated AniList IDs: $id_list"

sql_query="SELECT anidb_id FROM $TABLE WHERE anilist_id IN ($id_list);"
debug_echo "SQL query: $sql_query"

# Query SQLite
sqlite3 "$DB_FILE" <<EOF > "$TMP_FILE"
.mode list
$sql_query
EOF

mapped_count=$(wc -l < "$TMP_FILE")

debug_echo "Mapping result contains $mapped_count lines."

if [[ "$mapped_count" -eq 0 ]]; then
    echo "No AniDB IDs found. Check your DB mapping." >&2
    exit 1
fi

if [[ "$DEBUG" -eq 1 ]]; then
    debug_echo "First 10 AniDB IDs from mapping:"
    head -n 10 "$TMP_FILE" | while read -r id; do debug_echo "  $id"; done
fi

mv "$TMP_FILE" "$OUTPUT_FILE"

echo "Done."
echo "Mapped $mapped_count AniDB IDs."
echo "Saved to: $OUTPUT_FILE"