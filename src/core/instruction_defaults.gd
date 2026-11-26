class_name InstructionDefaults
extends RefCounted

## Role-derived baseline instructions. Each role_id maps to a neutral starting
## point that data/instructions.json can override per player.

const D := FMEnums.Duty
const SD := FMEnums.SupportDepth
const W := FMEnums.WidthMode
const R := FMEnums.Runs
const P := FMEnums.Pressing
const TA := FMEnums.TackleAggression
const PR := FMEnums.PassingRisk

const ROLE_BASELINES := {
	"gk": {
		"duty": D.DEFEND, "support_depth": SD.DEEP, "width": W.NARROW,
		"runs": R.HOLD, "pressing": P.LOW, "tackle_aggression": TA.CAUTIOUS,
		"passing_risk": PR.SAFE, "shoot_on_sight": false, "man_mark": false,
	},
	"cb": {
		"duty": D.DEFEND, "support_depth": SD.DEEP, "width": W.NARROW,
		"runs": R.HOLD, "pressing": P.LOW, "tackle_aggression": TA.BALANCED,
		"passing_risk": PR.SAFE, "shoot_on_sight": false, "man_mark": false,
	},
	"lb": {
		"duty": D.SUPPORT, "support_depth": SD.STANDARD, "width": W.WIDE,
		"runs": R.BALANCED, "pressing": P.STANDARD, "tackle_aggression": TA.BALANCED,
		"passing_risk": PR.BALANCED, "shoot_on_sight": false, "man_mark": false,
	},
	"rb": {
		"duty": D.SUPPORT, "support_depth": SD.STANDARD, "width": W.WIDE,
		"runs": R.BALANCED, "pressing": P.STANDARD, "tackle_aggression": TA.BALANCED,
		"passing_risk": PR.BALANCED, "shoot_on_sight": false, "man_mark": false,
	},
	"dm": {
		"duty": D.DEFEND, "support_depth": SD.DEEP, "width": W.STANDARD,
		"runs": R.HOLD, "pressing": P.STANDARD, "tackle_aggression": TA.BALANCED,
		"passing_risk": PR.SAFE, "shoot_on_sight": false, "man_mark": false,
	},
	"cm": {
		"duty": D.SUPPORT, "support_depth": SD.STANDARD, "width": W.STANDARD,
		"runs": R.BALANCED, "pressing": P.HIGH, "tackle_aggression": TA.BALANCED,
		"passing_risk": PR.BALANCED, "shoot_on_sight": false, "man_mark": false,
	},
	"am": {
		"duty": D.ATTACK, "support_depth": SD.ADVANCED, "width": W.STANDARD,
		"runs": R.FORWARD, "pressing": P.HIGH, "tackle_aggression": TA.CAUTIOUS,
		"passing_risk": PR.RISKY, "shoot_on_sight": false, "man_mark": false,
	},
	"lw": {
		"duty": D.ATTACK, "support_depth": SD.ADVANCED, "width": W.WIDE,
		"runs": R.FORWARD, "pressing": P.STANDARD, "tackle_aggression": TA.CAUTIOUS,
		"passing_risk": PR.RISKY, "shoot_on_sight": true, "man_mark": false,
	},
	"rw": {
		"duty": D.ATTACK, "support_depth": SD.ADVANCED, "width": W.WIDE,
		"runs": R.FORWARD, "pressing": P.STANDARD, "tackle_aggression": TA.CAUTIOUS,
		"passing_risk": PR.RISKY, "shoot_on_sight": true, "man_mark": false,
	},
	"st": {
		"duty": D.ATTACK, "support_depth": SD.ADVANCED, "width": W.NARROW,
		"runs": R.FORWARD, "pressing": P.STANDARD, "tackle_aggression": TA.CAUTIOUS,
		"passing_risk": PR.RISKY, "shoot_on_sight": true, "man_mark": false,
	},
}

const FALLBACK_ROLE := "cm"


static func for_role(role_id: String) -> PlayerInstructions:
	var key := role_id if ROLE_BASELINES.has(role_id) else FALLBACK_ROLE
	var baseline: Dictionary = ROLE_BASELINES[key]
	var result := PlayerInstructions.from_dict(baseline)
	if result == null:
		push_error("InstructionDefaults: bad baseline for role '%s'" % role_id)
		return PlayerInstructions.new()
	return result


static func role_ids() -> Array[String]:
	var result: Array[String] = []
	for key in ROLE_BASELINES:
		result.append(String(key))
	return result
