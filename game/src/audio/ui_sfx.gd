## UISfx — autoload
## UI 按鈕點擊音。runtime 合成一段短促衰減音（AudioStreamWAV），走 SFX bus。
## 用法：按鈕在 _ready 把 pressed 連到 play_click，例：
##   my_button.pressed.connect(UISfx.play_click)
extends Node

const SAMPLE_RATE: int = 22050
const DURATION_SEC: float = 0.045          # 短促
const FREQ_HZ: float = 880.0               # 清脆的「噠」
const AMPLITUDE: float = 0.28              # 不刺耳

var _player: AudioStreamPlayer
var _click: AudioStreamWAV

func _ready() -> void:
	_player = AudioStreamPlayer.new()
	_player.bus = "SFX"
	add_child(_player)
	_click = _build_click()

## 播放點擊音。stream 缺失時安全 no-op。
func play_click() -> void:
	if _click == null:
		return
	_player.stream = _click
	_player.play()

## 合成一段 8-bit 衰減正弦，前段加極短淡入避免爆音。
func _build_click() -> AudioStreamWAV:
	var n: int = int(SAMPLE_RATE * DURATION_SEC)
	var data: PackedByteArray = PackedByteArray()
	data.resize(n)
	for i: int in range(n):
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = exp(-t * 60.0)                        # 指數衰減
		var fade_in: float = clampf(float(i) / 64.0, 0.0, 1.0)   # ~3ms 淡入
		var sample: float = sin(TAU * FREQ_HZ * t) * env * fade_in * AMPLITUDE
		var v: int = clampi(int(sample * 127.0), -128, 127)
		data[i] = v & 0xFF                                     # 8-bit signed → byte
	var wav: AudioStreamWAV = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_8_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = data
	return wav
