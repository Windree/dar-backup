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
        echo "Creating full archive '$name'."
        dar --create "$temp/$name" --fs-root "$source" -Q --no-overwrite --compress=zstd "$@" 1>/dev/null
    else
        local name=incremental-$(date +%Y%m%d-%H%M%S)
        echo "Creating incremental archive '$name'."
        dar --create "$temp/$name" --ref "$last_archive" --fs-root "$source" -Q --no-overwrite --compress=zstd "$@" 1>/dev/null
    fi
}

function test() {
    echo "Testing..."
    local data=/data
    local files_count=0
    while IFS="" read -r dar || [ -n "$dar" ]; do
        echo "Testing '$dar'"
        files_count=$((files_count+1))
        if ! dar --test "$data/$dar" -Q "$@"; then
            echo "Test failed!"
            exit 1
        fi
        local size=$(du --total --bytes "$data"/"$dar".*.* | tail -n 1 | cut -f 1 | numfmt --grouping)
        echo "File: '$dar' ($size bytes)"
    done < <(find "$data" -maxdepth 1 -type f -name "*.*.dar" | grep -oP '[^/]+(?=\.\d+\.dar)' | sort | uniq)
    if [ $files_count -eq 0 ]; then
        echo "Failed to find files to test"
        exit 2
    fi
}

if [ $# -lt 1 ]; then
    echo "At least 1 arguments required. create or test"
    exit -1
fi

case "$1" in
"create")
    shift
    create "$@"
    ;;
"test")
    shift
    test "$@"
    ;;
*)
    echo "Unsupported action '$1'"
    exit -2
    ;;

esac
