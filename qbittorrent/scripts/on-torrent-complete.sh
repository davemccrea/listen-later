#!/usr/bin/env bash
# Run by qBittorrent when a torrent finishes:
#   on-torrent-complete.sh "%L" "%F" "%N"
#
# Hardlinks the finished download into Calibre-Web-Automated's ingest folder or
# the Audiobookshelf library. Hardlinks rather than copies, so the torrent keeps
# seeding from the same bytes, the library copy costs no extra disk, and CWA is
# free to delete what it ingests without touching the seeding copy. Renaming the
# library copy is likewise safe — it is a separate directory entry.
#
# Torrents in any other category are left alone.
#
# The qBittorrent side of this lives in ./config, which is gitignored, so for the
# record it needs:
#   Options > Downloads > Run external program on torrent finished:
#     /scripts/on-torrent-complete.sh "%L" "%F" "%N"
#   Categories with save paths: ebooks -> /downloads/ebooks
#                               audiobooks -> /downloads/audiobooks
#   Automatic Torrent Management on by default, so those save paths are used.
set -euo pipefail

category=${1:-}
content_path=${2:-}
name=${3:-}

ingest_dir=/downloads/_ingest
audiobook_dir=/downloads/_library/audiobooks/_incoming
staging_dir=/downloads/_staging
log_file=/config/qBittorrent/logs/import.log

log() {
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >>"$log_file"
}

# Lower rank wins when a release ships the same book in several formats, so
# Calibre gets one copy per book instead of one per format.
format_rank() {
    case ${1,,} in
        epub) echo 1 ;;
        azw3) echo 2 ;;
        mobi) echo 3 ;;
        pdf)  echo 4 ;;
        cbz)  echo 5 ;;
        cbr)  echo 6 ;;
        *)    echo 99 ;;
    esac
}

# Hardlink into staging, then rename into place. Creating a hardlink fires only
# IN_CREATE, and CWA's ingest watcher listens for close_write and moved_to only,
# so a link made directly in the ingest folder is never noticed. The rename gives
# it the moved_to it wants, and makes the file appear atomically either way.
link_into() {
    local src=$1 dest=$2 tmp
    if [[ -e $dest ]]; then
        log "skip, already present: $dest"
        return
    fi
    tmp=$staging/$(basename "$dest")
    if [[ -d $src ]]; then
        cp -al "$src" "$tmp"    # recursive hardlink of the whole release
    else
        ln "$src" "$tmp"
    fi
    mkdir -p "$(dirname "$dest")"
    mv "$tmp" "$dest"
    log "linked: $src -> $dest"
}

ingest_ebooks() {
    local -A best_file=() best_rank=()
    local file ext rank key

    while IFS= read -r -d '' file; do
        ext=${file##*.}
        if [[ $ext == "$file" ]]; then
            continue
        fi
        rank=$(format_rank "$ext")
        if (( rank == 99 )); then
            continue    # cover art, .nfo, .txt
        fi
        key=${file%.*}  # same book, different format
        if [[ -z ${best_rank[$key]:-} ]] || (( rank < best_rank[$key] )); then
            best_rank[$key]=$rank
            best_file[$key]=$file
        fi
    done < <(find "$content_path" -type f -print0)

    if (( ${#best_file[@]} == 0 )); then
        log "no supported ebook format in $content_path"
        return
    fi

    for key in "${!best_file[@]}"; do
        file=${best_file[$key]}
        link_into "$file" "$ingest_dir/$(basename "$file")"
    done
}

ingest_audiobook() {
    link_into "$content_path" "$audiobook_dir/$name"
}

if [[ $category != ebooks && $category != audiobooks ]]; then
    exit 0
fi

mkdir -p "$(dirname "$log_file")" "$ingest_dir" "$audiobook_dir" "$staging_dir"

# Staging must share a mount with both source and destination: hardlinks cannot
# cross mount points, and the rename below has to stay a rename, not a copy.
staging=$(mktemp -d "$staging_dir/XXXXXXXX")
trap 'rm -rf "$staging"' EXIT

if [[ -z $content_path || ! -e $content_path ]]; then
    log "content path missing for '$name' (category '$category')"
    exit 1
fi

case $category in
    ebooks)     ingest_ebooks ;;
    audiobooks) ingest_audiobook ;;
esac
