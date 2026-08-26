#!/usr/bin/env fish
set -g fish_trace 1
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
    
    set -l last_dar (find_last_archive "$target")
    
    if test -z "$last_dar"
        set -l name "full"
        log_info "Creating an archive: '$name'"
        if not dar --create "$temp/$name" --fs-root "$source" -Q --no-overwrite --compress=zstd $argv >/dev/null
            log_error "Failed to create an archive: '$name'"
            exit 1
        end
    else
        set -l last_ref (string replace -r '\.[^.]+\.[^.]+$' '' $last_dar)
        set -l name "incremental-"(date +%Y%m%d-%H%M%S)
        echo "Info: Creating an incremental archive '$name' based on '$last_ref'."
        if not dar --create "$temp/$name" --ref "$last_ref" --fs-root "$source" -Q --no-overwrite --compress=zstd $argv >/dev/null
            log_error "Failed to create an incremental archive"
            exit 1
        end
    end
    
    set -l size (du --total --bytes "$temp" | tail -n 1 | cut -f 1)
    set -l count (find "$temp" -type f | wc -l)
    mv "$temp"/* "$target"
    rm --dir $temp
    log_success "Archive created successfully"
    log_info "Size: $size bytes"
    log_info "Files: $count"
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
        log_error "Directory found but there no archives"
        exit 2
    end

    set -l index 0
    get_archives "$archive_dir" | while read -l archive_basename
        set index (math $index + 1)
        log_info "[$index/$count] extracting '$archive_basename'"
        if not dar -x "$archive_dir/$archive_basename" $argv --fs-root="$target" -Q --quiet -w -ae
            log_error "[$index/$count] extraction of '$archive_basename' failed"
            exit 1
        end
    end
    log_success "Completed"
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
    
    set -l source_temp (mktemp --directory --tmpdir="$temp_dir")
    set -l archive_temp (mktemp --directory --tmpdir="$temp_dir")
    log_info "Creating copy of the '$source'"
    cp -r "$source/." "$source_temp"
    log_info "Extracting the archive '$archive_dir'"
    extract "$archive_dir" "$archive_temp" -O
    if not diff -rq "$source_temp" "$archive_temp"
        log_error "Source and archive are not equal"
        remove "$source_temp" "$archive_temp"
        exit 1
    end
    remove "$source_temp" "$archive_temp"
    log_success "Source and archive are equal"
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

# Main Execution Guard
if test (count $argv) -lt 1
    echo "Usage: $_ {create|extract|verify} [args]"
    exit 1
end

set -l action $argv[1]
set -e argv[1] # Shift action out of arguments array

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
        log_error "Unsupported action '$action'"
        exit 1
end
