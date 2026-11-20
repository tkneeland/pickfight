# Source me (bash). Resolves the account and loads hive.conf, accounts/_shared.conf and accounts/<handle>.conf.
# Account: env HIVE_ACCOUNT, else `gh api user -q .login` (cached 1 h). Exports HIVE_ACCOUNT, HIVE_DIR, HIVE_STATE (per repo and
# account local state dir), REPO, ROOT (main checkout), TZ, HIVE_TZ and every conf setting. Defines the hive_* helpers below.
# Runs on macOS (BSD date/stat, bash 3.2), Linux and Git Bash on Windows (GNU date/stat): the shims below pick the form.
# Fork budget (issue #338): every hive script sources this file, and a process spawn costs ~10x more on Git Bash, so the
# load path below uses parameter expansion instead of dirname/basename, and the platform probes (uname, GNU date, jq CRLF) and
# the checkout root run once per process tree: they are exported, and a child script that finds them set reuses them.
_s=${BASH_SOURCE[0]:-$0}; case $_s in */*) _s=${_s%/*}; [ -n "$_s" ] || _s=/;; *) _s=.;; esac
HIVE_DIR=$(cd "$_s" && pwd)
[ -n "${HIVE_OS:-}" ] || HIVE_OS=$(uname -s)
if [ -z "${HIVE_GNU:-}" ]; then   # a real probe (a Mac with GNU date first on PATH is GNU)
  if date --version >/dev/null 2>&1; then HIVE_GNU=1; else HIVE_GNU=0; fi
fi
export HIVE_OS HIVE_GNU

# ---- portable date/stat/sed/jq shims ---------------------------------------------------------------------
hive_fmt()       { local e=${1%.*}; if [ "$HIVE_GNU" = 1 ]; then date -d "@$e" "$2"; else date -r "$e" "$2"; fi; }   # epoch '+fmt'
hive_epoch_fmt() { hive_fmt "$@"; }
hive_mtime()     { if [ "$HIVE_GNU" = 1 ]; then stat -c %Y "$1" 2>/dev/null; else stat -f %m "$1" 2>/dev/null; fi; }   # file mtime, epoch s
# 2026-10-22T15:00:42Z -> epoch. hive_iso2epoch prints 0 on bad input; hive_iso_to_epoch fails instead.
hive_iso_to_epoch() { if [ "$HIVE_GNU" = 1 ]; then date -u -d "$1" +%s 2>/dev/null; else date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null; fi; }
hive_iso2epoch() { hive_iso_to_epoch "$1" || echo 0; }
hive_sed_i()     { if [ "$HIVE_OS" = Darwin ]; then sed -i '' "$@"; else sed -i "$@"; fi; }
hive_desktop_notify() {  # title message; best effort
  if command -v osascript >/dev/null 2>&1; then osascript -e "display notification \"$2\" with title \"$1\"" 2>/dev/null
  elif command -v notify-send >/dev/null 2>&1; then notify-send "$1" "$2" 2>/dev/null; fi; return 0; }
# Windows jq.exe ends lines with CRLF, which survives $(...) and breaks every comparison; --binary turns that off. Only wrapped when needed.
if [ -z "${HIVE_JQ_CRLF:-}" ]; then   # probed once per process tree, and only where jq.exe can exist (Windows)
  HIVE_JQ_CRLF=0
  case $HIVE_OS in MINGW*|MSYS*|CYGWIN*) case "$(command jq -n -r '"x","y"' 2>/dev/null)" in *$'\r'*) HIVE_JQ_CRLF=1;; esac;; esac
  export HIVE_JQ_CRLF
fi
[ "$HIVE_JQ_CRLF" = 1 ] && jq() { command jq -b "$@"; }
# hive_posix_tz <zone>: Git Bash (MSYS) has no zoneinfo and silently falls back to UTC for IANA names. On GNU date, when the
# zone prints as GMT, translate the common ones to POSIX rules (correct on every platform). Anything else passes through.
hive_posix_tz() {
  [ "$HIVE_GNU" = 1 ] && [ -n "$1" ] && [ "$(TZ=$1 date +%Z)" = GMT ] || { echo "$1"; return; }
  case $1 in
    America/New_York|America/Detroit|America/Toronto|US/Eastern) echo EST5EDT,M3.2.0,M11.1.0;;
    America/Chicago|US/Central) echo CST6CDT,M3.2.0,M11.1.0;;
    America/Denver|US/Mountain) echo MST7MDT,M3.2.0,M11.1.0;;
    America/Los_Angeles|US/Pacific) echo PST8PDT,M3.2.0,M11.1.0;;
    America/Phoenix) echo MST7;;
    Europe/London|Europe/Dublin|Europe/Lisbon) echo GMT0BST,M3.5.0/1,M10.5.0;;
    Europe/Berlin|Europe/Paris|Europe/Madrid|Europe/Rome|Europe/Amsterdam|Europe/Stockholm|Europe/Warsaw|CET) echo CET-1CEST,M3.5.0,M10.5.0/3;;
    Asia/Kolkata) echo IST-5:30;;
    Asia/Tokyo) echo JST-9;;
    Australia/Sydney|Australia/Melbourne) echo AEST-10AEDT,M10.1.0,M4.1.0/3;;
    *) echo "$1";;
  esac
}

# ---- account and conf ------------------------------------------------------------------------------------
# HIVE_ROOT: the main checkout these scripts live in; for a private install outside any repo, the install dir (tools/agents/../..)
case ${HIVE_ROOT_CACHE:-} in   # "<HIVE_DIR>|<root>", exported: a child script of the same checkout skips the git call
  "$HIVE_DIR|"*) HIVE_ROOT=${HIVE_ROOT_CACHE#*|};;
  *) HIVE_ROOT=$(git -C "$HIVE_DIR" rev-parse --path-format=absolute --git-common-dir 2>/dev/null) && HIVE_ROOT=${HIVE_ROOT%/*} || HIVE_ROOT=$(cd "$HIVE_DIR/../.." && pwd)
     HIVE_ROOT_CACHE="$HIVE_DIR|$HIVE_ROOT"; export HIVE_ROOT_CACHE;;
esac
HIVE_CONF=${HIVE_CONF:-$HIVE_ROOT/hive.conf}
if [ ! -f "$HIVE_CONF" ]; then echo "hive-env: no hive.conf at $HIVE_CONF (copy it from the template, or set HIVE_CONF)" >&2; return 1 2>/dev/null || exit 1; fi
if [ -z "${HIVE_ACCOUNT:-}" ]; then
  _c=$HOME/.claude/hive/.account-cache; _m=$(hive_mtime "$_c" || echo 0)
  if [ -f "$_c" ] && [ $(( $(date +%s) - ${_m:-0} )) -lt 3600 ]; then HIVE_ACCOUNT=$(cat "$_c")
  else HIVE_ACCOUNT=$(gh api user -q .login 2>/dev/null); [ -n "$HIVE_ACCOUNT" ] && { mkdir -p "$HOME/.claude/hive"; echo "$HIVE_ACCOUNT" > "$_c"; }; fi
fi
if [ ! -f "$HIVE_DIR/accounts/${HIVE_ACCOUNT:-none}.conf" ]; then
  echo "hive-env: no tools/agents/accounts/${HIVE_ACCOUNT:-<unknown>}.conf (set HIVE_ACCOUNT or add the conf)" >&2; return 1 2>/dev/null || exit 1
fi
export HIVE_ACCOUNT HIVE_DIR
. "$HIVE_CONF"
[ -f "$HIVE_DIR/accounts/_shared.conf" ] && . "$HIVE_DIR/accounts/_shared.conf"
. "$HIVE_DIR/accounts/$HIVE_ACCOUNT.conf"
: "${HANDOFF_WEEKLY_USED:=85}" "${HANDOFF_HARD_WEEKLY_USED:=95}" "${RESET_GRACE_HOURS:=24}" "${WORKER_TARGET:=${DAY_AGENTS:-3}}" "${PACE_SLACK:=10}" "${FIVE_H_SLOW_USED:=70}" "${FIVE_H_STOP_USED:=90}"
: "${PEER_QUEUE_MIN:=5}" "${BEACON_FRESH_HOURS:=6}" "${DIGEST_HOUR:=9}" "${QUIET_START:=${NIGHT_START:-20}}" "${QUIET_END:=${NIGHT_END:-9}}"   # NIGHT_*/DAY_AGENTS: pre-pace confs
: "${MAIN_BRANCH:=main}" "${MERGE_METHOD:=merge}" "${DISCORD:=0}" "${MIN_WEEKLY_REMAINING_FOR_TICKETS:=0}" "${SUCCESSION_RANK:=9}"
: "${STUDIO_REPO:=}" "${HIVE_STUDIO_CACHE:=$HOME/.claude/hive/studio}"
: "${TRACKER:=github}" "${PRIVATE:=0}" "${SINGLE_ACCOUNT:=0}" "${SCOPE_FILTER:=}" "${WATCH_HOOKS:=}" "${CLOSEOUT_STATUS:=ready-for-human}"
: "${PROJECT_NAME:=}" "${OWNER:=}" "${DECISIONS_ISSUE:=}" "${REQUIRE_REVIEW_PASS:=1}" "${TRUSTED_TICKET_AUTHORS:=}" "${RESERVE:=0}"
: "${DISCORD_BUGS_NAME:=change-requests}" "${DISCORD_DEV_NAME:=hive}" "${DISCORD_DEV_ROLE:=Dev}" "${TICKETMAKER_CHANNEL:=}"
# private: nothing about AT ever lands on GitHub, Discord or the channel
[ "$PRIVATE" = 1 ] && SINGLE_ACCOUNT=1 && DECISIONS_ISSUE= && DISCORD=0
if [ "$TRACKER" = local ]; then
  TRACKER_DIR=${TRACKER_DIR:-$HIVE_ROOT/.scratch}
  case $TRACKER_DIR in /*|[A-Za-z]:/*|[A-Za-z]:\\*) ;; *) TRACKER_DIR=$HIVE_ROOT/$TRACKER_DIR;; esac
  [ -d "$TRACKER_DIR" ] || { echo "hive-env: TRACKER_DIR $TRACKER_DIR does not exist" >&2; return 1 2>/dev/null || exit 1; }
  export TRACKER_DIR
elif [ -z "${REPO:-}" ]; then echo "hive-env: REPO is not set in $HIVE_CONF" >&2; return 1 2>/dev/null || exit 1; fi
[ -n "${TZ:-}" ] && { [ "$HIVE_GNU" = 1 ] && TZ=$(hive_posix_tz "$TZ"); export TZ; }   # hive_posix_tz only rewrites on GNU date
export REPO
_tzl=""; [ -n "${TZ_LABEL:-}" ] || { TZ_LABEL=$(date +%Z); _tzl=$TZ_LABEL; }
# HIVE_TZ: the one zone every hive-wide time is shown in (status, asks, #hive posts), so accounts in different zones agree.
# Default: this account's TZ. HIVE_TZ_LABEL is printed after those times.
if [ -z "${HIVE_TZ:-}" ]; then HIVE_TZ=${TZ:-}   # already translated above
elif [ "$HIVE_GNU" = 1 ]; then HIVE_TZ=$(hive_posix_tz "$HIVE_TZ"); fi
if [ -z "${HIVE_TZ_LABEL:-}" ]; then   # same zone as TZ, whose label was just read: no second date call
  if [ -n "$_tzl" ] && [ -n "${TZ:-}" ] && [ "$HIVE_TZ" = "$TZ" ]; then HIVE_TZ_LABEL=$_tzl; else HIVE_TZ_LABEL=$(TZ=${HIVE_TZ:-$TZ} date +%Z); fi
fi; export HIVE_TZ HIVE_TZ_LABEL
hive_tzfmt() { TZ=${HIVE_TZ:-${TZ:-}} hive_fmt "$@"; }   # hive_tzfmt <epoch> <+format>: a time in HIVE_TZ
# PROJECT_NAME: the hive's voice (Discord posts, notifications); default the repo name
[ -n "$PROJECT_NAME" ] || { PROJECT_NAME=${REPO#*/}; PROJECT_NAME=${PROJECT_NAME:-${HIVE_ROOT##*/}}; }
ROOT=${REPO_PATH:-$HIVE_ROOT}
# REPO_PATHS: every checkout AT ships to (private installs can drive several client repos); default the one ROOT
REPO_PATHS=${REPO_PATHS:-$ROOT}
_rp=""; for _p in $REPO_PATHS; do case $_p in /*|[A-Za-z]:/*|[A-Za-z]:\\*) _rp+="$_p ";; *) _rp+="$HIVE_ROOT/$_p ";; esac; done; REPO_PATHS=${_rp% }; export REPO_PATHS
# per repo and account local state, so several accounts or repos on one machine never collide
HIVE_SLUG=${PROJECT:-${REPO:-${HIVE_ROOT##*/}}}; HIVE_SLUG=${HIVE_SLUG//\//__}
HIVE_STATE=${HIVE_STATE_DIR:-$HOME/.claude/hive/$HIVE_SLUG/$HIVE_ACCOUNT}   # HIVE_STATE_DIR: scratch state for tests
# One-time move from the claude-autotriage layout (~/.claude/at/<repo>/<handle>): same file names, so the mode, outbox,
# inbox, msg.conf and usage snapshot carry over on every machine that pulls the rename, not only the installer's.
if [ -z "${HIVE_STATE_DIR:-}" ] && [ ! -e "$HIVE_STATE" ] && [ -d "$HOME/.claude/at/$HIVE_SLUG/$HIVE_ACCOUNT" ]; then
  mkdir -p "${HIVE_STATE%/*}" && mv "$HOME/.claude/at/$HIVE_SLUG/$HIVE_ACCOUNT" "$HIVE_STATE" 2>/dev/null &&
    echo "hive-env: moved state ~/.claude/at/$HIVE_SLUG/$HIVE_ACCOUNT -> $HIVE_STATE" >&2
fi
# One-time import from the old pf-* hive (Pickfight, Match3). hive.conf LEGACY_STATE, written by install.sh from the old
# pf-env.sh, names each account's old state dir relative to $HOME: space-separated "<handle>=<dir>" rules, then one bare
# "<dir>" for every other handle, where {handle} stands for the handle. That dir can be ~/.claude itself (shared with
# Claude Code and other projects), so only the known hive files are copied (never moved) under their hive names, private
# (600), and the PF_ key prefix in the confs becomes HIVE_. Nothing is read aloud: the confs hold the channel topic and the
# Discord token.
hive_legacy_import() {
  local r p="" src m f n c=0
  for r in $LEGACY_STATE; do
    case $r in *=*) [ "${r%%=*}" = "$HIVE_ACCOUNT" ] || continue; p=${r#*=};; *) p=$r;; esac; break
  done
  p=${p//\{handle\}/$HIVE_ACCOUNT}; src=$HOME/$p
  [ -n "$p" ] && [ -d "$src" ] || return 0
  mkdir -p "$HIVE_STATE" || return 0
  for m in pf-msg.conf:msg.conf pf-discord.conf:discord.conf pf-triagemaster:triagemaster pf-ticketmaker:ticketmaker \
           pf-takeover:takeover pf-at-mode:at-mode pf-stuck:stuck .pf-triage-seen:.triage-seen usage-snapshot.json \
           msg-inbox.log .msg-last-id ask-open.txt reserve-last-launch "$src"/.discord-*-last "$src"/.discord-*-handled; do
    f=${m%%:*}; f=${f##*/}; n=${m#*:}; n=${n##*/}
    [ -e "$src/$f" ] || continue
    case $f in
      *.conf) ( umask 077; sed 's/^PF_/HIVE_/' "$src/$f" > "$HIVE_STATE/$n" );;
      *) cp -Rp "$src/$f" "$HIVE_STATE/$n" || continue; [ -d "$HIVE_STATE/$n" ] || chmod 600 "$HIVE_STATE/$n";;
    esac
    c=$((c + 1))
  done
  [ $c -gt 0 ] && echo "hive-env: imported $c state files from ~/$p (the old pf-* hive; kept there) -> $HIVE_STATE" >&2
  return 0
}
if [ -z "${HIVE_STATE_DIR:-}" ] && [ ! -e "$HIVE_STATE" ] && [ -n "${LEGACY_STATE:-}" ]; then hive_legacy_import; fi
[ -d "$HIVE_STATE" ] || mkdir -p "$HIVE_STATE"; export HIVE_STATE ROOT HIVE_SLUG
HIVE_OUTBOX=$HIVE_STATE/outbox.log

# ---- accounts and the triagemaster role -----------------------------------------------------------------
hive_handles() { for f in "$HIVE_DIR"/accounts/*.conf; do [ -e "$f" ] || continue; b=$(basename "$f" .conf); case $b in _*|example-*) ;; *) echo "$b";; esac; done; }
hive_rank_of() { sed -n 's/^SUCCESSION_RANK=\([0-9]*\).*/\1/p' "$HIVE_DIR/accounts/$1.conf" | head -n 1; }
hive_conf_of() { sed -n "s/^$2=//p" "$HIVE_DIR/accounts/$1.conf" 2>/dev/null | sed 's/[[:space:]]*#.*//; s/^"//; s/"$//' | head -n 1; }   # <handle> <KEY>
hive_is_reserve() { [ "$(hive_conf_of "$1" RESERVE)" = 1 ]; }
hive_display_name() { local n; n=$(hive_conf_of "$1" DISPLAY_NAME); hive_is_reserve "$1" && n="${n:-$1} (reserve)"; [ -n "$n" ] && echo "$n ($1)" || echo "$1"; }
hive_rank1() { for h in $(hive_handles); do [ "$(hive_rank_of "$h")" = 1 ] && echo "$h"; done | head -1; }
hive_peers() { if [ -n "${WATCH_PEERS:-}" ]; then echo $WATCH_PEERS; else for h in $(hive_handles); do [ "$h" = "$HIVE_ACCOUNT" ] || echo "$h"; done; fi; }
hive_triagemaster() { cat "$HIVE_STATE/triagemaster" 2>/dev/null || hive_rank1; }
hive_is_triagemaster() { [ "$SINGLE_ACCOUNT" = 1 ] || [ "$(hive_triagemaster)" = "$HIVE_ACCOUNT" ]; }
[ "$SINGLE_ACCOUNT" = 1 ] && { hive_peers() { :; }; hive_triagemaster() { echo "$HIVE_ACCOUNT"; }; }

# ---- tracker (TRACKER=github: GitHub Issues; TRACKER=local: TRACKER_DIR/<feature>/issues/NN-slug.md, one "Status:" line) ----
# Local ticket ids are "<feature>/<NN>", e.g. ipad/01. SCOPE_FILTER (ERE) limits AT to tickets whose file or body matches it.
hive_ticket_file() { ls "$TRACKER_DIR/${1%%/*}/issues/${1#*/}"-*.md 2>/dev/null | head -1; }
hive_ticket_status() { sed -n 's/^Status: *\([A-Za-z-]*\).*/\1/p' "$(hive_ticket_file "$1")" | head -1; }
hive_ticket_title() { sed -n '1s/^# *//p' "$(hive_ticket_file "$1")" | cut -c1-60; }
hive_in_scope() { [ -z "$SCOPE_FILTER" ] || grep -qE "$SCOPE_FILTER" "$1"; }   # file
# hive_tickets <status-ERE>: in-scope local ticket ids whose Status matches
hive_tickets() {
  local f id; for f in "$TRACKER_DIR"/*/issues/[0-9]*-*.md; do
    [ -e "$f" ] || continue
    grep -qE "^Status: *($1)([^A-Za-z-]|$)" "$f" || continue
    hive_in_scope "$f" || continue
    id=${f#$TRACKER_DIR/}; id=${id%%/issues/*}/$(basename "$f" | cut -d- -f1); echo "$id"
  done
}
# hive_set_status <id> <status> ["comment"]: rewrites the Status line and appends a dated comment under ## Comments
hive_set_status() {
  local f; f=$(hive_ticket_file "$1") || return 1; [ -n "$f" ] || return 1
  awk -v s="$2" '!d && /^Status:/ {print "Status: " s; d=1; next} {print}' "$f" > "$f.hive-tmp" && mv "$f.hive-tmp" "$f"   # first Status line only
  if [ -n "${3:-}" ]; then grep -q '^## Comments' "$f" || printf '\n## Comments\n' >> "$f"; printf '\n- %s (AT) %s\n' "$(date +%F)" "$3" >> "$f"; fi
}
# active work packages: Atlas state files (removed at closeout)
hive_active_packages() { ls "$ROOT"/.claude/atlas-state/*.json 2>/dev/null | wc -l | tr -d ' '; }
# PRs AT may act on: private mode only touches PRs this account opened
hive_pr_author_flag() { [ "$PRIVATE" = 1 ] && echo "--author @me"; }
# review-blocked marker: a GitHub label normally; a local file in private mode (no labels on client repos)
hive_review_blocked() { # <repo-slug> <pr>
  if [ "$PRIVATE" = 1 ]; then [ -f "$HIVE_STATE/review-blocked/${1//\//__}-$2" ]; else gh pr view "$2" -R "$1" --json labels -q '.labels[].name' 2>/dev/null | grep -qx review-blocked; fi; }
# review-passed marker (REQUIRE_REVIEW_PASS=1: hive-automerge.sh and hive-ship.sh merge only PRs that carry it): the
# review-passed label normally; a local file in private mode. hive_mark_review <slug> <pr> passed|blocked|clear sets it.
hive_review_passed() { # <repo-slug> <pr>
  [ "$REQUIRE_REVIEW_PASS" = 1 ] || return 0
  if [ "$PRIVATE" = 1 ]; then [ -f "$HIVE_STATE/review-passed/${1//\//__}-$2" ]; else gh pr view "$2" -R "$1" --json labels -q '.labels[].name' 2>/dev/null | grep -qx review-passed; fi; }
# hive_grill_pr <repo-slug> <pr>: 0 only when the PR's changed files are exactly hive.conf GRILL_DOC and its author is this
# account (the one review mark a control panel may set; docs/agents/hive.md "Grill results go to the repo at once").
hive_grill_pr() {
  [ "$PRIVATE" != 1 ] && [ -n "${GRILL_DOC:-}" ] && [ "$(gh pr view "$2" -R "$1" --json files,author -q '"\(.author.login) \([.files[].path] | join(","))"' 2>/dev/null)" = "$HIVE_ACCOUNT $GRILL_DOC" ]
}
hive_mark_review() { # <repo-slug> <pr> passed|blocked|clear
  hive_grill_pr "$1" "$2" || hive_guard mark-review || return 1
  local k=${1//\//__}-$2 d
  if [ "$PRIVATE" = 1 ]; then
    rm -f "$HIVE_STATE/review-passed/$k" "$HIVE_STATE/review-blocked/$k"
    case $3 in passed|blocked) d=$HIVE_STATE/review-$3; mkdir -p "$d"; date +%s > "$d/$k";; esac; return 0
  fi
  case $3 in
    passed) gh pr edit "$2" -R "$1" --add-label review-passed --remove-label review-blocked >/dev/null;;
    blocked) gh pr edit "$2" -R "$1" --add-label review-blocked --remove-label review-passed >/dev/null;;
    *) gh pr edit "$2" -R "$1" --remove-label review-passed --remove-label review-blocked >/dev/null;;
  esac
}
hive_slug_of() { git -C "$1" remote get-url origin 2>/dev/null | sed -E 's#^.*[:/]([^/:]+/[^/]+)$#\1#; s#\.git$##'; }

# ---- studio-wide settings (STUDIO_REPO, edited from the hive hub) ----------------------------------------
# The cache is $HIVE_STUDIO_CACHE (~/.claude/hive/studio), shared by every game on this machine. Reads never call GitHub.
HIVE_STUDIO_FILES="hive/account-limits.conf"
# hive_studio_sync: refresh the cached studio files from GitHub at most every 5 min (hive-beacon.sh calls it). A failed
# fetch keeps the last copy; a file the studio does not have is cached empty.
hive_studio_sync() {
  [ -n "$STUDIO_REPO" ] || return 0
  local p f t m stamp=$HIVE_STUDIO_CACHE/.synced-at
  mkdir -p "$HIVE_STUDIO_CACHE" || return 0
  m=$(hive_mtime "$stamp" || echo 0)
  [ $(( $(date +%s) - ${m:-0} )) -lt 300 ] && return 0
  touch "$stamp"
  for p in $HIVE_STUDIO_FILES; do
    f=$HIVE_STUDIO_CACHE/${p##*/}
    if t=$(gh api "repos/$STUDIO_REPO/contents/$p" -H "Accept: application/vnd.github.raw+json" 2>&1); then
      printf '%s\n' "$t" > "$f.tmp.$$" && mv "$f.tmp.$$" "$f"
    else
      case $t in *"Not Found"*|*"HTTP 404"*) : > "$f";; esac
    fi
  done
  return 0
}
# hive_limits <handle>: sets l_5h (FIVE_H_STOP_USED) and l_wmin (MIN_WEEKLY_REMAINING_FOR_TICKETS) for that account. The
# hub's studio hive/account-limits.conf ("<handle> five_h=<used %> weekly=<used %>", either key optional) wins; then the
# account conf, then _shared.conf, then 90 and 0. weekly=W is stored as l_wmin = 100 - W. No forks in the common case.
hive_limits() {
  local h k v kv rest f=$HIVE_STUDIO_CACHE/account-limits.conf; l_5h=""; l_wmin=""
  if [ -n "$STUDIO_REPO" ] && [ -s "$f" ]; then
    while read -r h rest; do
      case $h in ''|'#'*) continue;; esac
      [ "$h" = "$1" ] || continue   # the hub writes the roster spelling, which is the conf name
      for kv in $rest; do
        k=${kv%%=*}; v=${kv#*=}
        case $v in ''|*[!0-9]*) continue;; esac
        [ "$v" -ge 1 ] && [ "$v" -le 100 ] || continue
        case $k in five_h) l_5h=$v;; weekly) l_wmin=$(( 100 - v ));; esac
      done
    done < "$f"
  fi
  if [ "$1" = "$HIVE_ACCOUNT" ]; then
    [ -n "$l_5h" ] || l_5h=$FIVE_H_STOP_USED_CONF; [ -n "$l_wmin" ] || l_wmin=$MIN_WEEKLY_REMAINING_FOR_TICKETS_CONF
    return 0
  fi
  for k in FIVE_H_STOP_USED MIN_WEEKLY_REMAINING_FOR_TICKETS; do
    case $k in FIVE_H_STOP_USED) [ -n "$l_5h" ] && continue;; *) [ -n "$l_wmin" ] && continue;; esac
    v=$(hive_conf_of "$1" "$k")
    case $v in ''|*[!0-9]*) v=$(sed -n "s/^$k=//p" "$HIVE_DIR/accounts/_shared.conf" 2>/dev/null | sed 's/[[:space:]]*#.*//; s/^"//; s/"$//' | head -n 1);; esac
    case $v in ''|*[!0-9]*) case $k in FIVE_H_STOP_USED) v=90;; *) v=0;; esac;; esac
    case $k in FIVE_H_STOP_USED) l_5h=$v;; *) l_wmin=$v;; esac
  done
  return 0
}
# hive_weekly_capped <used7> <weekly reset epoch> <min remaining>: 0 when the account is at its weekly ticket limit, i.e. its
# remaining weekly (100 - used7) is at or below <min remaining>, outside the last RESET_GRACE_HOURS before its weekly reset
# (that window spends what is left). Unknown used7: not capped. Unknown reset: capped.
hive_weekly_capped() {
  case $1 in ''|*[!0-9]*) return 1;; esac
  [ $(( 100 - $1 )) -le "${3:-0}" ] || return 1
  case $2 in ''|*[!0-9]*|0) return 0;; esac
  [ $(( $2 - $(date +%s) )) -gt $(( RESET_GRACE_HOURS * 3600 )) ]
}
# this account's own limits: the hub's values replace the conf's (a 5h slow-down above the stop is pulled down to it)
FIVE_H_STOP_USED_CONF=$FIVE_H_STOP_USED MIN_WEEKLY_REMAINING_FOR_TICKETS_CONF=$MIN_WEEKLY_REMAINING_FOR_TICKETS
hive_limits "$HIVE_ACCOUNT"; FIVE_H_STOP_USED=$l_5h MIN_WEEKLY_REMAINING_FOR_TICKETS=$l_wmin
[ "$FIVE_H_SLOW_USED" -gt "$FIVE_H_STOP_USED" ] 2>/dev/null && FIVE_H_SLOW_USED=$FIVE_H_STOP_USED

