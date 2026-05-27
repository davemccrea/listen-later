#!/usr/bin/env bash
set -euo pipefail

STACKS_ROOT="${STACKS_ROOT:-$PWD}"

trap 'echo; echo "Interrupted."; exit 130' INT TERM

usage() {
    cat <<EOF
Usage: $(basename "$0") <docker compose args...>
       $(basename "$0") update   # pull then up -d --remove-orphans
       $(basename "$0") ports    # list host port mappings

Runs 'docker compose <args>' in every stack found under STACKS_ROOT.

Environment:
  STACKS_ROOT  Root to search for stacks (default: \$PWD)
EOF
    exit 1
}

find_stacks() {
    find "$STACKS_ROOT" \
        -maxdepth 3 \
        \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \
           -o -name "compose.yml"     -o -name "compose.yaml" \) \
        -not -path "*/node_modules/*" \
        -not -path "*/.git/*" \
        2>/dev/null \
        | xargs -I{} dirname {} \
        | sort -u
}

run_on_stacks() {
    local label="$1"; shift

    mapfile -t stacks < <(find_stacks)
    [[ ${#stacks[@]} -eq 0 ]] && { echo "No stacks found under: $STACKS_ROOT"; exit 1; }

    local failed=0
    for stack in "${stacks[@]}"; do
        echo "==> $(basename "$stack"): docker compose $label"
        if (cd "$stack" && docker compose "$@"); then
            :
        else
            echo "    FAILED"
            (( failed++ )) || true
        fi
        echo
    done

    (( failed > 0 )) && { echo "$failed stack(s) failed." >&2; exit 1; }
    return 0
}

[[ $# -eq 0 ]] && usage

case "$1" in
    help|-h|--help)
        usage
        ;;
    update)
        run_on_stacks "pull" pull
        run_on_stacks "up -d --remove-orphans" up -d --remove-orphans
        ;;
    ports)
        mapfile -t stacks < <(find_stacks)
        [[ ${#stacks[@]} -eq 0 ]] && { echo "No stacks found under: $STACKS_ROOT"; exit 1; }
        declare -a rows=()
        for stack in "${stacks[@]}"; do
            name=$(basename "$stack")
            compose_file=$(find "$stack" -maxdepth 1 \
                \( -name "docker-compose.yml" -o -name "docker-compose.yaml" \
                   -o -name "compose.yml"     -o -name "compose.yaml" \) \
                | head -1)
            while IFS= read -r line; do
                port="${line#"${line%%[![:space:]]*}"}"
                port="${port#- }"
                port="${port//\'/}"
                port="${port//\"/}"
                [[ "$port" =~ ^([0-9.]+:)?([0-9]+):([0-9]+) ]] || continue
                rows+=("${BASH_REMATCH[2]}|${name}|${BASH_REMATCH[0]}")
            done < <(grep -E "^\s+- ['\"]?[0-9]" "$compose_file" 2>/dev/null || true)
        done
        printf "%-20s %s\n" "STACK" "PORT MAPPING"
        printf "%-20s %s\n" "-----" "------------"
        if [[ ${#rows[@]} -gt 0 ]]; then
            IFS=$'\n' sorted=($(printf '%s\n' "${rows[@]}" | sort -t'|' -k1,1n)); unset IFS
            for row in "${sorted[@]}"; do
                name="${row#*|}"; name="${name%|*}"
                mapping="${row##*|}"
                printf "%-20s %s\n" "$name" "$mapping"
            done
        fi
        ;;
    *)
        run_on_stacks "$*" "$@"
        ;;
esac
