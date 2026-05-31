## MusicPlayer — autoload
## 遊戲開始即循環播放主題曲；bus = "Music"，受 AudioSettings 音樂音量控制。
## 暫停選單開啟時 (tree paused) BGM 仍持續播放。
## 留 play()/stop() 公開 API 供日後分場景換曲。
extends Node

const MAIN_BGM_PATH: String = "res://assets/audio/music/muzha_main_bgm.ogg"

var _player: AudioStreamPlayer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS  # 暫停時 BGM 不停
	_player = AudioStreamPlayer.new()
	_player.bus = "Music"
	add_child(_player)

	var stream: AudioStream = load(MAIN_BGM_PATH)
	if stream == null:
		push_warning("[MusicPlayer] failed to load %s" % MAIN_BGM_PATH)
		return
	play(stream)

## 播放指定串流並強制循環。
## 在程式碼設 loop 而非靠 .import：本專案 .gitignore 排除 *.import，
## 別台機器重匯入會 default loop=false，故 runtime 強制比較穩。
func play(stream: AudioStream) -> void:
	if stream == null:
		return
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	_player.stream = stream
	_player.play()

func stop() -> void:
	_player.stop()
