class_name StartMenu
extends Control
## 开局全局模式界面：选择游戏模式（自由模拟 / 剧情模式·三体游戏），
## 并配置全局参数（角色数量、时间倍率、世界种子、LLM、AI 语音）。

const CASTING_PANEL_SCRIPT := preload("res://scripts/ui/casting_panel.gd")

const MODE_FREE := "free_sim"
const MODE_STORY := "story"
const TIME_SCALES := [1.0, 10.0, 100.0, 1000.0]

const FREE_DESC := "自由模拟：女娲之镜的硅基文明沙盘。作为镜外之神俯瞰与干预，或化身硅灵与 AI 角色互动，见证文明兴衰。"
const STORY_DESC := "剧情模式 · 三体游戏：忠实还原《三体》中的三体游戏——你以真实身份戴上 V 装具进入三体世界，周文王、墨子、秦始皇与冯·诺伊曼、牛顿、庞加莱、爱因斯坦、伽利略等历史人物将与你同行并称呼你的名字；每进入一个文明都有独立的地图、地貌与天象。在恒纪元/乱纪元中通过对话与抉择推动文明；失败则世界毁灭、文明轮回。最终结局：将文明刻成墓碑，让知识不朽。"

var mode_desc: Label
var free_btn: Button
var story_btn: Button
var char_count: SpinBox
var time_scale_opt: OptionButton
var world_seed: SpinBox
var llm_enabled: CheckButton
var provider_opt: OptionButton
var base_url_edit: LineEdit
var model_edit: LineEdit
var api_key_edit: LineEdit
var tts_enabled: CheckButton
var tts_provider_opt: OptionButton
var start_btn: Button
var player_name_edit: LineEdit
var start_era_opt: OptionButton
var auto_pilot_check: CheckButton
var view_opt: OptionButton
var view_mode_story := "first"
var view_mode_free := "third"
var casting_panel = null

func _ready() -> void:
	# 场景根控件不会被引擎自动拉伸到视口大小（本机 4.7.1 实测），
	# 显式跟随视口尺寸，保证面板在任何分辨率/方向下都严格居中。
	var viewport := get_viewport()
	size = viewport.get_visible_rect().size
	viewport.size_changed.connect(_on_viewport_resized)
	_build_ui()
	_prefill()

func _on_viewport_resized() -> void:
	size = get_viewport().get_visible_rect().size

