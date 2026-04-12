#!/usr/bin/env bash
set -euo pipefail


############################
##########CONFIG############
############################
DEBUG=1
debug_echo() {
    if [[ "$DEBUG" -eq 1 ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

# auto => Fetch from anilist save into $ANILIST_FILE them map from AniDB and save into $ANIDB_FILE
# manual => Get ids directly from $ANILIST_FILE them map from AniDB and save into $ANIDB_FILE
MODE="manual" 

API_URL="https://graphql.anilist.co"

ANILIST_FILE="anilist_ids.txt"
ANIDB_FILE="anidb_ids.txt"

DB_FILE="../anime_mappings.db"
TABLE="anime"


############################
########GET#ANILIST#########
############################

if [["$MODE" == "auto"]]; then ## ONLY FETCH FROM ANILIST IN AUTO MODE 


    # DETERMINE SEASON
    month=$(date +%-m)  ## EDIT MANUALLY TO GET DIFFERENT ANIME SEASON
    year=$(date +%Y)    ## EDIT MANUALLY TO GET DIFFERENT ANIME SEASON
    case $month in
        12|1|2)  SEASON="WINTER" ;; # ANILIST treats December as next year's winter ^)_(^
        3|4|5)   SEASON="SPRING" ;;
        6|7|8)   SEASON="SUMMER" ;;
        9|10|11) SEASON="FALL" ;;
        *) echo "Invalid month: $month"; exit 1 ;;
    esac
    [[ $month -eq 12 ]] && year=$((year + 1))
    YEAR="$year"


    > "$ANILIST_FILE" # wiping out $ANILIST_FILE
        
    page=1 ## AUTO INCREMENTING
    per_page=12 ## LOWER MEAN MORE PAGES ! AND YOU MAY GET 429 OR 403 HTTP RESPONSE
    has_next_page=true

    while [[ "$has_next_page" == "true" ]]; do

        echo "Fetching page $page..." >&2

        query="{\"query\":\"{ Page(page:$page, perPage:$per_page) { pageInfo{ hasNextPage } media(season:$SEASON, seasonYear:$YEAR, type:ANIME) { id } } }\"}"
        debug_echo "GraphQL query: $query"

        response=$(curl -s -X POST "$API_URL" \
            -H "Content-Type: application/json" \
            -d "$query")

        ids=$(echo "$response" | jq -r '.data.Page.media[].id // empty')
        has_next_page=$(echo "$response" | jq -r '.data.Page.pageInfo.hasNextPage // false')

        debug_echo "Extracted IDs: $ids"
        debug_echo "hasNextPage = $has_next_page"

        if [[ -z "$ids" && $page -eq 1 ]]; then
            echo "No anime found for $SEASON $YEAR." >&2
            exit 0
        fi

        echo "$ids" >> "$ANILIST_FILE" ## WRITE IDS INTO $ANILIST_FILE 
        page=$((page + 1))
        sleep 2 ## AVOID 429
    done

    total_ids=$(wc -l < "$ANILIST_FILE")
    echo "Fetched $total_ids AniList IDs."

    debug_echo "All AniList IDs collected: $(tr '\n' ' ' < "$ANILIST_FILE")"

else
    echo "\$MODE=\"manual\" => mapping into ANIDB directly from \$ANILIST_FILE ..."
fi


############################
########MAP#TO#ANIDB########
############################
echo "Mapping AniList IDs → AniDB IDs..."

# Downloading manami-project/anime-offline-database db into /tmp
temp_dir=$(mktemp -d)
OFFDB_FILE="$temp_dir/anime-offline-database.jsonl"
echo "Downloading manami-project/anime-offline-database into $OFFDB_FILE"
### manami-project/anime-offline-database HAS ALL ANIME DATA COMBINED
### It could be used to map anything from/into [Anilist, MAL, Kitsu, AniDB ...] but missing TMDB and TVDB
curl -L -o $OFFDB_FILE https://github.com/manami-project/anime-offline-database/releases/download/latest/anime-offline-database.jsonl


> "$ANIDB_FILE" # WIPE OUT $ANIDB_FILE
echo "..."
echo "Starting Mapping ...."


while read -r id; do

    [[ -z "$id" ]] && continue # SKIP WHEN EMPTY LINE

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
done < "$ANILIST_FILE" > "$ANIDB_FILE" ## READ FROM $ANILIST_FILE AND LOOP OUTPUT STORED INTO $ANIDB_FILE

echo "Done."
echo "[Anilist] ids Saved to: $ANILIST_FILE"
echo "[AniDB]   ids Saved to: $ANIDB_FILE"