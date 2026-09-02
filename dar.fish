#!/usr/bin/env fish
# set -g fish_trace 1
set -g temp_files
set -g docker_compose_directory ""
set -g docker_compose_timeout 60
set -g docker_backup_service ".docker/backup/service"

function create
    set -l source "$argv[2]"
    set -l target "$argv[1]"
    set -e argv[1..2]

    if not test_writeable "$target"
        log_error "Target directory '$target' is not writable or does not exist."
        exit 1
    end

    if not test_readable "$source"
        log_error "Source directory '$source' is not readable or does not exist."
        exit 1
    end
    
    set -l temp (mktemp --directory --tmpdir="$target")
    set -a temp_files $temp
    
    set -l last_dar (find_last_archive "$target")

    save_docker_compose_state "$source"

    # dar directly opens the target files using special filesystem performance flags that unprivileged user namespaces (rootlesskit) actively block. Use -aa tag to block read ataime
    set -l common_flags "-aa" "-Q" "--no-overwrite" "--compress=zstd"
    if test -z "$last_dar"
        set -l name "full"
        log_info "Creating an archive: '$name'"
        set dar_output (dar --create "$temp/$name" --fs-root "$source" $common_flags $argv &| string collect)
        if test $status -ne 0
            log_error "Failed to create an archive: '$name'"
            # Print the captured output and warnings
            log_error "$dar_output"
            exit 1
        end
    else
        set -l last_ref (string replace -r '\.[^.]+\.[^.]+$' '' $last_dar)
        set -l name "incremental-"(date +%Y%m%d-%H%M%S)
        log_info "Creating an incremental archive '$name' based on '$last_ref'."
        set dar_output (dar --create "$temp/$name" --ref "$last_ref" --fs-root "$source" $common_flags $argv &| string collect)
        if test $status -ne 0
            log_error "Failed to create an incremental archive"
            # Print the captured output and warnings
            log_error "$dar_output"
            exit 1
        end
    end

    restore_docker_compose_state

    set -l size (du --total --bytes "$temp" | tail -n 1 | cut -f 1)
    set -l count (find "$temp" -type f | wc -l)
    
    if not mv "$temp"/* "$target"
        log_error "Failed to move created archive to the persistent storage"
        exit 1
    end

    log_success "Archive created successfully"
    log_info "Size: $size bytes"
    log_info "Files: $count"
end

function extract
    set -l archive_dir "$argv[1]"
    set -l target "$argv[2]"
    set -e argv[1..2]

    if not test_readable "$archive_dir"
        log_error "Archive directory '$archive_dir' is not readable or does not exist."
        exit 1
    end

    if not test_writeable "$target"
        log_error "Target directory '$target' is not writable or does not exist."
        exit 1
    end

    set -l count (get_archives "$archive_dir" | wc -l)
    if test $count -eq 0
        log_error "No archives found in the directory"
        exit 2
    end
    
    save_docker_compose_state "$target"

    set -l index 0
    get_archives "$archive_dir" | while read -l archive_basename
        set index (math $index + 1)
        log_info "[$index/$count] extracting '$archive_basename'"
        if not dar -x "$archive_dir/$archive_basename" --fs-root="$target" -Q --quiet -w -ae $argv
            log_error "[$index/$count] extraction of '$archive_basename' failed"
            exit 1
        end
    end

    restore_docker_compose_state

    log_success "Completed"
end

function verify
    set -l archive_dir "$argv[1]"
    set -e argv[1]
    
    if not test_readable "$archive_dir"
        log_error "Archive directory '$archive_dir' is not readable or does not exist."
        exit 1
    end

    set -l total (get_archives "$archive_dir" | wc -l)
    
    if test $total -eq 0
        log_error "Directory found but there no archives"
        exit 2
    end

    set -l index 0
    get_archives "$archive_dir" | while read -l archive_basename
        set index (math $index + 1)
        
        log_info "[$index/$total] verifying '$archive_basename'"
        if not dar --test "$archive_dir/$archive_basename" -Q --quiet $argv
            log_error "[$index/$total] verification of '$archive_basename' failed"
            exit 1
        end
    end
    log_success "No errors found"
end

function compare
    set -l archive_dir "$argv[1]"
    set -l source "$argv[2]"
    set -l temp_dir "$argv[3]"
    set -e argv[1..3]

    if not test_readable "$archive_dir"
        log_error "Archive directory '$archive_dir' is not readable or does not exist."
        exit 1
    end
    
    if not test_readable "$source"
        log_error "Source directory '$source' is not readable or does not exist."
        exit 1
    end

    if not test_writeable "$temp_dir"
        log_error "Temporary directory '$temp_dir' is not writable or does not exist."
        exit 1
    end
    
    set -l temp (mktemp --directory --tmpdir="$temp_dir")
    set -a temp_files $temp
    set -l source_temp "$temp/source"
    set -l archive_temp "$temp/archive"
    mkdir "$source_temp" "$archive_temp"

    save_docker_compose_state "$source"

    log_info "Creating temporary copy of the '$source'"
    cp -r "$source/." "$source_temp"

    restore_docker_compose_state

    log_info "Extracting the archive '$archive_dir'"
    extract "$archive_dir" "$archive_temp" -O $argv
    
    set results (diff -rq "$source_temp" "$archive_temp" | grep -vE " is a socket|Special file" &| string collect)

    if test (count $results) -gt 0
        log_error "Source and archive are not equal"
        printf "%s\n" $results
        exit 1
    end
    log_success "Source and archive are equal"
end

function save_docker_compose_state
    is_docker_compose_stopped "$argv[1]"; and return 0
    set -g docker_compose_directory "$argv[1]"
    log_info "Stopping the docker compose"
    if not stop_docker_containers "$argv[1]"
        log_error "Failed to stop docker compose"
        exit 1
    end
    log_info "Docker compose restart queued"
end

function restore_docker_compose_state
    test -z "$docker_compose_directory"; and return 0
    log_info "Executing queued docker compose restart"
    if not start_docker_containers "$docker_compose_directory"
        log_error "Failed to restart docker containers"
        exit 1
    end
    set -g docker_compose_directory ""
end

function is_docker_compose_stopped
    set -l file "$argv[1]/$docker_backup_service"
    set -l state (timeout $docker_compose_timeout "$file" state)
    test "$state" = "none"; and return 0
    return 1
end

function start_docker_containers
    set -l file "$argv[1]/$docker_backup_service"
    test ! -x "$file"; and return 0
    timeout $docker_compose_timeout "$file" start
    return $status
end

function stop_docker_containers
    set -l file "$argv[1]/$docker_backup_service"
    test ! -x "$file"; and return 0
    timeout $docker_compose_timeout "$file" stop; and return 0
    return 1
end

function get_archives
    find "$argv[1]" -maxdepth 1 -type f -name "*.*.dar" | grep -oP '[^/]+(?=\.\d+\.dar)' | sort | uniq
end

function find_last_archive
    find "$argv[1]" -maxdepth 1 -type f -name "*.*.dar" -printf '%T@\t%p\n' | sort -n | tail -1 | cut -f2-
end

function test_readable
    test -r "$argv[1]"
end

function test_writeable
    test -w "$argv[1]"
end

function remove
    rm -rf $argv
end

function log_info
    set_color cyan; echo -s "ℹ️  Info: " $argv; set_color normal
end

function log_success
    set_color green; echo -s "✅ OK: " $argv; set_color normal
end

function log_error
    set_color red; echo -s "❌ Error: " $argv; set_color normal
end

function on_exit --on-event fish_exit
    if test -n "$docker_compose_directory"
        log_error "Docker compose restart still queued before exit the program"
        if start_docker_containers "$docker_compose_directory"
            log_info "Docker compose restarted on exit"
        else
            log_error "Failed to start docker compose on exit"
            exit 2
        end
    end
    set -l count (count $temp_files)
    if test $count -gt 0
        log_info "Cleaning up $count temporary files or directories"
        rm -rf $temp_files
    end
end

set -l action $argv[1]
set -e argv[1]


switch "$action"
    case create
        create $argv
    case extract
        extract $argv
    case verify
        verify $argv
    case compare
        compare $argv
    case '*'
        echo ""
        echo "Usage:"
        echo "  $_ create  <target_dir> <source_dir> [dar_flags...]  - Create full or incremental backup"
        echo "  $_ extract <archive_dir> <target_dir> [dar_flags...] - Extract archives sequentially"
        echo "  $_ verify  <archive_dir> [dar_flags...]              - Test integrity of archives"
        echo "  $_ compare <archive_dir> <source_dir> <temp_dir>     - Compare filesystem state against archives using temporary directory"
        exit 1
end