# ---- budget, pace ----------------------------------------------------------------------------------------
hive_weekly_used()  { jq -r '.rate_limits.seven_day.used_percentage // 0 | floor' "$HIVE_STATE/usage-snapshot.json" 2>/dev/null || echo 0; }
hive_weekly_reset() { jq -r '.rate_limits.seven_day.resets_at // 0 | floor' "$HIVE_STATE/usage-snapshot.json" 2>/dev/null || echo 0; }
# 0 when dispatching is allowed: under HANDOFF_WEEKLY_USED, or inside the last RESET_GRACE_HOURS before the weekly reset
hive_budget_ok() {
  [ "$(hive_weekly_used)" -lt "$HANDOFF_WEEKLY_USED" ] && return 0
  r=$(hive_weekly_reset); [ "$r" -gt 0 ] && [ $(( r - $(date +%s) )) -le $(( RESET_GRACE_HOURS * 3600 )) ]
}
# hive_live_agents: issue numbers (one per line, deduped) of this checkout's worktrees on an issue branch (issue-N or
# <type>/N-) whose issue is still open and that something wrote to in the last 30 min. Idle leftovers don't count.
hive_live_agents() {   # optional $1: the open issue numbers (space separated) when the caller already has them
  # No awk/sed/head/tr/sort in the common case (issue #338): gh and git are the only spawns when no issue worktree exists.
  local open res="" k w _ b wt i gd re1='.*issue-([0-9]+)' re2='^[a-z]+/([0-9]+)-'
  if [ -n "${1:-}" ]; then open=$1; else open=$(gh issue list -R "$REPO" --state open -L 300 --json number -q '.[].number' 2>/dev/null); open=${open//$'\n'/ }; fi
  open=" $open "
  while read -r k w _; do
    case $k in
      worktree) wt=$w; continue;;
      branch) b=${w#refs/heads/};;
      *) continue;;
    esac
    i=""; if [[ $b =~ $re1 ]]; then i=${BASH_REMATCH[1]}; elif [[ $b =~ $re2 ]]; then i=${BASH_REMATCH[1]}; fi
    [ -n "$i" ] || continue
    case "$open" in *" $i "*) ;; *) continue;; esac
    gd=$(git -C "$wt" rev-parse --absolute-git-dir 2>/dev/null)
    { [ -n "$(find "$gd/index" "$gd/HEAD" -mmin -30 2>/dev/null)" ] ||
      [ -n "$(find "$wt" -path "$wt/.git" -prune -o -path "$wt/node_modules" -prune -o -type f -mmin -30 -print 2>/dev/null | head -1)" ]; } && res="$res$i"$'\n'
  done < <(git -C "$ROOT" worktree list --porcelain 2>/dev/null)
  case $res in
    '') ;;
    *$'\n'*$'\n'*) printf '%s' "$res" | sort -un;;   # more than one: dedupe and order numerically
    *) printf '%s' "$res";;
  esac
  return 0
}
hive_five_h_used() { jq -r '.rate_limits.five_hour.used_percentage // 0 | floor' "$HIVE_STATE/usage-snapshot.json" 2>/dev/null || echo 0; }
# prints "ahead" when weekly use is more than PACE_SLACK points above the on-pace line (the share of the 7-day window elapsed
# x HANDOFF_WEEKLY_USED), else "on pace". No usage snapshot yet, or inside the last RESET_GRACE_HOURS: "on pace".
hive_pace() {
  local u r n; u=$(hive_weekly_used); r=$(hive_weekly_reset); n=$(date +%s)
  [ "$r" -gt "$n" ] 2>/dev/null || { echo "on pace"; return; }
  [ $(( r - n )) -le $(( RESET_GRACE_HOURS * 3600 )) ] && { echo "on pace"; return; }   # the reset grace window spends what is left
  awk -v u="$u" -v r="$r" -v n="$n" -v h="$HANDOFF_WEEKLY_USED" -v s="$PACE_SLACK" \
    'BEGIN{e=1-(r-n)/604800; if (e<0) e=0; print (u > e*h + s) ? "ahead" : "on pace"}'
}
# worker target right now: WORKER_TARGET while on pace, 1 while ahead of pace or once the 5h window reaches FIVE_H_SLOW_USED,
# 0 at FIVE_H_STOP_USED or when the weekly budget says stop. Start workers only while running < target; never above it.
hive_worker_target() {
  hive_budget_ok || { echo 0; return; }
  local f; f=$(hive_five_h_used)
  if [ "$f" -ge "$FIVE_H_STOP_USED" ]; then echo 0; elif [ "$f" -ge "$FIVE_H_SLOW_USED" ]; then echo 1
  elif [ "$(hive_pace)" = ahead ]; then echo 1; else echo "$WORKER_TARGET"; fi
}
# 0 inside an account's quiet hours (QUIET_START..QUIET_END in its TZ), when the hive pings that person only about p1. Work is
# unaffected. Optional $1: another account's handle (its conf's TZ and hours; NIGHT_* in a pre-pace conf); default this account.
hive_quiet() {
  local tz=${TZ:-} qs=$QUIET_START qe=$QUIET_END h
  if [ -n "${1:-}" ] && [ "$1" != "$HIVE_ACCOUNT" ]; then
    tz=$(hive_conf_of "$1" TZ); tz=${tz:-${TZ:-}}
    qs=$(hive_conf_of "$1" QUIET_START); qs=${qs:-$(hive_conf_of "$1" NIGHT_START)}; qs=${qs:-20}
    qe=$(hive_conf_of "$1" QUIET_END); qe=${qe:-$(hive_conf_of "$1" NIGHT_END)}; qe=${qe:-9}
  fi
  h=$(TZ=$tz date +%H); h=$((10#$h))
  if [ "$qs" -gt "$qe" ]; then [ "$h" -ge "$qs" ] || [ "$h" -lt "$qe" ]
  else [ "$h" -ge "$qs" ] && [ "$h" -lt "$qe" ]; fi
}

# ---- repo helpers ---------------------------------------------------------------------------------------
hive_merge_flag() { case $MERGE_METHOD in squash) echo --squash;; rebase) echo --rebase;; *) echo --merge;; esac; }
# Run BOOT_CHECK_CMD in a throwaway clone of the current checkout's committed HEAD. Returns its exit status; 0 if unset.
hive_fresh_clone_check() {
  [ -n "${BOOT_CHECK_CMD:-}" ] || return 0
  local d rc; d=$(mktemp -d "${TMPDIR:-/tmp}/hive-fresh.XXXXXX") || return 1
  git clone -q "$PWD" "$d/clone" || { rm -rf "$d"; return 1; }
  ( cd "$d/clone" && FRESH_CLONE="$d/clone" bash -c "$BOOT_CHECK_CMD" ); rc=$?
  rm -rf "$d"; return $rc
}
hive_run_tests() { [ -n "${TEST_CMD:-}" ] || return 0; bash -c "$TEST_CMD"; }
# hive_branch_issue <branch>: the ticket a branch names at its start, `issue-<n>-` or `<type>/issue-<n>-` or `<type>/<n>-`
# ("" when none). `fix/issue-12-from-issue-9` gives 12; `chore/tissue-5-x` gives nothing.
hive_branch_issue() { printf '%s' "$1" | sed -nE 's#^([a-z]+/)?issue-([0-9]+)-.*#\2#p; s#^[a-z]+/([0-9]+)-.*#\1#p' | head -1; }
# hive_pr_conflict_risk <slug> <pr> [ticket]: is the PR conflict-risk (rule 6)? 0 yes, 1 no, 2 unknown (a GitHub read
# failed; callers treat it as "not for a non-triagemaster to merge"). Rule 6 labels the ticket, not the PR, so this reads
# the PR's own labels and those of the issues it closes (one GraphQL call), then the ticket its head branch names and the
# optional [ticket]. Pickfight #1287: a PR merged unchecked because only its ticket had the label.
hive_pr_conflict_risk() {
  local out branch n labels
  out=$(gh api graphql -F owner="${1%%/*}" -F name="${1#*/}" -F n="$2" -f query='query($owner:String!,$name:String!,$n:Int!){repository(owner:$owner,name:$name){pullRequest(number:$n){headRefName labels(first:50){nodes{name}} closingIssuesReferences(first:20){nodes{labels(first:50){nodes{name}}}}}}}' \
    --jq '.data.repository.pullRequest | (([.labels.nodes[].name] + [.closingIssuesReferences.nodes[].labels.nodes[].name]) | index("conflict-risk") != null | tostring) + " " + .headRefName' 2>/dev/null) || return 2
  case $out in true\ *) return 0;; false\ *) ;; *) return 2;; esac
  branch=${out#* }
  for n in $(printf '%s\n%s\n' "${3:-}" "$(hive_branch_issue "$branch")" | grep -E '^[0-9]+$' | sort -u); do
    labels=$(gh issue view "$n" -R "$1" --json labels -q '.labels[].name' 2>/dev/null) || return 2
    printf '%s\n' "$labels" | grep -qx conflict-risk && return 0
  done
  return 1
}
# hive_merge_gated <slug> <pr> [ticket]: 0 when this account must not merge the PR (conflict-risk, or unknown, and not
# the triagemaster). Private mode has no labels, so never gated.
hive_merge_gated() { [ "$PRIVATE" != 1 ] || return 1; hive_is_triagemaster && return 1; hive_pr_conflict_risk "$@"; [ $? != 1 ]; }
# hive_screen <kind>: this repo's screen session name for a watcher, hive-<kind>-<repo>-<account>. The repo is in the
# name so one machine can run several games' hives side by side (a bare hive-<kind>-<account> was one game's only).
hive_screen() { printf 'hive-%s-%s-%s' "$1" "${HIVE_SLUG#*__}" "$HIVE_ACCOUNT"; }
hive_run_install() { [ -n "${INSTALL_CMD:-}" ] && ( cd "$ROOT" && bash -c "$INSTALL_CMD" ); return 0; }
# Append one tagged line to the outbox the main terminal watches: hive_outbox FIRE "text"
hive_outbox() { printf '[%s] %s\n' "$1" "$2" >> "$HIVE_OUTBOX"; }

