class_name StoryUI
extends Control
## 三体游戏剧情界面（v2）：
## 左上信息卡（纪元/状态/倒计时/真相）、左中任务卡（任务/下一步指引/进度）、
## 左下事件流（自动事件的滚动提示）、底部叙事与抉择、
## 右上菜单（操作指南/保存/读取/返回主菜单）、V装具载入、脱水抉择与结局覆盖层。

const CASTING_PANEL_SCRIPT := preload("res://scripts/ui/casting_panel.gd")

signal choice_pressed(index: int)
signal continue_pressed()
signal overlay_pressed()
signal boot_finished()
signal cinematic_finished()
signal dehydrate_chosen(do_dehydrate: bool)
signal intro_finished()
signal wake_finished()

## 打字速度与中文语音同步（约 4.5 字/秒，随剧情节奏档位缩放），文字不跑在语音前面
const SPEECH_CHARS_PER_SEC := 4.5
## 脑机接口恍惚特效：色差 + 波浪畸变 + 重影 + 噪点 + 暗角
const FX_SHADER := """
shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform float time : hint_range(0.0, 100.0) = 0.0;
uniform vec3 tint = vec3(0.45, 0.85, 1.0);
uniform float heat : hint_range(0.0, 1.0) = 0.0;
uniform float cold : hint_range(0.0, 1.0) = 0.0;
uniform float anomaly : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 dir = uv - vec2(0.5, 0.5);
	float dist = length(dir);
	float wave = sin(uv.y * 42.0 + time * 3.2) * 0.0016 + sin(uv.x * 36.0 - time * 2.6) * 0.0013;
	// 热浪：空气仿佛在燃烧，垂直上升的扭曲波纹
	float heatWave = sin(uv.x * 55.0 + time * 8.0) * 0.0022 + sin(uv.x * 130.0 - time * 11.0) * 0.0012;
	uv.y += heatWave * heat;
	uv.x += sin(uv.y * 90.0 + time * 6.0) * 0.0008 * heat;
	wave *= 1.0 + heat * 4.0;
	uv += normalize(dir + vec2(0.001, 0.001)) * wave * (strength + heat * 0.25);
	float ca = strength * 0.008 + anomaly * 0.016;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;
	vec3 ghost = texture(screen_tex, uv + dir * (0.006 * strength + 0.012 * anomaly)).rgb;
	col = mix(col, ghost, strength * 0.22 + anomaly * 0.30);
	float n = fract(sin(dot(uv * 90.0, vec2(12.9898, 78.233)) + time * 11.0) * 43758.5453);
	col *= 1.0 - (n - 0.5) * (strength * 0.12 + anomaly * 0.10);
	// 大变动异象：白光脉动与边缘撕裂
	col += vec3(anomaly) * (0.06 + 0.05 * sin(time * 17.0));
	// 热浪色温：偏橙红
	col = mix(col, col * vec3(1.14, 0.88, 0.72), heat * 0.34);
	col += vec3(1.0, 0.42, 0.12) * heat * 0.06;
	// 严寒：偏蓝 + 霜粒
	col = mix(col, col * vec3(0.72, 0.86, 1.12), cold * 0.30);
	col += vec3(0.2, 0.42, 0.85) * cold * 0.035;
	col = mix(col, vec3(0.5, 0.6, 0.8), cold * (n - 0.5) * 0.10);
	float vig = smoothstep(0.85, 0.35, dist);
	col = mix(col, col * tint, strength * 0.16);
	col *= mix(1.0, vig, strength * 0.85 + cold * 0.15);
	COLOR = vec4(col, 1.0);
}
"""
const GUIDE_TEXT := "◆ 你以真实身份进入三体世界，历史人物与你同行，亲手推动文明的命运。\n\n" \
	+ "1. 普通对白显示在角色头顶气泡与底部字幕中；只有重要抉择时底部才会出现选项，点击推进剧情；\n" \
	+ "2. 发光的灯塔＝当前目标，走过去触发关键节点；\n" \
	+ "3. 恒纪元/乱纪元会自动轮转：酷热时弹出「脱水抉择」，脱水期间无法移动、免疫酷热，恒纪元自动复水；\n" \
	+ "4. 天灾、拒绝脱水、持续的高温与严寒都会累积红色「毁灭进度」——只有恒纪元能让它逐日消退，满格即文明倾覆；\n" \
	+ "5. 太阳的运行不可预测——灾变与喘息交替无常，文明随时可能在一场无人能料的天变中倾覆；\n" \
	+ "6. 每个文明都藏着一段「真相碎片」：任务完成且文明进度≥75% 才能收集，集齐五段才能通关；\n" \
	+ "7. 按 F 可与同伴交谈；剧情模式中你始终扮演自己，无法进入神模式。"

var era_label: Label
var kind_label: Label
var count_label: Label
var clue_dots: Label
var favor_label: Label
var treasure_label: Label
var task_title: Label
var task_desc: Label
var objective_label: Label
var next_step_label: Label
var progress_bar: ProgressBar
var truth_bar: ProgressBar
var doom_bar: ProgressBar
var event_label: Label
var reply_label: Label
var narrator_label: Label
var choices_box: BoxContainer
var continue_btn: Button
var pause_btn: Button
var overlay: ColorRect
var overlay_title: Label
var overlay_text: RichTextLabel
var overlay_btn: Button

var flash_rect: ColorRect
var boot_overlay: ColorRect
var boot_label: Label
var boot_bar: ProgressBar
var cinematic_overlay: ColorRect
var cinematic_circle: Panel
var cinematic_scan: ColorRect
var cinematic_glyph: Label
var cinematic_sparks: CPUParticles2D
var _spiral_line: Line2D
var _orbit_dots: Array[Control] = []
var cinematic_vsuit: Label
var cinematic_title: Label
var cinematic_subtitle: Label
var cinematic_bar: ProgressBar
var cinematic_skip: Button
var letterbox_top: ColorRect
var letterbox_bottom: ColorRect
var intro_overlay: ColorRect
var intro_title: Label
var intro_text: Label
var intro_btn: Button
var _intro_divider: Label
var wake_overlay: ColorRect
var wake_label: Label
var _external_label: Label
var _banner_label: Label
var _banner_tween: Tween
var _card_styles: Array[StyleBoxFlat] = []
var _fx_rect: ColorRect
var _fx_material: ShaderMaterial
var _fx_strength := 0.0
var _fx_target := 0.0
var _fx_heat := 0.0
var _fx_cold := 0.0
var _fx_anomaly := 0.0
var _fx_time := 0.0
var milestone_panel: PanelContainer
var milestone_title: Label
var milestone_subtitle: Label
var dehydrate_overlay: ColorRect
var pause_overlay: ColorRect
var guide_overlay: ColorRect
var casting_panel = null

var _boot_time := 0.0
var _cinematic_time := 0.0
var _cinematic_duration := 3.0
var _cinematic_active := false
var _objective_title := ""
var _events: Array = []
var hud_info_panel: PanelContainer
var hud_task_panel: PanelContainer
var hud_event_panel: PanelContainer
var event_scroll: ScrollContainer
var _narrator: PanelContainer
var _narrator_content: VBoxContainer
var _narrator_scroll: ScrollContainer
var _narrator_header: HBoxContainer
var _narrator_collapsed := false
var _narrator_enabled := false
var _collapse_btn: Button
var _subtitle_label: Label
var _subtitle_tween: Tween
var _narrator_fade: Tween = null
var _hud_visible := true

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# 挂在 CanvasLayer 下的根控件需要显式设置尺寸，否则为 0x0
	size = get_viewport().get_visible_rect().size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	hide()

