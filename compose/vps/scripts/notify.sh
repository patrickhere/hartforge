#!/bin/bash
# notify.sh - VPS notification path. SLACK FIRST, ntfy as the fallback.
#
#   notify.sh [-t alerts|news] [-T title] [-p 1-5] [-g tag] -- "body"
#
# WHY THIS EXISTS: the six scripts in /opt/scripts each raw-curled ntfy, so every
# VPS alert reached the phone and never landed in slack. slack is the primary
# sink; ntfy is what catches the case where slack is unreachable.
#
# WHY A WEBHOOK AND NOT THE BOT TOKEN: this box is publicly exposed. a webhook
# can only post to the single channel it is bound to; the bot token can post
# anywhere the bot is. for the same reason there is no `op` CLI here - the
# service account token unlocks the entire vault, and this host is shipped only
# the handful of secrets it needs, by homelab-compose/render-env.sh on the mac.
#
# ONE WEBHOOK MEANS ONE CHANNEL. topic routing (alerts -> #alerts,
# news -> #briefing) is what the mac's bot token does and a webhook cannot. until
# a second webhook exists for #briefing, `-t news` still delivers - it just lands
# in the webhook's channel with a [news] prefix rather than being routed.

set -uo pipefail

# shellcheck source=/dev/null
[ -r /opt/scripts/.env ] && . /opt/scripts/.env

SERVER="https://ntfy.hartforge.dev"
topic="homelab-alerts"; title=""; priority="3"; tags=""; click=""

while [ $# -gt 0 ]; do
  case "$1" in
    -t) case "${2:-}" in
          alerts) topic="homelab-alerts" ;;
          news)   topic="homelab-news" ;;
          *)      topic="${2:-homelab-alerts}" ;;
        esac; shift 2 ;;
    -T) title="${2:-}"; shift 2 ;;
    -p) priority="${2:-3}"; shift 2 ;;
    -g) tags="${2:-}"; shift 2 ;;
    # ntfy's "Actions:" button has no webhook equivalent, so a link becomes a
    # link in the slack text and stays a Click header on the ntfy side.
    -c) click="${2:-}"; shift 2 ;;
    --) shift; break ;;
    -*) echo "notify: unknown flag $1" >&2; exit 1 ;;
    *)  break ;;
  esac
done

body="$*"
[ -n "$body" ] || { echo "notify: empty body" >&2; exit 1; }

slack_err=""
posted_slack=0

if [ -n "${SLACK_WEBHOOK:-}" ]; then
  # a news item through the alerts webhook is labelled rather than silently
  # misfiled, so it is obvious which ones want the second webhook.
  prefix=""
  [ "$topic" = "homelab-news" ] && prefix="[news] "
  text="$prefix"
  [ -n "$title" ] && text="${text}*${title}*"$'\n'
  text="${text}${body}"
  [ -n "$click" ] && text="${text}"$'\n'"${click}"

  payload="$(python3 -c 'import json,sys; print(json.dumps({"text": sys.argv[1], "unfurl_links": False}))' "$text" 2>/dev/null)"
  if [ -n "$payload" ]; then
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
            -H 'Content-Type: application/json' -d "$payload" "$SLACK_WEBHOOK" 2>/dev/null)"
    if [ "$code" = "200" ]; then posted_slack=1; else slack_err="http $code"; fi
  else
    slack_err="payload build failed"
  fi
else
  slack_err="no webhook in /opt/scripts/.env"
fi

# ntfy: a short pointer when slack worked, the full body when it did not. an
# alert that only exists in a channel nobody is looking at is not an alert.
if [ "$posted_slack" = 1 ]; then
  ntfy_body="check slack"
  ntfy_prio="$priority"
else
  ntfy_body="$body"
  ntfy_prio="$priority"
fi

http="$(curl -s -o /dev/null -w '%{http_code}' --max-time 15 \
        -u "${NTFY_USER:-}:${NTFY_PASS:-}" \
        -H "Title: ${title:-homelab}" \
        -H "Priority: $ntfy_prio" \
        ${tags:+-H "Tags: $tags"} \
        ${click:+-H "Click: $click"} \
        -d "$ntfy_body" "$SERVER/$topic" 2>/dev/null)"

if [ "$posted_slack" = 1 ]; then
  echo "sent to slack (ntfy ping $http)"
  exit 0
fi

echo "slack failed ($slack_err); full body sent over ntfy $topic (http $http)" >&2
# still exit 0 when ntfy took it - the message was delivered, just not to slack.
[ "$http" = "200" ] && exit 0
echo "DELIVERY FAILED: slack=$slack_err ntfy=$http" >&2
exit 1
