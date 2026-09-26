# Issue #147 evidence

- `full-suite.txt`: every scenario in `SCENARIO_NAMES`, run on main `d00dba3` as 5 parallel `--scenarios=` shards. **177 passed, 1 failed, 178 total.**
- The one failure is `controller_page_look_picker_after_name`, a #151 scenario. It looks for LF line endings in `controller/index.html`, and this Windows checkout (autocrlf) has CRLF. It passes on an LF clone of the same commit; that rerun is at the end of `full-suite.txt`. #147 doesn't touch that page.
- Fresh-clone boot: the only ERROR is qrencode "Could not create child process", which is an environment issue (qrencode isn't installed here).
