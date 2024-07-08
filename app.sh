#!/usr/bin/env bash
set -Eeuo pipefail

function check_source() {
    if [ -d "$1" ]; then
        return 0
    fi
    echo >&2 "Source directory '$1' not found"
    exit 1
}

function check_target() {
    if [ -d "$1" ]; then
        return 0
    fi
    echo >&2 "Target directory '$1' not found"
    exit 2
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

check_source "${2:-}"
check_target "${1:-}"

docker_compose=$2/docker-compose.yml
docker_status=$(get_docker_status "$docker_compose")
dir=$(dirname "$(readlink -f -- "$0")")
dar_image=$(basename "$dir")-dar
temp=$(basename "$(mktemp --dry-run)")
log=$(mktemp)

function cleanup() {
    if [ "$docker_status" == "running" ]; then
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

function build_image() {
    local dar_image_path=$dir/dar/image
    local numfmt_image_path=$dir/numfmt/image
    if ! docker build --quiet "$dar_image_path" -t "$dar_image" 2>"$log" >/dev/null; then
        echo "Error build '$dar_image_path'"
        cat "$log"
        exit 3
    fi
}

function main() {
    local backup_path=$1
    local source_path=$2
    shift 2
    if [ "$docker_status" == "running" ]; then
        echo "Stoping docker..."
        stop_docker "$source_path"
    fi

    docker run --rm -v "$source_path:/source" -v "$backup_path:/data" "$dar_image" create "$temp" "$@"

    if [ "$docker_status" == "running" ]; then
        echo "Staring docker..."
        start_docker "$source_path"
    fi
    docker_status=""

    if ! docker run --rm -v "$backup_path/$temp:/data" "$dar_image" test; then
        exit 1
    fi
    mv "$backup_path/$temp/"* "$backup_path"
    rm -d "$backup_path/$temp/"
    echo "Result: OK."
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

build_image
main "$@"
