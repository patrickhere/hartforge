#!/usr/bin/env zsh
# HartForge MOTD (macOS) — Catppuccin Mocha, with a small Pokémon buddy.
# Sprite sits left of the stat panel when it fits $COLUMNS, else stacks below.
# Shared across all Mac hosts; the subtitle nickname is resolved by Tailscale IP below.

# Invoked from .zprofile before .zshrc sets PATH — make sure our tools resolve.
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

emulate -L zsh
setopt no_nomatch

# ── Catppuccin Mocha palette (truecolor) ─────────────────────────────
autoload -U colors
RS=$'\033[0m'
c() { print -n -- $'\033[38;2;'"$1"'m' }   # fg from "r;g;b"
MAUVE="$(c '203;166;247')"; LAV="$(c '180;190;254')"; BLUE="$(c '137;180;250')"
SKY="$(c '137;220;235')";   GRN="$(c '166;227;161')"; YEL="$(c '249;226;175')"
RED="$(c '243;139;168')";   PCH="$(c '250;179;135')"; TEAL="$(c '148;226;213')"
TXT="$(c '205;214;244')";   SUB="$(c '166;173;200')"; OVL="$(c '108;112;134')"
BLD=$'\033[1m'

# ── Pokémon buddy (rare shiny, like the games) ───────────────────────
SHINY=""
if (( RANDOM % 128 == 0 )); then
  RAW="$(pokemon-colorscripts -r --shiny 2>/dev/null)"; SHINY=" ${YEL}✨shiny${RS}"
else
  RAW="$(pokemon-colorscripts -r 2>/dev/null)"
fi
POKE_NAME="${RAW%%$'\n'*}"                 # first line = name
POKE_BODY="${RAW#*$'\n'}"                   # rest = sprite
sprite=("${(@f)POKE_BODY}")

# visible width of a string (strip ANSI, count chars)
vislen() { local s; s="$(print -r -- "$1" | sed $'s/\x1b\\[[0-9;]*m//g')"; print -r -- ${#s} }
SPRITE_W=0
for l in "$sprite[@]"; do w=$(vislen "$l"); (( w > SPRITE_W )) && SPRITE_W=$w; done

# ── System info ──────────────────────────────────────────────────────
HNAME="$(scutil --get ComputerName 2>/dev/null || hostname -s)"
OSV="macOS $(sw_vers -productVersion)"
MODEL="$(sysctl -n machdep.cpu.brand_string 2>/dev/null)"
DATE="$(date '+%A, %B %-d · %H:%M')"
IP="$(ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 2>/dev/null || echo 'offline')"
if command -v tailscale &>/dev/null; then TS="$(tailscale ip -4 2>/dev/null | head -1)"; fi

# HartForge blacksmith naming scheme, keyed off Tailscale IP (stable per host)
case "$TS" in
  100.112.186.36) NICK="the anvil" ;;      # Mac Mini — always-on homelab
  100.90.89.126)  NICK="the workbench" ;;  # MacBook — portable dev machine
  *)              NICK="$HNAME" ;;
esac

# uptime
BOOT=$(sysctl -n kern.boottime | sed -n 's/.*{ sec = \([0-9]*\).*/\1/p')
UP=$(( $(date +%s) - BOOT )); D=$((UP/86400)); H=$(((UP%86400)/3600)); M=$(((UP%3600)/60))
UPTIME=""; (( D>0 )) && UPTIME="${D}d "; (( H>0 )) && UPTIME="${UPTIME}${H}h "; UPTIME="${UPTIME}${M}m"

# load
LOAD="$(sysctl -n vm.loadavg | awk '{print $2" "$3" "$4}')"

# memory via vm_stat (fast; active+wired+compressed as "used")
PS=$(sysctl -n hw.pagesize); MEM_TOTAL=$(( $(sysctl -n hw.memsize)/1024/1024/1024 ))
USED_PAGES=$(vm_stat | awk '/Pages active/{a=$3}/Pages wired/{w=$4}/Pages occupied by compressor/{c=$5}END{gsub(/\./,"",a);gsub(/\./,"",w);gsub(/\./,"",c);print a+w+c}')
MEM_USED=$(( USED_PAGES * PS / 1024/1024/1024 )); MEM_PCT=$(( MEM_USED*100/MEM_TOTAL ))
(( MEM_PCT>=90 )) && MC=$RED || { (( MEM_PCT>=70 )) && MC=$YEL || MC=$TXT; }

