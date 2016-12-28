#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

readonly PG_CONNECT="postgis://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"
readonly DIFFS=${DIFFS:-true}
readonly DB_SCHEMA=${OSM_SCHEMA:-public}

function extract_timestamp() {
    local file="$1"
    osmconvert "$file" --out-timestamp
}

function exec_sql() {
	local sql_cmd="$1"
	PG_PASSWORD=$OSM_PASSWORD psql \
        --host="$DB_HOST" \
        --port=5432 \
        --dbname="$OSM_DB" \
        --username="$OSM_USER" \
        -c "$sql_cmd"
}

function exec_sql_file() {
    local sql_file=$1
    PG_PASSWORD=$OSM_PASSWORD psql \
        --host="$DB_HOST" \
        --port=5432 \
        --dbname="$OSM_DB" \
        --username="$OSM_USER" \
        -v ON_ERROR_STOP=1 \
        -a -f "$sql_file"
}

function import_pbf_diffs() {
    local pbf_file="$1"
    local diffs_file="$IMPORT_DIR/latest.osc.gz"

#    echo "Drop indizes for faster inserts"
#    drop_osm_delete_indizes
# Lets keep indexes for now

    echo "Import changes from $diffs_file"
    imposm3 diff \
        -connection "$PG_CONNECT" \
        -mapping "$MAPPING_YAML" \
        -cachedir "$IMPOSM_CACHE_DIR" \
        -diffdir "$IMPORT_DIR" \
        -dbschema-import "${DB_SCHEMA}" \
        "$diffs_file"

    local timestamp=$(extract_timestamp "$diffs_file")
    echo "Set $timestamp for latest updates from $diffs_file"

    # Redo tables that are hard coded in import-sql
    # vacuum analyze

}
