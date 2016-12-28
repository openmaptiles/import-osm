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

function update_points() {
    exec_sql_file "point_update.sql"
}

function update_scaleranks() {
    exec_sql_file "update_scaleranks.sql"
}

function create_osm_water_point_table() {
    exec_sql_file "water_point_table.sql"
}

function subdivide_polygons() {
    exec_sql_file "subdivide_polygons.sql"
}

function update_scaleranks() {
    exec_sql_file "update_scaleranks.sql"
}

function create_timestamp_history() {
    exec_sql "DROP TABLE IF EXISTS $HISTORY_TABLE"
    exec_sql "CREATE TABLE $HISTORY_TABLE (timestamp timestamp)"
}

function store_timestamp_history {
    local timestamp="$1"

    exec_sql "DELETE FROM $HISTORY_TABLE WHERE timestamp='$timestamp'::timestamp"
    exec_sql "INSERT INTO $HISTORY_TABLE VALUES ('$timestamp'::timestamp)"
}

function update_timestamp() {
    local timestamp="$1"
    store_timestamp_history "$timestamp"
    exec_sql "SELECT update_timestamp('$timestamp')"
}


function drop_osm_delete_indizes() {
    exec_sql "SELECT drop_osm_delete_indizes()"
}

function create_osm_delete_indizes() {
    exec_sql "SELECT create_osm_delete_indizes()"
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

    echo "Drop indizes for faster inserts"
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

    # Redo tables that are hard coded in import-sql
    # vacuum analyze
    echo "Create osm_water_point table with precalculated centroids"
#    create_osm_water_point_table

    echo "Update osm_place_polygon with point geometry"
#    update_points

#    echo "Subdividing polygons in $OSM_DB"
#    subdivide_polygons

    local timestamp=$(extract_timestamp "$diffs_file")
    echo "Set $timestamp for latest updates from $diffs_file"
#    update_timestamp "$timestamp"

    echo "Create indizes for faster dirty tile calculation"
#    create_osm_delete_indizes

#    cleanup_osm_changes
# vacuum analyze
}