func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.045, 0.09)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	# 中央容器：任何分辨率/方向下都保证面板严格居中
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.09, 0.09, 0.14, 0.98)
	panel_style.border_color = Color(0.85, 0.62, 0.35, 0.75)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	panel_style.content_margin_left = 22
	panel_style.content_margin_right = 22
	panel_style.content_margin_top = 18
	panel_style.content_margin_bottom = 18
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var scroll := ScrollContainer.new()
	var scroll_style := StyleBoxFlat.new()
	scroll_style.bg_color = Color(0, 0, 0, 0)
	scroll.add_theme_stylebox_override("panel", scroll_style)
	var vp := get_viewport().get_visible_rect().size
	var panel_w := maxi(420, mini(int(vp.x * 0.9), 680))
	var panel_h := maxi(420, mini(int(vp.y * 0.88), 620))
	scroll.custom_minimum_size = Vector2(panel_w, panel_h)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var vbox := VBoxContainer.new()
	vbox.custom_minimum_size = Vector2(panel_w - 24, 0)
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "◈ 女娲之镜：硅灵文明"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 28)
	vbox.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "开局 · 选择游戏模式与全局配置"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.75, 0.8, 0.95)
	vbox.add_child(subtitle)

	vbox.add_child(_section_label("游戏模式"))
	var mode_hbox := HBoxContainer.new()
	mode_hbox.add_theme_constant_override("separation", 10)
	vbox.add_child(mode_hbox)
	var group := ButtonGroup.new()
	free_btn = Button.new()
	free_btn.text = "自由模拟"
	free_btn.toggle_mode = true
	free_btn.button_group = group
	free_btn.custom_minimum_size = Vector2(0, 52)
	free_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	free_btn.add_theme_font_size_override("font_size", 17)
	free_btn.toggled.connect(func(on: bool) -> void:
		if on:
			mode_desc.text = FREE_DESC
			_sync_view_ui(MODE_FREE)
	)
	mode_hbox.add_child(free_btn)
	story_btn = Button.new()
	story_btn.text = "剧情模式 · 三体游戏"
	story_btn.toggle_mode = true
	story_btn.button_group = group
	story_btn.custom_minimum_size = Vector2(0, 52)
	story_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	story_btn.add_theme_font_size_override("font_size", 17)
	story_btn.toggled.connect(func(on: bool) -> void:
		if on:
			mode_desc.text = STORY_DESC
			_sync_view_ui(MODE_STORY)
	)
	mode_hbox.add_child(story_btn)
	mode_desc = Label.new()
	mode_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mode_desc.custom_minimum_size = Vector2(0, 58)
	mode_desc.modulate = Color(0.9, 0.93, 1.0)
	vbox.add_child(mode_desc)

	vbox.add_child(_section_label("默认视角"))
	var view_row := HBoxContainer.new()
	view_row.add_theme_constant_override("separation", 10)
	vbox.add_child(view_row)
	view_row.add_child(_field_label("进入游戏后的默认人称（当前所选模式）"))
	view_opt = OptionButton.new()
	view_opt.add_item("第一人称")
	view_opt.add_item("第三人称")
	view_opt.custom_minimum_size = Vector2(140, 0)
	view_row.add_child(view_opt)
	var view_hint := Label.new()
	view_hint.text = "剧情模式默认第一人称、自由模拟默认第三人称，可按需修改；游戏内仍可用 V 键（移动端「视角」按钮）随时切换。"
	view_hint.modulate = Color(0.7, 0.75, 0.85)
	view_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(view_hint)

	vbox.add_child(_section_label("剧情模式 · 你的名字"))
	var name_row := HBoxContainer.new()
	vbox.add_child(name_row)
	name_row.add_child(_field_label("你在三体世界中的名字（历史人物会这样称呼你）"))
	player_name_edit = LineEdit.new()
	player_name_edit.placeholder_text = "旅人"
	player_name_edit.max_length = 12
	player_name_edit.custom_minimum_size = Vector2(150, 0)
	name_row.add_child(player_name_edit)
	if UIManager != null:
		UIManager.wire_virtual_keyboard(player_name_edit)

	vbox.add_child(_section_label("剧情模式 · 起始文明"))
	var era_row := HBoxContainer.new()
	vbox.add_child(era_row)
	era_row.add_child(_field_label("进入三体游戏的第一个文明"))
	start_era_opt = OptionButton.new()
	start_era_opt.custom_minimum_size = Vector2(200, 0)
	start_era_opt.add_item("随机文明")
	start_era_opt.set_item_metadata(0, "random")
	var idx := 1
	for era in StoryModeManager.eras:
		start_era_opt.add_item(str(era.get("name", "未知文明")))
		start_era_opt.set_item_metadata(idx, str(era.get("id", "")))
		idx += 1
	era_row.add_child(start_era_opt)

	vbox.add_child(_section_label("剧情模式 · 自动模式"))
	auto_pilot_check = CheckButton.new()
	auto_pilot_check.text = "启用自动模式（自动探索 / 攻略 AI 角色 / 最优抉择）"
	vbox.add_child(auto_pilot_check)
	var auto_hint := Label.new()
	auto_hint.text = "自动模式下系统代打：自动前往灯塔与遗宝探索、选择得分最高的对话选项、酷热时自动脱水保命，并主动与历史人物交谈提升好感（交谈时边走边聊、偶尔回望，不站桩）；游戏内可随时开关。"
	auto_hint.modulate = Color(0.7, 0.75, 0.85)
	auto_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(auto_hint)

	vbox.add_child(_section_label("全局配置"))
	var row1 := HBoxContainer.new()
	vbox.add_child(row1)
	row1.add_child(_field_label("初始角色数量（仅自由模拟）"))
	char_count = SpinBox.new()
	char_count.min_value = 1
	char_count.max_value = 30
	char_count.step = 1
	char_count.custom_minimum_size = Vector2(140, 0)
	row1.add_child(char_count)

	var row2 := HBoxContainer.new()
	vbox.add_child(row2)
	row2.add_child(_field_label("默认时间倍率"))
	time_scale_opt = OptionButton.new()
	time_scale_opt.add_item("1x（实时）")
	time_scale_opt.add_item("10x")
	time_scale_opt.add_item("100x")
	time_scale_opt.add_item("1000x")
	time_scale_opt.custom_minimum_size = Vector2(140, 0)
	row2.add_child(time_scale_opt)

	var row3 := HBoxContainer.new()
	vbox.add_child(row3)
	row3.add_child(_field_label("世界种子"))
	world_seed = SpinBox.new()
	world_seed.min_value = 0
	world_seed.max_value = 999999
	world_seed.step = 1
	world_seed.custom_minimum_size = Vector2(140, 0)
	row3.add_child(world_seed)

	vbox.add_child(_section_label("LLM（AI 角色驱动，可选）"))
	llm_enabled = CheckButton.new()
	llm_enabled.text = "启用 LLM 驱动角色"
	vbox.add_child(llm_enabled)
	provider_opt = OptionButton.new()
	provider_opt.add_item("Ollama（本地）")
	provider_opt.add_item("OpenAI 兼容")
	vbox.add_child(provider_opt)
	base_url_edit = _make_edit("Base URL（默认 https://api.siliconflow.cn/v1）")
	vbox.add_child(base_url_edit)
	model_edit = _make_edit("模型名（默认 Qwen/Qwen3-30B-A3B-Instruct-2507）")
	vbox.add_child(model_edit)
	api_key_edit = _make_edit("API Key（可选，也可用环境变量 OPENAI_API_KEY）")
	api_key_edit.secret = true
	vbox.add_child(api_key_edit)
	var llm_hint := Label.new()
	llm_hint.text = "未启用或离线时，角色自动降级为规则 AI，游戏始终可玩。"
	llm_hint.modulate = Color(0.7, 0.75, 0.85)
	llm_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(llm_hint)

	vbox.add_child(_section_label("AI 语音（Edge TTS / GPT-SoVITS，可选）"))
	tts_enabled = CheckButton.new()
	tts_enabled.text = "启用 AI 语音（仅玩家 10 米内的对话发声）"
	vbox.add_child(tts_enabled)
	var tts_provider_hbox := HBoxContainer.new()
	vbox.add_child(tts_provider_hbox)
	tts_provider_hbox.add_child(_field_label("语音提供方"))
	tts_provider_opt = OptionButton.new()
	tts_provider_opt.add_item("Edge TTS（微软在线）", 0)
	tts_provider_opt.add_item("GPT-SoVITS（本机角色）", 1)
	tts_provider_hbox.add_child(tts_provider_opt)

	var casting_btn := Button.new()
	casting_btn.text = "🎭 排片 · 提前安排剧情角色形象与声音"
	casting_btn.custom_minimum_size = Vector2(0, 46)
	casting_btn.add_theme_font_size_override("font_size", 16)
	casting_btn.pressed.connect(func(): casting_panel.open())
	vbox.add_child(casting_btn)
	var casting_hint := Label.new()
	casting_hint.text = "为旁白、玩家及剧情各纪元的历史人物/同伴预选 TTS 声线与 VRM 形象，方便排片；进入剧情后仍可随时在菜单里调整。"
	casting_hint.modulate = Color(0.7, 0.75, 0.85)
	casting_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(casting_hint)

	start_btn = Button.new()
	start_btn.text = "进入游戏"
	start_btn.custom_minimum_size = Vector2(0, 52)
	start_btn.add_theme_font_size_override("font_size", 19)
	start_btn.pressed.connect(_on_start)
	vbox.add_child(start_btn)

	casting_panel = CASTING_PANEL_SCRIPT.new()
	casting_panel.hide()
	add_child(casting_panel)

