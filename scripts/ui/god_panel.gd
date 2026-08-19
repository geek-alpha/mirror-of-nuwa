class_name GodPanel
extends Control
## 上帝面板：模式切换、LLM设置、神谕、世界操作、选中信息与成就。

var selected_label: Label
var llm_status_label: Label
var achievement_label: Label
var mode_label: Label
var llm_box: VBoxContainer
var llm_enabled_check: CheckButton
var provider_option: OptionButton
var base_url_edit: LineEdit
var model_edit: LineEdit
var api_key_edit: LineEdit
var oracle_input: LineEdit
var broadcast_check: CheckButton
var tts_enabled_check: CheckButton
var tts_provider_option: OptionButton
var voice_option: OptionButton
var voice_pool_menu: PopupMenu
var tts_status_label: Label

func _ready() -> void:
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	position = Vector2(10, 10)
	custom_minimum_size = Vector2(300, 0)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(300, 0)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	var title := Label.new()
	title.text = "◈ 女娲之镜：硅灵文明"
	title.add_theme_font_size_override("font_size", 18)
	vbox.add_child(title)
	mode_label = Label.new()
	mode_label.add_theme_font_size_override("font_size", 13)
	mode_label.modulate = Color(1.0, 0.82, 0.55)
	vbox.add_child(mode_label)
	# 模式
	var mode_hbox := HBoxContainer.new()
	vbox.add_child(mode_hbox)
	var god_btn := Button.new()
	god_btn.text = "神模式"
	god_btn.pressed.connect(func(): PlayerGodController.exit_possession())
	mode_hbox.add_child(god_btn)
	var possess_btn := Button.new()
	possess_btn.text = "附身选中"
	possess_btn.pressed.connect(_on_possess_selected)
	mode_hbox.add_child(possess_btn)
	# LLM 状态
	llm_status_label = Label.new()
	llm_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(llm_status_label)
	var llm_toggle := Button.new()
	llm_toggle.text = "LLM 设置"
	llm_toggle.pressed.connect(func(): llm_box.visible = not llm_box.visible)
	vbox.add_child(llm_toggle)
	llm_box = VBoxContainer.new()
	llm_box.visible = false
	vbox.add_child(llm_box)
	llm_enabled_check = CheckButton.new()
	llm_enabled_check.text = "启用 LLM 驱动角色"
	llm_box.add_child(llm_enabled_check)
	provider_option = OptionButton.new()
	provider_option.add_item("Ollama（本地）")
	provider_option.add_item("OpenAI 兼容")
	llm_box.add_child(provider_option)
	base_url_edit = _make_line_edit("Base URL（默认 https://api.siliconflow.cn/v1）")
	llm_box.add_child(base_url_edit)
	model_edit = _make_line_edit("模型名（默认 Qwen/Qwen3-30B-A3B-Instruct-2507）")
	llm_box.add_child(model_edit)
	api_key_edit = _make_line_edit("API Key（仅需填写此项）")
	api_key_edit.secret = true
	llm_box.add_child(api_key_edit)
	var apply_btn := Button.new()
	apply_btn.text = "应用设置"
	apply_btn.pressed.connect(_apply_llm_settings)
	llm_box.add_child(apply_btn)
	var test_btn := Button.new()
	test_btn.text = "测试连接"
	test_btn.pressed.connect(_on_test_connection)
	llm_box.add_child(test_btn)
	# AI 语音（Edge TTS）
	var voice_title := Label.new()
	voice_title.text = "AI 语音"
	voice_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(voice_title)
	var voice_hint := Label.new()
	voice_hint.text = "角色声音自动随机分配；仅玩家 10 米内的对话会发声。"
	voice_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(voice_hint)
	tts_enabled_check = CheckButton.new()
	tts_enabled_check.text = "启用 AI 语音"
	tts_enabled_check.button_pressed = ConfigManager.tts_enabled()
	tts_enabled_check.toggled.connect(_on_tts_enabled_toggled)
	vbox.add_child(tts_enabled_check)
	var provider_hbox := HBoxContainer.new()
	vbox.add_child(provider_hbox)
	var provider_label := Label.new()
	provider_label.text = "语音提供方"
	provider_hbox.add_child(provider_label)
	tts_provider_option = OptionButton.new()
	tts_provider_option.add_item("Edge TTS（微软在线）", 0)
	tts_provider_option.add_item("GPT-SoVITS（本机角色）", 1)
	tts_provider_option.select(0 if TTSManager.provider != "sovits" else 1)
	tts_provider_option.item_selected.connect(_on_tts_provider_selected)
	provider_hbox.add_child(tts_provider_option)
	var voice_hbox := HBoxContainer.new()
	vbox.add_child(voice_hbox)
	voice_option = OptionButton.new()
	voice_option.custom_minimum_size = Vector2(200, 0)
	voice_option.item_selected.connect(_on_voice_selected)
	voice_hbox.add_child(voice_option)
	var refresh_voices_btn := Button.new()
	refresh_voices_btn.text = "刷新声音"
	refresh_voices_btn.pressed.connect(_on_refresh_voices)
	voice_hbox.add_child(refresh_voices_btn)
	var voice_pool_btn := Button.new()
	voice_pool_btn.text = "选择声音池"
	voice_pool_btn.pressed.connect(_open_voice_pool_menu)
	voice_hbox.add_child(voice_pool_btn)
	voice_pool_menu = PopupMenu.new()
	voice_pool_menu.allow_search = true
	voice_pool_menu.hide_on_checkable_item_selection = false
	voice_pool_menu.id_pressed.connect(_on_voice_pool_toggled)
	add_child(voice_pool_menu)
	tts_status_label = Label.new()
	tts_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(tts_status_label)
	TTSManager.voices_loaded.connect(func(_voices): _sync_voice_option())
	# 神谕
	var oracle_title := Label.new()
	oracle_title.text = "神谕"
	oracle_title.add_theme_font_size_override("font_size", 15)
	vbox.add_child(oracle_title)
	oracle_input = _make_line_edit("输入神谕文本…")
	vbox.add_child(oracle_input)
	broadcast_check = CheckButton.new()
	broadcast_check.text = "广播给整个聚落"
	vbox.add_child(broadcast_check)
	var oracle_btn := Button.new()
	oracle_btn.text = "发送神谕"
	oracle_btn.pressed.connect(_on_send_oracle)
	vbox.add_child(oracle_btn)
	# 世界操作
	var ops_hbox := HBoxContainer.new()
	vbox.add_child(ops_hbox)
	var create_btn := Button.new()
	create_btn.text = "创造角色"
	create_btn.pressed.connect(_on_create_character)
	ops_hbox.add_child(create_btn)
	var delete_btn := Button.new()
	delete_btn.text = "湮灭选中"
	delete_btn.pressed.connect(_on_delete_selected)
	ops_hbox.add_child(delete_btn)
	var ops_hbox2 := HBoxContainer.new()
	vbox.add_child(ops_hbox2)
	var regen_btn := Button.new()
	regen_btn.text = "生成新世界"
	regen_btn.pressed.connect(_on_regenerate)
	ops_hbox2.add_child(regen_btn)
	var save_btn := Button.new()
	save_btn.text = "保存"
	save_btn.pressed.connect(func(): SaveManager.save_game())
	ops_hbox2.add_child(save_btn)
	var load_btn := Button.new()
	load_btn.text = "读取"
	load_btn.pressed.connect(func(): SaveManager.load_game())
	ops_hbox2.add_child(load_btn)
	var menu_btn := Button.new()
	menu_btn.text = "主菜单"
	menu_btn.pressed.connect(func():
		StoryModeManager.reset()
		get_tree().change_scene_to_file("res://scenes/ui/start_menu.tscn")
	)
	ops_hbox2.add_child(menu_btn)
	var history_btn := Button.new()
	history_btn.text = "历史年鉴"
	history_btn.pressed.connect(func(): UIManager.toggle_history())
	vbox.add_child(history_btn)
	# 选中信息
	selected_label = Label.new()
	selected_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	selected_label.custom_minimum_size = Vector2(0, 70)
	vbox.add_child(selected_label)
	achievement_label = Label.new()
	achievement_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(achievement_label)
	_prefill_llm_settings()
	refresh()

