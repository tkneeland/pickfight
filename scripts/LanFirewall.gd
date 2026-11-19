extends RefCounted
## Issue #1268: Windows Firewall blocking Couch phones.
##
## A Couch host serves the phone page and its WebSocket on the LAN. Windows asks
## once, on first launch, whether to let the game through its firewall, and the
## prompt only ticks *Private* networks. Windows 11 files every new Wi-Fi as
## *Public*, so the usual answer silently blocks every phone: the page never
## loads and the host never sees an attempt. This checks, off the main thread,
## whether inbound connections to this executable are allowed on the network the
## join address is on, and can add the rule that lets them in (one Windows admin
## prompt). Nothing runs outside Windows.
##
## `poll()` is called every frame by the lobby. A check is one PowerShell run of
## about 6 s on a worker thread; it repeats every RECHECK_MSEC while the answer
## is not "open" (the player may answer the Windows prompt or fix it by hand), and
## stops once phones can get in.

const SfxScript := preload("res://scripts/Sfx.gd")

## Between checks while not yet open.
const RECHECK_MSEC: int = 20000
## The firewall rule `fix` adds (one per executable path).
const RULE_NAME: String = "Pickfight phones"

## "unknown" (not checked, not Windows, or no answer), "open", "blocked",
## "fixing" (the admin prompt is up) or "fix_failed" (declined, or still blocked after).
var state: String = "unknown"
## The firewall profile of the join address's network: "Public", "Private", "Domain" or "".
var profile: String = ""
## Whether this host can be checked at all: Windows, and not a scripted run (the
## scenario suite, a probe), which must never start PowerShell or a UAC prompt.
## Scenarios that test the lobby set it back on with fake runners.
var supported: bool = OS.get_name() == "Windows" and not SfxScript.is_script_main_loop(Engine.get_main_loop() as SceneTree)
## The executable the rules are about.
var exe_path: String = OS.get_executable_path()
## Test seams. `check_runner.call(script) -> String` returns the check's JSON;
## `fix_runner.call(script) -> int` returns the elevated run's exit code. Both run
## on the worker thread. The defaults run PowerShell.
var check_runner: Callable = _run_powershell_output
var fix_runner: Callable = _run_powershell_exit_code

var _thread: Thread
var _job: String = "" # "check" or "fix", what `_thread` runs
var _next_check_msec: int = 0
var _after_fix: bool = false # the check running now follows a fix
var _checked_ip: String = "" # the join address the last check judged
var _ports: PackedInt32Array = PackedInt32Array()

## A new lobby: check again straight away, whatever was known.
func reset() -> void:
	_next_check_msec = 0

## Whether the lobby should show the warning and the Allow button.
func needs_fix() -> bool:
	return state == "blocked" or state == "fixing" or state == "fix_failed"

## Whether a check or fix is running.
func busy() -> bool:
	return _thread != null

## Collects a finished job and starts a check when one is due. `wanted` is a
## Couch join QR on screen; `ip` the address that QR points at. Returns true
## when `state` changed.
func poll(now_msec: int, wanted: bool, ip: String) -> bool:
	var before: String = state
	if _thread != null and not _thread.is_alive():
		var out: Variant = _thread.wait_to_finish()
		_thread = null
		_finish(_job, out, ip)
		if _job == "fix":
			_start("check", ip) # see what the fix changed, now
	if not supported or not wanted or _thread != null:
		return state != before
	# Open stays open for this address; a new join address (another network) is checked again.
	var due: bool = (state != "open" or ip != _checked_ip) and now_msec >= _next_check_msec
	if due and state != "fixing":
		_next_check_msec = now_msec + RECHECK_MSEC
		_start("check", ip)
	return state != before

## Asks Windows (one admin prompt) to let phones in on `ports` (the page's and the
## WebSocket's). Does nothing while a job runs or when nothing needs fixing.
func fix(ports: PackedInt32Array) -> bool:
	if not supported or _thread != null or not needs_fix():
		return false
	_ports = ports
	state = "fixing"
	_start("fix", "")
	return true

