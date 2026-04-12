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

ANILIST_FILE="anilist_ids.txt"
ANIDB_FILE="anidb_ids.txt"

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

> "$ANILIST_FILE"

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

    echo "$ids" >> "$ANILIST_FILE"
    page=$((page + 1))
    sleep 2
done

total_ids=$(wc -l < "$ANILIST_FILE")
echo "Fetched $total_ids AniList IDs."

debug_echo "All AniList IDs collected: $(tr '\n' ' ' < "$ANILIST_FILE")"

# =========================
# MAP → ANIDB IDS (FAST)
# =========================
echo "Mapping AniList IDs → AniDB IDs..."

temp_dir=$(mktemp -d)
OFFDB_FILE="$temp_dir/anime-offline-database.jsonl"
echo "Downloading https://github.com/manami-project/anime-offline-database/releases/download/latest/anime-offline-database.jsonl into $OFFDB_FILE"
curl -L -o $OFFDB_FILE https://github.com/manami-project/anime-offline-database/releases/download/latest/anime-offline-database.jsonl


> "$ANIDB_FILE"
echo ""
echo "Strating Mapping ...."


while read -r id; do

    [[ -z "$id" ]] && continue

    result=$(jq -r --arg id "$id" '
        select(.sources | type == "array") |
        select(any(.sources[]; test("anilist\\.co/anime/" + $id))) |
        .sources[] | select(contains("anidb.net/anime/")) | split("/")[-1]
        ' "$OFFDB_FILE" 2>/dev/null)

    if [[ -n "$result" ]]; then
        echo "$result"
    else
        echo "none"
    fi
done < "$ANILIST_FILE" > "$ANIDB_FILE"

echo "Done."
# echo "Mapped $mapped_count AniDB IDs."
echo "Saved to: $ANILIST_FILE"