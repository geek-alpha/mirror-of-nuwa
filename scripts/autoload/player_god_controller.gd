extends Node
## 玩家控制器：上帝模式（相机+射线选中+神谕）与化身模式（第三人称移动+交互）。

var god_camera: GodCamera = null
var possession_cam: PossessionController = null
var interaction: InteractionSystem = null

const MOVE_ACCEL := 16.0
const AIR_ACCEL := 8.0
const MOVE_DECEL := 22.0
const MAX_WALK := 4.2
const SPRINT_MULT := 1.5
const JUMP_VELOCITY := 7.5
const DOUBLE_JUMP_VELOCITY := 6.6
const MAX_AIR_JUMPS := 1
const GRAVITY := 22.0
const TURN_SPEED := 8.0
const JUMP_BUFFER_TIME := 0.12
const COYOTE_TIME := 0.12
const DIALOGUE_STOP_DISTANCE := 3.0
const DIALOGUE_LEAVE_RADIUS := 5.5

var _jump_buffer := 0.0
var _coyote_time := 0.0
var _air_jumps := 0
var _footstep_looping := false
## 移动锁定（剧情用：脱水沉眠时化身无法移动，只能环顾四周）
var _movement_locked := false

func set_movement_lock(locked: bool) -> void:
	_movement_locked = locked

func setup_camera() -> void:
	if god_camera == null:
		god_camera = GodCamera.new()
		god_camera.name = "GodCamera"
		WorldManager.world.add_child(god_camera)
		god_camera.make_current()
	GameState.camera = god_camera
	if interaction == null:
		interaction = InteractionSystem.new()
		add_child(interaction)

## 移动端：右侧单指拖动旋转当前相机视角
func touch_look(relative: Vector2) -> void:
	if GameState.input_locked or UIManager.text_input_active():
		return
	if GameState.mode == GameState.Mode.GOD:
		if god_camera != null:
			god_camera.touch_orbit(relative)
	elif possession_cam != null:
		possession_cam.touch_orbit(relative)

## 移动端：缩放（附身模式拉近/拉远；神模式无缩放效果）
func touch_zoom(dir: int) -> void:
	if GameState.input_locked:
		return
	if GameState.mode == GameState.Mode.POSSESS and possession_cam != null:
		possession_cam.zoom_step(dir)

## 移动端：点按世界选中（等价于桌面左键点击）
func select_at_screen(screen_pos: Vector2) -> void:
	if GameState.input_locked:
		return
	if GameState.mode == GameState.Mode.GOD and god_camera != null:
		_select_at_position(screen_pos)

## 移动端：跳跃按钮
func touch_jump() -> void:
	if GameState.input_locked or GameState.mode != GameState.Mode.POSSESS or UIManager.text_input_active():
		return
	_jump_buffer = JUMP_BUFFER_TIME

## 移动端：交谈按钮（等价于 F）
func touch_interact() -> void:
	if GameState.input_locked or GameState.mode != GameState.Mode.POSSESS or UIManager.text_input_active():
		return
	var c = GameState.possessed_character
	if c != null and is_instance_valid(c):
		interaction.try_talk_nearest(c)

## 移动端：切换第一/第三人称（等价于 V）
func touch_toggle_view() -> void:
	if GameState.input_locked:
		return
	if GameState.mode == GameState.Mode.POSSESS and possession_cam != null and not UIManager.text_input_active():
		toggle_view_mode()

## 移动端：返回神模式（等价于 G）
func touch_exit_possession() -> void:
	if GameState.input_locked:
		return
	if GameState.is_story_mode():
		return  # 剧情模式：玩家始终扮演自己，禁止回到神模式
	if GameState.mode == GameState.Mode.POSSESS:
		exit_possession()

