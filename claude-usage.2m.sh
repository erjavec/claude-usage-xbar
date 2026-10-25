#!/bin/bash
# <xbar.title>Claude Usage</xbar.title>
# <xbar.version>v2.3</xbar.version>
# <xbar.author>David Erjavec</xbar.author>
# <xbar.desc>Claude Code 5h + weekly rate-limit windows per saved account (cswitch), throttled+cached, plus today's tokens/cost (ccusage).</xbar.desc>
# <xbar.dependencies>bash,jq,curl,ccusage,cswitch</xbar.dependencies>
# <xbar.abouturl>https://github.com/erjavec/claude-usage-xbar</xbar.abouturl>

# xbar runs plugins without your shell profile: add the usual install locations
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$HOME/.bun/bin:$HOME/.volta/bin:/usr/bin:/bin:/usr/sbin:$PATH"
export LC_ALL=C  # force dot-decimal so printf/awk parse ccusage's numbers under comma locales
ENDPOINT="https://api.anthropic.com/api/oauth/usage"
BETA="oauth-2025-04-20"
PROFILE="https://api.anthropic.com/api/oauth/profile"
CACHEDIR="${CU_CACHEDIR:-$HOME/.cache/claude-usage}"   # one <label>.cache per account; CU_* override is for testing
MAXAGE=600  # only call the usage endpoint at most once per this many seconds per account (avoid HTTP 429)
ACCTDIR="${CSWITCH_DIR:-$HOME/.claude-accounts}"          # written by cswitch
SAVED_SVC="${CSWITCH_SAVED_SVC:-Claude Code-credentials (cswitch)}"
CSWITCH=$(command -v cswitch || true)                   # "Switch to" items are hidden without it

# ---- helpers ----
rnd(){ awk -v v="$1" 'BEGIN{if(v==""){exit} printf"%d",v+0.5}'; }
color(){ [ -z "$1" ]&&{ echo "#888888";return;}; [ "$1" -ge 90 ]&&{ echo red;return;}; [ "$1" -ge 70 ]&&{ echo orange;return;}; echo green; }
bar(){ local p=${1:-0} w=$2 f i o=""; f=$(((p*w+50)/100)); [ "$f" -gt "$w" ]&&f=$w; for((i=0;i<w;i++));do [ "$i" -lt "$f" ]&&o+="█"||o+="░";done; printf "%s" "$o"; }
human(){ awk -v n="${1:-0}" 'BEGIN{if(n>=1e6)printf"%.2fM",n/1e6;else if(n>=1e3)printf"%.0fk",n/1e3;else printf"%d",n}'; }
epoch(){ local iso=${1%%.*}; iso=${iso%Z}; iso=${iso%+00:00}; [ -z "$iso" ]&&return 1; date -j -u -f "%Y-%m-%dT%H:%M:%S" "$iso" +%s 2>/dev/null; }
passed(){ local t; t=$(epoch "$1")||return 1; [ "$t" -le "$(date -u +%s)" ]; }
countdown(){ local t n d; t=$(epoch "$1")||{ printf "?";return;}
  n=$(date -u +%s); d=$((t-n)); [ $d -lt 0 ]&&d=0
  [ $d -ge 86400 ]&&printf "%dd %dh" $((d/86400)) $(((d%86400)/3600))||printf "%dh %02dm" $((d/3600)) $(((d%3600)/60)); }
# secrets go through pipes: not argv (ps), not here-strings (bash 3.2 backs those with temp files)
cj(){ printf '%s' "$1" | jq -r "$2" 2>/dev/null; }
token_of(){ cj "$1" '.claudeAiOauth.accessToken // .accessToken // empty'; }
token_valid(){ local exp; exp=$(cj "$1" '.claudeAiOauth.expiresAt // 0 | floor'); [ "${exp:-0}" -gt $(( $(date +%s)*1000 + 60000 )) ]; }

# ---- active token ----
LIVE_CREDS=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
TOKEN=$(token_of "$LIVE_CREDS")
[ -z "$TOKEN" ] && [ -f "$HOME/.claude/.credentials.json" ] && TOKEN=$(token_of "$(cat "$HOME/.claude/.credentials.json")")