func _make_line_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	if UIManager != null:
		UIManager.wire_virtual_keyboard(edit)
	return edit

func _prefill_llm_settings() -> void:
	llm_enabled_check.button_pressed = ConfigManager.llm_enabled()
	provider_option.select(0 if ConfigManager.llm_provider() == "ollama" else 1)
	base_url_edit.text = ConfigManager.llm_base_url()
	model_edit.text = ConfigManager.llm_model()
	api_key_edit.text = ConfigManager.llm_api_key()

func _apply_llm_settings() -> void:
	var provider_name := "ollama" if provider_option.selected == 0 else "openai"
	ConfigManager.save_llm_settings({
		"enabled": llm_enabled_check.button_pressed,
		"provider": provider_name,
		"base_url": base_url_edit.text.strip_edges(),
		"model": model_edit.text.strip_edges(),
		"api_key": api_key_edit.text.strip_edges(),
		"temperature": ConfigManager.llm_temperature(),
		"max_tokens": ConfigManager.llm_max_tokens()
	})
	LLMService.reload_provider()
	refresh()

func _on_test_connection() -> void:
	llm_status_label.text = "LLM：正在测试连接…"
	var res: Dictionary = await LLMService.test_connection()
	llm_status_label.text = "LLM：%s" % str(res.get("message", "未知结果"))
	refresh()