func _build_ui() -> void:
	# ---------- 脑机接口恍惚特效层（全屏 shader，置于最底层） ----------
	_fx_rect = ColorRect.new()
	_fx_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fx_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fx_rect.color = Color.WHITE
	var shader := Shader.new()
	shader.code = FX_SHADER
	_fx_material = ShaderMaterial.new()
	_fx_material.shader = shader
	_fx_material.set_shader_parameter("strength", 0.0)
	_fx_material.set_shader_parameter("time", 0.0)
	_fx_rect.material = _fx_material
	_fx_rect.hide()
	add_child(_fx_rect)

	# ---------- 左上：纪元信息卡 ----------
	hud_info_panel = PanelContainer.new()
	var info_panel := hud_info_panel
	info_panel.offset_left = 12
	info_panel.offset_top = 8
	info_panel.offset_right = 312
	info_panel.offset_bottom = 124
	info_panel.custom_minimum_size = Vector2(300, 116)
	# 内容超出时裁剪在卡片内部，避免文字/控件溢出到卡片外
	info_panel.clip_contents = true
	info_panel.add_theme_stylebox_override("panel", _card_style(6))
	info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(info_panel)
	_decorate_card(info_panel, 300.0)
	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 3)
	info_panel.add_child(info_vbox)
	var row1 := HBoxContainer.new()
	row1.add_theme_constant_override("separation", 8)
	info_vbox.add_child(row1)
	var vsuit := Label.new()
	vsuit.text = "◈ V装具"
	vsuit.modulate = Color(0.5, 0.9, 1.0)
	vsuit.add_theme_font_size_override("font_size", 13)
	vsuit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	vsuit.custom_minimum_size = Vector2(0, 22)
	row1.add_child(vsuit)
	era_label = Label.new()
	era_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	era_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	era_label.custom_minimum_size = Vector2(0, 22)
	era_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	era_label.add_theme_font_size_override("font_size", 15)
	row1.add_child(era_label)
	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	info_vbox.add_child(row2)
	kind_label = Label.new()
	kind_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kind_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	kind_label.custom_minimum_size = Vector2(0, 20)
	kind_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	kind_label.add_theme_font_size_override("font_size", 14)
	kind_label.modulate = Color(1.0, 0.78, 0.5)
	row2.add_child(kind_label)
	var row3 := HBoxContainer.new()
	row3.add_theme_constant_override("separation", 10)
	info_vbox.add_child(row3)
	count_label = Label.new()
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count_label.custom_minimum_size = Vector2(0, 16)
	count_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	count_label.add_theme_font_size_override("font_size", 11)
	count_label.modulate = Color(0.85, 0.85, 0.85)
	row3.add_child(count_label)
	clue_dots = Label.new()
	clue_dots.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	clue_dots.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	clue_dots.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	clue_dots.custom_minimum_size = Vector2(0, 16)
	clue_dots.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	clue_dots.add_theme_font_size_override("font_size", 11)
	clue_dots.modulate = Color(1.0, 0.9, 0.6)
	row3.add_child(clue_dots)
	var row4 := HBoxContainer.new()
	row4.add_theme_constant_override("separation", 10)
	info_vbox.add_child(row4)
	favor_label = Label.new()
	favor_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	favor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	favor_label.custom_minimum_size = Vector2(0, 16)
	favor_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	favor_label.add_theme_font_size_override("font_size", 11)
	favor_label.modulate = Color(0.75, 0.95, 1.0)
	row4.add_child(favor_label)
	treasure_label = Label.new()
	treasure_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	treasure_label.custom_minimum_size = Vector2(0, 16)
	treasure_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	treasure_label.add_theme_font_size_override("font_size", 11)
	treasure_label.modulate = Color(1.0, 0.85, 0.45)
	row4.add_child(treasure_label)

	# ---------- 左中：任务卡 + 下一步指引 ----------
	hud_task_panel = PanelContainer.new()
	var task_panel := hud_task_panel
	task_panel.offset_left = 12
	task_panel.offset_top = 132
	task_panel.offset_right = 312
	task_panel.offset_bottom = 316
	task_panel.custom_minimum_size = Vector2(300, 184)
	task_panel.clip_contents = true
	task_panel.add_theme_stylebox_override("panel", _card_style(6))
	task_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(task_panel)
	_decorate_card(task_panel, 300.0)
	var task_scroll := ScrollContainer.new()
	task_scroll.custom_minimum_size = Vector2(272, 168)
	task_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	task_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	task_panel.add_child(task_scroll)
	var task_vbox := VBoxContainer.new()
	task_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_vbox.add_theme_constant_override("separation", 4)
	task_scroll.add_child(task_vbox)
	task_title = Label.new()
	task_title.add_theme_font_size_override("font_size", 15)
	task_vbox.add_child(task_title)
	task_desc = Label.new()
	task_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	task_desc.custom_minimum_size = Vector2(0, 24)
	task_desc.add_theme_font_size_override("font_size", 12)
	task_vbox.add_child(task_desc)
	objective_label = Label.new()
	objective_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	objective_label.modulate = Color(0.55, 0.95, 1.0)
	objective_label.custom_minimum_size = Vector2(0, 18)
	objective_label.add_theme_font_size_override("font_size", 13)
	task_vbox.add_child(objective_label)
	next_step_label = Label.new()
	next_step_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	next_step_label.custom_minimum_size = Vector2(0, 24)
	next_step_label.add_theme_font_size_override("font_size", 14)
	task_vbox.add_child(next_step_label)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size = Vector2(0, 11)
	progress_bar.max_value = 100.0
	progress_bar.show_percentage = true
	progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	task_vbox.add_child(progress_bar)
	_glow_bar(progress_bar, Color(1.0, 0.75, 0.35))
	truth_bar = ProgressBar.new()
	truth_bar.custom_minimum_size = Vector2(0, 11)
	truth_bar.max_value = 100.0
	truth_bar.show_percentage = true
	truth_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	task_vbox.add_child(truth_bar)
	_glow_bar(truth_bar, Color(0.45, 0.9, 1.0))
	doom_bar = ProgressBar.new()
	doom_bar.custom_minimum_size = Vector2(0, 11)
	doom_bar.max_value = 100.0
	doom_bar.show_percentage = true
	doom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	doom_bar.value = 0.0
	task_vbox.add_child(doom_bar)
	_glow_bar(doom_bar, Color(0.92, 0.25, 0.2))

	# ---------- 左下：事件流（自动/系统事件提示） ----------
	hud_event_panel = PanelContainer.new()
	var event_panel := hud_event_panel
	event_panel.offset_left = 12
	event_panel.offset_top = 324
	event_panel.offset_right = 312
	event_panel.offset_bottom = 436
	event_panel.custom_minimum_size = Vector2(300, 112)
	event_panel.clip_contents = true
	event_panel.add_theme_stylebox_override("panel", _card_style(6))
	event_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(event_panel)
	_decorate_card(event_panel, 300.0)
	event_scroll = ScrollContainer.new()
	event_scroll.custom_minimum_size = Vector2(272, 96)
	event_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	event_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_panel.add_child(event_scroll)
	var event_vbox := VBoxContainer.new()
	event_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	event_scroll.add_child(event_vbox)
	var event_title := Label.new()
	event_title.text = "最近事件"
	event_title.add_theme_font_size_override("font_size", 12)
	event_title.modulate = Color(0.8, 0.85, 0.95)
	event_vbox.add_child(event_title)
	event_label = Label.new()
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.custom_minimum_size = Vector2(0, 66)
	event_label.add_theme_font_size_override("font_size", 12)
	event_label.modulate = Color(0.9, 0.93, 1.0)
	event_vbox.add_child(event_label)

	# ---------- 右上：菜单按钮 ----------
	pause_btn = Button.new()
	pause_btn.text = "☰ 菜单"
	pause_btn.anchor_left = 1.0
	pause_btn.anchor_right = 1.0
	pause_btn.offset_left = -110
	pause_btn.offset_top = 12
	pause_btn.offset_right = -12
	pause_btn.offset_bottom = 48
	pause_btn.pressed.connect(func(): pause_overlay.show())
	add_child(pause_btn)

	# ---------- 底部：紧凑叙事条（可折叠，不遮挡视线） ----------
	_narrator = PanelContainer.new()
	_narrator.anchor_left = 0.0
	_narrator.anchor_right = 1.0
	_narrator.anchor_top = 1.0
	_narrator.anchor_bottom = 1.0
	_narrator.offset_left = 40
	_narrator.offset_right = -40
	_narrator.offset_top = -230
	_narrator.offset_bottom = -12
	_narrator.custom_minimum_size = Vector2(0, 210)
	_narrator.clip_contents = true
	_narrator.add_theme_stylebox_override("panel", _card_style(10))
	_narrator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_narrator)
	var nvbox := VBoxContainer.new()
	nvbox.add_theme_constant_override("separation", 5)
	nvbox.alignment = BoxContainer.ALIGNMENT_END
	_narrator.add_child(nvbox)
	_narrator_header = HBoxContainer.new()
	nvbox.add_child(_narrator_header)
	var header_spacer := Control.new()
	header_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_narrator_header.add_child(header_spacer)
	_collapse_btn = Button.new()
	_collapse_btn.text = "收起 ▾"
	_collapse_btn.custom_minimum_size = Vector2(80, 22)
	_collapse_btn.focus_mode = Control.FOCUS_NONE
	_collapse_btn.pressed.connect(_toggle_narrator)
	_narrator_header.add_child(_collapse_btn)
	_narrator_content = VBoxContainer.new()
	_narrator_content.add_theme_constant_override("separation", 6)
	nvbox.add_child(_narrator_content)
	reply_label = Label.new()
	reply_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	reply_label.modulate = Color(0.55, 0.88, 1.0)
	reply_label.add_theme_font_size_override("font_size", 15)
	reply_label.add_theme_constant_override("line_spacing", 1)
	reply_label.hide()
	_narrator_content.add_child(reply_label)
	# 正文放入可滚动区域：长文本不会把「继续」按钮挤出面板
	_narrator_scroll = ScrollContainer.new()
	_narrator_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_narrator_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_narrator_scroll.custom_minimum_size = Vector2(0, 58)
	_narrator_content.add_child(_narrator_scroll)
	narrator_label = Label.new()
	narrator_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	narrator_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	narrator_label.add_theme_font_size_override("font_size", 16)
	narrator_label.add_theme_constant_override("line_spacing", 1)
	narrator_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_narrator_scroll.add_child(narrator_label)
	# 选项竖排：长文案不再横向溢出、不会被裁掉
	choices_box = VBoxContainer.new()
	choices_box.add_theme_constant_override("separation", 6)
	_narrator_content.add_child(choices_box)
	continue_btn = Button.new()
	continue_btn.text = "继续 ›"
	continue_btn.custom_minimum_size = Vector2(0, 34)
	continue_btn.hide()
	continue_btn.pressed.connect(func(): continue_pressed.emit())
	_narrator_content.add_child(continue_btn)

	# ---------- 底部临时字幕：普通台词/旁白在这里逐字显示（剧情栏只留给抉择） ----------
	_subtitle_label = Label.new()
	_subtitle_label.anchor_left = 0.5
	_subtitle_label.anchor_right = 0.5
	_subtitle_label.anchor_top = 1.0
	_subtitle_label.anchor_bottom = 1.0
	_subtitle_label.offset_left = -440
	_subtitle_label.offset_right = 440
	_subtitle_label.offset_top = -158
	_subtitle_label.offset_bottom = -96
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_subtitle_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_subtitle_label.add_theme_font_size_override("font_size", 18)
	_subtitle_label.add_theme_constant_override("line_spacing", 2)
	_subtitle_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_subtitle_label.add_theme_constant_override("outline_size", 8)
	_subtitle_label.modulate = Color(0.95, 0.97, 1.0, 0)
	_subtitle_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_subtitle_label)

	# ---------- 天灾闪光 ----------
	flash_rect = ColorRect.new()
	flash_rect.color = Color(0, 0, 0, 0)
	flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash_rect.hide()
	add_child(flash_rect)

	# ---------- V 装具载入层 ----------
	boot_overlay = ColorRect.new()
	boot_overlay.color = Color(0.0, 0.0, 0.0, 0.94)
	boot_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	boot_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	boot_overlay.hide()
	add_child(boot_overlay)
	var boot_center := CenterContainer.new()
	boot_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	boot_overlay.add_child(boot_center)
	var boot_vbox := VBoxContainer.new()
	boot_vbox.custom_minimum_size = Vector2(520, 0)
	boot_vbox.add_theme_constant_override("separation", 18)
	boot_center.add_child(boot_vbox)
	var boot_title := Label.new()
	boot_title.text = "V 装具同步中……"
	boot_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_title.add_theme_font_size_override("font_size", 26)
	boot_title.modulate = Color(0.5, 0.9, 1.0)
	boot_vbox.add_child(boot_title)
	boot_label = Label.new()
	boot_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_label.add_theme_font_size_override("font_size", 18)
	boot_vbox.add_child(boot_label)
	boot_bar = ProgressBar.new()
	boot_bar.custom_minimum_size = Vector2(0, 18)
	boot_bar.max_value = 100.0
	boot_bar.show_percentage = false
	boot_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	boot_vbox.add_child(boot_bar)
	var boot_hint := Label.new()
	boot_hint.text = "神经连接建立中…… 三维坐标校准…… 历史人物接入……"
	boot_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boot_hint.modulate = Color(0.7, 0.75, 0.85)
	boot_vbox.add_child(boot_hint)

	# ---------- 电影式过场层（进文明 / 纪元切换 / 世界毁灭） ----------
	cinematic_overlay = ColorRect.new()
	cinematic_overlay.color = Color(0.0, 0.0, 0.0, 0.97)
	cinematic_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	cinematic_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	cinematic_overlay.hide()
	add_child(cinematic_overlay)
	var cine_center := CenterContainer.new()
	cine_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	cinematic_overlay.add_child(cine_center)
	var cine_vbox := VBoxContainer.new()
	cine_vbox.custom_minimum_size = Vector2(900, 0)
	cine_vbox.add_theme_constant_override("separation", 16)
	cine_center.add_child(cine_vbox)
	cinematic_vsuit = Label.new()
	cinematic_vsuit.text = "V装具同步中……"
	cinematic_vsuit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cinematic_vsuit.modulate = Color(0.5, 0.9, 1.0, 0.9)
	cinematic_vsuit.add_theme_font_size_override("font_size", 15)
	cine_vbox.add_child(cinematic_vsuit)
	cinematic_circle = Panel.new()
	cinematic_circle.custom_minimum_size = Vector2(170, 170)
	cinematic_circle.pivot_offset = Vector2(85, 85)
	cine_vbox.add_child(cinematic_circle)
	var marker := Label.new()
	marker.text = "✦"
	marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	marker.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	marker.set_anchors_preset(Control.PRESET_FULL_RECT)
	marker.add_theme_font_size_override("font_size", 24)
	marker.modulate = Color(1.0, 0.9, 0.6, 0.9)
	marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cinematic_circle.add_child(marker)
	cinematic_title = Label.new()
	cinematic_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cinematic_title.add_theme_font_size_override("font_size", 34)
	cinematic_title.modulate = Color(1, 1, 1, 0)
	cine_vbox.add_child(cinematic_title)
	cinematic_subtitle = Label.new()
	cinematic_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cinematic_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cinematic_subtitle.custom_minimum_size = Vector2(0, 44)
	cinematic_subtitle.add_theme_font_size_override("font_size", 17)
	cinematic_subtitle.modulate = Color(1.0, 0.85, 0.55, 0)
	cine_vbox.add_child(cinematic_subtitle)
	letterbox_top = ColorRect.new()
	letterbox_top.color = Color(0, 0, 0, 1)
	letterbox_top.anchor_right = 1.0
	letterbox_top.offset_top = 0
	letterbox_top.offset_bottom = 0
	letterbox_top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cinematic_overlay.add_child(letterbox_top)
	letterbox_bottom = ColorRect.new()
	letterbox_bottom.color = Color(0, 0, 0, 1)
	letterbox_bottom.anchor_top = 1.0
	letterbox_bottom.anchor_right = 1.0
	letterbox_bottom.offset_top = 0
	letterbox_bottom.offset_bottom = 0
	letterbox_bottom.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cinematic_overlay.add_child(letterbox_bottom)
	cinematic_bar = ProgressBar.new()
	cinematic_bar.anchor_left = 0.5
	cinematic_bar.anchor_right = 0.5
	cinematic_bar.anchor_top = 1.0
	cinematic_bar.anchor_bottom = 1.0
	cinematic_bar.offset_left = -260
	cinematic_bar.offset_right = 260
	cinematic_bar.offset_top = -30
	cinematic_bar.offset_bottom = -18
	cinematic_bar.max_value = 100.0
	cinematic_bar.show_percentage = false
	cinematic_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cinematic_overlay.add_child(cinematic_bar)
	cinematic_skip = Button.new()
	cinematic_skip.text = "跳过 ›"
	cinematic_skip.anchor_left = 1.0
	cinematic_skip.anchor_right = 1.0
	cinematic_skip.anchor_top = 1.0
	cinematic_skip.anchor_bottom = 1.0
	cinematic_skip.offset_left = -110
	cinematic_skip.offset_right = -16
	cinematic_skip.offset_top = -56
	cinematic_skip.offset_bottom = -22
	cinematic_skip.focus_mode = Control.FOCUS_NONE
	cinematic_skip.pressed.connect(_finish_cinematic)
	cinematic_overlay.add_child(cinematic_skip)

	# ---------- 全息扫描线（V装具感） ----------
	cinematic_scan = ColorRect.new()
	cinematic_scan.color = Color(0.45, 0.9, 1.0, 0.24)
	cinematic_scan.anchor_right = 1.0
	cinematic_scan.offset_top = 0
	cinematic_scan.offset_bottom = 3
	cinematic_scan.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cinematic_overlay.add_child(cinematic_scan)

	# ---------- 玄奥卦象字符 ----------
	cinematic_glyph = Label.new()
	cinematic_glyph.text = "☰ ☱ ☲ ☳ ☴ ☵ ☶ ☷"
	cinematic_glyph.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cinematic_glyph.anchor_left = 0.5
	cinematic_glyph.anchor_right = 0.5
	cinematic_glyph.anchor_top = 0.5
	cinematic_glyph.anchor_bottom = 0.5
	cinematic_glyph.offset_left = -180
	cinematic_glyph.offset_right = 180
	cinematic_glyph.offset_top = 150
	cinematic_glyph.offset_bottom = 190
	cinematic_glyph.add_theme_font_size_override("font_size", 24)
	cinematic_glyph.modulate = Color(1.0, 0.85, 0.5, 0.35)
	cinematic_glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cinematic_overlay.add_child(cinematic_glyph)

	# ---------- 光尘粒子（古老与科技的星辉） ----------
	cinematic_sparks = CPUParticles2D.new()
	cinematic_sparks.amount = 90
	cinematic_sparks.lifetime = 2.2
	cinematic_sparks.one_shot = false
	cinematic_sparks.emitting = true
	cinematic_sparks.direction = Vector2(0, 1)
	cinematic_sparks.spread = 180.0
	cinematic_sparks.gravity = Vector2(0, -14)
	cinematic_sparks.initial_velocity_min = 30.0
	cinematic_sparks.initial_velocity_max = 95.0
	cinematic_sparks.scale_amount_min = 1.0
	cinematic_sparks.scale_amount_max = 2.6
	cinematic_sparks.color = Color(1.0, 0.85, 0.5, 0.8)
	cinematic_overlay.add_child(cinematic_sparks)

	# ---------- 黄金螺线（数学之美的中心符号） ----------
	_spiral_line = Line2D.new()
	_spiral_line.width = 2.0
	_spiral_line.antialiased = true
	_spiral_line.default_color = Color(1.0, 0.82, 0.5, 0.85)
	_spiral_line.joint_mode = Line2D.LINE_JOINT_ROUND
	_spiral_line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	_spiral_line.end_cap_mode = Line2D.LINE_CAP_ROUND
	cinematic_overlay.add_child(_spiral_line)

	# ---------- 三体轨道光点：三颗太阳沿椭圆轨道运动 ----------
	for i in 3:
		var dot := Panel.new()
		dot.custom_minimum_size = Vector2(9, 9)
		dot.pivot_offset = Vector2(4.5, 4.5)
		var ds := StyleBoxFlat.new()
		ds.bg_color = Color(1.0, 0.85, 0.5, 0.92)
		ds.shadow_color = Color(1.0, 0.7, 0.3, 0.85)
		ds.shadow_size = 8
		ds.set_corner_radius_all(5)
		dot.add_theme_stylebox_override("panel", ds)
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cinematic_overlay.add_child(dot)
		_orbit_dots.append(dot)

	# ---------- 纪元引言层：背景介绍独立成幕，讲完再正式进入角色剧情 ----------
	intro_overlay = ColorRect.new()
	# 半透明引言幕：播报背景时仍能隐约看到天象与世界，更有氛围
	intro_overlay.color = Color(0.02, 0.02, 0.05, 0.55)
	intro_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	intro_overlay.hide()
	add_child(intro_overlay)
	var intro_center := CenterContainer.new()
	intro_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	intro_overlay.add_child(intro_center)
	var intro_panel := PanelContainer.new()
	var intro_style := StyleBoxFlat.new()
	# 半透明面板：背景介绍期间仍能看到巡览中的世界，不遮挡画面
	intro_style.bg_color = Color(0.07, 0.06, 0.11, 0.45)
	intro_style.border_color = Color(0.85, 0.62, 0.35, 0.8)
	intro_style.set_border_width_all(2)
	intro_style.set_corner_radius_all(14)
	intro_style.content_margin_left = 34
	intro_style.content_margin_right = 34
	intro_style.content_margin_top = 28
	intro_style.content_margin_bottom = 28
	intro_panel.add_theme_stylebox_override("panel", intro_style)
	intro_center.add_child(intro_panel)
	var intro_vbox := VBoxContainer.new()
	intro_vbox.custom_minimum_size = Vector2(720, 0)
	intro_vbox.add_theme_constant_override("separation", 18)
	intro_panel.add_child(intro_vbox)
	intro_title = Label.new()
	intro_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_title.add_theme_font_size_override("font_size", 30)
	intro_title.modulate = Color(1.0, 0.85, 0.55)
	intro_vbox.add_child(intro_title)
	_intro_divider = Label.new()
	_intro_divider.text = "—— ☰ 三体 · 天机 ☰ ——"
	_intro_divider.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro_divider.add_theme_font_size_override("font_size", 14)
	_intro_divider.modulate = Color(0.9, 0.7, 0.4, 0.6)
	intro_vbox.add_child(_intro_divider)
	intro_text = Label.new()
	intro_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_text.custom_minimum_size = Vector2(0, 130)
	intro_text.add_theme_font_size_override("font_size", 17)
	intro_text.add_theme_constant_override("line_spacing", 2)
	intro_text.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.55))
	intro_text.add_theme_constant_override("outline_size", 5)
	intro_text.modulate = Color(0.92, 0.94, 1.0)
	intro_vbox.add_child(intro_text)
	var intro_hint := Label.new()
	intro_hint.text = "—— 背景介绍 ——"
	intro_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	intro_hint.modulate = Color(0.7, 0.75, 0.9)
	intro_vbox.add_child(intro_hint)
	intro_btn = Button.new()
	intro_btn.text = "开始剧情 ›"
	intro_btn.custom_minimum_size = Vector2(260, 46)
	intro_btn.focus_mode = Control.FOCUS_NONE
	intro_btn.pressed.connect(_finish_intro)
	intro_vbox.add_child(intro_btn)

	# ---------- 睁眼苏醒层：V装具结束后的黑场淡出，第一人称睁眼即见向导 ----------
	wake_overlay = ColorRect.new()
	wake_overlay.color = Color(0, 0, 0, 1)
	wake_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	wake_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	wake_overlay.hide()
	add_child(wake_overlay)
	wake_label = Label.new()
	wake_label.text = "你缓缓睁开了眼睛……"
	wake_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	wake_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	wake_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	wake_label.add_theme_font_size_override("font_size", 26)
	wake_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	wake_label.add_theme_constant_override("outline_size", 8)
	wake_label.modulate = Color(1, 1, 1, 0)
	wake_overlay.add_child(wake_label)

	# ---------- 外部系统音（穿越网文式降临提示，苏醒前播放） ----------
	_external_label = Label.new()
	_external_label.anchor_left = 0.5
	_external_label.anchor_right = 0.5
	_external_label.anchor_top = 0.5
	_external_label.anchor_bottom = 0.5
	_external_label.offset_left = -420
	_external_label.offset_right = 420
	_external_label.offset_top = -120
	_external_label.offset_bottom = -40
	_external_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_external_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_external_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_external_label.add_theme_font_size_override("font_size", 20)
	_external_label.modulate = Color(0.55, 0.9, 1.0, 0)
	_external_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_external_label)

	# ---------- 顶部横幅：天象预警 / 旅途跋涉字幕 / 人物登场聚焦 ----------
	_banner_label = Label.new()
	_banner_label.anchor_left = 0.5
	_banner_label.anchor_right = 0.5
	_banner_label.offset_left = -380
	_banner_label.offset_right = 380
	_banner_label.offset_top = 96
	_banner_label.offset_bottom = 138
	_banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner_label.add_theme_font_size_override("font_size", 21)
	_banner_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	_banner_label.add_theme_constant_override("outline_size", 8)
	_banner_label.modulate = Color(1, 1, 1, 0)
	_banner_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_banner_label)

	# ---------- 关键节点横幅（非阻塞，顶部滑入） ----------
	milestone_panel = PanelContainer.new()
	milestone_panel.anchor_left = 0.5
	milestone_panel.anchor_right = 0.5
	milestone_panel.offset_left = -360
	milestone_panel.offset_right = 360
	milestone_panel.offset_top = -90
	milestone_panel.offset_bottom = -34
	milestone_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	milestone_panel.hide()
	add_child(milestone_panel)
	var ms_vbox := VBoxContainer.new()
	milestone_panel.add_child(ms_vbox)
	milestone_title = Label.new()
	milestone_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	milestone_title.add_theme_font_size_override("font_size", 22)
	milestone_title.modulate = Color(1.0, 0.85, 0.5)
	ms_vbox.add_child(milestone_title)
	milestone_subtitle = Label.new()
	milestone_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	milestone_subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	milestone_subtitle.custom_minimum_size = Vector2(0, 24)
	milestone_subtitle.add_theme_font_size_override("font_size", 14)
	milestone_subtitle.modulate = Color(0.9, 0.93, 1.0)
	ms_vbox.add_child(milestone_subtitle)

	# ---------- 脱水抉择层 ----------
	dehydrate_overlay = ColorRect.new()
	dehydrate_overlay.color = Color(0.25, 0.05, 0.01, 0.88)
	dehydrate_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	dehydrate_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	dehydrate_overlay.hide()
	add_child(dehydrate_overlay)
	var dh_center := CenterContainer.new()
	dh_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dehydrate_overlay.add_child(dh_center)
	var dh_panel := PanelContainer.new()
	var dh_style := StyleBoxFlat.new()
	dh_style.bg_color = Color(0.12, 0.05, 0.02, 0.98)
	dh_style.border_color = Color(1.0, 0.4, 0.2, 0.9)
	dh_style.set_border_width_all(2)
	dh_style.set_corner_radius_all(12)
	dh_style.content_margin_left = 28
	dh_style.content_margin_right = 28
	dh_style.content_margin_top = 22
	dh_style.content_margin_bottom = 22
	dh_panel.add_theme_stylebox_override("panel", dh_style)
	dh_center.add_child(dh_panel)
	var dh_vbox := VBoxContainer.new()
	dh_vbox.custom_minimum_size = Vector2(560, 0)
	dh_vbox.add_theme_constant_override("separation", 12)
	dh_panel.add_child(dh_vbox)
	var dh_title := Label.new()
	dh_title.text = "☀ 乱纪元 · 酷热"
	dh_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dh_title.add_theme_font_size_override("font_size", 24)
	dh_title.modulate = Color(1.0, 0.6, 0.3)
	dh_vbox.add_child(dh_title)
	var dh_text := Label.new()
	dh_text.text = "太阳正逼近大地，热浪灼烧万物。族人纷纷脱水，蜷成干枯的皮囊沉入沙中——只有那样，才能活过这一纪。\n\n脱水后将无法移动，需沉眠至恒纪元被复水；硬撑下去则会加速文明的毁灭进程。\n\n你要如何选择？"
	dh_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dh_text.custom_minimum_size = Vector2(0, 90)
	dh_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dh_vbox.add_child(dh_text)
	var dh_hbox := HBoxContainer.new()
	dh_hbox.add_theme_constant_override("separation", 14)
	dh_vbox.add_child(dh_hbox)
	var dehydrate_btn := Button.new()
	dehydrate_btn.text = "脱水保命（沉眠至恒纪元）"
	dehydrate_btn.custom_minimum_size = Vector2(260, 44)
	dehydrate_btn.pressed.connect(func():
		dehydrate_overlay.hide()
		dehydrate_chosen.emit(true)
	)
	dh_hbox.add_child(dehydrate_btn)
	var endure_btn := Button.new()
	endure_btn.text = "硬撑下去（加速毁灭）"
	endure_btn.custom_minimum_size = Vector2(260, 44)
	endure_btn.pressed.connect(func():
		dehydrate_overlay.hide()
		dehydrate_chosen.emit(false)
	)
	dh_hbox.add_child(endure_btn)

	# ---------- 菜单覆盖层 ----------
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0.0, 0.0, 0.0, 0.82)
	pause_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.hide()
	add_child(pause_overlay)
	var pm_center := CenterContainer.new()
	pm_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_overlay.add_child(pm_center)
	var pm_panel := PanelContainer.new()
	pm_center.add_child(pm_panel)
	var pm_vbox := VBoxContainer.new()
	pm_vbox.custom_minimum_size = Vector2(360, 0)
	pm_vbox.add_theme_constant_override("separation", 12)
	pm_panel.add_child(pm_vbox)
	var pm_title := Label.new()
	pm_title.text = "☰ 三体游戏菜单"
	pm_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pm_title.add_theme_font_size_override("font_size", 22)
	pm_vbox.add_child(pm_title)
	var pace_row := HBoxContainer.new()
	pm_vbox.add_child(pace_row)
	var pace_label := Label.new()
	pace_label.text = "剧情节奏（文字+语音综合速度）"
	pace_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pace_row.add_child(pace_label)
	var pace_opt := OptionButton.new()
	pace_opt.add_item("舒缓")
	pace_opt.add_item("标准")
	pace_opt.add_item("紧凑")
	pace_opt.select(1)
	pace_opt.item_selected.connect(func(idx: int):
		StoryModeManager.set_story_pace([0.75, 1.0, 1.3][idx])
	)
	pace_row.add_child(pace_opt)
	pm_vbox.add_child(_make_menu_button("操作指南", func(): guide_overlay.show()))
	pm_vbox.add_child(_make_menu_button("🎭 排片 · 形象与声音", _open_casting))
	pm_vbox.add_child(_make_menu_button("保存", func(): SaveManager.save_game()))
	pm_vbox.add_child(_make_menu_button("读取", func(): SaveManager.load_game()))
	pm_vbox.add_child(_make_menu_button("返回主菜单", func(): StoryModeManager.return_to_menu()))
	pm_vbox.add_child(_make_menu_button("关闭", func(): pause_overlay.hide()))
	var pm_hint := Label.new()
	pm_hint.text = "提示：顶部时间条可随时调速/暂停。"
	pm_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	pm_hint.modulate = Color(0.75, 0.8, 0.9)
	pm_vbox.add_child(pm_hint)

	# ---------- 操作指南覆盖层 ----------
	guide_overlay = ColorRect.new()
	guide_overlay.color = Color(0.0, 0.0, 0.0, 0.88)
	guide_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	guide_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	guide_overlay.hide()
	add_child(guide_overlay)
	var gd_center := CenterContainer.new()
	gd_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	guide_overlay.add_child(gd_center)
	var gd_panel := PanelContainer.new()
	gd_center.add_child(gd_panel)
	var gd_vbox := VBoxContainer.new()
	gd_vbox.custom_minimum_size = Vector2(620, 0)
	gd_vbox.add_theme_constant_override("separation", 14)
	gd_panel.add_child(gd_vbox)
	var gd_title := Label.new()
	gd_title.text = "操作指南 · 三体游戏"
	gd_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	gd_title.add_theme_font_size_override("font_size", 22)
	gd_vbox.add_child(gd_title)
	var gd_text := Label.new()
	gd_text.text = GUIDE_TEXT
	gd_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gd_text.custom_minimum_size = Vector2(0, 220)
	gd_text.add_theme_font_size_override("font_size", 15)
	gd_vbox.add_child(gd_text)
	var gd_close := Button.new()
	gd_close.text = "我明白了"
	gd_close.custom_minimum_size = Vector2(200, 42)
	gd_close.pressed.connect(func(): guide_overlay.hide())
	gd_vbox.add_child(gd_close)

	# ---------- 排片覆盖层（提前安排角色形象与声音） ----------
	casting_panel = CASTING_PANEL_SCRIPT.new()
	casting_panel.hide()
	add_child(casting_panel)
	casting_panel.close_requested.connect(func(): pause_overlay.show())

	# ---------- 主覆盖层：文明完成 / 世界毁灭 / 结局 ----------
	overlay = ColorRect.new()
	overlay.color = Color(0.0, 0.0, 0.0, 0.82)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.hide()
	add_child(overlay)
	var opanel := PanelContainer.new()
	opanel.anchor_left = 0.5
	opanel.anchor_top = 0.5
	opanel.anchor_right = 0.5
	opanel.anchor_bottom = 0.5
	opanel.offset_left = -340
	opanel.offset_right = 340
	opanel.offset_top = -220
	opanel.offset_bottom = 220
	overlay.add_child(opanel)
	var ovbox := VBoxContainer.new()
	ovbox.alignment = BoxContainer.ALIGNMENT_CENTER
	ovbox.add_theme_constant_override("separation", 14)
	opanel.add_child(ovbox)
	overlay_title = Label.new()
	overlay_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	overlay_title.add_theme_font_size_override("font_size", 26)
	ovbox.add_child(overlay_title)
	overlay_text = RichTextLabel.new()
	overlay_text.bbcode_enabled = true
	overlay_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	overlay_text.custom_minimum_size = Vector2(540, 200)
	overlay_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ovbox.add_child(overlay_text)
	overlay_btn = Button.new()
	overlay_btn.custom_minimum_size = Vector2(260, 44)
	overlay_btn.pressed.connect(func(): overlay_pressed.emit())
	ovbox.add_child(overlay_btn)