# ---- the private channel: usage beacons, heartbeats, claude_at (hive-msg.sh fills $HIVE_STATE/msg-inbox.log) ----------------
# Inbox lines are "epoch|from|TYPE|rest". A USAGE line's rest is "<5h>% <7d>% <7d reset ISO> r5=<5h reset ISO> agents=<n>
# at=<snapshot ISO> [claude_at=<ISO>]" (hive-beacon.sh sends it). Nothing here touches GitHub.
HIVE_INBOX=$HIVE_STATE/msg-inbox.log
# A peer is live while any channel message from it (any type: HELLO goes out only after an hour with no other send, USAGE
# only on change or hourly) is under HIVE_PEER_LIVE_SECS old. hive-msg.sh heartbeat wakes peer-silent only after 2 h.
: "${HIVE_PEER_LIVE_SECS:=5400}"
# hive_peer_heard <handle>: epoch of the newest inbox line of any type from <handle>; 0 when none.
hive_peer_heard() { awk -F'|' -v p="$1" '$2 == p && $1 + 0 > m { m = $1 + 0 } END { print int(m) }' "$HIVE_INBOX" 2>/dev/null || echo 0; }
# hive_msg_quota_until: prints the epoch an ntfy 429 backoff ends ($HIVE_STATE/.msg-backoff-until, written by hive-msg.sh
# send) while it is still ahead of now (HIVE_NOW overrides now); else exit 1.
hive_msg_quota_until() {
  local u; u=$(tr -d '\r ' 2>/dev/null < "$HIVE_STATE/.msg-backoff-until")
  case $u in ''|*[!0-9]*) return 1;; esac
  [ "$u" -gt "${HIVE_NOW:-$(date -u +%s)}" ] && echo "$u"
}
# ---- control-panel mode (issue #300) -----------------------------------------------------------------------
# hive_pid_alive <pid>: Git Bash-safe (ps -W lists Windows pids); unknown when neither tool works counts as dead
hive_pid_alive() { [ -n "$1" ] || return 1; kill -0 "$1" 2>/dev/null && return 0
  if ps -W >/dev/null 2>&1; then ps -W 2>/dev/null | awk -v p="$1" '$1==p||$4==p{f=1} END{exit !f}'; else return 1; fi; }