func _on_tts_enabled_toggled(on: bool) -> void:
	TTSManager.set_enabled(on)
	refresh()

func _on_tts_provider_selected(index: int) -> void:
	TTSManager.set_provider("sovits" if index == 1 else "edge")
	tts_provider_option.select(0 if TTSManager.provider != "sovits" else 1)
	refresh()

func _on_voice_selected(index: int) -> void:
	var shown: Array = TTSManager.provider_voices()
	if index >= 0 and index < shown.size():
		TTSManager.set_voice(_voice_id_of(shown[index]))
		refresh()

func _on_refresh_voices() -> void:
	tts_status_label.text = "语音：正在刷新声音列表…"
	TTSManager.refresh_voices_with_upgrade()

func _sync_voice_option() -> void:
	if voice_option == null:
		return
	var prev := voice_option.get_item_text(voice_option.selected) if voice_option.selected >= 0 else ""
	voice_option.clear()
	var shown: Array = TTSManager.provider_voices()
	for i in shown.size():
		voice_option.add_item(_voice_label_for(shown[i]), i)
	var idx := _voice_index_in(TTSManager.current_voice, shown)
	if idx >= 0:
		voice_option.select(idx)
	elif prev != "":
		var prev_idx := _voice_index_in(prev, shown)
		if prev_idx >= 0:
			voice_option.select(prev_idx)
	elif voice_option.item_count > 0:
		voice_option.select(0)
	_sync_voice_pool_menu()

func _sync_voice_pool_menu() -> void:
	if voice_pool_menu == null:
		return
	voice_pool_menu.clear()
	var shown: Array = TTSManager.provider_voices()
	for i in shown.size():
		var v := _voice_id_of(shown[i])
		voice_pool_menu.add_check_item(_voice_label_for(shown[i]), i)
		voice_pool_menu.set_item_checked(i, TTSManager.is_voice_enabled(v))

func _open_voice_pool_menu() -> void:
	_sync_voice_pool_menu()
	voice_pool_menu.popup()

func _on_voice_pool_toggled(id: int) -> void:
	var shown: Array = TTSManager.provider_voices()
	if id < 0 or id >= shown.size():
		return
	var v := _voice_id_of(shown[id])
	var list: Array = TTSManager.enabled_voices.duplicate()
	if list.has(v):
		list.erase(v)
	else:
		list.append(v)
	TTSManager.set_enabled_voices(list)
	var idx := voice_pool_menu.get_item_index(id)
	if idx >= 0:
		voice_pool_menu.set_item_checked(idx, TTSManager.is_voice_enabled(v))
	refresh()

func _voice_id_of(entry) -> String:
	if entry is Dictionary:
		return str(entry.get("id", entry.get("name", "")))
	return str(entry)

func _voice_label_for(entry) -> String:
	if entry is Dictionary and str(entry.get("provider", "")) == "sovits":
		return "[GPT] %s" % str(entry.get("name", entry.get("id", "")))
	return "[Edge] %s" % _voice_id_of(entry)

func _voice_index_in(voice_id: String, list: Array) -> int:
	for i in list.size():
		if _voice_id_of(list[i]) == voice_id:
			return i
	return -1

func _on_possess_selected() -> void:
	if GameState.selected_character != null:
		PlayerGodController.possess(GameState.selected_character)
	elif not PlayerGodController.possess_nearest_to_screen_center():
		selected_label.text = "附近没有可附身的硅灵，请先点击选中一个角色"