func _make_menu_button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 42)
	b.pressed.connect(on_press)
	return b

func _card_style(margin: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.12, 0.97)
	style.border_color = Color(0.85, 0.62, 0.35, 0.55)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = margin
	style.content_margin_right = margin
	style.content_margin_top = margin
	style.content_margin_bottom = margin
	style.shadow_color = Color(0.9, 0.6, 0.25, 0.22)
	style.shadow_size = 10
	_card_styles.append(style)
	return style

## 黄金比例角饰：卡片两上角各一段精确的四分之一圆弧（数学之美的 UI 表达）
func _decorate_card(panel: Control, width: float) -> void:
	var r := 14.0
	var tl := Line2D.new()
	tl.width = 1.5
	tl.antialiased = true
	tl.default_color = Color(1.0, 0.8, 0.45, 0.45)
	var pts := PackedVector2Array()
	for i in 15:
		var ang := float(i) / 14.0 * (PI / 2.0)
		pts.append(Vector2(cos(ang), sin(ang)) * r)
	tl.points = pts
	panel.add_child(tl)
	var tr := Line2D.new()
	tr.width = 1.5
	tr.antialiased = true
	tr.default_color = Color(1.0, 0.8, 0.45, 0.45)
	var pts2 := PackedVector2Array()
	for i in 15:
		var ang := float(i) / 14.0 * (PI / 2.0)
		pts2.append(Vector2(-cos(ang), sin(ang)) * r)
	tr.points = pts2
	tr.position = Vector2(width, 0)
	panel.add_child(tr)