## Waits for a running check (scenarios, and quitting with one in flight: a few
## seconds at most). A fix waits on the Windows admin prompt for as long as nobody
## answers it, so quitting never waits for one; that thread is left to end on its own.
func finish_now() -> void:
	if _thread != null and _job == "check":
		_thread.wait_to_finish()
		_thread = null

func _start(job: String, ip: String) -> void:
	_job = job
	if job == "check":
		_checked_ip = ip
	_after_fix = job == "check" and state == "fixing"
	var script: String = check_script(exe_path) if job == "check" else fix_script(exe_path, _ports)
	var runner: Callable = check_runner if job == "check" else fix_runner
	_thread = Thread.new()
	_thread.start(runner.bind(script))

func _finish(job: String, out: Variant, ip: String) -> void:
	if job == "fix":
		if int(out) != 0:
			state = "fix_failed" # declined or refused: the check that follows can still find it open
		return
	var report: Variant = JSON.parse_string(str(out)) if out is String else null
	var verdict: Dictionary = evaluate(report as Dictionary if report is Dictionary else {}, ip)
	profile = verdict["profile"]
	var got: String = verdict["state"]
	if _after_fix or state == "fix_failed":
		state = "open" if got == "open" else ("fix_failed" if got == "blocked" else got)
	else:
		state = got
	_after_fix = false

## The verdict for one check's report: {"state": "open"|"blocked"|"unknown", "profile"}.
## Inbound to this program on the join address's network is blocked when a block
## rule covers it (block wins over allow in Windows Firewall), or when no allow
## rule does and the profile's default is to block (also what Windows does while
## its own prompt is unanswered). A profile with the firewall off is open.
static func evaluate(report: Dictionary, ip: String) -> Dictionary:
	var nets: Array = _as_array(report.get("nets", []))
	var category: String = ""
	for net: Variant in nets:
		if net is Dictionary and _as_array(net.get("ips", [])).has(ip):
			category = str(net.get("category", ""))
			break
	if category == "" and nets.size() == 1 and nets[0] is Dictionary:
		category = str(nets[0].get("category", ""))
	var name: String = "Domain" if category == "DomainAuthenticated" else category
	if not name in ["Public", "Private", "Domain"]:
		return {"state": "unknown", "profile": ""}
	if report.get("rules") == null:
		return {"state": "unknown", "profile": name} # the rules query failed: no verdict, not "no rules"
	var firewall: Variant = report.get("firewall", {})
	var settings: Variant = (firewall as Dictionary).get(name) if firewall is Dictionary else null
	if not settings is Dictionary:
		return {"state": "unknown", "profile": name}
	if str(settings.get("on", "")) != "True":
		return {"state": "open", "profile": name}
	var allowed: bool = false
	for rule: Variant in _as_array(report.get("rules", [])):
		if not rule is Dictionary:
			continue
		if not _covers(str(rule.get("profile", "")), name):
			continue
		if not str(rule.get("protocol", "")) in ["TCP", "Any", ""]:
			continue
		match str(rule.get("action", "")):
			"Block":
				return {"state": "blocked", "profile": name}
			"Allow":
				allowed = true
	if allowed or str(settings.get("def", "")) == "Allow":
		return {"state": "open", "profile": name}
	return {"state": "blocked", "profile": name}

## Whether a rule's profile list ("Any", "Public", "Private, Public", ...) covers `name`.
static func _covers(rule_profiles: String, name: String) -> bool:
	if rule_profiles == "Any" or rule_profiles == "":
		return true
	for part: String in rule_profiles.split(","):
		if part.strip_edges() == name:
			return true
	return false

## ConvertTo-Json writes a one-item array as the item on some PowerShell versions.
static func _as_array(value: Variant) -> Array:
	if value is Array:
		return value
	if value == null:
		return []
	return [value]

## A PowerShell single-quoted string literal.
static func _ps_quote(text: String) -> String:
	return "'" + text.replace("'", "''") + "'"

