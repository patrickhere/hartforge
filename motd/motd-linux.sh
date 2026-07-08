#!/bin/bash
# HartForge MOTD (Linux) — Catppuccin Mocha, with a small Pokémon buddy when available.
# Sprite sits left of the stat panel when it fits $COLUMNS, else stacks below.
# If pokemon-colorscripts isn't installed, the Buddy row and sprite are skipped gracefully.
# Shared across all Linux hosts; the subtitle nickname is resolved by Tailscale IP below.

export PATH="$PATH:/usr/local/bin:/root/.local/bin:$HOME/.local/bin"

# ── Catppuccin Mocha palette (truecolor) ──────────────────────────────
RS=$'\033[0m'
c() { printf '\033[38;2;%sm' "$1"; }
MAUVE="$(c '203;166;247')"; LAV="$(c '180;190;254')"; BLUE="$(c '137;180;250')"
SKY="$(c '137;220;235')";   GRN="$(c '166;227;161')"; YEL="$(c '249;226;175')"
RED="$(c '243;139;168')";   PCH="$(c '250;179;135')"; TEAL="$(c '148;226;213')"
TXT="$(c '205;214;244')";   SUB="$(c '166;173;200')"; OVL="$(c '108;112;134')"
BLD=$'\033[1m'

# ── System info ────────────────────────────────────────────────────────
HNAME=$(hostname -s 2>/dev/null || hostname)
OSV=$(grep ^PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"')
DATE=$(date '+%A, %B %-d · %H:%M')
IP=$(hostname -I 2>/dev/null | awk '{print $1}')
TS=""
if command -v tailscale &>/dev/null; then TS="$(tailscale ip -4 2>/dev/null | head -1)"; fi

# HartForge blacksmith naming scheme, keyed off Tailscale IP (stable per host)
case "$TS" in
  100.70.8.13) NICK="the outpost" ;;  # VPS — remote/cloud
  *)           NICK="$HNAME" ;;
esac

# uptime
UPTIME=$(uptime -p 2>/dev/null | sed 's/^up //')

# load
read -r L1 L5 L15 _ < /proc/loadavg
LOAD="$L1 $L5 $L15"

# memory
read -r MEM_TOTAL MEM_AVAIL <<< "$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%d %d", t/1024/1024, a/1024/1024}' /proc/meminfo)"
MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
MEM_PCT=0
[ "$MEM_TOTAL" -gt 0 ] 2>/dev/null && MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
if [ "$MEM_PCT" -ge 90 ]; then MC=$RED; elif [ "$MEM_PCT" -ge 70 ]; then MC=$YEL; else MC=$TXT; fi

# disk
read -r DISK_USED DISK_TOTAL DISK_PCT <<< "$(df -h / | awk 'NR==2{gsub(/%/,"",$5); print $3, $2, $5}')"
if [ "$DISK_PCT" -ge 90 ] 2>/dev/null; then DC=$RED; elif [ "$DISK_PCT" -ge 70 ] 2>/dev/null; then DC=$YEL; else DC=$TXT; fi

# docker (running / total)
DOCKER=""
if command -v docker &>/dev/null && docker info &>/dev/null; then
  D_RUNNING=$(docker ps -q 2>/dev/null | wc -l | tr -d ' ')
  D_TOTAL=$(docker ps -aq 2>/dev/null | wc -l | tr -d ' ')
  DOCKER="${D_RUNNING} running / ${D_TOTAL} total"
fi

# service (from /etc/hartforge.conf, if present)
SVC="" SVC_COLOR=$GRN
if [ -f /etc/hartforge.conf ]; then
  . /etc/hartforge.conf
  if [ -n "$SVC_NAME" ] && [ -n "$SVC_CHECK" ]; then
    if eval "$SVC_CHECK" &>/dev/null; then SVC="${SVC_NAME} running"; SVC_COLOR=$GRN
    else SVC="${SVC_NAME} stopped"; SVC_COLOR=$RED; fi
  fi
