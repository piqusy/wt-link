# shellcheck shell=bash
# runtime.sh — Package manager runners and spinner/polling helpers for wt-link.

run_pm_install() {
    local pm="$1" dir="$2"
    case "$pm" in
        bun)  bun install --cwd="$dir" ;;
        yarn) yarn install --cwd "$dir" ;;
        pnpm) pnpm install --dir "$dir" ;;
        npm)  npm install --prefix "$dir" ;;
    esac
}

run_pm_build() {
    local pm="$1" dir="$2"
    case "$pm" in
        bun)  (cd "$dir" && bun run build) ;;
        yarn) (cd "$dir" && yarn run build) ;;
        pnpm) (cd "$dir" && pnpm run build) ;;
        npm)  (cd "$dir" && npm run build) ;;
    esac
}

run_pm_start() {
    local pm="$1" dir="$2"
    case "$pm" in
        bun)  (cd "$dir" && bun start) ;;
        yarn) (cd "$dir" && yarn run start) ;;
        pnpm) (cd "$dir" && pnpm run start) ;;
        npm)  (cd "$dir" && npm run start) ;;
    esac
}

# run_with_spinner <label> <command> [args...]
#   Runs <command> in the background while showing a braille spinner.
#   stdout/stderr from the command are captured; on failure the last 5 lines
#   are printed to help diagnose the problem.
run_with_spinner() {
    local label="$1"; shift
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    local tmp_out
    tmp_out="$(mktemp)"

    printf "  %s %s" "${spinner:0:1}" "$label"

    "$@" >"$tmp_out" 2>&1 &
    local pid=$!

    while kill -0 "$pid" 2>/dev/null; do
        local spin_char="${spinner:$(( i % ${#spinner} )):1}"
        printf "\r  %s %s" "$spin_char" "$label"
        sleep 0.1
        i=$(( i + 1 ))
    done

    wait "$pid"
    local exit_code=$?

    printf "\r\033[K"

    if [[ $exit_code -ne 0 ]]; then
        warn "$label (exit $exit_code)"
        tail -5 "$tmp_out" | while IFS= read -r line; do echo "    $line"; done
    fi

    rm -f "$tmp_out"
    return $exit_code
}

# wait_pid_with_spinner <pid> <label>
#   Shows a braille spinner while waiting for an already-running background pid.
wait_pid_with_spinner() {
    local pid="$1" label="$2"
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0
    printf "  %s %s" "${spinner:0:1}" "$label"
    while kill -0 "$pid" 2>/dev/null; do
        printf "\r  %s %s" "${spinner:$(( i % ${#spinner} )):1}" "$label"
        sleep 0.1
        i=$(( i + 1 ))
    done
    printf "\r\033[K"
    wait "$pid"
    return $?
}

# wait_for_herd <domain> <timeout_secs>
#   Polls http:// and https:// for the domain until any HTTP response is received
#   or the timeout expires. Displays a spinner while waiting.
wait_for_herd() {
    local domain="$1"
    local timeout_secs="${2:-10}"
    local spinner='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local elapsed=0
    local interval=1

    # Give Herd a moment to update its config before we start polling
    sleep 0.5

    while (( elapsed < timeout_secs )); do
        local code_http code_https
        code_http="$(curl -sI --max-time 2 -o /dev/null -w '%{http_code}' "http://$domain/" 2>/dev/null || echo "000")"
        code_https="$(curl -sI --max-time 2 -o /dev/null -w '%{http_code}' "https://$domain/" 2>/dev/null || echo "000")"

        if [[ "$code_http" != "000" || "$code_https" != "000" ]]; then
            printf "\r\033[K"
            success "$domain is live"
            return 0
        fi

        local spin_char="${spinner:$(( elapsed % ${#spinner} )):1}"
        printf "\r  %s Waiting for %s to respond… (%ds)" "$spin_char" "$domain" "$elapsed"
        sleep "$interval"
        (( elapsed += interval )) || true
    done

    printf "\r\033[K"
    warn "$domain did not respond within ${timeout_secs}s — it may still be starting up"
}
