#!/bin/env bash
set -Eeuo pipefail

function get_docker_compose() {
  echo "$1/docker-compose.yml"
}

function get_docker_status() {
  [ -z "$(docker-compose -f "$docker_compose" top)" ] && (
    echo "stopped"
  ) || (
    echo "running"
  )
}

dir=$(dirname "$(readlink -f -- "$0")")
image=$(basename "$dir")-dar
temp="$(mktemp --directory --tmpdir="$2")"
docker_compose=$(get_docker_compose "$1")
docker_status=$(get_docker_status "$docker_compose")

function build_image() {
  docker build "$dir/dar/image" -t "$image"
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
  echo "File: $(basename "$file")($(du --summarize --bytes "$file" | cut -f 1 | numfmt --grouping) bytes)"
  mv "$file" "$backup_path"
}

function start_docker() {
  if ! docker-compose -f "$docker_compose" up -d; then
    echo error starting container
    exit
  fi
}

function stop_docker() {
  if ! docker-compose -f "$docker_compose" stop; then
    echo error stopping container
    exit
  fi
}

function create_archive() {
  local last_dar=$(find "$2" -maxdepth 1 -type f -name "*.dar" -printf '%T@\t%p\n' | sort -n | tail -1 | cut -f2-)
  local last_archive=${last_dar%.*.*}
  if [ -z "$last_archive" ]; then
    local archive=full
    docker run --rm -v "$1:/files" -v "$temp:/data" "$image" --create "/data/full" --fs-root "/files" -Q --no-overwrite --compress=zstd >/dev/null
    echo "$temp/$archive"
  else
    local archive=incremental-$(date +%F-%T | sed 's/:/-/g')
    docker run --rm -v "$1:/files" -v "$temp:/data" -v "$last_dar:/ref.1.dar" "$image" --create "/data/$archive" --ref "/ref" --fs-root "/files" -Q --no-overwrite --compress=zstd >/dev/null
    echo "$temp/$archive"
  fi
}

function cleanup() {
  [ "$docker_status" == "running" ] && (
    start_docker "$docker_compose"
  )
  [ -d "$temp" ] && (
    rm -rf "$temp"
  )
}

trap cleanup EXIT

build_image
main "$1" "$2"
