#!/usr/bin/env bash
set -Eeuo pipefail

declare dir=$(dirname "$(readlink -f -- "$0")")
declare dar_image=$(basename "$dir")-dar
declare temp=$(basename "$(mktemp --dry-run)")
declare log=$(mktemp --dry-run)

function build_image() {
    local dar_image_path=$dir/dar/image
    local numfmt_image_path=$dir/numfmt/image
    if ! docker build --quiet "$dar_image_path" -t "$dar_image" 2>"$log" >/dev/null; then
        echo "Error build '$dar_image_path'"
        cat "$log"
        exit 3
    fi
}

function create() {
    if [ ! -v 1 ] || [ ! -d "$1" ]; then
        echo "Archive directory '$1' not found"
    fi
    if [ ! -v 2 ] || [ ! -d "$2" ]; then
        echo "Source directory '$2' not found"
    fi

    local archive_path=$1
    local source_path=$2
    shift 2
    
    export docker_compose="$source_path/docker-compose.yml"
    export backup_before="$source_path/backup/before"
    export backup_after="$source_path/backup/after"

    if [ -x "$backup_before" ]; then 
        "$backup_before"
    fi

    docker run --rm -v "$source_path:/source" -v "$archive_path:/data" "$dar_image" create "$temp" "$@"

    if [ -x "$backup_after" ]; then 
        "$backup_after"
    fi

    if ! docker run --rm -v "$archive_path/$temp:/data" "$dar_image" test; then
        exit 1
    fi
    mv "$archive_path/$temp/"* "$archive_path"
    rm -d "$archive_path/$temp/"
    echo "Result: OK."
}

function extract() {
    if [ ! -v 1 ] || [ ! -d "$1" ]; then
        echo "Archive directory '$1' not found"
    fi
    if [ ! -v 2 ] || [ ! -d "$2" ]; then
        echo "Target directory '$2' not found"
    fi

    local archive_path=$1
    local target_path=$2
    shift 2

    docker run --rm -v "$1:/target" -v "$2:/data" "$dar_image" extract "$@"
    echo "Result: OK."
}


function cleanup() {
    if [ -d "$temp" ]; then
        rm -rf "$temp"
    fi
    if [ -f "$log" ]; then
        rm -f "$log"
    fi
}

trap cleanup exit

action=$1
shift

build_image

case "$action" in
"create")
    create "$@"
    ;;
"extract")
    extract "$@"
    ;;
*)
    echo "Unsupported action '$action'"
    exit -2
    ;;

esac
