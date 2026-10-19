# #683 verification (82ec3bf + merge of main)
- Worker: `pf-atlas.sh run '683|680|239|relay|remote'` gave 88/88. Full suite: 847 passed, 1 failed. The failure is the known local `axe_wins_clash_against_every_weapon`. Fresh-clone boot check: clean.
- After merging main (strings.csv append blocks unioned to 414 unique keys, 10 columns; translations reimported), `pf-atlas.sh run '683|688|693|680'` gave 13/13.
- Relay round trip tested in-process against Relay.gd over real WebSockets. Phone page JS passes `node --check`; it was not run in a real browser, and the Pages-hosted page is untested until Pages is live.
- ADR-0025 records phones over the relay as a transport in Local matches, not a mixed match kind.
- Known limits: the phone/PC hello gate is not a security boundary; a stale Pages page skips the build check.
