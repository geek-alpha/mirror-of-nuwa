class_name HistoryUI
extends Control
## 历史年鉴界面：事件日志、文明年鉴、角色传记三个标签页。

var event_label: RichTextLabel
var annals_label: RichTextLabel
var bio_label: RichTextLabel
var bio_select: OptionButton
var filter_select: OptionButton
var tabs: TabContainer

func _ready() -> void:
	anchor_left = 0.5
	anchor_top = 0.5
	anchor_right = 0.5
	anchor_bottom = 0.5
	offset_left = -340
	offset_top = -280
	offset_right = 340
	offset_bottom = 280
	custom_minimum_size = Vector2(680, 560)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 560)
	add_child(panel)
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vbox)
	var top := HBoxContainer.new()
	vbox.add_child(top)
	var title := Label.new()
	title.text = "历史年鉴"
	title.add_theme_font_size_override("font_size", 18)
	top.add_child(title)
	top.add_spacer(true)
	var close_btn := Button.new()
	close_btn.text = "关闭"
	close_btn.pressed.connect(func(): hide())
	top.add_child(close_btn)
	tabs = TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(tabs)
	# 事件日志
	var event_box := VBoxContainer.new()
	tabs.add_child(event_box)
	event_box.name = "事件日志"
	filter_select = OptionButton.new()
	filter_select.add_item("全部", 0)
	filter_select.add_item("世界", 1)
	filter_select.add_item("诞生", 2)
	filter_select.add_item("陨落", 3)
	filter_select.add_item("对话", 4)
	filter_select.add_item("科技", 5)
	filter_select.add_item("建筑", 6)
	filter_select.add_item("宗教", 7)
	filter_select.add_item("战争", 8)
	filter_select.add_item("干预", 9)
	filter_select.item_selected.connect(func(_i): refresh())
	event_box.add_child(filter_select)
	event_label = RichTextLabel.new()
	event_label.bbcode_enabled = true
	event_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	event_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	event_label.scroll_following = true
	event_box.add_child(event_label)
	# 文明年鉴
	var annals_box := VBoxContainer.new()
	tabs.add_child(annals_box)
	annals_box.name = "文明年鉴"
	annals_label = RichTextLabel.new()
	annals_label.bbcode_enabled = true
	annals_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	annals_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	annals_box.add_child(annals_label)
	# 角色传记
	var bio_box := VBoxContainer.new()
	tabs.add_child(bio_box)
	bio_box.name = "角色传记"
	bio_select = OptionButton.new()
	bio_select.item_selected.connect(func(_i): _refresh_bio())
	bio_box.add_child(bio_select)
	bio_label = RichTextLabel.new()
	bio_label.bbcode_enabled = true
	bio_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bio_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bio_box.add_child(bio_label)
	refresh()

func refresh() -> void:
	if event_label == null:
		return
	# 事件日志
	var filter_map := {
		0: "", 1: "world", 2: "birth", 3: "death", 4: "dialogue",
		5: "technology", 6: "building", 7: "religion", 8: "war", 9: "intervention"
	}
	var filter := str(filter_map.get(filter_select.selected, ""))
	var events := HistoryManager.get_events(filter)
	if events.is_empty():
		event_label.text = "（暂无事件）"
	else:
		var lines: Array[String] = []
		for ev in events:
			lines.append("[%s] %s\n  %s" % [ev.get("date_text", ""), ev.get("title", ""), ev.get("details", "")])
		event_label.text = "\n".join(lines)
	annals_label.text = HistoryManager.get_annals_text()
	# 角色下拉
	var prev_id := ""
	if bio_select.selected >= 0 and bio_select.selected < bio_select.item_count:
		prev_id = str(bio_select.get_item_metadata(bio_select.selected))
	bio_select.clear()
	var chars := CharacterManager.all_characters()
	for c in chars:
		var cid: String = c.character_data.id
		bio_select.add_item(c.character_data.name)
		bio_select.set_item_metadata(bio_select.item_count - 1, cid)
		if cid == prev_id:
			bio_select.select(bio_select.item_count - 1)
	_refresh_bio()

func _refresh_bio() -> void:
	if bio_label == null:
		return
	if bio_select.item_count == 0:
		bio_label.text = "（没有可查看的角色）"
		return
	var cid := str(bio_select.get_item_metadata(bio_select.selected))
	bio_label.text = HistoryManager.get_biography_text(cid)

func show_for(character_id: String = "") -> void:
	visible = true
	refresh()
	if character_id != "":
		for i in bio_select.item_count:
			if str(bio_select.get_item_metadata(i)) == character_id:
				bio_select.select(i)
				tabs.current_tab = 2
				_refresh_bio()
				break
