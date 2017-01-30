#!/bin/bash
set -o errexit
set -o pipefail
set -o nounset

readonly PG_CONNECT="postgis://$POSTGRES_USER:$POSTGRES_PASSWORD@$POSTGRES_HOST/$POSTGRES_DB"

function update() {
    imposm3 run \
        -connection "$PG_CONNECT" \
        -mapping "$MAPPING_YAML" \
        -cachedir "$IMPOSM_CACHE_DIR" \
        -diffdir "$DIFF_DIR" \
        -expiretiles-dir "$TILES_DIR" \
        -expiretiles-zoom 14 \
        -config config.json
}

function merge_pbf() {
    pbf=$( ls "$IMPORT_DIR"/*.pbf)
    while :
    do
        if compgen -G "$IMPORT_DIR/*/*/*.osc.gz" > /dev/null; then
            for change_file in "$IMPORT_DIR/*/*/*.osc.gz";
            do
                echo "Updating with $change_file"
                cp $pbf $pbf.old
                osmconvert $pbf.old $change_file -o=$pbf
                rm $pbf.old
            done
        fi
    done
}

update & merge_pbf
