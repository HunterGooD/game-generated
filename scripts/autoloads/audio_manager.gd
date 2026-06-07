extends Node

# AudioManager — global audio service for music, ambient, and SFX.
# Use AudioManager.play_sfx(stream), play_music(stream), play_ambient(stream).

var music_player: AudioStreamPlayer
var ambient_player: AudioStreamPlayer
var sfx_players: Array[AudioStreamPlayer] = []
const MAX_SFX_PLAYERS := 8


func _ready() -> void:
	music_player = AudioStreamPlayer.new()
	music_player.bus = "Master"
	music_player.volume_db = -8.0
	add_child(music_player)

	ambient_player = AudioStreamPlayer.new()
	ambient_player.bus = "Master"
	ambient_player.volume_db = -12.0
	add_child(ambient_player)

	for i in MAX_SFX_PLAYERS:
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		sfx_players.append(p)


func play_music(stream: AudioStream, volume_db: float = -8.0) -> void:
	if stream == null:
		return
	if music_player == null:
		return
	music_player.stream = stream
	music_player.volume_db = volume_db
	music_player.play()


func stop_music() -> void:
	if music_player and music_player.playing:
		music_player.stop()


func play_ambient(stream: AudioStream, volume_db: float = -14.0) -> void:
	if stream == null:
		return
	if ambient_player == null:
		return
	ambient_player.stream = stream
	ambient_player.volume_db = volume_db
	ambient_player.play()


func play_sfx(stream: AudioStream, volume_db: float = -4.0) -> void:
	if stream == null:
		return
	for p in sfx_players:
		if not p.playing:
			p.stream = stream
			p.volume_db = volume_db
			p.play()
			return
	# All players busy — interrupt the oldest one.
	if sfx_players.size() > 0:
		var p: AudioStreamPlayer = sfx_players[0]
		p.stream = stream
		p.volume_db = volume_db
		p.play()


func play_sfx_path(path: String, volume_db: float = -4.0) -> void:
	if not ResourceLoader.exists(path):
		return
	var stream: AudioStream = load(path) as AudioStream
	if stream:
		play_sfx(stream, volume_db)
