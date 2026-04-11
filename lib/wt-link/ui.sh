# shellcheck shell=bash
# ui.sh — Output helpers for wt-link.
# Globals inherited from bin/wt-link — colour vars may be empty on no-colour terminals:
: "${BOLD-}" "${CYAN-}" "${GREEN-}" "${YELLOW-}" "${RED-}" "${RESET-}"

log()     { echo -e "${BOLD}${CYAN}▶ $*${RESET}"; }
success() { echo -e "${GREEN}✓ $*${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $*${RESET}"; }
error()   { echo -e "${RED}✗ $*${RESET}" >&2; exit 1; }
step()    { echo -e "  ${BOLD}$*${RESET}"; }
