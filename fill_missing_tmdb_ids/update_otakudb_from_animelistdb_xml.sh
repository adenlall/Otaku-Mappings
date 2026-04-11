#!/usr/bin/env bash
set -euo pipefail

DEBUG=1                     # <-- Set to 1 to enable debug output, 0 to disable
debug_echo() {
    if [[ "$DEBUG" -eq 1 ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

DB_FILE="../anime_mappings.db"
TABLE_NAME="anime"
ID_LIST="ids.txt"

# temp_dir=$(mktemp -d)
# XML_FILE="$temp_dir/anime-list.xml"
# echo "https://github.com/Anime-Lists/anime-lists/raw/refs/heads/master/anime-list.xml => $XML_FILE"
# curl -L -o $XML_FILE https://github.com/Anime-Lists/anime-lists/raw/refs/heads/master/anime-list.xml

XML_FILE=/tmp/tmp.jy3jkI0wRz/anime-list.xml

declare -A ALLOWED_IDS
while read -r id; do
    [[ -n "$id" ]] && ALLOWED_IDS["$id"]=1
done < "$ID_LIST"

debug_echo "Loaded ${#ALLOWED_IDS[@]} allowed AniDB IDs from $ID_LIST"

cp "$DB_FILE" "${DB_FILE}.backup"

{
    echo "BEGIN TRANSACTION;"

    debug_echo "Starting XML parsing with xmlstarlet..."

    xmlstarlet sel -t \
        -m "//anime" \
        -v "@anidbid" -o "|" \
        -v "@tvdbid" -o "|" \
        -v "@defaulttvdbseason" -o "|" \
        -v "@tmdbtv" -o "|" \
        -v "@tmdbseason"  \
        -n \
        "$XML_FILE" | while IFS='|' read -r anidb tvdb season tmdb tmdb_season; do

        debug_echo "Raw line: anidb='$anidb' tvdb='$tvdb' season='$season' tmdb='$tmdb' tmdb_season='$tmdb_season'"

        # Skip if anidb is not in the allowed list
        if [[ -z "${ALLOWED_IDS[$anidb]:-}" ]]; then
            debug_echo "Skipping anidb=$anidb (not in allowed list)"
            continue
        fi

        debug_echo "Processing allowed anidb=$anidb"

        # Build UPDATE statement using COALESCE to preserve existing non-NULL values
        updates=()
        [[ -n "$tvdb" ]] && updates+=("thetvdb_id = COALESCE(thetvdb_id, $tvdb)")
        [[ -n "$season" ]] && updates+=("thetvdb_season = COALESCE(thetvdb_season, $season)")
        [[ -n "$tmdb" ]] && updates+=("themoviedb_id = COALESCE(themoviedb_id, $tmdb)")

        if [[ ${#updates[@]} -gt 0 ]]; then
            set_clause=$(IFS=,; echo "${updates[*]}")
            sql="UPDATE $TABLE_NAME SET $set_clause WHERE anidb_id = $anidb;"
            debug_echo "Generated SQL: $sql"
            echo "$sql"
        else
            debug_echo "No non-empty mapping fields for anidb=$anidb; no UPDATE generated"
        fi
    done

    echo "COMMIT;"
} | sqlite3 "$DB_FILE"

echo "Update complete for $(wc -l < "$ID_LIST") targeted records."
