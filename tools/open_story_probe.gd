extends Node
## 开放剧情（AI 兜底）无头探针：验证 AI 事件、寻宝、目标收官在无 LLM 时可跑通。
## 用法：godot --headless --path . res://tools/open_story_probe.tscn

var frames := 0
var step := 0
var step_frames := 0

func _ready() -> void:
	TTSManager.enabled = false
	(ConfigManager.config["llm"] as Dictionary)["enabled"] = false
	GameState.game_mode = GameState.MODE_STORY
	GameState.player_name = "探针"
	StoryModeManager.boot_duration = 0.05
	StoryModeManager.cinematic_duration = 0.05
	StoryModeManager.transition_duration = 0.05
	StoryModeManager.destroy_cutscene_duration = 0.05
	StoryModeManager.hot_cutscene_duration = 0.05
	StoryModeManager.cold_cutscene_duration = 0.05
	StoryModeManager.stable_cutscene_duration = 0.05
	StoryModeManager.era_cutscene_duration = 0.05
	StoryModeManager.arrival_duration = 0.1
	StoryModeManager.wake_duration = 0.1
	StoryModeManager.cinematic_enabled = false
	StoryModeManager.auto_advance_enabled = false
	StoryModeManager.open_story = true
	StoryModeManager.start_story($World)
	UIManager.setup()
	PlayerGodController.setup_camera()
	StoryModeManager.after_ui_ready()
	TimeManager.set_time_scale(1.0)

func _process(_delta: float) -> void:
	frames += 1
	step_frames += 1
	var p = StoryModeManager.player
	var wait := 30
	match step:
		0:
			# 等引言幕出现后进入苏醒流程
			if StoryModeManager._intro_active:
				StoryModeManager._on_intro_finished()
				step = 1
				step_frames = 0
		1:
			wait = 240
			if StoryModeManager._ai_beat_active or StoryModeManager._ai_request_pending:
				if StoryModeManager.story_ui != null \
						and StoryModeManager.story_ui.choices_box.get_child_count() >= 2:
					print("OPEN: 开场AI事件已生成（选项数=%d）" \
						% StoryModeManager.story_ui.choices_box.get_child_count())
					print("OPEN: 向导=%s 同伴开场=%s" % [
						StoryModeManager.figure.character_data.name,
						"无（等待场景触发）" if StoryModeManager.companion == null else "已在场"
					])
					StoryModeManager._on_choice(0)
					StoryModeManager._ai_event_cooldown = 2.0
					step = 2
					step_frames = 0
		2:
			wait = 300
			if StoryModeManager._ai_beat_active:
				print("OPEN: 后续AI事件已生成")
				StoryModeManager._on_choice(1)
				step = 3
				step_frames = 0
		3:
			wait = 30
			if p != null and StoryModeManager._treasures.size() > 0:
				var tpos: Vector3 = StoryModeManager._treasures[0].get("pos", Vector3.ZERO)
				p.global_position = tpos + Vector3(0.5, 0, 0.5)
				p.velocity = Vector3.ZERO
				step = 4
				step_frames = 0
		4:
			wait = 60
			if StoryModeManager._treasures_found >= 1:
				print("OPEN: 寻宝拾取成功（遗宝=%d，好感=%s）" % [
					StoryModeManager._treasures_found, StoryModeManager._last_favor_text
				])
				step = 5
				step_frames = 0
		5:
			wait = 2400
			if StoryModeManager._ai_beat_active:
				StoryModeManager._on_choice(0)
				step_frames = 0
				print("OPEN: 结算事件（等待同伴入场）")
			elif StoryModeManager.companion != null \
					and not StoryModeManager._companion_walking_in:
				print("OPEN: 同伴已通过场景触发入队")
				step = 6
				step_frames = 0
		6:
			wait = 30
			if StoryModeManager.beacons.size() > 0 and p != null:
				var b = StoryModeManager.beacons[0]
				p.global_position = b.global_position + Vector3(0.5, 0, 0.5)
				p.velocity = Vector3.ZERO
				step = 7
				step_frames = 0
		7:
			wait = 30
			if StoryModeManager.beacons.size() > 0 and p != null:
				var b = StoryModeManager.beacons[0]
				p.global_position = b.global_position + Vector3(0.5, 0, 0.5)
				p.velocity = Vector3.ZERO
				step = 8
				step_frames = 0
		8:
			wait = 30
			if StoryModeManager.beacons.size() > 0 and p != null:
				var b = StoryModeManager.beacons[0]
				p.global_position = b.global_position + Vector3(0.5, 0, 0.5)
				p.velocity = Vector3.ZERO
				step = 9
				step_frames = 0
		9:
			wait = 60
			print("OPEN: 目标完成=%s 任务完成=%s 遗宝=%d" % [
				StoryModeManager.objective_complete,
				StoryModeManager.task_complete,
				StoryModeManager._treasures_found
			])
			StoryModeManager._ai_event_cooldown = 2.0
			step = 10
			step_frames = 0
		10:
			wait = 900
			if StoryModeManager.task_complete:
				step = 11
				step_frames = 0
			elif StoryModeManager._ai_beat_active:
				var is_ending: bool = StoryModeManager._ai_beat.has("then")
				StoryModeManager._on_choice(0)
				step_frames = 0
				if is_ending:
					print("OPEN: 收官AI事件已生成（带结算回调）")
				else:
					print("OPEN: 结算中途的普通事件")
		11:
			wait = 60
			print("OPEN: 收官结算：任务完成=%s 覆盖层可见=%s 遗宝=%d" % [
				StoryModeManager.task_complete,
				StoryModeManager.story_ui.overlay.visible,
				StoryModeManager._treasures_found
			])
			get_tree().quit()
	if frames > 3600:
		print("OPEN: 探针超时（step=%d）" % step)
		get_tree().quit()
	elif step_frames > wait:
		print("OPEN: 步骤 %d 等待超时，强制推进（帧=%d）" % [step, frames])
		if step == 5:
			var cd: float = 999.0
			var fd: float = 999.0
			var cv := Vector3.ZERO
			if StoryModeManager.companion != null:
				cd = StoryModeManager.companion.global_position.distance_to(StoryModeManager.player.global_position)
				cv = StoryModeManager.companion.velocity
			if StoryModeManager.figure != null:
				fd = StoryModeManager.figure.global_position.distance_to(StoryModeManager.player.global_position)
			print("OPEN: 调试 同伴距离=%.1f 速度=%s 向导距离=%.1f walking=%s reaction=%s beat=%s timer=%.1f" % [
				cd, cv, fd,
				StoryModeManager._companion_walking_in,
				StoryModeManager._reaction_playing,
				StoryModeManager._ai_beat_active,
				StoryModeManager._companion_entrance_timer
			])
		step += 1
		step_frames = 0