func _on_send_oracle() -> void:
	var text := oracle_input.text.strip_edges()
	if text == "":
		return
	var targets: Array = []
	var selected = GameState.selected_character
	if broadcast_check.button_pressed:
		var fid: String = str(selected.character_data.faction_id) if selected != null else ""
		for c in CharacterManager.all_characters():
			if fid == "" or c.character_data.faction_id == fid:
				targets.append(c)
	elif selected != null:
		targets.append(selected)
	if targets.is_empty():
		refresh()
		selected_label.text = "神谕没有发送：请先在世界中点击选中一个角色，或勾选「广播给整个聚落」"
		return
	for c in targets:
		PlayerGodController.send_oracle(c, text)
	oracle_input.clear()
	refresh()

func _on_create_character() -> void:
	var pos: Vector3 = GameState.selected_character.global_position if GameState.selected_character != null else Vector3(0, 0, 0)
	var fid: String = "faction_crystal_dawn"
	if GameState.selected_character != null:
		fid = GameState.selected_character.character_data.faction_id
	CharacterManager.spawn_random_character(pos + Vector3(randf_range(-4, 4), 0, randf_range(-4, 4)), fid)
	refresh()

func _on_delete_selected() -> void:
	var obj = GameState.selected_object
	if obj is AICharacter:
		CharacterManager.kill_character(obj)
	elif obj is Building:
		WorldManager.buildings.erase(obj)
		obj.queue_free()
		HistoryManager.log_event("intervention", "神摧毁了一座建筑", obj.building_name)
	elif obj is ResourceNode:
		obj.collect(obj.amount)
	GameState.selected_character = null
	GameState.selected_object = null
	refresh()

func _on_regenerate() -> void:
	PlayerGodController.exit_possession()
	TimeManager.game_time = 0.0
	TimeManager.set_time_scale(float(ConfigManager.game_setting("time_scale_default", 1.0)))
	HistoryManager.clear()
	GameState.achievements.clear()
	CharacterManager.clear_all()
	CivilizationManager.initialize_factions()
	WorldManager.clear_world_objects()
	WorldManager.world_seed = randi()
	WorldManager.initialize_world(WorldManager.world)
	CharacterManager.spawn_initial_characters()
	GameState.selected_character = null
	GameState.selected_object = null
	HistoryManager.log_event("world", "世界重生", "女娲之镜映照出一个全新的世界。")
	UIManager.refresh_all()

func refresh() -> void:
	if selected_label == null:
		return
	if mode_label != null:
		mode_label.text = "当前模式：%s" % ("三体游戏 · 剧情模式" if GameState.is_story_mode() else "自由模拟 · 硅基文明")
	if GameState.selected_character != null and is_instance_valid(GameState.selected_character):
		var c = GameState.selected_character
		selected_label.text = "选中：%s\n%s | %s | %s\n%s" % [
			c.character_data.name,
			Enums.ROLE_NAMES.get(c.character_data.role, c.character_data.role),
			c.character_data.current_emotion,
			c.character_data.current_action,
			c.get_status_text()
		]
	elif GameState.selected_object != null and is_instance_valid(GameState.selected_object):
		var obj = GameState.selected_object
		if obj is Building:
			selected_label.text = "选中建筑：%s（%s）" % [obj.building_name, obj.function]
		elif obj is ResourceNode:
			selected_label.text = "选中资源：%s ×%d" % [obj.resource_name, int(obj.amount)]
		else:
			selected_label.text = "选中：%s" % obj.name
	else:
		selected_label.text = "未选中对象（左键点击世界中的角色/建筑/资源）"
	llm_status_label.text = "LLM：%s" % LLMService.status_text
	if tts_status_label != null:
		if TTSManager.voices.is_empty():
			tts_status_label.text = TTSManager.status_text
		else:
			var provider_pool: Array = TTSManager.provider_voices()
			tts_status_label.text = "%s（已启用 %d/%d 个声音，角色随机分配）" % [
				TTSManager.status_text,
				TTSManager.active_voice_count(),
				provider_pool.size()
			]
	var ach_names := {
		"intervention": "干预者",
		"witness": "见证者",
		"creator": "创世神"
	}
	var ach_list: Array[String] = []
	for a in GameState.achievements:
		ach_list.append(ach_names.get(a, str(a)))
	achievement_label.text = "成就：%s" % ("、".join(ach_list) if not ach_list.is_empty() else "暂无")
