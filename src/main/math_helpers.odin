package main

import rl "vendor:raylib"
import b3 "vendor:box3d"
import "core:math"

abs_f32 :: proc(value: f32) -> f32 {
	if value < 0 {
		return -value
	}
	return value
}

move_towards :: proc(current, target, max_delta: f32) -> f32 {
	if current < target {
		return min(current + max_delta, target)
	}
	return max(current - max_delta, target)
}

lerp_f32 :: proc(a, b, amount: f32) -> f32 {
	return a + (b - a) * amount
}

lerp_v3 :: proc(a, b: rl.Vector3, amount: f32) -> rl.Vector3 {
	return a + (b - a) * amount
}

horizontal_length :: proc(value: rl.Vector3) -> f32 {
	return math.sqrt(value.x * value.x + value.z * value.z)
}

horizontal_distance :: proc(a, b: rl.Vector3) -> f32 {
	dx := a.x - b.x
	dz := a.z - b.z
	return math.sqrt(dx * dx + dz * dz)
}

forward_from_yaw :: proc(yaw: f32) -> rl.Vector3 {
	return {
		math.sin(yaw),
		0,
		-math.cos(yaw),
	}
}

right_from_yaw :: proc(yaw: f32) -> rl.Vector3 {
	return {
		math.cos(yaw),
		0,
		math.sin(yaw),
	}
}

rotate_local_xz :: proc(local: rl.Vector3, yaw: f32) -> rl.Vector3 {
	cos_yaw := math.cos(yaw)
	sin_yaw := math.sin(yaw)
	return {
		local.x * cos_yaw - local.z * sin_yaw,
		local.y,
		local.x * sin_yaw + local.z * cos_yaw,
	}
}

world_from_local :: proc(origin, local: rl.Vector3, yaw: f32) -> rl.Vector3 {
	return origin + rotate_local_xz(local, yaw)
}

rotate_v3_quat :: proc(rotation: b3.Quat, value: rl.Vector3) -> rl.Vector3 {
	// Standard unit-quaternion vector rotation:
	// v' = v + 2*w*(q.xyz x v) + 2*(q.xyz x (q.xyz x v)).
	qv := rl.Vector3{rotation.x, rotation.y, rotation.z}
	uv := rl.Vector3{
		qv.y * value.z - qv.z * value.y,
		qv.z * value.x - qv.x * value.z,
		qv.x * value.y - qv.y * value.x,
	}
	uuv := rl.Vector3{
		qv.y * uv.z - qv.z * uv.y,
		qv.z * uv.x - qv.x * uv.z,
		qv.x * uv.y - qv.y * uv.x,
	}
	return value + uv * (2.0 * rotation.w) + uuv * 2.0
}

BOUNCE_BPM :: f32(135.0)
BOUNCE_ANGULAR_SPEED :: f32(2.0 * rl.PI * BOUNCE_BPM / 60.0)

update_visual_bounce :: proc() {
	if !bounce_mode {
		bounce_wave = 0
		return
	}
	bounce_clock += TIME_STEP
	if bounce_clock > 1000.0 {
		bounce_clock -= 1000.0
	}
	// Niko B - "Why's this dealer?" is 135 BPM. One full squash/stretch hop is
	// locked to each quarter-note beat: squash on the beat, tallest halfway to
	// the next beat. This keeps every bouncing object phase-locked together.
	phase := bounce_clock * BOUNCE_ANGULAR_SPEED
	bounce_wave = 0.5 - 0.5 * math.cos(phase)
}

visual_bounce_y :: proc(amplitude: f32, phase: f32 = 0.0) -> f32 {
	// Bouncy mode is intentionally visual-only. Do not translate the object or
	// its physics body; the meme motion comes entirely from squash/stretch.
	_ = amplitude
	_ = phase
	return 0
}

visual_bounce_transform_point :: proc(point, anchor: rl.Vector3) -> rl.Vector3 {
	if !bounce_mode { return point }
	delta := point - anchor
	return anchor + rl.Vector3{
		delta.x * visual_bounce_horizontal_scale(),
		delta.y * visual_bounce_vertical_scale(),
		delta.z * visual_bounce_horizontal_scale(),
	}
}

visual_bounce_vertical_scale :: proc() -> f32 {
	if !bounce_mode { return 1.0 }
	// Hard squash at the floor, tall stretch at the top.
	return lerp_f32(0.55, 1.38, bounce_wave)
}

visual_bounce_horizontal_scale :: proc() -> f32 {
	if !bounce_mode { return 1.0 }
	// Preserve the cartoon mass illusion: wide when squashed, narrow when stretched.
	return lerp_f32(1.32, 0.88, bounce_wave)
}