## 纪元主题色：卡片边框、辉光与进度条随文明色调（古文明 × 科技）
func apply_era_theme(accent: Color) -> void:
	for style in _card_styles:
		if style == null:
			continue
		style.border_color = Color(accent.r, accent.g, accent.b, 0.75)
		style.shadow_color = Color(accent.r, accent.g, accent.b, 0.28)
	if progress_bar != null:
		_glow_bar(progress_bar, accent)

func _glow_bar(bar: ProgressBar, fill: Color) -> void:
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.shadow_color = Color(fill.r, fill.g, fill.b, 0.55)
	fg.shadow_size = 6
	fg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("fill", fg)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.12, 0.12, 0.18, 0.9)
	bg.set_corner_radius_all(4)
	bar.add_theme_stylebox_override("background", bg)

func _process(delta: float) -> void:
	if not visible:
		return
	_tick_fx(delta)
	_tick_era_fx(delta)
	if StoryModeManager.active:
		update_banner(StoryModeManager.era_kind_text(), StoryModeManager.destroyed_count)
	_tick_boot(delta)
	_tick_cinematic(delta)

func setup_era(era: Dictionary, destroyed_count: int, truth_value: float, collected_clues: Array) -> void:
	era_label.text = str(era.get("name", "三体游戏"))
	var task: Dictionary = era.get("task", {})
	task_title.text = "任务：%s" % str(task.get("title", ""))
	task_desc.text = str(task.get("description", ""))
	count_label.text = "毁灭轮回 ×%d" % destroyed_count
	if favor_label != null:
		favor_label.text = "好感 —"
	if treasure_label != null:
		treasure_label.text = "遗宝 ×0"
	objective_label.text = ""
	next_step_label.text = ""
	_events.clear()
	event_label.text = ""
	_set_truth(truth_value, collected_clues)
	_hide_overlay()
	hide_pause()
	hide_guide()
	if casting_panel != null:
		casting_panel.hide()
	show()