## 移动端：附身按钮（优先附身选中角色，否则附身屏幕中央最近角色）
func touch_possess() -> void:
	if GameState.input_locked or GameState.mode != GameState.Mode.GOD:
		return
	if GameState.is_story_mode():
		return  # 剧情模式：只能扮演自己的化身，不能附身其他角色
	if GameState.selected_character != null and is_instance_valid(GameState.selected_character):
		possess(GameState.selected_character)
	elif not possess_nearest_to_screen_center():
		UIManager.append_system_message("附近没有可附身的硅灵，请先点选一个角色。")

func _process(delta: float) -> void:
	if GameState.input_locked:
		return
	if GameState.mode == GameState.Mode.GOD:
		_process_god_mode()

func _physics_process(delta: float) -> void:
	# 化身移动放在物理帧里，与 move_and_slide 保持一致步长，移动更顺滑
	if GameState.input_locked:
		return
	if GameState.mode == GameState.Mode.POSSESS:
		_process_possess_mode(delta)

func _process_god_mode() -> void:
	# 选中改由 _input 处理（直接使用事件坐标，规避窗口缩放/鼠标状态问题）
	pass

func _input(event: InputEvent) -> void:
	if GameState.input_locked:
		return
	# 打字中按 Esc 退出输入框，回到游戏操控
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		var esc_focus := get_viewport().gui_get_focus_owner()
		if esc_focus is LineEdit or esc_focus is TextEdit:
			esc_focus.release_focus()
	# 附身模式下：任何按键先解除 UI 按钮焦点，防止空格/回车误触发面板按钮（如“神模式”）
	if GameState.mode == GameState.Mode.POSSESS and event is InputEventKey and event.pressed:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is Button:
			focus.release_focus()
	# 附身模式下：点击 3D 世界退出文字输入，方便随时恢复操控
	if GameState.mode == GameState.Mode.POSSESS and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
			and not UIManager.is_pointer_over_ui():
		get_viewport().gui_release_focus()
	if GameState.mode == GameState.Mode.GOD and event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT and event.pressed \
			and not UIManager.is_pointer_over_ui():
		# 引擎在派发到 _input 前已将鼠标事件转换到视口坐标系，
		# 直接使用 event.position 做射线拾取；不要再乘 get_final_transform()，
		# 否则窗口缩放/拉伸（如最大化）时拾取坐标会被错误放大而偏离。
		_select_at_position(event.position)

func _select_at_position(screen_pos: Vector2) -> void:
	if god_camera == null:
		return
	# 点击3D世界时释放UI输入焦点，确保键盘回到游戏控制
	get_viewport().gui_release_focus()
	var from := god_camera.project_ray_origin(screen_pos)
	var to := from + god_camera.project_ray_normal(screen_pos) * 3000.0
	var query := PhysicsRayQueryParameters3D.create(from, to)
	var result := god_camera.get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():
		var obj = result.get("collider", null)
		if obj is AICharacter:
			_select_character(obj)
			return
		if obj is Building or obj is ResourceNode:
			GameState.selected_character = null
			GameState.selected_object = obj
			EventBus.character_selected.emit(null)
			return
	# 射线未直接命中角色时，用屏幕邻近拾取兜底：点角色附近即可选中
	var picked := _pick_nearest_to_screen(screen_pos)
	if picked != null:
		_select_character(picked)
		return
	GameState.selected_character = null
	GameState.selected_object = null
	EventBus.character_selected.emit(null)

func _select_character(character) -> void:
	GameState.selected_character = character
	GameState.selected_object = character
	EventBus.character_selected.emit(character)

func _pick_nearest_to_screen(mouse_pos: Vector2) -> AICharacter:
	var best: AICharacter = null
	var best_dist := INF
	for c in CharacterManager.all_characters():
		if c == null or not c.alive:
			continue
		var screen := god_camera.unproject_position(c.global_position + Vector3(0, 1.0, 0))
		var d := screen.distance_to(mouse_pos)
		if d < 60.0 and d < best_dist:
			best_dist = d
			best = c
	return best