# ---- which saved account is active: the one the CLI (Keychain login) is on ----
# ~/.claude.json is not that: the Claude desktop app writes its own login into it. So ask the profile
# endpoint which org the Keychain token belongs to (cached per token, one call per token refresh).
live_org(){ local fp cf="$CACHEDIR/live-org" org=""
  [ -n "$TOKEN" ] || return 0
  fp=$(printf '%s' "$TOKEN" | shasum | cut -c1-12)
  if [ -f "$cf" ] && [ "$(cut -d' ' -f1 "$cf")" = "$fp" ]; then cut -d' ' -f2 "$cf"; return 0; fi
  org=$(printf 'Authorization: Bearer %s\nanthropic-beta: %s\n' "$TOKEN" "$BETA" \
    | curl -s -m 6 -H @- "$PROFILE" 2>/dev/null | jq -r '.organization.uuid // empty' 2>/dev/null)
  if [ -n "$org" ]; then mkdir -p "$CACHEDIR" 2>/dev/null && chmod 700 "$CACHEDIR" 2>/dev/null
    printf '%s %s\n' "$fp" "$org" > "$cf"; fi
  printf '%s' "$org"; }
JSON_ORG=$(jq -r '.oauthAccount.organizationUuid // empty' "$HOME/.claude.json" 2>/dev/null)
LIVE_ORG=$(live_org)
ACTIVE_ORG=${LIVE_ORG:-$JSON_ORG}   # offline or token expired: fall back to ~/.claude.json (checked below)
ACTIVE=""; JSON_LABEL=""; LABELS=()
for f in "$ACCTDIR"/*.oauth.json; do [ -e "$f" ] || continue
  l=$(basename "$f" .oauth.json); LABELS+=("$l")
  o=$(jq -r '.organizationUuid // empty' "$f")
  [ -n "$ACTIVE_ORG" ] && [ "$o" = "$ACTIVE_ORG" ] && ACTIVE=$l
  [ -n "$JSON_ORG" ] && [ "$o" = "$JSON_ORG" ] && JSON_LABEL=$l
done
ALABEL=${ACTIVE:-live}
# the desktop app (or a session) is on another account than the CLI: worth a note, not an alarm
DESKTOP=""; [ -n "$LIVE_ORG" ] && [ -n "$JSON_ORG" ] && [ "$LIVE_ORG" != "$JSON_ORG" ] && DESKTOP=${JSON_LABEL:-another account}
# fallback only: a session still running on the old account can write its token back after a switch, so
# without the profile answer the Keychain login may not match ~/.claude.json (plan type vs the saved login)
MISMATCH=""
if [ -z "$LIVE_ORG" ] && [ -n "$ACTIVE" ]; then
  ASUB=$(cj "$(security find-generic-password -s "$SAVED_SVC" -a "$ACTIVE" -w 2>/dev/null)" '.claudeAiOauth.subscriptionType // empty')
  LSUB=$(cj "$LIVE_CREDS" '.claudeAiOauth.subscriptionType // empty')
  [ -n "$ASUB" ] && [ -n "$LSUB" ] && [ "$ASUB" != "$LSUB" ] && MISMATCH="$LSUB"
fi

# ---- quota windows for one account: throttled endpoint call + last-good cache ----
# fetch <label> <token|empty>  -> sets F FR S SR OP OR CACHED_AT SRC HTTP
fetch(){ local label=$1 tok=$2 cache="$CACHEDIR/$1.cache" now fp resp body
  F=""; FR=""; S=""; SR=""; OP=""; OR=""; HTTP=""; SRC="none"; CACHED_AT=0; TOKFP=""
  now=$(date +%s)
  # shellcheck source=/dev/null
  [ -f "$cache" ] && . "$cache" 2>/dev/null
  [ -z "$CACHED_AT" ] && CACHED_AT=0
  if [ -n "$tok" ]; then
    # cache belongs to the token that produced it; a re-login invalidates it
    fp=$(printf "%s" "$tok" | shasum | cut -c1-12)
    if [ "$TOKFP" != "$fp" ] || [ $((now - CACHED_AT)) -ge "$MAXAGE" ]; then
      resp=$(printf 'Authorization: Bearer %s\nanthropic-beta: %s\n' "$tok" "$BETA" \
        | curl -s -m 8 -w $'\n%{http_code}' -H @- "$ENDPOINT")
      HTTP=$(printf "%s" "$resp"|tail -n1); body=$(printf "%s" "$resp"|sed '$d')
      if [ "$HTTP" = "200" ]; then
        F=$(rnd "$(jq -r '.five_hour.utilization // empty' <<<"$body")")
        FR=$(jq -r '.five_hour.resets_at // empty' <<<"$body")
        S=$(rnd "$(jq -r '.seven_day.utilization // empty' <<<"$body")")
        SR=$(jq -r '.seven_day.resets_at // empty' <<<"$body")
        OP=$(rnd "$(jq -r '.seven_day_opus.utilization // empty' <<<"$body")")
        OR=$(jq -r '.seven_day_opus.resets_at // empty' <<<"$body")
        mkdir -p "$CACHEDIR" 2>/dev/null && chmod 700 "$CACHEDIR" 2>/dev/null
        printf 'F=%q\nFR=%q\nS=%q\nSR=%q\nOP=%q\nOR=%q\nCACHED_AT=%q\nTOKFP=%q\n' "$F" "$FR" "$S" "$SR" "$OP" "$OR" "$now" "$fp" > "$cache"
        CACHED_AT=$now; SRC="live"; return
      fi
      [ "$CACHED_AT" -gt 0 ] && SRC="stale"   # call failed (e.g. 429) -> last good values
      return
    fi
    SRC="cache"; return                         # within throttle window -> no call
  fi
  [ "$CACHED_AT" -gt 0 ] && SRC="old"           # no usable token (inactive, expired) -> last known
}

# window line; a window whose reset time has passed is shown as reset (0%)
window(){ local name=$1 pct=$2 at=$3
  if [ -z "$at" ]; then
    echo "${name}  ${pct:-0}%  $(bar "${pct:-0}" 10) | font=Menlo color=$(color "${pct:-0}")"
    echo "no active window | size=11 color=#888888"
  elif passed "$at"; then
    echo "${name}  0%  $(bar 0 10) | font=Menlo color=green"
    echo "window reset since last reading | size=11 color=#888888"
  else
    echo "${name}  ${pct}%  $(bar "$pct" 10) | font=Menlo color=$(color "$pct")"
    echo "resets in $(countdown "$at") | size=11 color=#888888"
  fi; }

# ---- snapshot.json for other tools: labels, percentages and times only (no emails, orgs or tokens) ----
# snap_add <label>: append the account fetch() just read
SNAP=""
snap_add(){ local ra=""
  [ "${CACHED_AT:-0}" -gt 0 ] && ra=$(date -u -r "$CACHED_AT" +%Y-%m-%dT%H:%M:%SZ)
  SNAP+=$(jq -nc --arg l "$1" --arg ra "$ra" --arg src "$SRC" --arg f "$F" --arg fr "$FR" --arg s "$S" --arg sr "$SR" '
    def n: if . == "" then null else . end;
    {label:$l, read_at:($ra|n), source:$src,
     five_hour:{pct:($f|n|if .==null then null else tonumber end), resets_at:($fr|n)},
     seven_day:{pct:($s|n|if .==null then null else tonumber end), resets_at:($sr|n)}}')$'\n'; }
# written to a temp file, then moved into place, so readers never see half a file
write_snapshot(){ local tmp="$CACHEDIR/snapshot.json.$$"
  mkdir -p "$CACHEDIR" 2>/dev/null && chmod 700 "$CACHEDIR" 2>/dev/null
  if printf '%s' "$SNAP" | jq -s --arg a "$ACTIVE" --arg g "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '{version:1, generated_at:$g, active:(if $a == "" then null else $a end), accounts:.}' > "$tmp" 2>/dev/null \
     && chmod 600 "$tmp" && mv -f "$tmp" "$CACHEDIR/snapshot.json"; then :; else rm -f "$tmp"; fi; }

render(){ local label=$1 is_active=$2 head email org
  email=$(jq -r '.emailAddress // empty' "$ACCTDIR/$label.oauth.json" 2>/dev/null)
  org=$(jq -r '.organizationName // empty' "$ACCTDIR/$label.oauth.json" 2>/dev/null)
  head="$label"; [ "$is_active" = 1 ] && head="● $label (active)" || head="○ $label"
  echo "$head | color=$([ "$is_active" = 1 ] && echo '#4a9eff' || echo '#888888')"
  [ -n "$org" ] && echo "${org/$email\'s Organization/personal org} | size=11 color=#888888"
  if [ -z "$F" ] && [ -z "$S" ]; then
    if [ "$is_active" = 1 ] && [ -z "$TOKEN" ]; then
      echo "No Claude Code token in Keychain | color=red"
      echo "Sign in with Claude Code, then Refresh | size=11 color=#888888"
    elif [ "$is_active" = 1 ]; then
      echo "Rate-limit windows unavailable (HTTP ${HTTP:-none}) | color=orange"
    elif [ -n "$HTTP" ]; then
      echo "no reading yet (HTTP $HTTP) | size=11 color=#888888"
    else
      echo "no reading yet (saved token expired; switch to it once) | size=11 color=#888888"
    fi
    return
  fi
  local when=""; [ "$CACHED_AT" -gt 0 ] && when=$(date -r "$CACHED_AT" +"%d.%m %H:%M")
  [ "$SRC" = "old" ] && echo "last known · as of $when | size=11 color=#888888" \
                     || echo "as of ${when#* } | size=11 color=#888888"
  window "5-hour:" "$F" "$FR"
  window "7-day: " "$S" "$SR"
  [ -n "$OP" ] && window "7-day Opus:" "$OP" "$OR"
  [ "$SRC" = "stale" ] && echo "endpoint busy (HTTP ${HTTP}); showing last good values | size=11 color=orange"
  if [ "$is_active" = 0 ] && [ -x "$CSWITCH" ]; then
    echo "Switch to $label | bash=$CSWITCH param1=$label terminal=false refresh=true"
  fi
}

# active account first
fetch "$ALABEL" "$TOKEN"
[ -n "$ACTIVE" ] && snap_add "$ACTIVE"   # an unsaved login has no label: the snapshot says active: null
AF=$F; ASRC=$SRC; ACTIVE_OUT=$(render "$ALABEL" 1)

# inactive saved accounts: live while their saved access token is still valid, else last known
OTHER_OUT=""
for l in "${LABELS[@]}"; do
  [ "$l" = "$ACTIVE" ] && continue
  creds=$(security find-generic-password -s "$SAVED_SVC" -a "$l" -w 2>/dev/null)
  tok=""; token_valid "$creds" && tok=$(token_of "$creds")
  fetch "$l" "$tok"
  snap_add "$l"
  OTHER_OUT+=$'---\n'"$(render "$l" 0)"$'\n'
done
write_snapshot

# ---- tokens / cost (ccusage; local, cheap, refreshes every run; all accounts combined) ----
TODAY=$(date +%F)
DAY=$(ccusage daily --json 2>/dev/null)
BLK=$(ccusage blocks --active --json 2>/dev/null)
TC=$(jq -r --arg d "$TODAY" '.daily[]?|select(.period==$d)|.totalCost // empty' <<<"$DAY" 2>/dev/null)
TT=$(jq -r --arg d "$TODAY" '.daily[]?|select(.period==$d)|.totalTokens // empty' <<<"$DAY" 2>/dev/null)
BC=$(jq -r '.blocks[]?|select(.isActive==true)|.costUSD // empty' <<<"$BLK" 2>/dev/null)
BH=$(jq -r '.blocks[]?|select(.isActive==true)|.burnRate.costPerHour // empty' <<<"$BLK" 2>/dev/null)
PC=$(jq -r '.blocks[]?|select(.isActive==true)|.projection.totalCost // empty' <<<"$BLK" 2>/dev/null)

# ==== menu-bar title: active account initial + its 5-hour % ====
TAG=""; [ -n "$ACTIVE" ] && TAG="$(printf '%s' "${ACTIVE:0:1}" | tr '[:lower:]' '[:upper:]') "
if [ -n "$AF" ]; then
  MARK=""; [ "$ASRC" = "stale" ] && MARK="*"; [ -n "$MISMATCH" ] && MARK="!"
  echo "⏣ ${TAG}${AF}%${MARK} | color=$(color "$AF")"
elif [ -z "$TOKEN" ]; then
  echo "⏣ ⚠︎ | color=red"
else
  echo "⏣ ${TAG}— | color=#888888"
fi

echo "---"
echo "Rate-limit windows | size=11 color=#888888"
printf '%s\n' "$ACTIVE_OUT"
[ -n "$OTHER_OUT" ] && printf '%s' "$OTHER_OUT"
[ -z "$ACTIVE" ] && echo "this login is not saved — run: cswitch save <label> | size=11 color=orange"
[ -n "$MISMATCH" ] && echo "⚠ Keychain holds a $MISMATCH login, not '$ACTIVE' — a session wrote its token back; restart sessions, run: cswitch $ACTIVE | size=11 color=red"
[ -n "$DESKTOP" ] && echo "Claude desktop app is on $DESKTOP, not the CLI | size=11 color=#888888"

echo "---"
# ---- cost section ----
if [ -n "$DAY" ]; then
  echo "Tokens / cost (ccusage, all accounts) | size=11 color=#888888"
  printf 'Today:  $%.2f · %s tokens\n' "${TC:-0}" "$(human "${TT:-0}")"
  if [ -n "$BC" ]; then
    LINE=$(printf 'This block:  $%.2f' "$BC")
    [ -n "$BH" ] && LINE=$(printf '%s · $%.2f/hr' "$LINE" "$BH")
    echo "$LINE"
    [ -n "$PC" ] && printf '~$%.2f projected by reset | size=11 color=#888888\n' "$PC"
  fi
else
  echo "ccusage not installed | color=orange"
  echo "run: npm i -g ccusage | size=11 color=#888888"
fi

echo "---"
echo "Updated $(date +%H:%M) · windows every $((MAXAGE/60))m | size=11 color=#888888"
echo "Force-update windows now | bash=/bin/rm param1=-rf param2=$CACHEDIR terminal=false refresh=true"
echo "Refresh | refresh=true"
echo "Anthropic Console… | href=https://console.anthropic.com/"