func update_banner(kind_text: String, destroyed_count: int) -> void:
	kind_label.text = kind_text
	count_label.text = "毁灭轮回 ×%d" % destroyed_count

func set_progress(value: float) -> void:
	progress_bar.value = clampi(int(value * 100.0), 0, 100)

## 毁灭进度越高红光越刺眼：进度攀升时填充色渐转亮红、辉光加深，营造“文明濒危”压迫感
func set_doom_progress(value: float) -> void:
	if doom_bar == null:
		return
	doom_bar.value = clampi(int(value * 100.0), 0, 100)
	var fill := doom_bar.get_theme_stylebox("fill")
	if fill is StyleBoxFlat:
		var v := clampf(value, 0.0, 1.0)
		var color := Color(0.62, 0.2, 0.18).lerp(Color(1.0, 0.16, 0.1), v)
		(fill as StyleBoxFlat).bg_color = color
		(fill as StyleBoxFlat).shadow_color = Color(color.r, color.g, color.b, 0.55 + 0.25 * v)
		(fill as StyleBoxFlat).shadow_size = 6 + int(10.0 * v)

func set_truth(value: float, collected_clues: Array) -> void:
	_set_truth(value, collected_clues)

## 好感度与遗宝计数（开放剧情模式）
func set_favorability(text: String) -> void:
	if favor_label != null:
		favor_label.text = text