func possess_nearest_to_screen_center() -> bool:
	## 未选中角色时：拾取画面中心附近最近的角色并附身
	if god_camera == null:
		return false
	var center := get_viewport().get_visible_rect().size / 2.0
	var best: AICharacter = null
	var best_dist := INF
	for c in CharacterManager.all_characters():
		if c == null or not c.alive:
			continue
		var screen := god_camera.unproject_position(c.global_position + Vector3(0, 1.0, 0))
		var d := screen.distance_to(center)
		if d < 160.0 and d < best_dist:
			best_dist = d
			best = c
	if best != null:
		possess(best)
		return true
	return false

func possess(character: AICharacter, silent := false) -> void:
	if character == null or not is_instance_valid(character) or not character.alive or character.dying:
		return
	# 剧情模式：只能附身玩家化身，禁止通过任何路径附身其他角色
	if GameState.is_story_mode() and StoryModeManager != null \
			and StoryModeManager.player != null and is_instance_valid(StoryModeManager.player) \
			and character != StoryModeManager.player:
		return
	GameState.possessed_character = character
	character.is_possessed = true
	character.velocity = Vector3.ZERO
	_air_jumps = 0
	_jump_buffer = 0.0
	_coyote_time = 0.0
	if god_camera != null:
		god_camera.current = false
	if possession_cam != null:
		possession_cam.current = false
		possession_cam.queue_free()
	possession_cam = PossessionController.new()
	possession_cam.name = "PossessionCamera"
	# 相机挂到世界而非角色身上：角色的转身/移动不会带动相机，视角完全独立
	WorldManager.world.add_child(possession_cam)
	possession_cam.bind(character)
	if GameState.is_story_mode():
		# 剧情模式默认第一人称视角
		possession_cam.set_first_person(true)
	possession_cam.make_current()
	GameState.camera = possession_cam
	GameState.set_mode(GameState.Mode.POSSESS)
	if silent:
		# 导演恢复附身：只恢复视角控制，不重复播报/写记忆
		UIManager.dialogue_context = {"player": character, "other": null}
		get_viewport().gui_release_focus()
		return
	UIManager.on_possession_started(character)
	# 释放 UI 焦点：避免“附身选中”等按钮残留焦点，之后按空格/回车误触发按钮
	get_viewport().gui_release_focus()
	EventBus.player_intervention.emit(character.character_data.id, "possession", "玩家化身进入%s" % character.character_data.name)
	MemorySystem.add_memory(character, "我感到一股强大的意志降临于我，我成为了神使。", 0.9, "awe", ["player", "possession"])

func exit_possession(silent := false) -> void:
	var c = GameState.possessed_character
	if c != null and is_instance_valid(c):
		c.is_possessed = false
		c.velocity = Vector3.ZERO
		# 附身期间旧行动被暂停，退出时清空并让 AI 重新决策
		c.moving = false
		c.current_action = {}
		c.action_on_arrive = {}
		c.action_remaining_hours = 0.0
		c.action_completed.emit(c)
		if silent or GameState.is_story_mode():
			UIManager.dialogue_context = {}
		else:
			UIManager.on_possession_ended("你已回到神模式")
	GameState.possessed_character = null
	if possession_cam != null:
		possession_cam.current = false
		possession_cam.queue_free()
		possession_cam = null
	if _footstep_looping:
		if AudioManager != null:
			AudioManager.stop_loop("footstep")
		_footstep_looping = false
	if god_camera != null:
		god_camera.current = true
		GameState.camera = god_camera
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		# 安全网：附身期间上帝相机不会移动（已按模式屏蔽输入），
		# 但为兼容旧存档/异常状态，退出时若相机卡在建筑/地形内或世界外则拉回安全位置。
		var cam_pos := god_camera.global_position
		var terrain_y := WorldManager.get_terrain_height(cam_pos.x, cam_pos.z)
		var half := TerrainGenerator.WORLD_SIZE / 2.0 - 3.0
		var out_of_bounds := absf(cam_pos.x) > half or absf(cam_pos.z) > half
		if cam_pos.y < terrain_y + 1.0 or out_of_bounds:
			god_camera.global_position = WorldManager.clamp_point(cam_pos, 4.0)
	GameState.set_mode(GameState.Mode.GOD)
	get_viewport().gui_release_focus()

