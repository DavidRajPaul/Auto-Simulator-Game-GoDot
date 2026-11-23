class_name FramePacer
extends RefCounted
## Decision logic behind FrameGuard: which frame-rate cap to run at and how far to lower the
## 3D render scale so frames keep landing on time. No engine calls here, so the headless
## smoothness suite feeds it frame times directly (tests/run_smoothness_tests.gd).
##
## Smooth beats fast: a steady 30 feels better than a 40–55 wobble. So the order is
## 1. lower the 3D resolution in small steps while frames miss their vsync,
## 2. if it is already at the floor and still missing (heavy scene, or the phone is hot and
##    throttling), drop to a steady 30 FPS at full resolution,
## 3. later, if the phone has lots of headroom again, try 60 once more (waiting longer after
##    every fallback so it never flip-flops).

enum Mode { AUTO, LOCK_30, LOCK_60 }

## A frame "misses" when it took this many times the target interval (a missed vsync at 60
## shows up as ~33 ms, twice the 16.7 ms target).
const MISS_RATIO: float = 1.4
## Frames longer than this are loading or resume pauses, not rendering load: ignored.
const IGNORE_MS: float = 250.0
## Lower the resolution when more than this share of frames missed in the last DOWN_WINDOW s.
const DOWN_MISS_SHARE: float = 0.08
const DOWN_WINDOW: int = 3
## Raise it when under UP_MISS_SHARE missed over UP_WINDOW s and the frame's measured work
## used less than UP_WORK_SHARE of the interval (or no work figure is available and nothing missed).
const UP_MISS_SHARE: float = 0.01
const UP_WINDOW: int = 10
const UP_WORK_SHARE: float = 0.72
const STEP: float = 0.05
## The dynamic factor multiplies the graphics preset's own scale (Low 0.7 → floor 0.7 × 0.8 = 0.56).
const MIN_FACTOR: float = 0.8
const COOLDOWN_DOWN_S: float = 3.0
const COOLDOWN_UP_S: float = 10.0
## Auto mode: seconds of misses with the resolution already at the floor before dropping to 30.
const FALLBACK_AFTER_S: float = 8.0
## Auto mode at 30: first retry of 60 after this long, doubling after every fallback.
const RETRY_60_S: float = 60.0
const RETRY_60_MAX_S: float = 480.0
## …and only when the work of a frame would fit in this share of a 60 FPS interval.
const RETRY_WORK_SHARE: float = 0.6
## Factor used when coming back up to 60, so the first seconds are not already over budget.
const RETRY_FACTOR: float = 0.9

var mode: int = Mode.AUTO
var target_fps: int = 60
var factor: float = 1.0
## Times the auto mode fell back to 30 this session (the retry wait doubles each time).
var fallbacks: int = 0

var _frames: int = 0
var _missed: int = 0
var _work_sum: float = 0.0
var _work_n: int = 0
var _bucket_s: float = 0.0
var _miss_hist: PackedFloat32Array = PackedFloat32Array()
var _work_hist: PackedFloat32Array = PackedFloat32Array()
var _cooldown_s: float = 0.0
var _slow_at_floor_s: float = 0.0
var _at_30_s: float = 0.0
var _retry_after_s: float = RETRY_60_S

func set_mode(m: int) -> void:
	mode = clampi(m, Mode.AUTO, Mode.LOCK_60)
	target_fps = 30 if mode == Mode.LOCK_30 else 60
	factor = 1.0
	_reset_windows()

func target_ms() -> float:
	return 1000.0 / float(target_fps)

## One frame. frame_ms = wall time since the last frame; work_ms = how long the frame's work
## took (CPU or GPU, whichever is longer), or a negative number when unknown.
## Returns true when target_fps or factor changed, so the caller applies them.
func feed(frame_ms: float, work_ms: float) -> bool:
	if frame_ms <= 0.0 or frame_ms > IGNORE_MS:
		return false
	_frames += 1
	if frame_ms > target_ms() * MISS_RATIO:
		_missed += 1
	if work_ms >= 0.0:
		_work_sum += work_ms
		_work_n += 1
	_bucket_s += frame_ms / 1000.0
	if _bucket_s < 1.0:
		return false
	return _end_second(_bucket_s)