fi

# visible width of a string (strip ANSI, count chars)
vislen() { local s; s=$(printf '%s' "$1" | sed $'s/\x1b\\[[0-9;]*m//g'); printf '%s' "${#s}"; }

# ── Pokémon buddy (rare shiny, like the games) — optional ─────────────
POKE_NAME="" SHINY="" SPRITE_W=0
sprite=()
if command -v pokemon-colorscripts &>/dev/null; then
  if (( RANDOM % 128 == 0 )); then
    RAW="$(pokemon-colorscripts -r --shiny 2>/dev/null)"; SHINY=" ${YEL}✨shiny${RS}"
  else
    RAW="$(pokemon-colorscripts -r 2>/dev/null)"
  fi
  POKE_NAME="${RAW%%$'\n'*}"
  POKE_BODY="${RAW#*$'\n'}"
  mapfile -t sprite <<< "$POKE_BODY"
  for l in "${sprite[@]}"; do w=$(vislen "$l"); (( w > SPRITE_W )) && SPRITE_W=$w; done
fi

# ── Build panel rows (colored string per line) ─────────────────────────
sep="${OVL}────────────────────────────────${RS}"
row() { printf "${SUB}%-8s${RS}%s" "$1" "$2"; }
panel=(
  "${MAUVE}${BLD}H A R T   F O R G E${RS}"
  "${OVL}${NICK}${RS}"
  ""
  "$(row Host   "${TXT}${HNAME}${RS}")"
  "$(row OS     "${TXT}${OSV}${RS}")"
  "$(row Uptime "${TXT}${UPTIME}${RS}")"
)
[ -n "$POKE_NAME" ] && panel+=("$(row Buddy "${TEAL}${POKE_NAME}${RS}${SHINY}")")
panel+=(
  "$sep"
  "$(row CPU    "${TXT}${LOAD}${RS}")"
  "$(row Memory "${MC}${MEM_USED}G / ${MEM_TOTAL}G  (${MEM_PCT}%)${RS}")"
  "$(row Disk   "${DC}${DISK_USED} / ${DISK_TOTAL}  (${DISK_PCT}%)${RS}")"
)
[ -n "$DOCKER" ] && panel+=("$(row Docker "${TXT}${DOCKER}${RS}")")
[ -n "$SVC" ]    && panel+=("$(row Service "${SVC_COLOR}${SVC}${RS}")")
panel+=("$(row Network "${TXT}${IP}${RS}${TS:+  ${SUB}ts ${SKY}${TS}${RS}}")")
panel+=("$sep")
panel+=("${OVL}${DATE}${RS}")

PANEL_W=0
for l in "${panel[@]}"; do w=$(vislen "$l"); (( w > PANEL_W )) && PANEL_W=$w; done

# ── Layout: side-by-side if a sprite exists and it fits, else stacked panel ──
GUT=3
COLS=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
echo ""
if [ "${#sprite[@]}" -gt 0 ] && (( SPRITE_W + GUT + PANEL_W <= COLS )); then
  S=${#sprite[@]}; P=${#panel[@]}; R=$(( S>P ? S : P ))
  s_off=$(( P>S ? (P-S)/2 : 0 )); p_off=$(( S>P ? (S-P)/2 : 0 ))
  pad=$(printf '%*s' "$SPRITE_W" '')
  for (( i=0; i<R; i++ )); do
    si=$(( i - s_off )); pi=$(( i - p_off ))
    if (( si>=0 && si<S )); then
      line="${sprite[$si]}"; fill=$(( SPRITE_W - $(vislen "$line") ))
      printf '%s%s%*s' "$line" "$RS" "$fill" ''
    else
      printf '%s' "$pad"
    fi
    printf '%*s' "$GUT" ''
    if (( pi>=0 && pi<P )); then printf '%s\n' "${panel[$pi]}"; else echo ""; fi
  done
else
  for l in "${panel[@]}"; do printf '  %s\n' "$l"; done
fi
echo ""