func set_treasure_count(count: int) -> void:
	if treasure_label != null:
		treasure_label.text = "遗宝 ×%d" % count

func _set_truth(value: float, collected_clues: Array) -> void:
	truth_bar.value = clampf(value, 0.0, 100.0)
	var total := maxi(StoryModeManager.eras.size(), 1)
	var dots: Array[String] = []
	for i in total:
		dots.append("●" if i < collected_clues.size() else "○")
	clue_dots.text = "真相 %d%% · %s" % [int(value), " ".join(dots)]

func set_next_step(text: String, tone: String) -> void:
	next_step_label.text = "下一步：%s" % text
	match tone:
		"action":
			next_step_label.modulate = Color(0.55, 0.9, 1.0)
		"danger":
			next_step_label.modulate = Color(1.0, 0.5, 0.4)
		"idle":
			next_step_label.modulate = Color(0.85, 0.85, 0.85)
		_:
			next_step_label.modulate = Color(1.0, 0.8, 0.5)

func push_event(text: String) -> void:
	## 最近事件：保留最近 5 条，新事件置顶且不自动消失；
	## 超出上限时挤出最旧的一条。
	var clean := text.strip_edges()
	if clean == "":
		return
	_events.push_front(clean)
	if _events.size() > 5:
		_events.pop_back()
	_refresh_events()

func _refresh_events() -> void:
	if event_label == null:
		return
	var lines: Array[String] = []
	for e in _events:
		lines.append(str(e))
	event_label.text = "\n".join(lines) if not lines.is_empty() else ""
	# 新事件置顶，刷新后滚动回顶部，保证最新一条可见
	if event_scroll != null:
		event_scroll.scroll_vertical = 0
	# 无事件时整个事件卡隐藏，避免空面板长期停留
	if hud_event_panel != null:
		# 同时尊重 HUD 整体显隐：结束/过场期间即使有新事件也不把事件卡顶出来
		hud_event_panel.visible = _hud_visible and not lines.is_empty()

func show_beat(speaker: String, text: String, choices: Array) -> void:
	if _narrator_fade != null and _narrator_fade.is_valid():
		_narrator_fade.kill()
	_narrator_enabled = true
	_narrator.visible = true
	_narrator.modulate.a = 1.0
	if _subtitle_label != null:
		_hide_subtitle_fade()
	# 简洁模式：只显示选项，隐藏标题行/回复/正文区
	if _narrator_header != null:
		_narrator_header.visible = false
	if reply_label != null:
		reply_label.hide()
	if _narrator_scroll != null:
		_narrator_scroll.hide()
	_narrator_content.visible = true
	_clear_choices()
	for i in choices.size():
		var btn := Button.new()
		btn.text = str(choices[i])
		btn.custom_minimum_size = Vector2(0, 34)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.pressed.connect(_on_choice.bind(i))
		choices_box.add_child(btn)
	continue_btn.hide()
	# 面板高度随选项数量收缩，尽量简洁
	var rows := maxi(choices.size(), 1)
	var panel_h := rows * 38 + 28
	_narrator.offset_top = -panel_h - 16
	_narrator.offset_bottom = -12
	_narrator.custom_minimum_size = Vector2(0, 0)

func show_narration(text: String) -> void:
	## 普通台词/旁白：不使用剧情栏，改为底部字幕（逐字显示，保持到下一节拍）
	_narrator_enabled = false
	if _narrator != null:
		_fade_out_narrator()
	_clear_choices()
	continue_btn.hide()
	if _subtitle_label == null:
		return
	_subtitle_label.text = text
	_subtitle_label.modulate.a = 1.0

## 底部字幕：一次只显示一句（由剧情管理器逐句驱动，语音同步）
func set_bottom_sentence(text: String) -> void:
	if _subtitle_label == null:
		return
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	_subtitle_label.text = text
	_subtitle_label.modulate.a = 1.0
	_subtitle_label.show()

func set_intro_sentence(text: String) -> void:
	if intro_text == null:
		return
	intro_text.text = text
	intro_text.modulate.a = 1.0

func show_reply(text: String) -> void:
	reply_label.text = "◆ %s" % text
	reply_label.show()

func show_objective(title: String, hint: String) -> void:
	show_narration(hint)
	reply_label.hide()
	_objective_title = title
	objective_label.text = "目标：%s（前往发光灯塔）" % title
	reply_label.hide()

func update_objective_distance(distance: float) -> void:
	if _objective_title == "":
		return
	objective_label.text = "目标：%s（距离 %dm）" % [_objective_title, int(distance)]

func objective_done() -> void:
	_objective_title = ""
	objective_label.text = "目标已完成 ✓"

func set_continue_visible(visible_flag: bool) -> void:
	continue_btn.visible = visible_flag

func flash(color: Color, max_alpha: float) -> void:
	flash_rect.color = Color(color.r, color.g, color.b, max_alpha)
	flash_rect.show()
	var tween := create_tween()
	tween.tween_property(flash_rect, "color:a", 0.0, 0.9)
	tween.tween_callback(flash_rect.hide)

func show_vsuit_boot(title: String) -> void:
	boot_label.text = "即将进入：%s" % title
	boot_bar.value = 0.0
	_boot_time = 0.0
	boot_overlay.show()

func hide_vsuit_boot() -> void:
	boot_overlay.hide()

func show_dehydrate_choice() -> void:
	dehydrate_overlay.show()

func hide_dehydrate_choice() -> void:
	dehydrate_overlay.hide()

func hide_pause() -> void:
	pause_overlay.hide()

func hide_guide() -> void:
	guide_overlay.hide()

func _open_casting() -> void:
	pause_overlay.hide()
	if casting_panel != null:
		casting_panel.open()

