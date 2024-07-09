#!/usr/bin/env bash
set -Eeuo pipefail

function create() {
    local source=/source
    local target=/data
    local temp=$target/$1
    shift
    mkdir -p "$temp"
    local last_dar=$(find "$target" -maxdepth 1 -type f -name "*.*.dar" -printf '%T@\t%p\n' | sort -n | tail -1 | cut -f2-)
    local last_archive=${last_dar%.*.*}
    if [ -z "$last_archive" ]; then
        local name=full
        echo "Creating an archive '$name'."
        if ! dar --create "$temp/$name" --fs-root "$source" -Q --no-overwrite --compress=zstd "$@" 1>/dev/null; then
            echo "Faled to create an archive"
            exit 1
        fi
    else
        local name=incremental-$(date +%Y%m%d-%H%M%S)
        echo "Creating an incremental archive '$name'."
        if ! dar --create "$temp/$name" --ref "$last_archive" --fs-root "$source" -Q --no-overwrite --compress=zstd "$@" 1>/dev/null; then
            echo "Faled to create an incremental archive"
            exit 1
        fi
    fi
    local size=$(du --total --bytes "$temp" | tail -n 1 | cut -f 1 | numfmt --grouping)
    local count=$(find "$temp" -type f | wc -l | numfmt --grouping)
    echo "Size: $size bytes."
    echo "Files: $count."
}

function test() {
    local data=/data
    local files_count=0
    while IFS="" read -r dar || [ -n "$dar" ]; do
        echo "Testing '$dar'"
        files_count=$((files_count + 1))
        if ! dar --test "$data/$dar" -Q "$@"; then
            echo "Test failed!"
            exit 1
        fi
    done < <(get_archives "$data")
    if [ $files_count -eq 0 ]; then
        echo "Failed to find files to test!"
        exit 2
    fi
}

function restore() {
    local data=/data
    local data=/target
    local archives=$(get_archives "$data")
    local count=$(cat "$archives" | wc -l)
    local index=0
    while IFS="" read -r dar || [ -n "$dar" ]; do
        index=$((index + 1))
        echo "$index/$count: Unpacking '$dar'"
        if ! dar --extract "$dar" --fs-root="$data" -Q --verbose=treated "$@"; then
            echo "$index/$count: Failed to unpacking '$dar'"
            exit 1
        fi
    done <<<"$archives"
}

function get_archives() {
    find "$1" -maxdepth 1 -type f -name "*.*.dar" | grep -oP '[^/]+(?=\.\d+\.dar)' | sort | uniq
}

if [ $# -lt 1 ]; then
    echo "At least 1 arguments required. create or test"
    exit -1
fi

action=$1
shift
case "$action" in
"create")
    create "$@"
    ;;
"test")
    test "$@"
    ;;
"restore")
    restore "$@"
    ;;
*)
    echo "Unsupported action '$1'"
    exit -2
    ;;

esac
