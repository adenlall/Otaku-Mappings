#!/usr/bin/env bash


#####CONFIGURATION#####

temp_dir=$(mktemp -d)
XML_FILE="$temp_dir/anime-list.xml"
## Anime-Lists/anime-lists for mapping from AniDB into TMDB and TVDB
curl -L -o $XML_FILE https://github.com/Anime-Lists/anime-lists/raw/refs/heads/master/anime-list.xml

OTAKU_DB="../anime_mappings.db"       # Otaku-mapping db file
TABLE_NAME="anime"                    # Table

ANILIST_FILE="anilist_ids.txt"        # File with AniList IDs
ANIDB_FILE="anidb_ids.txt"            # File with AniDB IDs

# $OTAKU_DB column names
COL_TITLE="mal_title"
COL_MAL="mal_id"
COL_ANILIST="anilist_id"
COL_ANIDB="anidb_id"
COL_TVDB_ID="thetvdb_id"
COL_TVDB_SEASON="thetvdb_season"
COL_TMDB_ID="themoviedb_id"
# =======================================================

# Check required tools
for cmd in sqlite3 xmlstarlet; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is not installed. Please install it first."
        exit 1
    fi
done

update_column() {
    local anilist_id="$1"
    local col_name="$2"
    local col_value="$3"

    # SKIP IF DATA ALREADY EXISTS
    if [[ -n "$col_value" ]]; then
        sqlite3 "$OTAKU_DB" "
            UPDATE \"$TABLE_NAME\"
            SET \"$col_name\" = $col_value
            WHERE \"$COL_ANILIST\" = $anilist_id
              AND (\"$col_name\" IS NULL OR \"$col_name\" = '');
        "
    fi
}

# Read both files side by side, using '|' as delimiter
paste -d '|' "$ANILIST_FILE" "$ANIDB_FILE" | while IFS='|' read -r raw_anilist raw_anidb; do
    # Trim whitespace
    anilist_id=$(echo "$raw_anilist" | xargs)
    anidb_pre=$(echo "$raw_anidb" | xargs)
    anidb_id="${anidb_pre%%|||*}"
    temp="${anidb_pre#*|||}"
    mal_id="${temp%%|||*}"
    title="${temp#*|||}"

    # SKIP IF ONE OF THE LINES EMPTY OR "none"
    if [[ -z "$anilist_id" || -z "$anidb_id" || "$anidb_id" == "none" ]]; then
        echo "EMPTY DATA +++++> anilist_id = $anilist_id |  anidb_id = $anidb_id"
        continue
    fi

    echo "Processing: AniList=$anilist_id  ↔  AniDB=$anidb_id"

    # # Create the row if it doesn't exist
    sqlite3 "$OTAKU_DB" "
        INSERT OR IGNORE INTO \"$TABLE_NAME\" (\"$COL_ANILIST\", \"$COL_ANIDB\", \"$COL_MAL\", \"$COL_TITLE\")
        VALUES ($anilist_id, $anidb_id, $mal_id, '$title');
    "

    # Now safely update anidb_id (only if missing/null) – row definitely exists
    sqlite3 "$OTAKU_DB" "
        UPDATE \"$TABLE_NAME\"
        SET \"$COL_ANIDB\" = $anidb_id
        WHERE \"$COL_ANILIST\" = $anilist_id
          AND (\"$COL_ANIDB\" IS NULL OR \"$COL_ANIDB\" = '');
    "

    # Extract metadata from XML using the 'anidb_id'
    tvdb_id=$(xmlstarlet sel -t -v "//anime[@anidbid='$anidb_id']/@tvdbid" -n "$XML_FILE" 2>/dev/null | head -1)
    tvdb_season=$(xmlstarlet sel -t -v "//anime[@anidbid='$anidb_id']/@defaulttvdbseason" -n "$XML_FILE" 2>/dev/null | head -1)
    tmdb_id=$(xmlstarlet sel -t -v "//anime[@anidbid='$anidb_id']/@tmdbtv" -n "$XML_FILE" 2>/dev/null | head -1)
    if [[ $tmdb_id -eq "" ]]; then
        tmdb_id=$(xmlstarlet sel -t -v "//anime[@anidbid='$anidb_id']/@tmdbid" -n "$XML_FILE" 2>/dev/null | head -1)
    fi

    echo "anidb_id    ::  $anidb_id"
    echo "tvdb_id     ::  $tvdb_id"
    echo "tvdb_season ::  $tvdb_season"
    echo "tmdb_id     ::  $tmdb_id"

    # Update each column only if the field is missing in the database
    update_column "$anilist_id" "$COL_TMDB_ID"      "$tmdb_id"
    update_column "$anilist_id" "$COL_TVDB_SEASON"  "$tvdb_season"
    update_column "$anilist_id" "$COL_TVDB_ID"      "$tvdb_id"
done

echo "Done."