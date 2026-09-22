# AC5 latency feel — verdict

**Verdict:** PASS

**Command/action:** human drags continuously for ~15s and attempts a deliberate pole swing, phone on the same Wi-Fi as the host.

**Prerequisite re-check:** `system_profiler SPAirPortDataType` on the host showed 802.11ac, channel 157 (5GHz, 80MHz) immediately before the test.

**Environment:** iPhone and host Mac both on the Mac's main Wi-Fi network (the phone was initially on a separate guest Wi-Fi network, which caused V3 to fail with a stuck-loading controller page; moving the phone to the main network resolved it and is a prerequisite for this and every other human-gated criterion).

**Operator report (verbatim, from conversation):**
> the controls are responsive and the iphone site ui looks perfect

**Scope note:** the operator separately raised that the resulting *movement mechanic* (extending pole with knockback) isn't the gameplay feel they want long-term (pickaxe/Getting-Over-It-style traversal instead). That is a design change to `Player.gd`'s existing mechanic, predating this ticket, and is out of scope for issue #1 (phone controller input transport). Filed as [issue #2](https://github.com/tkneeland/pickfight/issues/2). It does not affect this criterion, which is about input transport latency, not mechanic feel.
