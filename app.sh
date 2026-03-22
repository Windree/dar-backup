#!/usr/bin/env bash
set -Eeuo pipefail

declare dir="$(dirname "$(readlink -f -- "$0")")"
declare temp_name="$(basename "$(mktemp --dry-run)")"
declare dar_image="dar-$(echo "$dir" | md5sum | awk '{ print $1 }')"
declare log="$(mktemp)"

function build_image() {
    local dar_image_path="$dir/dar/image"
    if ! docker build --quiet "$dar_image_path" -t "$dar_image" 2>"$log" >/dev/null; then
        echo "An error building '$dar_image_path'"
        cat "$log"
        exit 3
    fi
}

function create() {
    if [ $# -lt 2 ]; then
        echo "Usage: create <archive_dir> <source_dir>"
        exit 1
    fi
    if [ ! -d "$1" ]; then
        echo "An archive directory '$1' not found"
        exit 1
    fi
    if [ ! -d "$2" ]; then
        echo "A source directory '$2' not found"
        exit 1
    fi

    local archive_dir="$1"
    local source_dir="$2"
    shift 2
    
    local docker_compose="$source_dir/docker-compose.yml"
    local run_before="$source_dir/.backup/before"
    local run_after="$source_dir/.backup/after"

    if [ -x "$run_before" ]; then 
        "$run_before"
    fi

    docker run --rm -v "$source_dir:/source" -v "$archive_dir:/data" "$dar_image" create "$temp_name" "$@"

    if [ -x "$run_after" ]; then 
        "$run_after"
    fi

    if ! verify "$archive_dir/$temp_name"; then
        echo "An archive validation failed"
        exit 1
    fi

    mv "$archive_dir/$temp_name/"* "$archive_dir/" 2>/dev/null || true
    rmdir "$archive_dir/$temp_name/"
    echo "Create: OK."
}

function extract() {
    if [ $# -lt 2 ]; then
        echo "Usage: extract <archive_dir> <target_dir>"
        exit 1
    fi
    if [ ! -d "$1" ]; then
        echo "An archive directory '$1' not found"
        exit 1
    fi
    if [ ! -d "$2" ]; then
        echo "A target directory '$2' not found"
        exit 1
    fi

    local archive_dir="$1"
    local target_path="$2"
    shift 2

    docker run --rm -v "$archive_dir:/data" -v "$target_path:/target" "$dar_image" extract "$@"
    echo "Extract: OK."
}

function verify() {
    if [ $# -lt 1 ]; then
        echo "Usage: verify <archive_dir>"
        exit 1
    fi
    if [ ! -d "$1" ]; then
        echo "An archive directory '$1' not found"
        exit 1
    fi

    local archive_dir="$1"
    shift 1

    docker run --rm -v "$archive_dir:/data" "$dar_image" verify "$@"
    echo "Verify: OK."
}

function cleanup() {
    [ -f "$log" ] && rm -f "$log"
}

trap cleanup EXIT

if [ $# -lt 1 ]; then
    echo "Usage: $0 {create|extract|verify} [args]"
    exit 1
fi

action="$1"
shift

build_image

case "$action" in
    "create") create "$@";;
    "extract") extract "$@";;
    "verify") verify "$@";;
    *)
        echo "Unsupported action '$action'"
        exit 2
        ;;
esac
