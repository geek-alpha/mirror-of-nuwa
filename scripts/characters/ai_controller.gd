class_name AIController
extends Node
## AI控制器：每个角色一个。按游戏时间间隔触发决策；LLM可用时请求LLM，
## 否则使用规则AI。LLM返回后应用情绪、记忆、关系与动作。

var character: AICharacter = null
var next_decision_hour := -1.0
var decision_interval := 1.0
var decision_pending := false

func _ready() -> void:
	character = get_parent() as AICharacter
	decision_interval = float(ConfigManager.game_setting("decision_interval_game_hours", 1.0))
	next_decision_hour = TimeManager.game_time + randf_range(0.2, 1.0)
	character.action_completed.connect(_on_action_completed)

func _on_action_completed(_character) -> void:
	# 动作完成后快速安排下一次决策，避免角色长时间发呆
	if next_decision_hour > TimeManager.game_time + 0.05:
		next_decision_hour = TimeManager.game_time + 0.05

func _process(_delta: float) -> void:
	if character == null or not character.alive or character.dying:
		return
	if character.is_possessed or decision_pending or character.llm_busy:
		return
	if character.current_action.size() > 0 or character.moving:
		return
	if TimeManager.game_time >= next_decision_hour:
		_make_decision()

func _make_decision() -> void:
	next_decision_hour = TimeManager.game_time + decision_interval * randf_range(0.7, 1.3)
	if ConfigManager.llm_enabled() and LLMService.is_available():
		decision_pending = true
		var prompt := PromptBuilder.build_decision_prompt(character)
		LLMService.request_decision(character.character_data.id, {"prompt": prompt}, _on_llm_result)
	else:
		var action := character.rule_based_decision()
		ActionExecutor.execute(character, action)

func _on_llm_result(result: Dictionary) -> void:
	decision_pending = false
	if character == null or not is_instance_valid(character) or not character.alive or character.dying:
		return
	if result.is_empty():
		var action := character.rule_based_decision()
		ActionExecutor.execute(character, action)
		return
	var d: CharacterData = character.character_data
	if result.has("emotion"):
		d.current_emotion = str(result["emotion"])
	if result.has("memory_to_store") and str(result["memory_to_store"]) != "":
		MemorySystem.add_memory(character, str(result["memory_to_store"]), 0.6, d.current_emotion, ["llm"])
	if result.has("relationship_change"):
		var rc: Dictionary = result["relationship_change"]
		RelationshipSystem.update_relationship(
			character,
			str(rc.get("target_id", "")),
			float(rc.get("change", 0.0)),
			str(rc.get("reason", ""))
		)
	if result.has("dialogue") and str(result["dialogue"]) != "":
		character.speak(str(result["dialogue"]), true)
		EventBus.dialogue_occurred.emit(character.character_data.id, "", str(result["dialogue"]))
	var action := {
		"action": str(result.get("action", "idle")),
		"target": result.get("target", null),
		"thought": str(result.get("thought", "")),
		"intent": str(result.get("intent", ""))
	}
	ActionExecutor.execute(character, action)
