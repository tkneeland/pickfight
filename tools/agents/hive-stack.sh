#!/bin/bash
# Usage: hive-stack.sh list | next | triage | review | claim <owner/repo> <n> | checkout <owner/repo>
# The studio's project priority stack (hive.md rule 28): the studio repo's hive/projects.conf, edited from the hub, top line
# first. Workers take tickets by project rank first, then p1/p2/p3, so work on a repo ranked above this game comes first.
#   list               the stack, one repo per line (this game's REPO appended when the stack doesn't list it)
#   next               the first ready ticket this account may take in a repo ranked ABOVE this game: "<repo> <n> <title>",
#                      exit 0; nothing above has one: exit 1. In a hive game (its repo has a hive.conf) only tickets its
#                      triagemaster assigned to this account count (rule 5). In a repo with no hive of its own (the hive's
#                      own repo, claude-hive) any open ready-for-agent ticket counts that nobody is assigned to or claimed
#                      in the last 24h. Order: p1, p2, p3, unlabelled, then oldest.
#   triage             the repos with no hive of their own that ranks above every hive game: their triage falls to the
#                      triagemaster of the highest-ranked hive game. On that machine it prints "<repo> <n> <title>" for each
#                      open issue there that is not triaged yet (no ready-for-agent, ready-for-human, needs-info or wontfix
#                      label, so needs-triage and unlabelled ones), exit 0; on any other machine, or with none, exit 1.
#   review             on that same machine: "<repo> <n> <title>" for each open, non-draft PR in those repos that is not
#                      marked review-passed or review-blocked yet (the triagemaster reviews and merges them, rule 28),
#                      exit 0; on any other machine, or with none, exit 1.
#   claim <repo> <n>   take such a self-serve ticket: refuses one already assigned or claimed; assigns this account and
#                      comments "[CLAIM] <account>". Exit 1 when someone else has it.
#   checkout <repo>    a clone of the repo for working its tickets, in $HIVE_CHECKOUT_DIR/<repo-name> (default: beside this
#                      game's checkout; never under ~/.claude, where headless sessions cannot edit), fetched
#                      and on its default branch; prints the path. An old clone under ~/.claude/hive/checkouts is moved
#                      when clean, else left alone with a note. Work there in a worktree, never on its default branch.
# Without STUDIO_REPO (or an empty stack) nothing ranks above this game: next exits 1.
. "$(dirname "$0")/hive-env.sh" || exit 2
cmd=${1:-}
stack_file=$HIVE_STUDIO_CACHE/projects.conf
lc() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }

stack() {
  local l seen=" "
  if [ -n "$STUDIO_REPO" ] && [ -s "$stack_file" ]; then
    while IFS= read -r l || [ -n "$l" ]; do
      l=${l%%#*}; l=${l//[[:space:]]/}
      case $l in */*) ;; *) continue;; esac
      case "$seen" in *" $(lc "$l") "*) continue;; esac
      seen+="$(lc "$l") "; echo "$l"
    done < "$stack_file"
  fi
  [ -n "${REPO:-}" ] && case "$seen" in *" $(lc "$REPO") "*) ;; *) echo "$REPO";; esac
}

# a repo with its own hive (a hive.conf at its root) has a triagemaster who assigns; cached a day per repo
has_hive() {
  local f="$HIVE_STUDIO_CACHE/.has-hive.$(lc "${1/\//__}")" v m
  m=$(hive_mtime "$f" || echo 0)
  if [ $(( $(date +%s) - ${m:-0} )) -lt 86400 ] && read -r v < "$f" 2>/dev/null; then [ "$v" = 1 ]; return; fi
  if gh api "repos/$1/contents/hive.conf" --silent 2>/dev/null; then v=1
  else case $(gh api "repos/$1/contents/hive.conf" 2>&1) in *"Not Found"*|*404*) v=0;; *) return 0;; esac; fi
  mkdir -p "$HIVE_STUDIO_CACHE" && echo "$v" > "$f"
  [ "$v" = 1 ]
}

# "<n>\t<title>" for each ready ticket this account may take in a repo, best first
ready_in() {
  local repo=$1 me; me=$(lc "$HIVE_ACCOUNT")
  local q='[.[] | {n: .number, t: .title, a: [.assignees[].login | ascii_downcase], p: ([.labels[].name] | if index("p1") then 1 elif index("p2") then 2 elif index("p3") then 3 else 4 end)}]'
  local all; all=$(gh issue list -R "$repo" -s open -l ready-for-agent -L 100 --json number,title,assignees,labels -q "$q" 2>/dev/null) || return 0
  if has_hive "$repo"; then
    printf '%s' "$all" | jq -r --arg me "$me" '[.[] | select(.a | index($me))] | sort_by(.p, .n) | .[] | "\(.n)\t\(.t)"'
  else
    printf '%s' "$all" | jq -r --arg me "$me" '[.[] | select((.a | length) == 0 or (.a | index($me)))] | sort_by(.p, .n) | .[] | "\(.n)\t\(.t)"' |
      while IFS=$'\t' read -r n t; do
        claimed_by_other "$repo" "$n" && continue
        printf '%s\t%s\n' "$n" "$t"
      done
  fi
}

# true when someone other than this account wrote "[CLAIM]" on the issue in the last 24h
claimed_by_other() {
  local since; since=$(( $(date +%s) - 86400 ))
  gh api "repos/$1/issues/$2/comments?per_page=100" -q ".[] | select(.body | startswith(\"[CLAIM]\")) | \"\(.user.login) \(.created_at)\"" 2>/dev/null |
    while read -r who at; do
      [ "$(lc "$who")" = "$(lc "$HIVE_ACCOUNT")" ] && continue
      t=$(hive_iso2epoch "$at")
      [ "${t:-0}" -ge "$since" ] && { echo x; break; }
    done | grep -q x
}

case $cmd in
  list) hive_studio_sync; stack ;;
  triage|review)
    hive_studio_sync
    hive_is_triagemaster || exit 1
    top=""; selfserve=()
    while read -r repo; do
      if has_hive "$repo"; then top=$repo; break; fi
      selfserve+=("$repo")
    done < <(stack)
    [ "$(lc "$top")" = "$(lc "${REPO:-}")" ] && [ ${#selfserve[@]} -gt 0 ] || exit 1
    out=""
    for repo in "${selfserve[@]}"; do
      if [ "$cmd" = triage ]; then
        out+=$(gh issue list -R "$repo" -s open -L 100 --json number,title,labels \
          -q '.[] | select([.labels[].name] | any(. == "ready-for-agent" or . == "ready-for-human" or . == "needs-info" or . == "wontfix") | not) | "'"$repo"' \(.number) \(.title)"' 2>/dev/null)
      else
        out+=$(gh pr list -R "$repo" -s open -L 100 --json number,title,labels,isDraft \
          -q '.[] | select((.isDraft | not) and ([.labels[].name] | any(. == "review-passed" or . == "review-blocked") | not)) | "'"$repo"' \(.number) \(.title)"' 2>/dev/null)
      fi
      out+=$'\n'
    done
    out=$(printf '%s' "$out" | sed '/^$/d')
    [ -n "$out" ] && { echo "$out"; exit 0; }
    exit 1 ;;
  next)
    hive_studio_sync
    while read -r repo; do
      [ "$(lc "$repo")" = "$(lc "${REPO:-}")" ] && break
      first=$(ready_in "$repo" | head -n 1)
      [ -n "$first" ] && { printf '%s %s\n' "$repo" "${first/$'\t'/ }"; exit 0; }
    done < <(stack)
    exit 1 ;;
  claim)
    repo=${2:-}; n=${3:-}
    case $repo in */*) ;; *) echo "usage: hive-stack.sh claim <owner/repo> <n>" >&2; exit 2;; esac
    case $n in ''|*[!0-9]*) echo "usage: hive-stack.sh claim <owner/repo> <n>" >&2; exit 2;; esac
    who=$(gh issue view "$n" -R "$repo" --json assignees -q '[.assignees[].login] | join(" ")' 2>/dev/null) || { echo "cannot read $repo#$n" >&2; exit 2; }
    for a in $who; do [ "$(lc "$a")" = "$(lc "$HIVE_ACCOUNT")" ] || { echo "$repo#$n is assigned to $a" >&2; exit 1; }; done
    claimed_by_other "$repo" "$n" && { echo "$repo#$n was claimed by someone else in the last 24h" >&2; exit 1; }
    gh issue edit "$n" -R "$repo" --add-assignee "$HIVE_ACCOUNT" >/dev/null || exit 2
    gh issue comment "$n" -R "$repo" --body "[CLAIM] $HIVE_ACCOUNT (project stack: $repo ranks above ${REPO:-this game})" >/dev/null || exit 2
    echo "claimed $repo#$n" ;;
  checkout)
    repo=${2:-}
    case $repo in */*) ;; *) echo "usage: hive-stack.sh checkout <owner/repo>" >&2; exit 2;; esac
    dir=$HIVE_CHECKOUT_DIR/${repo#*/}
    # migrate a clone from the old home, ~/.claude/hive/checkouts/<owner__repo> (headless sessions cannot edit under ~/.claude)
    old=$HOME/.claude/hive/checkouts/${repo/\//__}
    if [ -d "$old/.git" ] && [ "$old" != "$dir" ]; then
      if [ -e "$dir" ]; then echo "note: old clone $old left in place ($dir exists); remove it by hand once nothing needs it" >&2
      elif [ -n "$(git -C "$old" status --porcelain 2>/dev/null)" ] || [ -n "$(git -C "$old" log --branches --not --remotes -n 1 2>/dev/null)" ] \
        || [ "$(git -C "$old" worktree list 2>/dev/null | wc -l)" -gt 1 ]; then
        echo "note: old clone $old has uncommitted changes, unpushed commits or worktrees; left in place, using a fresh clone at $dir" >&2
      else mkdir -p "$HIVE_CHECKOUT_DIR" && mv "$old" "$dir" && echo "note: moved clone $old -> $dir" >&2; fi
    fi
    if [ -d "$dir/.git" ]; then
      git -C "$dir" fetch -q origin && git -C "$dir" checkout -q "$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD | sed 's#^origin/##')" \
        && git -C "$dir" merge -q --ff-only "$(git -C "$dir" symbolic-ref --short refs/remotes/origin/HEAD)" || { echo "cannot update $dir" >&2; exit 2; }
    else
      mkdir -p "$HIVE_CHECKOUT_DIR" && gh repo clone "$repo" "$dir" -- -q || { echo "cannot clone $repo" >&2; exit 2; }
    fi
    echo "$dir" ;;
  *) sed -n '2,/^[^#]/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 2 ;;
esac