# disk
read DISK_USED DISK_TOTAL DISK_PCT <<< "$(df -h / | awk 'NR==2{gsub(/%/,"",$5);print $3,$2,$5}')"
(( DISK_PCT>=90 )) && DC=$RED || { (( DISK_PCT>=70 )) && DC=$YEL || DC=$TXT; }

# docker (running / total)
DOCKER=""
if command -v docker &>/dev/null && docker info &>/dev/null; then
  DOCKER="$(docker ps -q 2>/dev/null | grep -c .) running / $(docker ps -aq 2>/dev/null | grep -c .) total"
fi

# service (from /etc/hartforge.conf, if present)
SVC="" SVC_COLOR=$GRN
if [[ -f /etc/hartforge.conf ]]; then
  source /etc/hartforge.conf
  if [[ -n "$SVC_NAME" && -n "$SVC_CHECK" ]]; then
    if eval "$SVC_CHECK" &>/dev/null; then SVC="${SVC_NAME} running"; SVC_COLOR=$GRN
    else SVC="${SVC_NAME} stopped"; SVC_COLOR=$RED; fi
  fi
fi

# ── Build panel rows (colored string per line) ───────────────────────
sep="${OVL}────────────────────────────────${RS}"
row() { printf "${SUB}%-8s${RS}%s" "$1" "$2" }   # label + value -> string
panel=(
  "${MAUVE}${BLD}H A R T   F O R G E${RS}"
  "${OVL}${NICK}${RS}"
  ""
  "$(row Host   "${TXT}${HNAME}${RS}")"
  "$(row OS     "${TXT}${OSV}${RS}")"
  "$(row Uptime "${TXT}${UPTIME}${RS}")"
  "$(row Buddy  "${TEAL}${POKE_NAME}${RS}${SHINY}")"
  "$sep"
  "$(row CPU    "${TXT}${LOAD}${RS}  ${OVL}${MODEL}${RS}")"
  "$(row Memory "${MC}${MEM_USED}G / ${MEM_TOTAL}G  (${MEM_PCT}%)${RS}")"
  "$(row Disk   "${DC}${DISK_USED} / ${DISK_TOTAL}  (${DISK_PCT}%)${RS}")"
)
[[ -n "$DOCKER" ]] && panel+=("$(row Docker "${TXT}${DOCKER}${RS}")")
[[ -n "$SVC" ]]    && panel+=("$(row Service "${SVC_COLOR}${SVC}${RS}")")
panel+=("$(row Network "${TXT}${IP}${RS}${TS:+  ${SUB}ts ${SKY}$TS${RS}}")")
panel+=("$sep")
panel+=("${OVL}${DATE}${RS}")

# panel display width
PANEL_W=0
for l in "$panel[@]"; do w=$(vislen "$l"); (( w > PANEL_W )) && PANEL_W=$w; done

# ── Layout: side-by-side if it fits, else stacked ────────────────────
GUT=3
COLS=${COLUMNS:-$(tput cols 2>/dev/null || echo 80)}
print ""
if (( SPRITE_W + GUT + PANEL_W <= COLS )); then
  # vertically center the shorter block
  S=$#sprite; P=$#panel; R=$(( S>P ? S : P ))
  s_off=$(( P>S ? (P-S)/2 : 0 )); p_off=$(( S>P ? (S-P)/2 : 0 ))
  pad="$(printf '%*s' $SPRITE_W '')"
  for (( i=1; i<=R; i++ )); do
    si=$(( i - s_off )); pi=$(( i - p_off ))
    if (( si>=1 && si<=S )); then
      line="$sprite[$si]"; fill=$(( SPRITE_W - $(vislen "$line") ))
      printf '%s%s%*s' "$line" "$RS" $fill ''
    else
      print -n -- "$pad"
    fi
    printf '%*s' $GUT ''
    (( pi>=1 && pi<=P )) && print -r -- "$panel[$pi]" || print ""
  done
else
  # stacked: panel first, then the (wide) sprite below
  for l in "$panel[@]"; do print -r -- "  $l"; done
  print ""
  print -r -- "$POKE_BODY"
fi
print ""