# hive_keepalive_running: this account's keepalive (hive-keepalive.sh, or the PowerShell one on Windows) is alive. Reads the first
# field of $HIVE_STATE/keepalive.pid ("<pid>" or "<pid> <ticks>") and guards against a recycled pid by checking the command line.
hive_keepalive_running() {
  local p cmd w
  [ -f "$HIVE_STATE/keepalive.pid" ] || return 1
  p=$(head -n 1 "$HIVE_STATE/keepalive.pid" 2>/dev/null | tr -d '\r'); p=${p%%[[:space:]]*}
  case $p in ''|*[!0-9]*) return 1;; esac
  hive_pid_alive "$p" || return 1
  cmd=$(ps -p "$p" -o command= 2>/dev/null | head -n 1)
  [ -n "$cmd" ] || cmd=$({ tr '\0' ' ' < "/proc/$p/cmdline"; } 2>/dev/null)   # Git Bash: ps has no -o, but /proc has the script's argv
  if [ -n "$cmd" ]; then case $cmd in *hive-keepalive.sh*) return 0;; *) return 1;; esac; fi
  w=$(ps -W 2>/dev/null | awk -v p="$p" '$1==p||$4==p{print; exit}')
  if [ -n "$w" ]; then case $(printf '%s' "$w" | tr 'A-Z' 'a-z') in *powershell*|*pwsh*) return 0;; *) return 1;; esac; fi
  return 0   # alive but neither ps could name it: trust the pid file
}
# hive_control_panel: an interactive session on a machine whose always-on keepalive session runs. Advisory, not a security boundary.
# hive_in_session_screen: an always-on session started before HIVE_SESSION existed has no env var; it is still the keepalive's
# `screen -dmS hive-<repo>-<account>` child, so a SCREEN ancestor with that session name marks it (no-op where ps -o is missing).
hive_in_session_screen() {
  local p=$$ i c
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
    p=$(ps -o ppid= -p "$p" 2>/dev/null | tr -d '[:space:]'); case $p in ''|0|1|*[!0-9]*) return 1;; esac
    c=$(ps -o command= -p "$p" 2>/dev/null)
    case $c in *"-dmS hive-"*"-$HIVE_ACCOUNT "*|*"-dmS hive-"*"-$HIVE_ACCOUNT") return 0;; esac
  done; return 1; }