func _prefill() -> void:
	char_count.value = int(ConfigManager.game_setting("character_count", 10))
	var scale_default := float(ConfigManager.game_setting("time_scale_default", 1.0))
	time_scale_opt.select(maxi(TIME_SCALES.find(scale_default), 0))
	world_seed.value = int(ConfigManager.game_setting("world_seed", 42))
	llm_enabled.button_pressed = ConfigManager.llm_enabled()
	provider_opt.select(0 if ConfigManager.llm_provider() == "ollama" else 1)
	base_url_edit.text = ConfigManager.llm_base_url()
	model_edit.text = ConfigManager.llm_model()
	api_key_edit.text = ConfigManager.llm_api_key()
	tts_enabled.button_pressed = ConfigManager.tts_enabled()
	tts_provider_opt.select(0 if ConfigManager.tts_provider() != "sovits" else 1)
	player_name_edit.text = str(ConfigManager.game_setting("player_name", ""))
	if player_name_edit.text.strip_edges() == "":
		player_name_edit.text = "旅人"
	auto_pilot_check.button_pressed = bool(ConfigManager.game_setting("auto_pilot_enabled", false))
	view_mode_story = _normalize_view_mode(str(ConfigManager.game_setting("view_mode_story", "first")))
	view_mode_free = _normalize_view_mode(str(ConfigManager.game_setting("view_mode_free", "third")))
	var active_mode := MODE_STORY if GameState.game_mode == MODE_STORY else MODE_FREE
	view_opt.select(0 if (view_mode_story if active_mode == MODE_STORY else view_mode_free) == "first" else 1)
	var want_era := str(ConfigManager.game_setting("story_start_era", "random"))
	var era_found := false
	for i in start_era_opt.item_count:
		if str(start_era_opt.get_item_metadata(i)) == want_era:
			start_era_opt.select(i)
			era_found = true
			break
	if not era_found:
		start_era_opt.select(0)
	if GameState.game_mode == MODE_STORY:
		story_btn.button_pressed = true
		mode_desc.text = STORY_DESC
	else:
		free_btn.button_pressed = true
		mode_desc.text = FREE_DESC