func show_era_complete(text: String, btn_text: String) -> void:
	_show_overlay("文明完成使命", text, btn_text)

func show_world_destroyed(reason: String, btn_text: String) -> void:
	_show_overlay("☀ 世界毁灭", reason, btn_text)

func show_ending(success: bool, text: String, btn_text: String) -> void:
	_show_overlay("三体游戏 · 通关" if success else "三体游戏 · 终局", text, btn_text)

func hide_overlay() -> void:
	_hide_overlay()

func hide_all() -> void:
	set_trance(0.0)
	hide()
	_hide_overlay()
	hide_vsuit_boot()
	hide_cinematic()
	hide_era_intro()
	hide_wake()
	if _external_label != null:
		_external_label.hide()
	if _banner_label != null:
		_banner_label.hide()
	if _subtitle_label != null:
		_hide_subtitle_fade()
	_hide_milestone()
	hide_dehydrate_choice()
	hide_pause()
	hide_guide()
	if casting_panel != null:
		casting_panel.hide()

func _on_choice(index: int) -> void:
	## 玩家按下选项后立即收起选项：清空按钮并隐藏剧情栏，
	## 直到下一个剧情节拍（show_beat）需要展示选项时再出现。
	_clear_choices()
	continue_btn.hide()
	_narrator_enabled = false
	if _narrator != null:
		_fade_out_narrator()
	choice_pressed.emit(index)

func _clear_choices() -> void:
	for child in choices_box.get_children():
		child.queue_free()

## 字幕过渡式收尾：淡出后隐藏，而非瞬间消失
func _hide_subtitle_fade() -> void:
	if _subtitle_label == null:
		return
	if _subtitle_tween != null and _subtitle_tween.is_valid():
		_subtitle_tween.kill()
	_subtitle_tween = create_tween()
	_subtitle_tween.tween_property(_subtitle_label, "modulate:a", 0.0, 0.3) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_subtitle_tween.tween_callback(_subtitle_label.hide)

## 剧情栏淡出：内容结束后过渡式收起，而不是瞬间消失
func _fade_out_narrator() -> void:
	if _narrator == null:
		return
	if _narrator_fade != null and _narrator_fade.is_valid():
		_narrator_fade.kill()
	_narrator.modulate.a = 1.0
	_narrator_fade = create_tween()
	_narrator_fade.tween_property(_narrator, "modulate:a", 0.0, 0.25) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_narrator_fade.tween_callback(func() -> void:
		_narrator.visible = false
		_narrator.modulate.a = 1.0
	)

func _toggle_narrator() -> void:
	_narrator_collapsed = not _narrator_collapsed
	_apply_narrator_collapse()

func _expand_narrator() -> void:
	if _narrator_collapsed:
		_narrator_collapsed = false
		_apply_narrator_collapse()

func _apply_narrator_collapse() -> void:
	if _narrator == null:
		return
	if _narrator_collapsed:
		_narrator.offset_top = -46
		_narrator.custom_minimum_size = Vector2(0, 34)
		_narrator_content.visible = false
		_collapse_btn.text = "展开 ▴"
	else:
		_narrator.offset_top = -230
		_narrator.custom_minimum_size = Vector2(0, 210)
		_narrator_content.visible = true
		_collapse_btn.text = "收起 ▾"


func _tick_boot(delta: float) -> void:
	if not boot_overlay.visible:
		return
	var duration := maxf(StoryModeManager.boot_duration, 0.05)
	_boot_time += delta
	boot_bar.value = clampf(_boot_time / duration * 100.0, 0.0, 100.0)
	if _boot_time >= duration:
		boot_overlay.hide()
		boot_finished.emit()

# ---------- 电影式过场 ----------

func show_cinematic(kind: String, title: String, subtitle: String, duration: float) -> void:
	_cinematic_kind_color(kind)
	_cinematic_duration = maxf(duration, 0.05)
	_cinematic_time = 0.0
	_cinematic_active = true
	# 过场期间隐藏全部剧情 HUD，屏幕只留世界与标题（干净、沉浸）
	set_hud_visible(false)
	cinematic_vsuit.text = "V装具同步中……" if kind == "era" else "天象骤变……"
	cinematic_vsuit.visible = kind == "era" or kind == "destroyed"
	cinematic_title.text = title
	cinematic_title.modulate.a = 0.0
	cinematic_subtitle.text = subtitle
	cinematic_subtitle.modulate.a = 0.0
	cinematic_circle.scale = Vector2.ONE * 0.2
	cinematic_circle.rotation = 0.0
	cinematic_bar.value = 0.0
	letterbox_top.offset_bottom = 0.0
	letterbox_bottom.offset_top = 0.0
	if cinematic_sparks != null:
		cinematic_sparks.position = Vector2(cinematic_overlay.size.x * 0.5, cinematic_overlay.size.y * 0.34)
	cinematic_overlay.show()

func hide_cinematic() -> void:
	_cinematic_active = false
	cinematic_overlay.hide()
	set_hud_visible(true)

## 剧情 HUD 显隐：过场/引言演出期间隐藏信息卡、任务卡、事件流、菜单与叙事条
func set_hud_visible(visible: bool) -> void:
	_hud_visible = visible
	if hud_info_panel != null:
		hud_info_panel.visible = visible
	if hud_task_panel != null:
		hud_task_panel.visible = visible
	if hud_event_panel != null:
		# 事件卡只在有事件时显示（见 _refresh_events）
		hud_event_panel.visible = visible and not _events.is_empty()
	if pause_btn != null:
		pause_btn.visible = visible
	if _narrator != null:
		_narrator.visible = visible and _narrator_enabled
	if _subtitle_label != null:
		_subtitle_label.visible = visible

## 脑机接口恍惚强度：V装具同步/苏醒/天象/毁灭按场景设定，平滑过渡
func set_trance(strength: float) -> void:
	_fx_target = clampf(strength, 0.0, 1.0)
	if _fx_target > 0.01:
		_fx_rect.show()

func _tick_fx(delta: float) -> void:
	if _fx_rect == null or not _fx_rect.visible:
		return
	_fx_time += delta
	_fx_strength = lerpf(_fx_strength, _fx_target, clampf(delta * 2.0, 0.0, 1.0))
	if _fx_strength < 0.01 and _fx_target < 0.01 \
			and _fx_heat < 0.01 and _fx_cold < 0.01 and _fx_anomaly < 0.01:
		_fx_rect.hide()
		return
	_fx_material.set_shader_parameter("strength", _fx_strength)
	_fx_material.set_shader_parameter("time", _fx_time)

## 纪元大气光效：酷热的热浪扭曲、严寒的霜蓝、大变动（双日/三日凌空）的白光异象
func _tick_era_fx(delta: float) -> void:
	if _fx_material == null:
		return
	var heat := 0.0
	var cold := 0.0
	var anomaly := 0.0
	if StoryModeManager != null and StoryModeManager.active:
		match StoryModeManager.era_kind:
			StoryModeManager.EraKind.CHAOS_HOT:
				heat = 0.8
			StoryModeManager.EraKind.CHAOS_COLD:
				cold = 0.75
			StoryModeManager.EraKind.DESTROYED:
				anomaly = 1.0
				heat = 0.5
		if StoryModeManager.sky != null and is_instance_valid(StoryModeManager.sky):
			match StoryModeManager.sky.current_conjunction():
				"triple":
					anomaly = maxf(anomaly, 0.9)
					heat = maxf(heat, 0.7)
				"binary":
					anomaly = maxf(anomaly, 0.3)
					heat = maxf(heat, 0.3)
	_fx_heat = lerpf(_fx_heat, heat, clampf(delta * 2.0, 0.0, 1.0))
	_fx_cold = lerpf(_fx_cold, cold, clampf(delta * 2.0, 0.0, 1.0))
	_fx_anomaly = lerpf(_fx_anomaly, anomaly, clampf(delta * 2.0, 0.0, 1.0))
	if _fx_heat > 0.01 or _fx_cold > 0.01 or _fx_anomaly > 0.01:
		_fx_rect.show()
	_fx_material.set_shader_parameter("heat", _fx_heat)
	_fx_material.set_shader_parameter("cold", _fx_cold)
	_fx_material.set_shader_parameter("anomaly", _fx_anomaly)

func _finish_cinematic() -> void:
	if not _cinematic_active:
		return
	hide_cinematic()
	cinematic_finished.emit()