# hive_in_keepalive_claude: the Windows keepalive's headless `claude -p` (pid in $HIVE_STATE/keepalive-claude.pid) is an ancestor of this
# shell. The Bash tool's shell is initialised from the user profile and may not see the keepalive's HIVE_SESSION (issue #307), and Git
# Bash `ps` cannot walk Windows-native parents, so ask Windows for the ancestry. No-op without powershell.exe (Linux/macOS).
hive_in_keepalive_claude() {
  local c start anc
  c=$(head -n 1 "$HIVE_STATE/keepalive-claude.pid" 2>/dev/null | tr -d '\r[:space:]')
  case $c in ''|*[!0-9]*) return 1;; esac
  command -v powershell.exe >/dev/null 2>&1 || return 1
  hive_pid_alive "$c" || return 1
  # guard against a recycled pid: the row must still name claude (unknown when ps -W cannot list it)
  local w; w=$(ps -W 2>/dev/null | awk -v p="$c" '$1==p||$4==p{print; exit}')
  if [ -n "$w" ]; then case $(printf "%s" "$w" | tr "A-Z" "a-z") in *claude*) ;; *) return 1;; esac; fi
  # Cygwin exec replaces the Windows process, so a child script's Windows parent is a dead fork stub: climb the Cygwin
  # ppid chain to the topmost Cygwin ancestor (started by a native process, e.g. claude.exe) and walk Windows parents from it.
  local cp=$$ pp i
  for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    pp=$({ tr -d '\r[:space:]' < "/proc/$cp/ppid"; } 2>/dev/null); case $pp in ''|0|1|*[!0-9]*) break;; esac
    [ -r "/proc/$pp/winpid" ] || break; cp=$pp
  done
  start=$({ tr -d '\r[:space:]' < "/proc/$cp/winpid"; } 2>/dev/null); case $start in ''|*[!0-9]*) start=$$;; esac
  anc=$(powershell.exe -NoProfile -NonInteractive -Command '$p='"$start"'; for ($i = 0; $i -lt 25 -and $p; $i++) { $o = Get-CimInstance Win32_Process -Filter "ProcessId=$p" -ErrorAction SilentlyContinue; if (-not $o) { break }; $p = $o.ParentProcessId; $p }' 2>/dev/null | tr -d '\r')
  printf '%s\n' "$anc" | grep -qx "$c"
}
hive_control_panel() { [ "${HIVE_SESSION:-}" != always-on ] && hive_keepalive_running && ! hive_in_session_screen && ! hive_in_keepalive_claude; }
# hive_guard <action>: refuses AT-only actions from a control-panel session
hive_guard() {
  hive_control_panel || return 0
  echo "hive: $1 refused: this is a control-panel session (the always-on session owns AT work). Pass it on with a ticket or PR comment, or by typing into the always-on screen session." >&2
  return 1
}
# hive_pidlock <pidfile>: takes a pidfile lock for this shell ($$; noclobber makes the create atomic). Exit 1 when a live
# process holds it; a stale file (dead pid) is replaced. hive_pidunlock <pidfile> removes it only while it holds our pid.
hive_pidlock() {
  local p i
  for i in 1 2; do
    ( set -C; echo "$$" > "$1" ) 2>/dev/null && return 0
    p=$(tr -d '\r ' 2>/dev/null < "$1")
    [ "$p" = "$$" ] && return 0
    case $p in ''|*[!0-9]*) ;; *) kill -0 "$p" 2>/dev/null && return 1;; esac
    rm -f "$1"
  done
  return 1
}
hive_pidunlock() { [ "$(tr -d '\r ' 2>/dev/null < "$1")" = "$$" ] && rm -f "$1"; return 0; }
# hive_beacon <handle>: sets b_pace (AHEAD/ON_PACE/BEHIND from pace=, empty if absent) b_age (s, 999999 if none) b_p5 b_r5 b_used b_reset (7d) b_at (ISO stamp) from the handle's newest
# USAGE line, or from this account's own usage-snapshot.json. Percent values are floored and empty when unknown ("?", or a
# 1970 reset). The age is from at= (when the snapshot was taken) when present. Run hive_usage_backfill first so a machine
# that was off does not decide on an empty or stale inbox.
hive_beacon() {
  local line rest ts e w p7 r7; b_pace=""; b_age=999999; b_p5=""; b_r5=""; b_used=""; b_reset=""; b_at=""
  if [ "$1" = "$HIVE_ACCOUNT" ]; then
    local snap=$HIVE_STATE/usage-snapshot.json; [ -s "$snap" ] || return 0
    e=$(hive_mtime "$snap") || return 0
    rest=$(jq -r '"\(.rate_limits.five_hour.used_percentage // "?"|if type=="number" then floor else . end)% \(.rate_limits.seven_day.used_percentage // "?"|if type=="number" then floor else . end)% \(.rate_limits.seven_day.resets_at // 0|floor|todate) r5=\(.rate_limits.five_hour.resets_at // 0|floor|todate)"' "$snap" 2>/dev/null) || return 0
  else
    line=$(awk -F'|' -v h="$1" '$2==h && $3=="USAGE" && $1+0>=m {m=$1+0; l=$0} END {print l}' "$HIVE_INBOX" 2>/dev/null)
    [ -n "$line" ] || return 0
    e=${line%%|*}; e=${e%.*}; rest=${line#*|*|*|}
    ts=$(echo "$rest" | sed -n 's/.* at=\([0-9TZ:-]*\).*/\1/p'); [ -n "$ts" ] && { w=$(hive_iso_to_epoch "$ts") && e=$w; }
  fi
  b_age=$(( $(date +%s) - e )); b_at=$(TZ=UTC hive_fmt "$e" +%Y-%m-%dT%H:%M:%SZ)
  read -r b_p5 p7 r7 _ <<EOT
$rest
EOT
  b_p5=${b_p5%\%}; b_p5=${b_p5%.*}; p7=${p7%\%}; p7=${p7%.*}
  case $rest in *" pace="*) b_pace=${rest#* pace=}; b_pace=${b_pace%% *};; esac
  b_r5=$(echo "$rest" | sed -n 's/.*r5=\([0-9TZ:-]*\).*/\1/p')
  case $b_p5 in ''|*[!0-9]*) b_p5="";; esac
  case $b_r5 in 1970-01-01*) b_p5=""; b_r5="";; esac
  case $p7 in ''|*[!0-9]*) p7="";; esac
  case $r7 in 1970-01-01*|'') p7=""; r7="";; esac
  b_used=$p7; b_reset=$r7
}
# hive_usage_backfill: when the inbox's newest USAGE line is missing or 30+ min old (listener down, machine was off; a live
# listener gets one every 15 min per account), fills it from the channel's cache (hive-msg.sh backfill: ntfy poll of the
# last 12h) before anyone reads beacons. At most one poll per 15 min (stamp file).
hive_usage_backfill() {
  [ "$SINGLE_ACCOUNT" = 1 ] && return 0
  local n m s; n=$(date +%s)
  m=$(awk -F'|' '$3=="USAGE" && $1+0>m {m=$1+0} END {print m+0}' "$HIVE_INBOX" 2>/dev/null); m=${m:-0}
  [ $(( n - ${m%.*} )) -lt 1800 ] && return 0
  s=$(hive_mtime "$HIVE_STATE/.msg-backfill-last" || true); s=${s:-0}
  [ $(( n - s )) -lt 900 ] && return 0
  touch "$HIVE_STATE/.msg-backfill-last"
  bash "$HIVE_DIR/hive-msg.sh" backfill >/dev/null 2>&1 || true
}
# hive_channel_fresh: 0 when the inbox holds at least one other account's USAGE line younger than BEACON_FRESH_HOURS. With
# none (no channel configured, listener down and backfill failed) there is no beacon evidence: callers make no decision.
hive_channel_fresh() {
  awk -F'|' -v me="$HIVE_ACCOUNT" -v now="$(date +%s)" -v w="$(( BEACON_FRESH_HOURS * 3600 ))" '$3=="USAGE" && $2!=me && now-$1<w {f=1} END {exit !f}' "$HIVE_INBOX" 2>/dev/null
}
# hive_claude_at: epoch of the newest write to any Claude Code transcript (*.jsonl, sessions and subagents) under this
# account's projects/ dir, i.e. the last message or tool call of any session. The status line and supervisors rewrite
# usage-snapshot.json without a session, so its mtime is not evidence. The projects dir comes from the snapshot's
# transcript_path (Windows backslashes normalised). Empty when unknown.
hive_claude_at() {
  local tp pd f m best=0
  tp=$(jq -r '.transcript_path // empty' "$HIVE_STATE/usage-snapshot.json" 2>/dev/null | tr '\\' / | tr -d '\r'); [ -n "$tp" ] || return 0
  pd=$(dirname "$(dirname "$tp")"); [ -d "$pd" ] || return 0
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    m=$(hive_mtime "$f"); [ "${m:-0}" -gt "$best" ] && best=$m
  done <<EOT
$(find "$pd" -maxdepth 4 -name '*.jsonl' -mmin -1440 2>/dev/null)
EOT
  if [ "$best" = 0 ]; then best=$(hive_mtime "$tp") || return 0; fi
  [ -n "$best" ] && echo "$best"
  return 0
}
# hive_peer_claude_at <handle>: epoch from the handle's newest USAGE line's claude_at=, empty when that line is over 1 h old
# or carries none (an older line's value is never reused).
hive_peer_claude_at() {
  local line e ts
  line=$(awk -F'|' -v h="$1" '$2==h && $3=="USAGE" && $1+0>=m {m=$1+0; l=$0} END {print l}' "$HIVE_INBOX" 2>/dev/null)
  [ -n "$line" ] || return 0
  e=${line%%|*}; e=${e%.*}; [ $(( $(date +%s) - e )) -lt 3600 ] || return 0
  ts=$(echo "$line" | sed -n 's/.* claude_at=\([0-9TZ:-]*\).*/\1/p'); [ -n "$ts" ] || return 0
  hive_iso_to_epoch "$ts"
}

