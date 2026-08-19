extends Node
## 音效管理器：加载 assets/audio 下的科幻音效，提供一键播放 / 循环氛围 / 3D 定位播放。

const AUDIO_DIR := "res://assets/audio/"
const SOUNDS := {
	"footstep": "footstep_loop.mp3",
	"beam": "freesound_community-futuristic-beam-81215.mp3",
	"hover": "freesound_community-hover-engine-6391.mp3",
	"tick": "freesound_community-labratory-clock-tick-science-fiction-alien-80353.mp3",
	"landing": "freesound_community-ufo-landing-93632.mp3",
	"whoosh": "rescopicsound-cinematic-designed-sci-fi-whoosh-transition-nexawave-228295.mp3",
	"discharge": "submority-morphed-metal-discharged-cinematic-trailer-sound-effects-124763.mp3",
	"drone": "freesound_community-drone-sound-hallway-91994.mp3",
	"teleport": "freesound_community-instant-teleport-90645.mp3",
	"teleporter": "freesound_community-teleporter-102110.mp3",
	"raygun": "flutie8211-ray-gun-blast-2-573561.mp3",
	"blaster": "freesound_community-blaster-2-81267.mp3",
	"tank": "freesound_community-robot-tank-34600.mp3",
	"scifi": "freesound_community-scifi-sound-85501.mp3",
	"powerup": "nico0825-power-up-strike-446145.mp3",
	"braam": "submority-braam-classic-satellite-g-cinematic-trailer-sound-effects-123877.mp3"
}

var _streams: Dictionary = {}
var _loops: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []

func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.name = "SFX%d" % i
		add_child(p)
		_pool.append(p)

func _stream(name: String) -> AudioStream:
	if not SOUNDS.has(name):
		return null
	if not _streams.has(name):
		var path := AUDIO_DIR + str(SOUNDS[name])
		if not ResourceLoader.exists(path):
			push_warning("音效缺失：" + path)
			return null
		_streams[name] = load(path)
	return _streams.get(name)

func play(name: String, volume_db := 0.0, pitch := 1.0) -> void:
	var stream := _stream(name)
	if stream == null:
		return
	var p := _idle_player()
	if p == null:
		return
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

func play_3d(name: String, world_pos: Vector3, volume_db := 0.0) -> void:
	var stream := _stream(name)
	if stream == null or WorldManager.world == null:
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = stream
	p.volume_db = volume_db
	p.max_distance = 70.0
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
	WorldManager.world.add_child(p)
	p.global_position = world_pos
	p.finished.connect(func() -> void:
		if is_instance_valid(p):
			p.queue_free()
	)
	p.play()

func start_loop(name: String, volume_db := -18.0) -> void:
	var stream := _stream(name)
	if stream == null:
		return
	if _loops.has(name) and is_instance_valid(_loops[name]):
		return
	var p := AudioStreamPlayer.new()
	p.name = "Loop_" + name
	p.stream = stream
	p.volume_db = volume_db
	p.finished.connect(func() -> void:
		if is_instance_valid(p):
			p.play()
	)
	add_child(p)
	_loops[name] = p
	p.play()

func stop_loop(name: String) -> void:
	if _loops.has(name) and is_instance_valid(_loops[name]):
		_loops[name].stop()
		_loops[name].queue_free()
	_loops.erase(name)

func stop_all_loops() -> void:
	for key in _loops.keys():
		stop_loop(str(key))

func _idle_player() -> AudioStreamPlayer:
	for p in _pool:
		if not p.playing:
			return p
	return null
