extends Node
## 全局事件总线：所有系统通过信号解耦通信。
## 设计意图：游戏中的一切事件（角色生死、战争、科技、玩家干预）都从这里广播，
## 便于 UI、历史记录、成就等系统以低耦合方式响应。

signal time_scale_changed(scale: float)
signal hour_ticked(hour: int)
signal day_changed(day: int)

signal character_born(character)
signal character_died(character)
signal dialogue_occurred(speaker_id: String, target_id: String, text: String)
signal character_selected(character)
signal player_intervention(character_id: String, kind: String, detail: String)

signal building_built(building)
signal resource_depleted(resource_id: String)
signal technology_discovered(faction_id: String, tech_id: String, tech_name: String)
signal religion_founded(faction_id: String, religion_name: String)
signal war_started(faction_a: String, faction_b: String)
signal war_ended(faction_a: String, faction_b: String)

signal oracle_sent(character_id: String, text: String)
signal world_regenerated()
signal game_mode_changed(mode: String)
signal history_updated()
signal save_completed(path: String)
signal load_completed()
signal llm_status_changed(available: bool, provider: String, model: String)
signal tts_provider_changed(provider: String)
signal achievement_unlocked(achievement_id: String)
