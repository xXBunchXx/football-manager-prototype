class_name RuleEvent
extends RefCounted

## One officiating decision. Emitted by the rules engine for logging, scoring
## and restart placement.

enum Type { FOUL, OFFSIDE, GOAL, SAVE, CARD, SUBSTITUTION, RESTART, HALF_TIME, FULL_TIME }

var type: int = Type.FOUL
var description: String = ""
var offender_id: String = ""
var side: int = -1
var severity: int = FMEnums.FoulSeverity.NONE
var restart_type: int = -1
var position: Vector3 = Vector3.ZERO


static func create(event_type: int, text: String, offender: String = "", event_side: int = -1, foul_severity: int = FMEnums.FoulSeverity.NONE, next_restart: int = -1, at_position: Vector3 = Vector3.ZERO) -> RuleEvent:
	var event := RuleEvent.new()
	event.type = event_type
	event.description = text
	event.offender_id = offender
	event.side = event_side
	event.severity = foul_severity
	event.restart_type = next_restart
	event.position = at_position
	return event