func _on_start() -> void:
	# 把当前选择的默认人称存回所选模式
	if story_btn.button_pressed:
		view_mode_story = "first" if view_opt.selected == 0 else "third"
	else:
		view_mode_free = "first" if view_opt.selected == 0 else "third"
	ConfigManager.save_game_settings({
		"character_count": int(char_count.value),
		"time_scale_default": TIME_SCALES[maxi(time_scale_opt.selected, 0)],
		"world_seed": int(world_seed.value),
		"story_world_seed": int(world_seed.value),
		"story_start_era": str(start_era_opt.get_item_metadata(maxi(start_era_opt.selected, 0))),
		"player_name": player_name_edit.text.strip_edges(),
		"auto_pilot_enabled": auto_pilot_check.button_pressed,
		"view_mode_story": view_mode_story,
		"view_mode_free": view_mode_free
	})
	var pname := player_name_edit.text.strip_edges()
	GameState.player_name = pname if pname != "" else "旅人"
	ConfigManager.save_llm_settings({
		"enabled": llm_enabled.button_pressed,
		"provider": "ollama" if provider_opt.selected == 0 else "openai",
		"base_url": base_url_edit.text.strip_edges(),
		"model": model_edit.text.strip_edges(),
		"api_key": api_key_edit.text.strip_edges(),
		"temperature": ConfigManager.llm_temperature(),
		"max_tokens": ConfigManager.llm_max_tokens()
	})
	LLMService.reload_provider()
	TTSManager.set_enabled(tts_enabled.button_pressed)
	TTSManager.set_provider("sovits" if tts_provider_opt.selected == 1 else "edge")
	GameState.game_mode = MODE_STORY if story_btn.button_pressed else MODE_FREE
	EventBus.game_mode_changed.emit(GameState.game_mode)
	get_tree().change_scene_to_file("res://scenes/main.tscn")

func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.modulate = Color(1.0, 0.82, 0.55)
	return label

func _field_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return label

func _make_edit(placeholder: String) -> LineEdit:
	var edit := LineEdit.new()
	edit.placeholder_text = placeholder
	if UIManager != null:
		UIManager.wire_virtual_keyboard(edit)
	return edit

func _sync_view_ui(mode: String) -> void:
	## 模式切换时：把当前选择存回原模式，再显示新模式已保存的默认视角
	if view_opt == null:
		return
	var leaving := MODE_STORY if story_btn.button_pressed else MODE_FREE
	if leaving == MODE_STORY:
		view_mode_story = "first" if view_opt.selected == 0 else "third"
	else:
		view_mode_free = "first" if view_opt.selected == 0 else "third"
	var saved := view_mode_story if mode == MODE_STORY else view_mode_free
	view_opt.select(0 if saved == "first" else 1)

func _normalize_view_mode(value: String) -> String:
	return "third" if value == "third" else "first"
