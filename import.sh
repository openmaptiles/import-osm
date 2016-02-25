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

readonly OSM_UPDATE_BASEURL=${OSM_UPDATE_BASEURL:-false}

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

	add_timestamp_column
    local timestamp=$(extract_timestamp "$pbf_file")
    update_timestamp "$timestamp"
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

	exec_sql "UPDATE osm_admin SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_aero_lines SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_aero_polygons SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_barrier_lines SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_barrier_polygons SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_buildings SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_buildings_gen0 SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_housenumbers_points SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_housenumbers_polygons SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_landusages SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_landusages_gen0 SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_landusages_gen1 SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_places SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_poi_points SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_poi_polygons SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_roads SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_water_lines SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_water_polygons SET timestamp='$timestamp' WHERE timestamp IS NULL"
	exec_sql "UPDATE osm_water_polygons_gen1 SET timestamp='$timestamp' WHERE timestamp IS NULL"
}

function drop_views() {
	exec_sql "DROP VIEW IF EXISTS poi_label_z14"
}

function add_timestamp_column() {
	exec_sql "ALTER TABLE osm_admin ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_aero_lines ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_aero_polygons ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_barrier_lines ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_barrier_polygons ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_buildings ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_buildings_gen0 ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_housenumbers_points ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_housenumbers_polygons ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_landusages ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_landusages_gen0 ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_landusages_gen1 ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_places ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_poi_points ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_poi_polygons ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_roads ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_water_lines ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_water_polygons ADD COLUMN timestamp timestamp"
	exec_sql "ALTER TABLE osm_water_polygons_gen1 ADD COLUMN timestamp timestamp"
}

function exec_sql() {
	local sql_cmd="$1"
	PG_PASSWORD=$OSM_PASSWORD psql \
        --host="$DB_HOST" \
        --port=5432 \
        --dbname="$OSM_DB" \
        --username="$OSM_USER" \
        -c "$sql_cmd" || true
}

function import_pbf_diffs() {
    local pbf_file="$1"
    local latest_diffs_file="$IMPORT_DATA_DIR/latest.osc.gz"

    cd "$IMPORT_DATA_DIR"
    if [ "$OSM_UPDATE_BASEURL" = false ]; then
        osmupdate "$pbf_file" "$latest_diffs_file"
    else
        echo "Downloading diffs from $OSM_UPDATE_BASEURL"
        osmupdate -v \
            "$pbf_file" "$latest_diffs_file" \
            --base-url="$OSM_UPDATE_BASEURL"
    fi

    imposm3 diff \
        -connection "$PG_CONNECT" \
        -mapping "$MAPPING_YAML" \
        -cachedir "$IMPOSM_CACHE_DIR" \
        -diffdir "$IMPORT_DATA_DIR" \
        -dbschema-import "${DB_SCHEMA}" \
        "$latest_diffs_file"

    local timestamp=$(extract_timestamp "$latest_diffs_file")
    echo "Set $timestamp for latest updates from $latest_diffs_file"
    update_timestamp "$timestamp"
}
