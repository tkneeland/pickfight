extends RefCounted
## What the host's screen shows beyond the world snapshot, as one small dict
## for a remote seat (issue #436): the round result, the scoreboard rows, the
## announcer banner, and the game mode's own HUD (King of the Hill holds,
## flag and ball scores, potato fuse, stock lives). The host streams it as a
## `{"t":"hud", ...}` text frame when it changes, a few times a second, never
## per frame; every value is rounded so a held pose does not look like change.
## Read-only: it never writes to the RoundManager or a mode node. Preload by
## path; never reference it by `class_name` (CLAUDE.md).

const STATE_ROUND_END: int = 2
const STATE_VICTORY: int = 5

static func capture(rm: Node) -> Dictionary:
	var state: int = int(rm.get("_state"))
	var hud: Dictionary = {"t": "hud", "state": state, "mode": str(rm.get("game_mode"))}
	var rows: Array = []
	for slot: int in rm.call("_roster"):
		rows.append([slot, str(rm.call("_slot_name", slot)), rm.score_of(slot)])
	if state == STATE_ROUND_END or state == STATE_VICTORY:
		rows = rows.duplicate()
		rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[2]) > int(b[2]))
	hud["board"] = rows
	if state == STATE_ROUND_END:
		hud["round_winner"] = int(rm.get("_last_winner_slot"))
		hud["round_winner_team"] = int(rm.get("_last_winner_team"))
	var feed: Control = rm.kill_feed()
	if feed != null:
		var banner: Control = feed.get("_banner")
		if banner != null and banner.visible:
			hud["banner"] = [str(feed.get("_banner_headline").text), str(feed.get("_banner_name").text)]
	var node: Variant = rm.get("_game_mode_node")
	if node != null and (state == 1 or state == 2):
		hud["m"] = _mode(str(rm.get("game_mode")), node, rm)
	return hud

static func _mode(id: String, node: Object, rm: Node) -> Dictionary:
	match id:
		"king_of_the_hill":
			var hold: Dictionary = {}
			for slot: int in node.get("hold_time"):
				hold[slot] = roundi(float(node.hold_time[slot]))
			return {"hold": hold, "win": roundi(float(node.seconds_to_win)),
				"moving": bool(node.get("hill_warning")),
				"team_hold": [roundi(node.team_hold_of(0)), roundi(node.team_hold_of(1))]}
		"capture_the_flag":
			return {"score": [int(node.scores[0]), int(node.scores[1])], "flag": [int(node.state[0]), int(node.state[1])],
				"carrier": [int(node.carrier[0]), int(node.carrier[1])], "win": int(node.captures_to_win)}
		"soccer":
			return {"score": [int(node.scores[0]), int(node.scores[1])], "win": int(node.goals_to_win)}
		"hot_potato":
			return {"it": int(node.it_slot), "fuse": ceili(float(node.fuse_left))}
		"stock":
			var lives: Dictionary = {}
			for slot: int in rm.get("_in_round"):
				lives[slot] = int(node.lives_of(slot))
			return {"lives": lives, "clock": str(node.clock_text())}
	return {}
