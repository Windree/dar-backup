#!/bin/env bash
set -Eeuxo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/functions/requires.sh"

requires locale basename mktemp docker mv du numfmt

function get_docker_compose() {
  echo "$1/docker-compose.yml"
}

function get_docker_status() {
  if [ -z "$(docker compose -f "$docker_compose" top)" ]; then
    echo "stopped"
  else
    echo "running"
  fi
}

locale=$((locale -a | grep en_AU || true) | head -n 1)
docker_compose=$(get_docker_compose "$1")
docker_status=$(get_docker_status "$docker_compose")
dir=$(dirname "$(readlink -f -- "$0")")
image=$(basename "$dir")-dar
temp="$(mktemp --directory --tmpdir="$2")"

function build_image() {
  local image_path=$dir/dar/image
  if ! docker build --quiet "$image_path" -t "$image" 2>/dev/null >/dev/null; then
    echo "Error build '$image_path'"
    exit 255
  fi
}

function main() {
  local source_path=$1
  local backup_path=$2
  if [ "$docker_status" == "running" ]; then
    echo "Stoping docker..."
    stop_docker "$source_path"
  fi
  echo "Creating archive..."
  local archive=$(create_archive "$source_path" "$backup_path")
  if [ "$docker_status" == "running" ]; then
    echo "Staring docker..."
    start_docker "$source_path"
  fi
  docker_status=""
  echo "Testing..."
  local file=$archive.1.dar
  if ! docker run --rm -v "$file:/data.1.dar" "$image" --test "/data" -Q; then
    echo "Test failed!"
    exit 1
  fi
  echo "File: $(basename "$file")($(du --summarize --bytes "$file" | cut -f 1 | LC_ALL=$locale numfmt --grouping) bytes)"
  mv "$file" "$backup_path"
}

function start_docker() {
    if ! docker compose -f "$docker_compose" up -d; then
    echo error starting container
    exit 2
  fi
}

function stop_docker() {
  if ! docker compose -f "$docker_compose" stop; then
    echo error stopping container
    exit 3
  fi
}

function create_archive() {
  local last_dar=$(find "$2" -maxdepth 1 -type f -name "*.dar" -printf '%T@\t%p\n' | sort -n | tail -1 | cut -f2-)
  local last_archive=${last_dar%.*.*}
  if [ -z "$last_archive" ]; then
    local name=full
    docker run --rm -v "$1:/files" -v "$temp:/data" "$image" --create "/data/$name" --fs-root "/files" -Q --no-overwrite --compress=zstd 1>/dev/null
    echo "$temp/$name"
  else
    local name=incremental-$(date +%F-%T | sed 's/:/-/g')
    docker run --rm -v "$1:/files" -v "$temp:/data" -v "$last_dar:/ref.1.dar" "$image" --create "/data/$name" --ref "/ref" --fs-root "/files" -Q --no-overwrite --compress=zstd 1>/dev/null
    echo "$temp/$name"
  fi
}

function cleanup() {
  if [ "$docker_status" == "running" ]; then
    start_docker "$docker_compose"
  fi
  if [ -d "$temp" ]; then
    rm -rf "$temp"
  fi
}

trap cleanup exit

build_image
main "$1" "$2"
