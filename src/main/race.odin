package main

import rl "vendor:raylib"

checkpoint_passed :: proc(position: rl.Vector3, checkpoint: Checkpoint) -> bool {
	// The checkpoint spans the incoming road just before the intersection.
	// Passing from any angle remains valid, but a normal corner approach will always count.
	return horizontal_distance(position, checkpoint.position) <= CHECKPOINT_RADIUS
}

update_race :: proc() {
	if race.started && !race.completed {
		race.elapsed += TIME_STEP
		if race.intro_visible && horizontal_distance(car_position(), race_start_position) > 5.0 {
			race.intro_visible = false
		}
	}

	if !race.started || race.completed || active_checkpoint_count <= 0 {
		return
	}

	position := car_position()
	target := CHECKPOINTS[race.checkpoint]
	inside_gate := checkpoint_passed(position, target)

	// Require the car to be outside before each gate becomes armed. This prevents
	// repeated or crossing routes from counting two overlapping gates at once.
	if !race.gate_armed {
		if !inside_gate {
			race.gate_armed = true
		}
		return
	}

	if inside_gate {
		race.gate_armed = false
		if race.checkpoint == active_checkpoint_count - 1 {
			race.completed = true
			race.finish_time = race.elapsed
		} else {
			race.checkpoint += 1
		}
	}
}

update_camera :: proc() {
	position := car_position()
	forward := forward_from_yaw(car.yaw)

	desired_position := position - forward * 10.5 + rl.Vector3{0, 6.3, 0}
	desired_target := position + forward * 5.5 + rl.Vector3{0, 0.65, 0}

	if !camera_ready {
		camera.position = desired_position
		camera.target = desired_target
		camera.up = {0, 1, 0}
		camera.fovy = 58
		camera.projection = .PERSPECTIVE
		camera_ready = true
		return
	}

	camera.position = lerp_v3(camera.position, desired_position, 0.12)
	camera.target = lerp_v3(camera.target, desired_target, 0.16)

	target_fov := 58.0 + clamp(car_speed() / BASE_TOP_SPEED, 0.0, 1.0) * 5.0
	if nitro_active() {
		target_fov += 7.0
	}
	camera.fovy = lerp_f32(camera.fovy, target_fov, 0.10)
}