func _end_second(span_s: float) -> bool:
	_miss_hist.append(float(_missed) / float(maxi(_frames, 1)))
	_work_hist.append(_work_sum / float(_work_n) if _work_n > 0 else -1.0)
	if _miss_hist.size() > UP_WINDOW:
		_miss_hist.remove_at(0)
		_work_hist.remove_at(0)
	_frames = 0
	_missed = 0
	_work_sum = 0.0
	_work_n = 0
	_bucket_s = 0.0
	_cooldown_s = maxf(_cooldown_s - span_s, 0.0)
	if target_fps == 30:
		_at_30_s += span_s
	var slow: bool = _share(DOWN_WINDOW) > DOWN_MISS_SHARE
	if slow and factor <= MIN_FACTOR + 0.001:
		_slow_at_floor_s += span_s
	elif not slow:
		_slow_at_floor_s = 0.0
	# 1. Auto: stuck at the floor and still missing → steady 30 at full resolution.
	if mode == Mode.AUTO and target_fps == 60 and _slow_at_floor_s >= FALLBACK_AFTER_S:
		target_fps = 30
		factor = 1.0
		fallbacks += 1
		_at_30_s = 0.0
		_retry_after_s = minf(RETRY_60_S * pow(2.0, float(fallbacks - 1)), RETRY_60_MAX_S)
		_reset_windows()
		_cooldown_s = COOLDOWN_UP_S
		return true
	# 2. Auto at 30 with lots of headroom for a while → try 60 again.
	if mode == Mode.AUTO and target_fps == 30 and _at_30_s >= _retry_after_s \
			and _miss_hist.size() >= UP_WINDOW and _share(UP_WINDOW) <= UP_MISS_SHARE:
		var work: float = _avg_work(UP_WINDOW)
		if work >= 0.0 and work <= (1000.0 / 60.0) * RETRY_WORK_SHARE:
			target_fps = 60
			factor = RETRY_FACTOR
			_reset_windows()
			_cooldown_s = COOLDOWN_DOWN_S
			return true
	if _cooldown_s > 0.0:
		return false
	# 3. Missing frames → lower the resolution a step.
	if slow and factor > MIN_FACTOR + 0.001:
		factor = maxf(factor - STEP, MIN_FACTOR)
		_cooldown_s = COOLDOWN_DOWN_S
		return true
	# 4. Calm for a while with spare time → raise it a step.
	if factor < 1.0 - 0.001 and _miss_hist.size() >= UP_WINDOW and _share(UP_WINDOW) <= UP_MISS_SHARE:
		var w: float = _avg_work(UP_WINDOW)
		if (w >= 0.0 and w <= target_ms() * UP_WORK_SHARE) or (w < 0.0 and _share(UP_WINDOW) == 0.0):
			factor = minf(factor + STEP, 1.0)
			_cooldown_s = COOLDOWN_UP_S
			return true
	return false

func _share(window: int) -> float:
	var n: int = mini(window, _miss_hist.size())
	if n == 0:
		return 0.0
	var s: float = 0.0
	for i: int in range(_miss_hist.size() - n, _miss_hist.size()):
		s += _miss_hist[i]
	return s / float(n)

func _avg_work(window: int) -> float:
	var n: int = mini(window, _work_hist.size())
	var s: float = 0.0
	var k: int = 0
	for i: int in range(_work_hist.size() - n, _work_hist.size()):
		if _work_hist[i] >= 0.0:
			s += _work_hist[i]
			k += 1
	return s / float(k) if k == n and k > 0 else -1.0

func _reset_windows() -> void:
	_miss_hist.clear()
	_work_hist.clear()
	_frames = 0
	_missed = 0
	_work_sum = 0.0
	_work_n = 0
	_bucket_s = 0.0
	_slow_at_floor_s = 0.0
	_cooldown_s = 0.0