func _tick_cinematic(delta: float) -> void:
	if not _cinematic_active:
		return
	_cinematic_time += delta
	var t := clampf(_cinematic_time / _cinematic_duration, 0.0, 1.0)
	cinematic_bar.value = t * 100.0
	# 遮罩从深黑淡出，让镜头运动与角色走位可见（仍保留电影感的暗角）
	cinematic_overlay.color = Color(0.0, 0.0, 0.0, _cinematic_background_alpha(t))
	# 中央象征图形：前 60% 放大，之后轻微脉动
	var grow := clampf(t / 0.6, 0.0, 1.0)
	var scale := 0.2 + 0.8 * (1.0 - pow(1.0 - grow, 3.0))
	if t > 0.6:
		scale += sin((t - 0.6) * 14.0) * 0.035
	cinematic_circle.scale = Vector2.ONE * maxf(scale, 0.05)
	cinematic_circle.rotation += delta * 0.8
	# 全息扫描线自上而下
	if cinematic_scan != null:
		cinematic_scan.position.y = fmod(t * 1.7, 1.0) * cinematic_overlay.size.y
	# 卦象字符脉动
	if cinematic_glyph != null:
		cinematic_glyph.modulate.a = 0.28 + sin(t * 16.0) * 0.12
	# 光尘跟随中心
	if cinematic_sparks != null:
		cinematic_sparks.position = Vector2(cinematic_overlay.size.x * 0.5, cinematic_overlay.size.y * 0.34)
	# 黄金螺线随过场生长旋转
	if _spiral_line != null:
		var cx := cinematic_overlay.size.x * 0.5
		var cy := cinematic_overlay.size.y * 0.34
		_spiral_line.points = _golden_spiral_points(cx, cy, t)
	# 三体轨道光点沿椭圆运动
	var ocx := cinematic_overlay.size.x * 0.5
	var ocy := cinematic_overlay.size.y * 0.34
	for i in _orbit_dots.size():
		var dot: Control = _orbit_dots[i]
		var a := t * TAU + i * TAU / 3.0
		var rx := 96.0 + i * 30.0
		var ry := rx * 0.55
		dot.position = Vector2(ocx + cos(a) * rx - 4.5, ocy + sin(a) * ry - 4.5)
		dot.rotation = a
	cinematic_title.modulate.a = clampf((t - 0.05) / 0.22, 0.0, 1.0)
	cinematic_subtitle.modulate.a = clampf((t - 0.28) / 0.25, 0.0, 1.0)
	var bar_h := 56.0 * clampf(t / 0.45, 0.0, 1.0)
	letterbox_top.offset_bottom = bar_h
	letterbox_bottom.offset_top = -bar_h
	if t >= 1.0:
		_finish_cinematic()

func _cinematic_background_alpha(t: float) -> float:
	# 开场保持深黑强化“同步/天变”仪式感，随后淡出让演出可见
	if t < 0.10:
		return 0.95
	if t < 0.42:
		return lerpf(0.95, 0.45, (t - 0.10) / 0.32)
	return 0.45

func _golden_spiral_points(cx: float, cy: float, t: float) -> PackedVector2Array:
	## 黄金螺线：每 90° 半径乘 φ，随过场从内向外生长
	var pts := PackedVector2Array()
	var phi := (1.0 + sqrt(5.0)) / 2.0
	var b := log(phi) / (PI / 2.0)
	var max_r := 190.0
	var a := t * 2.6
	var n := 0
	while n < 90:
		var r := 3.5 * exp(b * a)
		if r > max_r:
			break
		pts.append(Vector2(cx + cos(a) * r, cy + sin(a) * r * 0.9))
		a += 0.09
		n += 1
	return pts

func _cinematic_kind_color(kind: String) -> void:
	var color := Color(1.0, 0.75, 0.35)
	match kind:
		"stable":
			color = Color(0.95, 0.8, 0.45)
		"hot":
			color = Color(1.0, 0.35, 0.1)
		"cold":
			color = Color(0.5, 0.75, 1.0)
		"destroyed":
			color = Color(1.0, 0.95, 0.85)
		"truth":
			color = Color(0.45, 0.95, 1.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(color.r, color.g, color.b, 0.28)
	style.border_color = Color(color.r, color.g, color.b, 0.9)
	style.set_border_width_all(3)
	style.set_corner_radius_all(140)
	cinematic_circle.add_theme_stylebox_override("panel", style)

# ---------- 纪元引言（独立背景介绍幕） ----------

func show_era_intro(title: String, text: String) -> void:
	intro_title.text = title
	intro_text.text = text
	intro_text.modulate.a = 0.0
	intro_overlay.show()
	var tw := create_tween()
	tw.tween_property(intro_text, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

func hide_era_intro() -> void:
	intro_overlay.hide()

func _finish_intro() -> void:
	if not intro_overlay.visible:
		return
	hide_era_intro()
	intro_finished.emit()

# ---------- 睁眼苏醒 ----------

func show_wake() -> void:
	wake_overlay.color.a = 1.0
	wake_label.modulate.a = 0.0
	wake_overlay.show()
	var duration := maxf(StoryModeManager.wake_duration, 0.2)
	var tw := create_tween()
	tw.tween_property(wake_label, "modulate:a", 1.0, 0.5)
	tw.tween_property(wake_overlay, "color:a", 0.0, maxf(duration - 0.7, 0.1)).set_delay(0.6)
	tw.tween_callback(_finish_wake)

func hide_wake() -> void:
	if wake_overlay != null:
		wake_overlay.hide()

func _finish_wake() -> void:
	hide_wake()
	wake_finished.emit()

## 外部系统音：苏醒前的降临提示（穿越网文式），淡入淡出
func show_external_voice(text: String) -> void:
	_external_label.text = "叮——\n%s" % text
	_external_label.modulate.a = 0.0
	_external_label.show()
	var pace := StoryModeManager.story_pace if StoryModeManager != null else 1.0
	var type_time := text.length() / maxf(4.5 * pace, 1.0)
	var tw := create_tween()
	tw.tween_property(_external_label, "modulate:a", 1.0, 0.4)
	tw.tween_interval(maxf(type_time + 0.8, 0.8))
	tw.tween_property(_external_label, "modulate:a", 0.0, 0.6)
	tw.tween_callback(_external_label.hide)

func hide_external_voice() -> void:
	if _external_label != null:
		_external_label.hide()

# ---------- 顶部横幅（预警/旅途字幕/登场聚焦） ----------

func show_warning(text: String) -> void:
	_show_banner(text, Color(1.0, 0.45, 0.3))

func show_journey_step(text: String) -> void:
	_show_banner(text, Color(0.55, 0.9, 1.0))

func show_character_entrance(name: String) -> void:
	_show_banner("◈ %s 登场" % name, Color(1.0, 0.82, 0.42))

func _show_banner(text: String, color: Color) -> void:
	_banner_label.text = text
	_banner_label.modulate = Color(color.r, color.g, color.b, 0.0)
	_banner_label.show()
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	var pace := StoryModeManager.story_pace if StoryModeManager != null else 1.0
	var type_time := text.length() / maxf(4.5 * pace, 1.0)
	_banner_tween = create_tween()
	_banner_tween.tween_property(_banner_label, "modulate:a", 1.0, 0.3)
	_banner_tween.tween_interval(maxf(type_time + 1.2, 1.0))
	_banner_tween.tween_property(_banner_label, "modulate:a", 0.0, 0.6)
	_banner_tween.tween_callback(_banner_label.hide)

# ---------- 关键节点横幅 ----------

func show_milestone(title: String, line: String, color: Color) -> void:
	milestone_title.text = title
	milestone_title.modulate = color
	milestone_subtitle.text = line
	milestone_panel.show()
	milestone_panel.offset_top = -90
	milestone_panel.offset_bottom = -34
	if milestone_panel.has_meta("ms_tween"):
		var old: Tween = milestone_panel.get_meta("ms_tween")
		old.kill()
	var tw := create_tween()
	milestone_panel.set_meta("ms_tween", tw)
	tw.tween_property(milestone_panel, "offset_top", 8.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(milestone_panel, "offset_bottom", 64.0, 0.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	var pace := StoryModeManager.story_pace if StoryModeManager != null else 1.0
	var hold := maxf(1.5, float(title.length() + line.length()) / maxf(4.5 * pace, 1.0) + 1.0)
	tw.tween_interval(hold)
	tw.tween_property(milestone_panel, "offset_top", -90.0, 0.32).set_ease(Tween.EASE_IN)
	tw.parallel().tween_property(milestone_panel, "offset_bottom", -34.0, 0.32).set_ease(Tween.EASE_IN)
	tw.tween_callback(_hide_milestone)

func _hide_milestone() -> void:
	milestone_panel.hide()

func _show_overlay(title: String, text: String, btn_text: String) -> void:
	# 终结/阶段覆盖层出现时清掉背后的剧情 HUD（信息卡/任务卡/事件流/菜单/叙事条/
	# 横幅/里程碑等），让结束画面与开局一样简洁
	set_hud_visible(false)
	if _external_label != null:
		_external_label.hide()
	if _banner_label != null:
		_banner_label.hide()
	_hide_milestone()
	overlay_title.text = title
	overlay_text.text = text
	overlay_btn.text = btn_text
	overlay.show()

func _hide_overlay() -> void:
	if overlay != null:
		overlay.hide()
