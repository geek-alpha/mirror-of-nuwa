class_name SpeechBubble
extends Node3D
## 漂浮在角色头顶的对话气泡：圆角面板 + 自动换行文字，始终面向相机，
## 并带轻微上下浮动（“漂浮在头顶”的感觉）。

var viewport: SubViewport
var panel: PanelContainer
var label: Label
var sprite: Sprite3D
var _float_t := 0.0
var _base_y := 0.0
var _fade_tween: Tween = null
## 目标文字世界尺寸（与角色名牌一致：font_size × pixel_size）
var _target_text_scale := 0.112

const BASE_WIDTH := 560.0
const WORLD_HEIGHT := 1.5

func set_target_text_scale(scale: float) -> void:
	_target_text_scale = maxf(scale, 0.01)

func _ready() -> void:
	_base_y = position.y
	viewport = SubViewport.new()
	viewport.name = "BubbleViewport"
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.size = Vector2i(int(BASE_WIDTH), 180)
	add_child(viewport)
	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	viewport.add_child(ui)
	panel = PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_FULL_RECT)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.07, 0.12, 0.94)
	style.border_color = Color(0.9, 0.68, 0.42, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(24)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	panel.add_theme_stylebox_override("panel", style)
	ui.add_child(panel)
	label = Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.97, 1.0))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	label.add_theme_constant_override("outline_size", 4)
	panel.add_child(label)
	sprite = Sprite3D.new()
	sprite.texture = viewport.get_texture()
	sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	sprite.shaded = false
	add_child(sprite)
	hide()
	set_process(false)

func show_text(text: String) -> void:
	if not is_inside_tree():
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	if sprite != null:
		sprite.modulate.a = 1.0
	label.text = text
	# 字号：默认 15，长文本自适应缩小；每行不超过 10 个字
	var font_size := 15
	if text.length() > 120:
		font_size = 12
	if text.length() > 240:
		font_size = 10
	var cpl := 10.0
	label.add_theme_font_size_override("font_size", font_size)
	# 计算总行数与最长一行（支持文本内的换行）
	var lines := 0
	var longest_line := 1
	for raw_line in text.split("\n"):
		var seg := str(raw_line)
		lines += maxi(ceili(seg.length() / cpl), 1)
		longest_line = maxi(longest_line, seg.length())
	# 宽度贴合最长一行（≤10 字）；行高按字号×1.4 紧凑排列
	var line_chars := mini(longest_line, int(cpl))
	var w := clampi(int(line_chars * font_size) + 42, 100, 400)
	# 行高留足（字号×1.5），总高多留 30px，确保最后一行完整不被截断
	var line_h := ceili(font_size * 1.5)
	var h := clampi(lines * line_h + 30, 40, 640)
	viewport.size = Vector2i(w, h)
	panel.custom_minimum_size = Vector2(float(w) - 20.0, float(h) - 14.0)
	label.custom_minimum_size = Vector2(float(w) - 36.0, float(h) - 26.0)
	# 文字世界尺寸与名牌一致：字号 × pixel_size = 名牌字号 × 名牌 pixel_size
	sprite.pixel_size = _target_text_scale / float(font_size)
	show()
	set_process(true)

func hide_bubble() -> void:
	# 语音/阅读结束后过渡式收尾：先淡出再隐藏，而不是瞬间消失
	if not visible:
		return
	if _fade_tween != null and _fade_tween.is_valid():
		_fade_tween.kill()
	_fade_tween = create_tween()
	_fade_tween.tween_property(sprite, "modulate:a", 0.0, 0.35) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	_fade_tween.tween_callback(_finish_hide)

func _finish_hide() -> void:
	if sprite != null:
		sprite.modulate.a = 1.0
	hide()
	set_process(false)

func _process(delta: float) -> void:
	_float_t += delta
	position.y = _base_y + sin(_float_t * 2.2) * 0.04
