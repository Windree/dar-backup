#!/usr/bin/env bash
set -Eeuo pipefail

docker_compose=
docker_status=
dir=$(dirname "$(readlink -f -- "$0")")
dar_image=$(basename "$dir")-dar
temp=$(basename "$(mktemp --dry-run)")
log=$(mktemp --dry-run)

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
    
    export docker_compose=$source_path/docker-compose.yml
    export docker_status=$(get_docker_status "$docker_compose")

    if [ "$docker_status" == "running" ]; then
        echo "Stoping docker..."
        stop_docker "$source_path"
    fi

    docker run --rm -v "$source_path:/source" -v "$archive_path:/data" "$dar_image" create "$temp" "$@"

    if [ "$docker_status" == "running" ]; then
        echo "Staring docker..."
        start_docker "$source_path"
    fi
    docker_status=""

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

    docker run --rm -v "$target_path:/target" -v "$archive_path:/data" "$dar_image" extract "$@"
    echo "Result: OK."
}

function get_docker_status() {
    if [ ! -f "$1" ]; then
        echo ""
    elif [ -z "$(docker compose -f "$1" top)" ]; then
        echo "stopped"
    else
        echo "running"
    fi
}

function start_docker() {
    if ! docker compose -f "$docker_compose" up -d; then
        echo Error starting container
        exit 2
    fi
}

function stop_docker() {
    if ! docker compose -f "$docker_compose" stop; then
        echo Error stopping container
        exit 2
    fi
}


function cleanup() {
    if [ "$docker_status" == "running" ] && [ -n "$docker_compose" ]; then
        start_docker "$docker_compose"
    fi
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
