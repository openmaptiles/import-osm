#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

readonly IMPORT_DATA_DIR=${IMPORT_DATA_DIR:-/data/import}
readonly IMPOSM_CACHE_DIR=${IMPOSM_CACHE_DIR:-/data/cache}
readonly MAPPING_JSON=${MAPPING_JSON:-/usr/src/app/mapping.json}

readonly OSM_DB=${OSM_DB:-osm}
readonly OSM_USER=${OSM_USER:-osm}
readonly OSM_PASSWORD=${OSM_PASSWORD:-osm}

readonly DB_SCHEMA=${OSM_SCHEMA:-public}
readonly DB_HOST=$DB_PORT_5432_TCP_ADDR
readonly PG_CONNECT="postgis://$OSM_USER:$OSM_PASSWORD@$DB_HOST/$OSM_DB"

function download_pbf() {
    local pbf_url=$1
	wget -q  --directory-prefix "$IMPORT_DATA_DIR" --no-clobber "$pbf_url"
}

function import_pbf() {
    local pbf_file="$1"
    imposm3 import \
        -connection "$PG_CONNECT" \
        -mapping "$MAPPING_YAML" \
        -overwritecache \
        -cachedir "$IMPOSM_CACHE_DIR" \
        -read "$pbf_file" \
        -dbschema-import="${DB_SCHEMA}" \
        -write -optimize -diff

    local timestamp=$(extract_timestamp "$pbf_file")
    store_timestamp_history "$timestamp"
}

function extract_timestamp() {
    local file="$1"
    osmconvert "$file" --out-timestamp
}

function store_timestamp_history {
    local timestamp="$1"
    local table_name="osm_timestamps"

    exec_sql "CREATE TABLE IF NOT EXISTS $table_name (timestamp timestamp)"
    exec_sql "DELETE FROM $table_name WHERE timestamp='$timestamp'::timestamp"
    exec_sql "INSERT INTO $table_name VALUES ('$timestamp'::timestamp)"
}

function update_timestamp() {
    local timestamp="$1"
    store_timestamp_history "$timestamp"

    exec_sql "SELECT update_timestamp('$timestamp')"
}

function enable_update_tracking() {
    exec_sql "SELECT enable_update_tracking()"
}

function disable_update_tracking() {
    exec_sql "SELECT disable_update_tracking()"
}

function enable_delete_tracking() {
    exec_sql "SELECT enable_delete_tracking()"
}

function disable_delete_tracking() {
    exec_sql "SELECT disable_delete_tracking()"
}

function drop_tables() {
    exec_sql "SELECT drop_tables()"
}

function cleanup_osm_changes() {
    exec_sql "SELECT cleanup_osm_tracking_tables()"
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

function import_pbf_diffs() {
    local pbf_file="$1"
    local diffs_file="$IMPORT_DATA_DIR/latest.osc.gz"

    echo "Import deletes from $diffs_file"
    enable_delete_tracking
    imposm3 diff \
        -no-create -no-modify \
        -connection "$PG_CONNECT" \
        -mapping "$MAPPING_YAML" \
        -cachedir "$IMPOSM_CACHE_DIR" \
        -diffdir "$IMPORT_DATA_DIR" \
        -dbschema-import "${DB_SCHEMA}" \
        "$diffs_file"
    disable_delete_tracking

    echo "Import creates and modifications from $diffs_file"
    enable_update_tracking
    imposm3 diff \
        -no-delete \
        -connection "$PG_CONNECT" \
        -mapping "$MAPPING_YAML" \
        -cachedir "$IMPOSM_CACHE_DIR" \
        -diffdir "$IMPORT_DATA_DIR" \
        -dbschema-import "${DB_SCHEMA}" \
        "$diffs_file"
    disable_update_tracking

    local timestamp=$(extract_timestamp "$diffs_file")
    echo "Set $timestamp for latest updates from $diffs_file"
    update_timestamp "$timestamp"
    cleanup_osm_changes
}