# ---- usage-limit stall ------------------------------------------------------------------------------------
# A Claude session stopped on a usage/session limit stays open but does nothing, so "is it running" is not enough.
# hive_limit_stalled: true when AT mode is on, no transcript for ROOT changed in STALL_MINUTES, and the newest one ends
# on a limit error. Only the main session's transcript is checked (see below).
: "${STALL_MINUTES:=15}"
hive_project_dir() { echo "$HOME/.claude/projects/$(printf '%s' "$ROOT" | sed 's#[^A-Za-z0-9]#-#g')"; }
hive_limit_stalled() {
  [ "$(cat "$HIVE_STATE/at-mode" 2>/dev/null || echo AT)" = AT ] || return 1
  local d; d=$(hive_project_dir); [ -d "$d" ] || return 1
  [ -n "$(find "$d" -name '*.jsonl' -mmin -"$STALL_MINUTES" 2>/dev/null | head -1)" ] && return 1
  # Only a stuck MAIN session counts. A subagent that died on a limit under a live main session is that
  # session's job to resume; restarting it from here too runs the same work twice. Main transcripts sit
  # directly in the project dir; subagent ones live under <session>/subagents/.
  local newest; newest=$(find "$d" -maxdepth 1 -name '*.jsonl' -mtime -2 -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1)
  [ -n "$newest" ] && tail -c 20000 "$newest" | grep -qE 'hit your (session|usage|weekly) limit|usage limit reached|"rate_limit"'
}