func toggle_view_mode() -> void:
	if possession_cam != null and is_instance_valid(possession_cam):
		possession_cam.toggle_view_mode()

func _process_possess_mode(delta: float) -> void:
	var c = GameState.possessed_character
	if c == null or not is_instance_valid(c) or not c.alive or c.dying:
		exit_possession()
		return
	var typing := UIManager.text_input_active()
	var input_dir: Vector2 = Vector2.ZERO if _movement_locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var player_moving := (not typing) and (not _movement_locked) and input_dir.length_squared() > 0.01
	# 对话跟随：玩家未操控时自动走近对话对象；玩家操控离开范围则结束对话
	var dialogue_ctx: Dictionary = UIManager.dialogue_context
	var has_conversation: bool = dialogue_ctx.get("other", null) != null
	var partner: AICharacter = _dialogue_partner(c)
	if has_conversation and partner == null:
		_end_dialogue()
	elif partner != null:
		var dist: float = c.global_position.distance_to(partner.global_position)
		if player_moving and dist > DIALOGUE_LEAVE_RADIUS:
			_end_dialogue()
			partner = null
	if Input.is_action_just_pressed("toggle_god_mode") and not UIManager.text_input_active() \
			and not GameState.is_story_mode():
		exit_possession()
		return
	if Input.is_action_just_pressed("toggle_view_mode") and not UIManager.text_input_active():
		toggle_view_mode()
		return
	if Input.is_action_just_pressed("interact") and not UIManager.text_input_active():
		interaction.try_talk_nearest(c)
		return
	var yaw := possession_cam.yaw if possession_cam != null else 0.0
	var forward := Vector3(-sin(yaw), 0.0, -cos(yaw))
	var right := Vector3(cos(yaw), 0.0, -sin(yaw))
	var wish := Vector3.ZERO
	if player_moving:
		wish = forward * -input_dir.y + right * input_dir.x
	elif partner != null and not _movement_locked:
		# 自动跟随对话对象，保持可交谈距离
		var to_partner: Vector3 = partner.global_position - c.global_position
		to_partner.y = 0.0
		if to_partner.length() > DIALOGUE_STOP_DISTANCE:
			wish = to_partner.normalized()
	var sprint := (not typing) and Input.is_action_pressed("sprint")
	var max_speed := MAX_WALK * (SPRINT_MULT if sprint and player_moving else 1.0)
	# 平滑加减速：地面快速响应，空中更"飘"
	var accel := MOVE_ACCEL if c.is_on_floor() else AIR_ACCEL
	if wish.length_squared() > 0.01:
		var target_vel := wish.normalized() * max_speed
		c.velocity.x = move_toward(c.velocity.x, target_vel.x, accel * delta)
		c.velocity.z = move_toward(c.velocity.z, target_vel.z, accel * delta)
	else:
		c.velocity.x = move_toward(c.velocity.x, 0.0, MOVE_DECEL * delta)
		c.velocity.z = move_toward(c.velocity.z, 0.0, MOVE_DECEL * delta)
	# 重力与跳跃
	if not c.is_on_floor():
		c.velocity.y -= GRAVITY * delta
	# 跳跃缓冲 + 土狼时间：落地前一小段窗口内按跳跃也能跳，手感更跟手
	if c.is_on_floor():
		_coyote_time = COYOTE_TIME
		_air_jumps = 0
	else:
		_coyote_time = maxf(0.0, _coyote_time - delta)
	if (not typing) and (not _movement_locked) and Input.is_action_just_pressed("jump"):
		_jump_buffer = JUMP_BUFFER_TIME
	else:
		_jump_buffer = maxf(0.0, _jump_buffer - delta)
	if _jump_buffer > 0.0:
		if _coyote_time > 0.0:
			# 第一次起跳（地面/土狼时间）
			c.velocity.y = JUMP_VELOCITY
			_jump_buffer = 0.0
			_coyote_time = 0.0
			_air_jumps = 0
		elif _air_jumps < MAX_AIR_JUMPS:
			# 二段跳：空中再次按跳跃，获得第二次抬升
			c.velocity.y = DOUBLE_JUMP_VELOCITY
			_air_jumps += 1
			_jump_buffer = 0.0
	c.move_and_slide()
	# 脚步音效：走动时循环、停下即停
	var hspeed := Vector2(c.velocity.x, c.velocity.z).length()
	if hspeed > 1.0:
		if not _footstep_looping:
			if AudioManager != null:
				AudioManager.start_loop("footstep", -16.0)
			_footstep_looping = true
	else:
		if _footstep_looping:
			if AudioManager != null:
				AudioManager.stop_loop("footstep")
			_footstep_looping = false
	# 角色平滑转向
	if wish.length_squared() > 0.01:
		var target_yaw := atan2(-wish.x, -wish.z)
		# 以恒定角速度转向（不瞬间“啪”地转过去），转身更有分量
		var diff := wrapf(target_yaw - c.rotation.y, -PI, PI)
		var step := TURN_SPEED * delta
		c.rotation.y += clampf(diff, -step, step)
	# 动画状态
	if not c.is_on_floor():
		c.set_animation_state("jump")
	elif Vector2(c.velocity.x, c.velocity.z).length() > 1.0:
		var speed := Vector2(c.velocity.x, c.velocity.z).length()
		c.set_animation_state("run" if sprint else "walk")
		c.set_move_speed(speed)
	else:
		c.set_animation_state("idle")
		c.set_move_speed(0.0)