## Prints one JSON line: the connected networks (category and IPv4 addresses),
## each firewall profile's on/off and default inbound action, and the enabled
## inbound rules for `exe` (action, profiles, protocol), or null rules when that
## query fails. The firewall keeps paths lower-cased and `-Program` matches
## case-sensitively, so every application filter is compared case-insensitively
## here, with %VARS% expanded. The active store merges local and Group Policy rules
## and settings, which is what Windows enforces.
static func check_script(exe: String) -> String:
	return "\n".join([
		"$ErrorActionPreference = 'SilentlyContinue'",
		"$want = [IO.Path]::GetFullPath(%s)" % _ps_quote(exe),
		"$nets = @(Get-NetConnectionProfile | ForEach-Object { @{ category = [string]$_.NetworkCategory; ips = @(Get-NetIPAddress -InterfaceIndex $_.InterfaceIndex -AddressFamily IPv4 | ForEach-Object { $_.IPAddress }) } })",
		"$fw = @{}",
		"Get-NetFirewallProfile -PolicyStore ActiveStore | ForEach-Object { $fw[[string]$_.Name] = @{ on = [string]$_.Enabled; def = [string]$_.DefaultInboundAction } }",
		"try { $rules = @(Get-NetFirewallApplicationFilter -PolicyStore ActiveStore -ErrorAction Stop | Where-Object { $_.Program -and [Environment]::ExpandEnvironmentVariables($_.Program) -ieq $want } | Get-NetFirewallRule | Where-Object { [string]$_.Direction -eq 'Inbound' -and [string]$_.Enabled -eq 'True' } | ForEach-Object { @{ action = [string]$_.Action; profile = [string]$_.Profile; protocol = [string]($_ | Get-NetFirewallPortFilter).Protocol } }) } catch { $rules = $null }",
		"@{ nets = $nets; firewall = $fw; rules = $rules } | ConvertTo-Json -Compress -Depth 5",
	])

## Run elevated: turns off this program's inbound block rules (they beat any allow),
## replaces its own earlier rule and allows TCP in on `ports` on every profile.
## Exits non-zero when anything fails (a policy-managed rule, say).
static func fix_script(exe: String, ports: PackedInt32Array) -> String:
	var port_list: PackedStringArray = PackedStringArray()
	for port: int in ports:
		if port > 0:
			port_list.append(str(port))
	var port_arg: String = (" -LocalPort " + ",".join(port_list)) if not port_list.is_empty() else ""
	return "\n".join([
		"$ErrorActionPreference = 'Stop'",
		"try {",
		"  $want = [IO.Path]::GetFullPath(%s)" % _ps_quote(exe),
		"  $mine = @(Get-NetFirewallApplicationFilter | Where-Object { $_.Program -and [Environment]::ExpandEnvironmentVariables($_.Program) -ieq $want } | Get-NetFirewallRule)",
		"  $mine | Where-Object { [string]$_.Direction -eq 'Inbound' -and [string]$_.Action -eq 'Block' } | Disable-NetFirewallRule",
		"  $mine | Where-Object { $_.DisplayName -eq %s } | Remove-NetFirewallRule" % _ps_quote(RULE_NAME),
		"  New-NetFirewallRule -DisplayName %s -Direction Inbound -Action Allow -Program $want -Protocol TCP%s -Profile Any | Out-Null" % [_ps_quote(RULE_NAME), port_arg],
		"  exit 0",
		"} catch { exit 1 }",
	])

## PowerShell's -EncodedCommand: the script as base64 UTF-16LE, so no quoting survives to the command line.
static func encode(script: String) -> String:
	return Marshalls.raw_to_base64(script.to_utf16_buffer())

static func _run_powershell_output(script: String) -> String:
	var out: Array = []
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encode(script)], out)
	return str(out[0]) if not out.is_empty() else ""

## Starts `script` in an elevated PowerShell (the UAC prompt) and waits for it.
## A declined prompt makes Start-Process throw: exit 1223, Windows' "cancelled".
static func _run_powershell_exit_code(script: String) -> int:
	var launcher: String = "\n".join([
		"try {",
		"  $p = Start-Process powershell.exe -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile','-NonInteractive','-ExecutionPolicy','Bypass','-EncodedCommand','%s'" % encode(script),
		"  exit $p.ExitCode",
		"} catch { exit 1223 }",
	])
	return OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-EncodedCommand", encode(launcher)])