# hive_login_expired: true when the newest main transcript's last assistant entry is Claude Code's "Login reached
# its time limit / Please run /login" notice. A long-running session's OAuth login can expire while the keychain
# holds a fresh one (any other session refreshed it); the session then answers every nudge with that notice and
# does nothing (2026-11-19, tommykneeland: logged out from 09:10 until a human looked). A restart picks the
# fresh login up.
hive_login_expired() {
  local d; d=$(hive_project_dir); [ -d "$d" ] || return 1
  local newest; newest=$(find "$d" -maxdepth 1 -name '*.jsonl' -mtime -2 -print0 2>/dev/null | xargs -0 ls -t 2>/dev/null | head -1)
  [ -n "$newest" ] || return 1
  tail -c 200000 "$newest" | grep '"type":"assistant"' | tail -n 1 | grep -qE 'Please run /login|Login reached its time limit'
}

# hive_session_idle: true when AT mode is on, the worker target is above 0, and no transcript for ROOT (main or
# subagent, so a running worker counts as activity) changed in IDLE_NUDGE_MINUTES. A session that ended its turn
# with tickets or blocked PRs waiting otherwise sits idle until a human types (2026-11-13: two accounts idle all
# night). Limit stalls are hive_limit_stalled's job, so a session parked on a limit is not "idle".
: "${IDLE_NUDGE_MINUTES:=30}"
hive_session_idle() {
  [ "$(cat "$HIVE_STATE/at-mode" 2>/dev/null || echo AT)" = AT ] || return 1
  local d; d=$(hive_project_dir); [ -d "$d" ] || return 1
  [ -n "$(find "$d" -name '*.jsonl' -mmin -"$IDLE_NUDGE_MINUTES" 2>/dev/null | head -1)" ] && return 1
  [ -n "$(find "$d" -name '*.jsonl' 2>/dev/null | head -1)" ] || return 1
  hive_limit_stalled && return 1
  [ "$(hive_worker_target 2>/dev/null || echo 0)" -gt 0 ]
}