func _dialogue_partner(character) -> AICharacter:
	## 返回当前对话对象；没有对话或对象失效时返回 null。
	if not UIManager.dialogue_visible():
		return null
	var ctx: Dictionary = UIManager.dialogue_context
	if ctx.get("player", null) != character:
		return null
	var other = ctx.get("other", null)
	if other == null or not is_instance_valid(other) or not other.alive:
		return null
	return other

func _end_dialogue() -> void:
	## 结束当前对话：隐藏对话面板并清空上下文。
	UIManager.on_possession_ended()

func send_oracle(character, text: String) -> void:
	## 向单个角色发送神谕：写入记忆、记录历史；LLM可用时生成神启反应，否则降级为祈祷。
	if character == null or not is_instance_valid(character):
		return
	MemorySystem.add_memory(character, "我收到了来自镜外之神的启示：%s" % text, 1.0, "awe", ["oracle"])
	character.speak("……我听到了！", true, true)
	EventBus.oracle_sent.emit(character.character_data.id, text)
	EventBus.player_intervention.emit(character.character_data.id, "oracle", text)
	HistoryManager.log_event("intervention", "神谕降临%s" % character.character_data.name, text, character.character_data.id, character.character_data.faction_id)
	GameState.pending_oracle[character.character_data.id] = text
	if ConfigManager.llm_enabled() and LLMService.is_available():
		var prompt := PromptBuilder.build_oracle_prompt(character, text)
		LLMService.request_oracle(character.character_data.id, prompt, func(result):
			if result.is_empty() or not is_instance_valid(character):
				return
			var d: CharacterData = character.character_data
			if result.has("emotion"):
				d.current_emotion = str(result["emotion"])
			if result.has("memory_to_store") and str(result["memory_to_store"]) != "":
				MemorySystem.add_memory(character, str(result["memory_to_store"]), 0.8, d.current_emotion, ["oracle"])
			if result.has("dialogue") and str(result["dialogue"]) != "":
				character.speak(str(result["dialogue"]), true, true)
			var action := {
				"action": str(result.get("action", "idle")),
				"target": result.get("target", null)
			}
			ActionExecutor.execute(character, action)
		)
	else:
		ActionExecutor.execute(character, {"action": Enums.ACTION_PRAY, "duration_hours": 1.0, "intent": "pray"})
