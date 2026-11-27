#!/bin/bash
# Offline test for hive-tm-check.sh's studio-wide review gate (hive.md rules 7, 12, 28): on the triagemaster, an open
# non-draft PR in another stacked repo with no review label 2h+ after it opened is a WARN; drafts, labelled, fresh PRs and
# this game's own repo (check 7 covers it) are not; another account never sees it. Stub gh, no network.
#   bash tools/agents/tests/tm-check-stack.sh
. "$(dirname "$0")/lib.sh"
T=$(mktemp -d "${TMPDIR:-/tmp}/hive-tmcheck-test.XXXXXX") || exit 1
hive_test_guard
hive_fixture "$T" "STUDIO_REPO=example/studio" || exit 1
mkdir -p "$T/bin" "$T/state" "$T/studio" "$T/gh"
cat > "$T/bin/gh" <<'STUB'
#!/bin/bash
# a tiny gh: PRs per repo in $GHD/<owner__repo>.prs.json; everything else empty
repo=""; args=("$@")
for ((i = 0; i < ${#args[@]}; i++)); do case ${args[i]} in --repo|-R) repo=${args[i+1]};; esac; done
case "$1 $2" in
  "api user") echo alice;;
  "pr list") f="$GHD/${repo/\//__}.prs.json"; [ -f "$f" ] && cat "$f" || echo '[]';;
  *) echo '[]';;
esac
STUB
chmod +x "$T/bin/gh"; hive_stub_jq "$T/bin"
git init -q "$T/root"; git -C "$T/root" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
export PATH="$T/bin:$PATH" HIVE_STATE_DIR=$T/state HIVE_STUDIO_CACHE=$T/studio REPO_PATH=$T/root GHD=$T/gh HIVE_TM_CHECK_SKIP_PROCS=1
hive_require_stub "$T/bin" gh
pass=0; fail=0
check() { if [ "$2" = "$3" ]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL $1: got '$2', want '$3'"; fi; }
tmc() { HIVE_ACCOUNT=${ACCT:-alice} bash "$AG/hive-tm-check.sh" 2>/dev/null | grep -i 'stacked-repo'; }
touch "$T/studio/.synced-at"
echo alice > "$T/state/triagemaster"
printf 'example/hive\nexample/project\nexample/game2\n' > "$T/studio/projects.conf"
old=2020-01-01T00:00:00Z; new=$(date -u +%Y-%m-%dT%H:%M:%SZ)
pr() { printf '{"number":%s,"createdAt":"%s","isDraft":%s,"labels":%s}' "$1" "$2" "$3" "$4"; }
echo "[$(pr 40 $old false '[]'),$(pr 41 $old true '[]'),$(pr 42 $old false '[{"name":"review-passed"}]'),$(pr 43 $new false '[]')]" > "$T/gh/example__hive.prs.json"
echo "[$(pr 50 $old false '[{"name":"p2"}]'),$(pr 51 $old false '[{"name":"review-blocked"}]')]" > "$T/gh/example__game2.prs.json"
echo "[$(pr 60 $old false '[]')]" > "$T/gh/example__project.prs.json"   # this game: check 7's job, not 7b's
check "tm: stale unlabelled PRs in other stacked repos" "$(tmc)" "WARN stacked-repo PR(s) open 2h+ with no review label: example/hive#40 example/game2#50: review them now with your reviewer subagent (hive-stack.sh review; rules 12, 28)"
check "not tm: no line" "$(ACCT=bob tmc)" ""
echo '[]' > "$T/gh/example__hive.prs.json"; echo '[]' > "$T/gh/example__game2.prs.json"
check "tm: nothing waiting" "$(tmc)" "PASS no stacked-repo PR waits 2h+ for review"
echo "tm-check-stack: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
