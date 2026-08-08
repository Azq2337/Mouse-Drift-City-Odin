package main

import rl "vendor:raylib"
import b3 "vendor:box3d"
import "core:math"

car_body_half :: proc(body_style: int) -> rl.Vector3 {
	switch body_style % CAR_BODY_COUNT {
	case 0:  return {0.86, 0.30, 1.42}
	case 1:  return {0.96, 0.30, 1.62}
	case 2:  return {0.82, 0.38, 1.30}
	case 3:  return {0.95, 0.24, 1.52}
	case 4:  return {0.84, 0.24, 1.34}
	case 5:  return {0.92, 0.22, 1.48}
	case 6:  return {0.90, 0.28, 1.70}
	case 7:  return {0.88, 0.36, 1.38}
	case 8:  return {0.74, 0.38, 1.14}
	case 9:  return {0.91, 0.28, 1.58}
	case 10: return {0.88, 0.27, 1.45}
	case 11: return {0.80, 0.27, 1.28}
	case 12: return {0.93, 0.23, 1.50}
	case 13: return {1.00, 0.25, 1.48}
	case 14: return {0.88, 0.32, 1.62}
	case 15: return {0.84, 0.38, 1.28}
	case 16: return {0.98, 0.33, 1.34}
	case 17: return {0.82, 0.20, 1.32}
	case 18: return {0.94, 0.29, 1.76}
	case:    return {0.99, 0.22, 1.56}
	}
}

car_body_name :: proc(body_style: int) -> cstring {
	switch body_style % CAR_BODY_COUNT {
	case 0:  return "STREET COUPE"
	case 1:  return "MUSCLE GT"
	case 2:  return "RALLY HATCH"
	case 3:  return "NEON SUPER"
	case 4:  return "ROADSTER"
	case 5:  return "WEDGE TURBO"
	case 6:  return "LONGNOSE GT"
	case 7:  return "BOX RALLY"
	case 8:  return "KEI SPORT"
	case 9:  return "GRAND TOURER"
	case 10: return "RETRO 80"
	case 11: return "CLUB RACER"
	case 12: return "MIDSHIP"
	case 13: return "WIDE TRACK"
	case 14: return "TOURING SEDAN"
	case 15: return "HOT HATCH"
	case 16: return "GROUP B"
	case 17: return "SPEEDSTER"
	case 18: return "V12 CRUISER"
	case:    return "ARCADE SPEC"
	}
}

car_part_name :: proc(part: int) -> cstring {
	switch part % CAR_PART_COUNT {
	case 0:  return "DUCKTAIL"
	case 1:  return "GT WING"
	case 2:  return "TWIN STRIPE"
	case 3:  return "CENTER STRIPE"
	case 4:  return "SIDE STRIPE"
	case 5:  return "SPLITTER"
	case 6:  return "SIDE SKIRTS"
	case 7:  return "WIDE FENDERS"
	case 8:  return "DIFFUSER"
	case 9:  return "RALLY LAMPS"
	case 10: return "HOOD VENTS"
	case 11: return "HOOD BULGE"
	case 12: return "CANARDS"
	case 13: return "TOW HOOK"
	case 14: return "MIRROR PODS"
	case 15: return "REAR LOUVRE"
	case 16: return "BUMPER BARS"
	case 17: return "NUMBER PLATE"
	case 18: return "MUD FLAPS"
	case:    return "SIDE EXHAUSTS"
	}
}

car_part_enabled :: proc(parts: u32, part: int) -> bool {
	return (parts & (u32(1) << u32(part))) != 0
}

car_part_enabled_count :: proc(parts: u32) -> int {
	count := 0
	for part in 0..<CAR_PART_COUNT {
		if car_part_enabled(parts, part) { count += 1 }
	}
	return count
}

car_color_name :: proc(index: int) -> cstring {
	switch index % CAR_COLOR_COUNT {
	case 0:  return "RED"
	case 1:  return "VERMILION"
	case 2:  return "ORANGE"
	case 3:  return "AMBER"
	case 4:  return "YELLOW LIME"
	case 5:  return "CHARTREUSE"
	case 6:  return "LIME"
	case 7:  return "SPRING GREEN"
	case 8:  return "EMERALD"
	case 9:  return "AQUA GREEN"
	case 10: return "CYAN"
	case 11: return "SKY"
	case 12: return "AZURE"
	case 13: return "COBALT"
	case 14: return "INDIGO"
	case 15: return "VIOLET"
	case 16: return "PURPLE"
	case 17: return "MAGENTA"
	case 18: return "ROSE"
	case:    return "CRIMSON"
	}
}

car_color_value :: proc(index: int) -> rl.Color {
	switch index % CAR_COLOR_COUNT {
	case 0:  return {235, 42, 42, 255}
	case 1:  return {235, 100, 42, 255}
	case 2:  return {235, 158, 42, 255}
	case 3:  return {235, 215, 42, 255}
	case 4:  return {196, 235, 42, 255}
	case 5:  return {138, 235, 42, 255}
	case 6:  return {81, 235, 42, 255}
	case 7:  return {42, 235, 61, 255}
	case 8:  return {42, 235, 119, 255}
	case 9:  return {42, 235, 177, 255}
	case 10: return {42, 235, 235, 255}
	case 11: return {42, 177, 235, 255}
	case 12: return {42, 119, 235, 255}
	case 13: return {42, 61, 235, 255}
	case 14: return {81, 42, 235, 255}
	case 15: return {138, 42, 235, 255}
	case 16: return {196, 42, 235, 255}
	case 17: return {235, 42, 215, 255}
	case 18: return {235, 42, 158, 255}
	case:    return {235, 42, 100, 255}
	}
}

create_car :: proc() -> Car_State {
	body_def := b3.DefaultBodyDef()
	body_def.type = .dynamicBody
	body_def.position = {race_start_position.x, 0.22, race_start_position.z}
	body_def.enableSleep = false
	body_def.enableContactRecycling = false
	body_def.gravityScale = 0.88
	body_def.motionLocks.angularX = true
	body_def.motionLocks.angularY = true
	body_def.motionLocks.angularZ = true

	body_id := b3.CreateBody(world_id, body_def)

	// A compact octagonal chassis is much less likely to catch a ramp lip than the
	// old full-size rectangular visual body. All 20 visual shells share this arcade
	// collision chassis so customization never changes whether a jump is possible.
	w: f32 = 0.72
	l: f32 = 0.90
	h: f32 = CAR_PHYSICS_HALF_HEIGHT
	cut: f32 = 0.20
	footprint := [8]b3.Vec3{
		{-w + cut, 0, -l}, {w - cut, 0, -l},
		{w, 0, -l + cut}, {w, 0, l - cut},
		{w - cut, 0, l}, {-w + cut, 0, l},
		{-w, 0, l - cut}, {-w, 0, -l + cut},
	}
	points: [16]b3.Vec3
	for index in 0..<8 {
		points[index] = {footprint[index].x, -h, footprint[index].z}
		points[index + 8] = {footprint[index].x, h, footprint[index].z}
	}
	hull := b3.CreateHull(&points[0], 16, 16)
	if hull != nil {
		shape_def := b3.DefaultShapeDef()
		shape_def.density = 0.95
		shape_def.baseMaterial.friction = 0.015
		shape_def.baseMaterial.restitution = 0.0
		_ = b3.CreateHullShape(body_id, shape_def, hull)
		b3.DestroyHull(hull)
	} else {
		fallback := b3.MakeBoxHull(w, h, l)
		shape_def := b3.DefaultShapeDef()
		shape_def.density = 0.95
		shape_def.baseMaterial.friction = 0.015
		_ = b3.CreateHullShape(body_id, shape_def, &fallback.base)
	}

	return Car_State{
		body_id = body_id,
		yaw = race_start_yaw,
		nitro_charge = 1.0,
		ignore_mouse_frames = 3,
	}
}

reset_car :: proc(reset_race := true) {
	if b3.Body_IsValid(car.body_id) {
		b3.DestroyBody(car.body_id)
	}
	car = create_car()

	for i in 0..<SMOKE_MAX {
		smoke_particles[i].active = false
	}
	for i in 0..<SKID_MAX {
		skid_segments[i].active = false
	}

	if reset_race {
		race = {}
	}
	camera_ready = false
}

car_physics_position :: proc() -> rl.Vector3 {
	position := b3.Body_GetPosition(car.body_id)
	return {f32(position.x), f32(position.y), f32(position.z)}
}

car_position :: proc() -> rl.Vector3 {
	position := car_physics_position()
	surface_y := road_elevation_at(position.x, position.z) + 0.55
	// The compact physics chassis sits much lower than the visual car. Preserve that
	// offset so the rendered body rides on a ramp instead of sinking into it.
	physics_visual_y := position.y + 0.37
	position.y = max(physics_visual_y, surface_y)
	return position
}

car_velocity :: proc() -> rl.Vector3 {
	velocity := b3.Body_GetLinearVelocity(car.body_id)
	return {velocity.x, velocity.y, velocity.z}
}

car_speed :: proc() -> f32 {
	return horizontal_length(car_velocity())
}

car_forward_speed :: proc() -> f32 {
	velocity := car_velocity()
	forward := forward_from_yaw(car.yaw)
	return velocity.x * forward.x + velocity.z * forward.z
}

STEER_GESTURE_FULL_DELTA :: f32(5.2)
STEER_RESPONSE           :: f32(0.76)
STEER_RETURN             :: f32(0.78)

nitro_charge_ratio :: proc() -> f32 {
	return clamp(car.nitro_charge, 0.0, 1.0)
}

nitro_input_strength :: proc() -> f32 {
	if car.ignore_mouse_frames <= 0 && rl.IsMouseButtonDown(.LEFT) && car.nitro_charge > 0.0001 {
		return 1.0
	}
	return 0.0
}

handbrake_input_strength :: proc() -> f32 {
	return clamp(car.handbrake_time / HANDBRAKE_DURATION, 0.0, 1.0)
}

nitro_active :: proc() -> bool {
	return nitro_input_strength() > 0
}

handbrake_active :: proc() -> bool {
	return handbrake_input_strength() > 0
}

CAR_PHYSICS_HALF_HEIGHT :: f32(0.18)
JUMP_BRIDGE_LIP_ZONE    :: f32(0.55)
JUMP_BRIDGE_CLEARANCE   :: f32(0.035)

apply_jump_bridge_support :: proc(velocity: ^rl.Vector3) {
	if car.jump_launch_cooldown > 0 {
		car.jump_launch_cooldown = max(0.0, car.jump_launch_cooldown - TIME_STEP)
	}

	physics_position := car_physics_position()
	for index in 0..<river_crossing_count {
		crossing := river_crossings[index]
		if crossing.bridge != .JUMP {
			continue
		}

		center := river_crossing_world_center(crossing)
		axis := crossing_road_axis(crossing)
		right := rl.Vector3{-axis.z, 0, axis.x}
		offset := physics_position - center
		along := offset.x * axis.x + offset.z * axis.z
		sideways := offset.x * right.x + offset.z * right.z
		distance := abs_f32(along)

		// The chassis never rolls, so let the helper support a wider lateral band
		// than the visible deck. This makes shallow side entries onto the jump ramp
		// feel forgiving instead of catching on a step.
		if abs_f32(sideways) > ROAD_WIDTH * 0.82 ||
		   distance < JUMP_BRIDGE_HALF_GAP ||
		   distance > JUMP_BRIDGE_HALF_GAP + JUMP_BRIDGE_RAMP_LENGTH {
			continue
		}

		// The driving model intentionally keeps the chassis level for predictable
		// top-down handling. Treat the jump ramp like a simple arcade suspension: the
		// body follows the visible deck height while approaching or landing instead of
		// asking a rotation-locked box to climb a contact manifold.
		t := (JUMP_BRIDGE_HALF_GAP + JUMP_BRIDGE_RAMP_LENGTH - distance) / JUMP_BRIDGE_RAMP_LENGTH
		t = clamp(t, 0.0, 1.0)
		base_y := road_elevation_at(center.x, center.z)
		surface_y := base_y + lerp_f32(JUMP_BRIDGE_BASE_HEIGHT, JUMP_BRIDGE_PEAK_HEIGHT, t)
		desired_body_y := surface_y + CAR_PHYSICS_HALF_HEIGHT + JUMP_BRIDGE_CLEARANCE

		if physics_position.y < desired_body_y && velocity^.y <= 1.0 {
			rotation := b3.Body_GetRotation(car.body_id)
			b3.Body_SetTransform(
				car.body_id,
				{physics_position.x, desired_body_y, physics_position.z},
				rotation,
			)
			physics_position.y = desired_body_y
			if velocity^.y < 0 {
				velocity^.y = 0
			}
		}

		along_speed := velocity^.x * axis.x + velocity^.z * axis.z
		moving_toward_gap := along * along_speed < 0
		if moving_toward_gap &&
		   distance <= JUMP_BRIDGE_HALF_GAP + JUMP_BRIDGE_LIP_ZONE &&
		   car.jump_launch_cooldown <= 0 {
			horizontal_speed := horizontal_length(velocity^)
			launch_speed := 5.4 + clamp(horizontal_speed * 0.10, 0.0, 2.4)
			velocity^.y = max(velocity^.y, launch_speed)
			car.jump_launch_cooldown = 0.72
		}

		return
	}
}

update_mouse_controls :: proc() {
	mouse_delta := ui_mouse_delta()

	if car.ignore_mouse_frames > 0 {
		car.ignore_mouse_frames -= 1
		car.handbrake_time = 0.0
		return
	}

	steer_target := clamp(mouse_delta.x / STEER_GESTURE_FULL_DELTA, -1.0, 1.0)
	if abs_f32(mouse_delta.x) < 0.25 {
		steer_target = 0
	}
	car.steer = lerp_f32(car.steer, steer_target, STEER_RESPONSE)
	if abs_f32(steer_target) < 0.01 {
		car.steer *= STEER_RETURN
	}

	// Mouse controls are intentionally button-only now: automatic throttle,
	// LMB spends the persistent nitro bar, RMB brakes/drifts and reverses.
	if rl.IsMouseButtonDown(.RIGHT) {
		car.handbrake_time = HANDBRAKE_DURATION
	} else {
		car.handbrake_time = 0.0
	}
}

update_car_physics :: proc() {
	update_mouse_controls()

	velocity := car_velocity()
	speed_before_turn := horizontal_length(velocity)

	// Use the current heading to detect whether the car is travelling backward.
	current_forward := forward_from_yaw(car.yaw)
	current_forward_speed := velocity.x * current_forward.x + velocity.z * current_forward.z
	turn_direction: f32 = 1.0
	if current_forward_speed < -0.2 {
		turn_direction = -1.0
	}

	// Speed-sensitive steering: responsive in city corners, calmer at top speed.
	speed_ratio := clamp(speed_before_turn / BASE_TOP_SPEED, 0.0, 1.0)
	steer_authority := lerp_f32(0.35, 1.0, clamp(speed_before_turn / 8.0, 0.0, 1.0))
	turn_rate := lerp_f32(2.35, 1.38, speed_ratio)

	handbrake_strength := handbrake_input_strength()
	// RMB is also the reverse control. Drift steering only exists while the car is
	// actually travelling forward; once speed reaches reverse, RMB is plain reverse.
	drift_strength := handbrake_strength
	if current_forward_speed <= 0.0 {
		drift_strength = 0.0
	}
	if drift_strength > 0 {
		turn_rate *= lerp_f32(1.0, 1.72, drift_strength)
		steer_authority = lerp_f32(
			steer_authority,
			max(steer_authority, 0.72),
			drift_strength,
		)
	}

	car.yaw += car.steer * turn_rate * steer_authority * turn_direction * TIME_STEP

	forward := forward_from_yaw(car.yaw)
	right := right_from_yaw(car.yaw)
	forward_speed := velocity.x * forward.x + velocity.z * forward.z
	lateral_speed := velocity.x * right.x + velocity.z * right.z

	braking := rl.IsMouseButtonDown(.RIGHT)
	nitro_strength := nitro_input_strength()
	if nitro_strength > 0 {
		car.nitro_charge = max(0.0, car.nitro_charge - TIME_STEP / NITRO_FULL_BURN_SECONDS)
	}

	if braking {
		if forward_speed > 0.35 {
			forward_speed = move_towards(forward_speed, 0, BRAKE_DECEL * TIME_STEP)
		} else {
			forward_speed -= REVERSE_ACCEL * TIME_STEP
		}
	} else if forward_speed < -0.35 {
		// Releasing RMB lets automatic throttle pull the car out of reverse first.
		forward_speed = move_towards(forward_speed, 0, BRAKE_DECEL * TIME_STEP)
	} else {
		engine_fade := 1.0 - clamp(abs_f32(forward_speed) / BASE_TOP_SPEED, 0.0, 0.72)
		acceleration := ENGINE_ACCEL * engine_fade + NITRO_ACCEL * nitro_strength
		forward_speed += acceleration * TIME_STEP
	}

	max_speed := lerp_f32(BASE_TOP_SPEED, NITRO_TOP_SPEED, nitro_strength)
	forward_speed = clamp(forward_speed, -REVERSE_TOP_SPEED, max_speed)

	// Re-evaluate after braking because this frame may be the one that crosses
	// through zero into reverse.
	drift_strength = handbrake_strength
	if forward_speed <= 0.0 {
		drift_strength = 0.0
	}
	grip := lerp_f32(BASE_LATERAL_GRIP, DRIFT_LATERAL_GRIP, drift_strength)
	if drift_strength > 0 {
		forward_speed *= 1.0 - 0.38 * drift_strength * TIME_STEP
	}

	lateral_speed *= max(0.0, 1.0 - grip * TIME_STEP)

	velocity.x = forward.x * forward_speed + right.x * lateral_speed
	velocity.z = forward.z * forward_speed + right.z * lateral_speed
	apply_jump_bridge_support(&velocity)
	b3.Body_SetLinearVelocity(car.body_id, {velocity.x, velocity.y, velocity.z})

	update_tire_effects()
}

rear_wheel_positions :: proc() -> (left, right: rl.Vector3) {
	position := car_position()
	left = world_from_local(position, {-0.66, -0.28, 0.92}, car.yaw)
	right = world_from_local(position, {0.66, -0.28, 0.92}, car.yaw)
	return
}

add_skid_segment :: proc(left_a, left_b, right_a, right_b: rl.Vector3) {
	skid_segments[skid_cursor] = {
		active = true,
		left_a = left_a,
		left_b = left_b,
		right_a = right_a,
		right_b = right_b,
	}
	skid_cursor = (skid_cursor + 1) % SKID_MAX
}

spawn_smoke :: proc(position, sideways: rl.Vector3) {
	particle := &smoke_particles[smoke_cursor]
	smoke_cursor = (smoke_cursor + 1) % SMOKE_MAX

	particle.active = true
	particle.position = position + rl.Vector3{0, 0.18, 0}
	particle.velocity = sideways * 0.35 + rl.Vector3{0, 0.45, 0}
	particle.life = 0.75
	particle.max_life = particle.life
	particle.radius = 0.18
}

update_tire_effects :: proc() {
	left, right := rear_wheel_positions()
	velocity := car_velocity()
	forward := forward_from_yaw(car.yaw)
	forward_speed := velocity.x * forward.x + velocity.z * forward.z
	drifting := handbrake_input_strength() > 0.35 && forward_speed > 8.0 && abs_f32(car.steer) > 0.12

	if drifting {
		// Deliberately arcade-generous: the instant the car establishes a real
		// forward drift, the next nitro burst is earned in full.
		car.nitro_charge = 1.0
		if car.has_last_rear {
			add_skid_segment(car.last_rear_left, left, car.last_rear_right, right)
		}
		car.smoke_timer -= TIME_STEP
		if car.smoke_timer <= 0 {
			sideways := right_from_yaw(car.yaw) * car.steer
			spawn_smoke(left, -sideways)
			spawn_smoke(right, sideways)
			car.smoke_timer = 0.055
		}
		car.has_last_rear = true
	} else {
		car.has_last_rear = false
		car.smoke_timer = 0
	}

	car.last_rear_left = left
	car.last_rear_right = right
}

update_smoke :: proc() {
	for i in 0..<SMOKE_MAX {
		particle := &smoke_particles[i]
		if !particle.active {
			continue
		}

		particle.life -= TIME_STEP
		if particle.life <= 0 {
			particle.active = false
			continue
		}

		particle.position += particle.velocity * TIME_STEP
		particle.velocity *= 0.985
		particle.radius += 0.22 * TIME_STEP
	}
}

car_draw_alpha_override: u8 = 255

car_visual_deform_active := false
car_visual_deform_anchor := rl.Vector3{}
car_visual_deform_horizontal: f32 = 1.0
car_visual_deform_vertical: f32 = 1.0

world_visual_deform_active := false
world_visual_deform_anchor := rl.Vector3{}

world_visual_transform_point :: proc(point: rl.Vector3) -> rl.Vector3 {
	if !world_visual_deform_active || !bounce_mode { return point }
	return visual_bounce_transform_point(point, world_visual_deform_anchor)
}

car_visual_transform_point :: proc(point: rl.Vector3) -> rl.Vector3 {
	if !car_visual_deform_active { return point }
	delta := point - car_visual_deform_anchor
	return car_visual_deform_anchor + rl.Vector3{
		delta.x * car_visual_deform_horizontal,
		delta.y * car_visual_deform_vertical,
		delta.z * car_visual_deform_horizontal,
	}
}

car_apply_draw_alpha :: proc(color: rl.Color) -> rl.Color {
	if car_draw_alpha_override >= 255 { return color }
	alpha := (u16(color.a) * u16(car_draw_alpha_override)) / 255
	return {color.r, color.g, color.b, u8(alpha)}
}

draw_oriented_box :: proc(center, half: rl.Vector3, yaw: f32, color: rl.Color) {
	draw_color := car_apply_draw_alpha(color)
	local := [8]rl.Vector3{
		{-half.x, -half.y, -half.z},
		{ half.x, -half.y, -half.z},
		{ half.x,  half.y, -half.z},
		{-half.x,  half.y, -half.z},
		{-half.x, -half.y,  half.z},
		{ half.x, -half.y,  half.z},
		{ half.x,  half.y,  half.z},
		{-half.x,  half.y,  half.z},
	}

	points: [8]rl.Vector3
	for i in 0..<8 {
		point := world_from_local(center, local[i], yaw)
		point = world_visual_transform_point(point)
		points[i] = car_visual_transform_point(point)
	}

	triangles := [12][3]int{
		{0, 2, 1}, {0, 3, 2},
		{4, 5, 6}, {4, 6, 7},
		{0, 4, 7}, {0, 7, 3},
		{1, 2, 6}, {1, 6, 5},
		{3, 7, 6}, {3, 6, 2},
		{0, 1, 5}, {0, 5, 4},
	}

	for triangle in triangles {
		rl.DrawTriangle3D(
			points[triangle[0]],
			points[triangle[1]],
			points[triangle[2]],
			draw_color,
		)
	}

	edges := [12][2]int{
		{0,1}, {1,2}, {2,3}, {3,0},
		{4,5}, {5,6}, {6,7}, {7,4},
		{0,4}, {1,5}, {2,6}, {3,7},
	}
	edge_color := rl.Color{18, 21, 28, draw_color.a}
	for edge in edges {
		rl.DrawLine3D(points[edge[0]], points[edge[1]], edge_color)
	}
}

draw_oriented_wedge :: proc(
	center, half: rl.Vector3,
	yaw, front_top_scale, rear_top_scale: f32,
	color: rl.Color,
) {
	draw_color := car_apply_draw_alpha(color)
	front_top := half.y * front_top_scale
	rear_top := half.y * rear_top_scale
	local := [8]rl.Vector3{
		{-half.x, -half.y, -half.z},
		{ half.x, -half.y, -half.z},
		{ half.x,  front_top, -half.z},
		{-half.x,  front_top, -half.z},
		{-half.x, -half.y,  half.z},
		{ half.x, -half.y,  half.z},
		{ half.x,  rear_top,  half.z},
		{-half.x,  rear_top,  half.z},
	}
	points: [8]rl.Vector3
	for i in 0..<8 {
		points[i] = car_visual_transform_point(world_from_local(center, local[i], yaw))
	}
	triangles := [12][3]int{
		{0, 2, 1}, {0, 3, 2},
		{4, 5, 6}, {4, 6, 7},
		{0, 4, 7}, {0, 7, 3},
		{1, 2, 6}, {1, 6, 5},
		{3, 7, 6}, {3, 6, 2},
		{0, 1, 5}, {0, 5, 4},
	}
	for triangle in triangles {
		rl.DrawTriangle3D(points[triangle[0]], points[triangle[1]], points[triangle[2]], draw_color)
	}
	edge_color := rl.Color{18, 21, 28, draw_color.a}
	edges := [12][2]int{
		{0,1}, {1,2}, {2,3}, {3,0},
		{4,5}, {5,6}, {6,7}, {7,4},
		{0,4}, {1,5}, {2,6}, {3,7},
	}
	for edge in edges {
		rl.DrawLine3D(points[edge[0]], points[edge[1]], edge_color)
	}
}

draw_oriented_ellipsoid :: proc(
	center, radii: rl.Vector3,
	yaw: f32,
	color: rl.Color,
) {
	draw_color := car_apply_draw_alpha(color)
	latitude_steps := 6
	longitude_steps := 12
	for latitude in 0..<latitude_steps {
		theta0 := -rl.PI * 0.5 + rl.PI * f32(latitude) / f32(latitude_steps)
		theta1 := -rl.PI * 0.5 + rl.PI * f32(latitude + 1) / f32(latitude_steps)
		for longitude in 0..<longitude_steps {
			phi0 := rl.PI * 2.0 * f32(longitude) / f32(longitude_steps)
			phi1 := rl.PI * 2.0 * f32(longitude + 1) / f32(longitude_steps)
			p00 := rl.Vector3{math.cos(theta0) * math.cos(phi0) * radii.x, math.sin(theta0) * radii.y, math.cos(theta0) * math.sin(phi0) * radii.z}
			p01 := rl.Vector3{math.cos(theta0) * math.cos(phi1) * radii.x, math.sin(theta0) * radii.y, math.cos(theta0) * math.sin(phi1) * radii.z}
			p10 := rl.Vector3{math.cos(theta1) * math.cos(phi0) * radii.x, math.sin(theta1) * radii.y, math.cos(theta1) * math.sin(phi0) * radii.z}
			p11 := rl.Vector3{math.cos(theta1) * math.cos(phi1) * radii.x, math.sin(theta1) * radii.y, math.cos(theta1) * math.sin(phi1) * radii.z}
			a := car_visual_transform_point(world_from_local(center, p00, yaw))
			b := car_visual_transform_point(world_from_local(center, p01, yaw))
			c := car_visual_transform_point(world_from_local(center, p11, yaw))
			d := car_visual_transform_point(world_from_local(center, p10, yaw))
			draw_quad_double_sided(a, b, c, d, draw_color)
		}
	}
}

draw_streamlined_body_shell :: proc(
	center: rl.Vector3,
	half_width,
	half_height,
	half_length,
	yaw: f32,
	color: rl.Color,
) {
	draw_color := car_apply_draw_alpha(color)
	// Rounded cars should read as cars, not as eggs or bars of soap. Build a
	// low-poly fastback shell from tapered longitudinal stations: broad shoulders,
	// a low roof line, and clearly narrower nose/tail sections.
	STATION_COUNT :: 7
	RING_COUNT    :: 6
	z_factors := [STATION_COUNT]f32{-1.0, -0.82, -0.48, 0.0, 0.50, 0.82, 1.0}
	width_factors := [STATION_COUNT]f32{0.38, 0.76, 0.97, 1.0, 0.96, 0.74, 0.34}
	top_factors := [STATION_COUNT]f32{0.34, 0.76, 1.0, 1.02, 0.94, 0.68, 0.28}
	points: [STATION_COUNT][RING_COUNT]rl.Vector3

	for station in 0..<STATION_COUNT {
		z := z_factors[station] * half_length
		width := width_factors[station] * half_width
		top := top_factors[station] * half_height
		bottom := -half_height * 0.82
		shoulder := half_height * 0.05
		local := [RING_COUNT]rl.Vector3{
			{-width * 0.78, bottom, z},
			{-width, shoulder, z},
			{-width * 0.58, top, z},
			{ width * 0.58, top, z},
			{ width, shoulder, z},
			{ width * 0.78, bottom, z},
		}
		for ring in 0..<RING_COUNT {
			points[station][ring] = car_visual_transform_point(world_from_local(center, local[ring], yaw))
		}
	}

	for station in 0..<(STATION_COUNT - 1) {
		for ring in 0..<RING_COUNT {
			next := (ring + 1) % RING_COUNT
			draw_quad_double_sided(
				points[station][ring],
				points[station + 1][ring],
				points[station + 1][next],
				points[station][next],
				draw_color,
			)
		}
	}

	front_center := car_visual_transform_point(world_from_local(center, {0, -half_height * 0.08, -half_length}, yaw))
	rear_center := car_visual_transform_point(world_from_local(center, {0, -half_height * 0.08, half_length}, yaw))
	for ring in 0..<RING_COUNT {
		next := (ring + 1) % RING_COUNT
		rl.DrawTriangle3D(front_center, points[0][next], points[0][ring], draw_color)
		rl.DrawTriangle3D(rear_center, points[STATION_COUNT - 1][ring], points[STATION_COUNT - 1][next], draw_color)
	}

	edge_color := rl.Color{18, 21, 28, draw_color.a}
	for station in 0..<(STATION_COUNT - 1) {
		for ring in 1..=4 {
			rl.DrawLine3D(points[station][ring], points[station + 1][ring], edge_color)
		}
	}
}

draw_rounded_cabin :: proc(position, offset, radii: rl.Vector3, yaw: f32, body_color: rl.Color) {
	center := world_from_local(position, offset, yaw)
	// Rounded body styles get a genuinely rounded cabin too. The previous roof strip
	// and pillar boxes formed a visible '+' from above and looked like loose blocks.
	draw_oriented_ellipsoid(center, radii, yaw, body_color)
	glass := rl.Color{25, 67, 91, 255}
	glass_center := center + rl.Vector3{0, radii.y * 0.02, -radii.z * 0.03}
	draw_oriented_ellipsoid(
		glass_center,
		{radii.x * 0.86, radii.y * 0.78, radii.z * 0.86},
		yaw,
		glass,
	)
}

draw_car_cabin :: proc(
	position, offset, half: rl.Vector3,
	yaw: f32,
	body_color: rl.Color,
) {
	center := world_from_local(position, offset, yaw)
	draw_oriented_wedge(center, half, yaw, 0.72, 1.0, body_color)
	glass := rl.Color{25, 67, 91, 255}
	front_z := -half.z - 0.012
	rear_z := half.z + 0.012
	draw_oriented_box(
		world_from_local(center, {0, 0.02, front_z}, yaw),
		{half.x * 0.76, half.y * 0.54, 0.022}, yaw, glass,
	)
	draw_oriented_box(
		world_from_local(center, {0, 0.03, rear_z}, yaw),
		{half.x * 0.72, half.y * 0.48, 0.022}, yaw, glass,
	)
	for side in 0..<2 {
		x := -half.x - 0.012
		if side != 0 { x = half.x + 0.012 }
		draw_oriented_box(
			world_from_local(center, {x, 0.02, 0}, yaw),
			{0.022, half.y * 0.48, half.z * 0.54}, yaw, glass,
		)
	}
}

draw_open_cockpit :: proc(position: rl.Vector3, yaw: f32, body_color: rl.Color, long: bool) {
	glass := rl.Color{28, 77, 102, 255}
	wind_z: f32 = -0.18
	seat_z: f32 = 0.28
	if long {
		wind_z = -0.30
		seat_z = 0.36
	}
	draw_oriented_box(world_from_local(position, {0, 0.39, wind_z}, yaw), {0.54, 0.18, 0.025}, yaw, glass)
	for side in 0..<2 {
		x: f32 = -0.30
		if side != 0 { x = 0.30 }
		draw_oriented_box(world_from_local(position, {x, 0.30, seat_z}, yaw), {0.17, 0.22, 0.25}, yaw, {28, 31, 37, 255})
		rl.DrawSphere(car_visual_transform_point(world_from_local(position, {x, 0.56, seat_z + 0.08}, yaw)), 0.12, car_apply_draw_alpha(body_color))
	}
}

draw_skid_marks :: proc() {
	for segment in skid_segments {
		if !segment.active {
			continue
		}
		rl.DrawLine3D(segment.left_a, segment.left_b, {16, 17, 20, 210})
		rl.DrawLine3D(segment.right_a, segment.right_b, {16, 17, 20, 210})
	}
}

draw_smoke :: proc() {
	for particle in smoke_particles {
		if !particle.active {
			continue
		}
		ratio := clamp(particle.life / particle.max_life, 0.0, 1.0)
		alpha := u8(clamp(ratio * 125.0, 0.0, 125.0))
		rl.DrawSphere(particle.position, particle.radius, {190, 195, 205, alpha})
	}
}

draw_car_model :: proc(
	position: rl.Vector3,
	yaw: f32,
	body_style: int,
	color_index: int,
	parts: u32,
	show_nitro: bool,
) {
	previous_deform_active := car_visual_deform_active
	previous_deform_anchor := car_visual_deform_anchor
	previous_deform_horizontal := car_visual_deform_horizontal
	previous_deform_vertical := car_visual_deform_vertical
	if bounce_mode {
		car_visual_deform_active = true
		// Anchor close to the tyres so squash/stretch reads as a planted landing,
		// not a car scaling around its roof.
		car_visual_deform_anchor = position + rl.Vector3{0, -0.30, 0}
		car_visual_deform_horizontal = visual_bounce_horizontal_scale()
		car_visual_deform_vertical = visual_bounce_vertical_scale()
	}
	defer {
		car_visual_deform_active = previous_deform_active
		car_visual_deform_anchor = previous_deform_anchor
		car_visual_deform_horizontal = previous_deform_horizontal
		car_visual_deform_vertical = previous_deform_vertical
	}

	body_color := car_color_value(color_index)
	body_half := car_body_half(body_style)
	style := body_style % CAR_BODY_COUNT

	switch style {
	case 0:
		// Restore the original simple blocky starter-car character. The rounder
		// silhouettes remain available on other body selections.
		draw_oriented_box(position, {0.84, 0.28, 1.38}, yaw, body_color)
		draw_oriented_wedge(world_from_local(position, {0, 0.10, -0.84}, yaw), {0.70, 0.14, 0.54}, yaw, 0.42, 1.0, body_color)
		draw_car_cabin(position, {0, 0.40, 0.30}, {0.56, 0.24, 0.62}, yaw, body_color)
	case 1:
		draw_oriented_box(position, {0.88, 0.27, 1.52}, yaw, body_color)
		draw_oriented_wedge(world_from_local(position, {0, 0.12, -0.82}, yaw), {0.78, 0.16, 0.64}, yaw, 0.34, 1.0, body_color)
		draw_car_cabin(position, {0, 0.34, 0.47}, {0.58, 0.20, 0.60}, yaw, body_color)
	case 2:
		draw_oriented_box(position, {0.72, 0.33, 1.24}, yaw, body_color)
		draw_car_cabin(position, {0, 0.48, 0.22}, {0.58, 0.30, 0.65}, yaw, body_color)
		draw_oriented_box(world_from_local(position, {0, 0.18, 1.20}, yaw), {0.62, 0.15, 0.10}, yaw, body_color)
	case 3:
		// Low rounded mid-engine supercar, visually far from the boxy rally shells.
		draw_streamlined_body_shell(position, 0.94, 0.24, 1.52, yaw, body_color)
		draw_oriented_wedge(world_from_local(position, {0, 0.05, -1.16}, yaw), {0.72, 0.09, 0.34}, yaw, 0.12, 0.58, body_color)
		draw_rounded_cabin(position, {0, 0.27, 0.30}, {0.54, 0.22, 0.58}, yaw, body_color)
		for side in 0..<2 {
			x: f32 = -0.84
			if side != 0 { x = 0.84 }
			draw_oriented_box(world_from_local(position, {x, -0.02, 0.25}, yaw), {0.10, 0.13, 0.72}, yaw, body_color)
		}
	case 4:
		draw_oriented_wedge(position, {0.76, 0.22, 1.31}, yaw, 0.32, 1.0, body_color)
		draw_open_cockpit(position, yaw, body_color, false)
	case 5:
		draw_oriented_wedge(position, {0.86, 0.20, 1.44}, yaw, 0.05, 1.0, body_color)
		draw_oriented_wedge(world_from_local(position, {0, 0.18, -0.35}, yaw), {0.70, 0.14, 0.78}, yaw, 0.02, 0.72, body_color)
		draw_car_cabin(position, {0, 0.28, 0.38}, {0.48, 0.15, 0.48}, yaw, body_color)
	case 6:
		draw_oriented_wedge(position, {0.82, 0.26, 1.66}, yaw, 0.30, 1.0, body_color)
		draw_oriented_box(world_from_local(position, {0, 0.14, -0.88}, yaw), {0.70, 0.13, 0.70}, yaw, body_color)
		draw_car_cabin(position, {0, 0.34, 0.56}, {0.54, 0.20, 0.57}, yaw, body_color)
	case 7:
		draw_oriented_box(position, {0.80, 0.32, 1.31}, yaw, body_color)
		draw_oriented_box(world_from_local(position, {0, 0.25, -1.17}, yaw), {0.68, 0.16, 0.18}, yaw, body_color)
		draw_car_cabin(position, {0, 0.51, 0.16}, {0.59, 0.31, 0.66}, yaw, body_color)
	case 8:
		// Tiny round city car / kei bubble.
		draw_streamlined_body_shell(position + rl.Vector3{0, 0.08, 0}, 0.70, 0.34, 1.10, yaw, body_color)
		draw_rounded_cabin(position, {0, 0.48, 0.12}, {0.54, 0.38, 0.62}, yaw, body_color)
		draw_oriented_box(world_from_local(position, {0, 0.06, -1.08}, yaw), {0.46, 0.07, 0.06}, yaw, body_color)
	case 9:
		draw_oriented_wedge(position, {0.83, 0.25, 1.54}, yaw, 0.46, 1.0, body_color)
		draw_car_cabin(position, {0, 0.36, 0.28}, {0.57, 0.22, 0.67}, yaw, body_color)
		draw_oriented_box(world_from_local(position, {0, 0.09, -1.42}, yaw), {0.62, 0.08, 0.14}, yaw, body_color)
	case 10:
		draw_oriented_wedge(position, {0.81, 0.25, 1.40}, yaw, 0.14, 1.0, body_color)
		draw_car_cabin(position, {0, 0.36, 0.30}, {0.54, 0.21, 0.57}, yaw, body_color)
		draw_oriented_box(world_from_local(position, {0, 0.17, -1.23}, yaw), {0.58, 0.12, 0.18}, yaw, body_color)
	case 11:
		draw_oriented_wedge(position, {0.72, 0.24, 1.23}, yaw, 0.38, 1.0, body_color)
		draw_car_cabin(position, {0, 0.34, 0.19}, {0.50, 0.20, 0.55}, yaw, body_color)
		draw_oriented_box(world_from_local(position, {0, -0.05, -1.24}, yaw), {0.64, 0.08, 0.11}, yaw, {24, 27, 32, 255})
	case 12:
		draw_streamlined_body_shell(position, 0.90, 0.23, 1.48, yaw, body_color)
		draw_rounded_cabin(position, {0, 0.27, -0.05}, {0.55, 0.21, 0.54}, yaw, body_color)
		draw_oriented_box(world_from_local(position, {0, 0.08, 1.19}, yaw), {0.72, 0.09, 0.22}, yaw, body_color)
	case 13:
		draw_oriented_wedge(position, {0.91, 0.22, 1.43}, yaw, 0.32, 1.0, body_color)
		draw_car_cabin(position, {0, 0.31, 0.18}, {0.55, 0.17, 0.57}, yaw, body_color)
		for side in 0..<2 {
			x: f32 = -0.91
			if side != 0 { x = 0.91 }
			draw_oriented_box(world_from_local(position, {x, -0.02, -0.62}, yaw), {0.09, 0.17, 0.38}, yaw, body_color)
			draw_oriented_box(world_from_local(position, {x, -0.02, 0.68}, yaw), {0.09, 0.17, 0.38}, yaw, body_color)
		}
	case 14:
		draw_oriented_box(position, {0.81, 0.29, 1.56}, yaw, body_color)
		draw_oriented_wedge(world_from_local(position, {0, 0.12, -0.88}, yaw), {0.70, 0.14, 0.58}, yaw, 0.40, 1.0, body_color)
		draw_car_cabin(position, {0, 0.46, 0.23}, {0.58, 0.27, 0.76}, yaw, body_color)
	case 15:
		draw_streamlined_body_shell(position + rl.Vector3{0, 0.04, 0}, 0.78, 0.31, 1.26, yaw, body_color)
		draw_rounded_cabin(position, {0, 0.46, 0.24}, {0.59, 0.34, 0.70}, yaw, body_color)
		draw_oriented_wedge(world_from_local(position, {0, 0.08, -1.14}, yaw), {0.64, 0.10, 0.17}, yaw, 0.18, 0.84, body_color)
	case 16:
		draw_oriented_box(position, {0.86, 0.29, 1.28}, yaw, body_color)
		draw_car_cabin(position, {0, 0.45, 0.08}, {0.58, 0.27, 0.62}, yaw, body_color)
		for side in 0..<2 {
			x: f32 = -0.91
			if side != 0 { x = 0.91 }
			draw_oriented_box(world_from_local(position, {x, 0.02, -0.66}, yaw), {0.10, 0.20, 0.38}, yaw, body_color)
			draw_oriented_box(world_from_local(position, {x, 0.02, 0.65}, yaw), {0.10, 0.20, 0.38}, yaw, body_color)
		}
	case 17:
		draw_oriented_wedge(position, {0.74, 0.18, 1.28}, yaw, 0.24, 1.0, body_color)
		draw_open_cockpit(position, yaw, body_color, true)
		draw_oriented_box(world_from_local(position, {0, 0.04, -1.18}, yaw), {0.58, 0.06, 0.12}, yaw, body_color)
	case 18:
		draw_streamlined_body_shell(position, 0.88, 0.27, 1.75, yaw, body_color)
		draw_oriented_wedge(world_from_local(position, {0, 0.08, -1.05}, yaw), {0.72, 0.12, 0.66}, yaw, 0.22, 0.80, body_color)
		draw_rounded_cabin(position, {0, 0.35, 0.58}, {0.58, 0.25, 0.64}, yaw, body_color)
	case:
		draw_oriented_wedge(position, {0.90, 0.19, 1.50}, yaw, 0.04, 1.0, body_color)
		draw_oriented_wedge(world_from_local(position, {0, 0.18, -0.62}, yaw), {0.72, 0.13, 0.72}, yaw, 0.02, 0.78, body_color)
		draw_car_cabin(position, {0, 0.27, 0.30}, {0.48, 0.14, 0.48}, yaw, body_color)
		for side in 0..<2 {
			x: f32 = -0.91
			if side != 0 { x = 0.91 }
			draw_oriented_wedge(world_from_local(position, {x, -0.02, 0.14}, yaw), {0.08, 0.12, 0.78}, yaw, 0.25, 1.0, body_color)
		}
	}

	wheel_color := rl.Color{18, 19, 23, 255}
	wheel_x := body_half.x - 0.11
	wheel_front := -body_half.z * 0.62
	wheel_rear := body_half.z * 0.62
	for side in 0..<2 {
		x := -wheel_x
		if side != 0 { x = wheel_x }
		for axle in 0..<2 {
			z := wheel_front
			if axle != 0 { z = wheel_rear }
			draw_oriented_box(world_from_local(position, {x, -0.19, z}, yaw), {0.12, 0.20, 0.31}, yaw, wheel_color)
		}
	}

	light_x := min(body_half.x * 0.52, 0.48)
	for side in 0..<2 {
		x := -light_x
		if side != 0 { x = light_x }
		draw_oriented_box(world_from_local(position, {x, 0.02, -body_half.z + 0.02}, yaw), {0.16, 0.08, 0.04}, yaw, {255, 238, 170, 255})
		draw_oriented_box(world_from_local(position, {x, 0.02, body_half.z - 0.02}, yaw), {0.16, 0.08, 0.04}, yaw, {255, 55, 70, 255})
	}

	dark := rl.Color{22, 24, 30, 255}
	stripe := rl.Color{238, 241, 245, 255}
	for part in 0..<CAR_PART_COUNT {
		if !car_part_enabled(parts, part) { continue }
		switch part {
		case 0: // ducktail
			draw_oriented_wedge(world_from_local(position, {0, 0.34, body_half.z - 0.14}, yaw), {body_half.x * 0.72, 0.07, 0.18}, yaw, 0.30, 1.0, body_color)
		case 1: // GT wing
			wing_z := body_half.z - 0.15
			draw_oriented_box(world_from_local(position, {-body_half.x * 0.60, 0.43, wing_z}, yaw), {0.055, 0.25, 0.055}, yaw, dark)
			draw_oriented_box(world_from_local(position, {body_half.x * 0.60, 0.43, wing_z}, yaw), {0.055, 0.25, 0.055}, yaw, dark)
			draw_oriented_box(world_from_local(position, {0, 0.66, wing_z}, yaw), {body_half.x * 0.84, 0.055, 0.20}, yaw, dark)
		case 2: // twin stripe
			for side in 0..<2 {
				x: f32 = -0.17
				if side != 0 { x = 0.17 }
				draw_oriented_box(world_from_local(position, {x, body_half.y + 0.035, 0}, yaw), {0.07, 0.032, body_half.z * 0.90}, yaw, stripe)
			}
		case 3: // center stripe
			draw_oriented_box(world_from_local(position, {0, body_half.y + 0.035, 0}, yaw), {0.11, 0.032, body_half.z * 0.92}, yaw, stripe)
		case 4: // side stripe
			for side in 0..<2 {
				x := -body_half.x - 0.018
				if side != 0 { x = body_half.x + 0.018 }
				draw_oriented_box(world_from_local(position, {x, 0.02, 0}, yaw), {0.025, 0.08, body_half.z * 0.78}, yaw, stripe)
			}
		case 5: // splitter
			draw_oriented_box(world_from_local(position, {0, -0.13, -body_half.z - 0.09}, yaw), {body_half.x * 0.90, 0.06, 0.16}, yaw, dark)
		case 6: // skirts
			for side in 0..<2 {
				x := -body_half.x - 0.04
				if side != 0 { x = body_half.x + 0.04 }
				draw_oriented_box(world_from_local(position, {x, -0.13, 0.08}, yaw), {0.055, 0.07, body_half.z * 0.78}, yaw, dark)
			}
		case 7: // wide fenders
			for side in 0..<2 {
				x := -body_half.x - 0.055
				if side != 0 { x = body_half.x + 0.055 }
				for axle in 0..<2 {
					z := wheel_front
					if axle != 0 { z = wheel_rear }
					draw_oriented_box(world_from_local(position, {x, 0.02, z}, yaw), {0.07, 0.14, 0.38}, yaw, body_color)
				}
			}
		case 8: // diffuser
			for fin in 0..<3 {
				x := f32(fin - 1) * body_half.x * 0.50
				draw_oriented_wedge(world_from_local(position, {x, -0.12, body_half.z + 0.08}, yaw), {0.10, 0.09, 0.18}, yaw, 1.0, 0.08, dark)
			}
		case 9: // rally lamps
			for lamp in 0..<4 {
				x := (f32(lamp) - 1.5) * 0.25
				rl.DrawSphere(car_visual_transform_point(world_from_local(position, {x, 0.12, -body_half.z - 0.07}, yaw)), 0.095, car_apply_draw_alpha({255, 241, 180, 255}))
			}
		case 10: // hood vents
			for side in 0..<2 {
				x: f32 = -0.22
				if side != 0 { x = 0.22 }
				draw_oriented_box(world_from_local(position, {x, body_half.y + 0.045, -body_half.z * 0.48}, yaw), {0.10, 0.025, 0.24}, yaw, dark)
			}
		case 11: // hood bulge
			draw_oriented_wedge(world_from_local(position, {0, body_half.y + 0.08, -body_half.z * 0.42}, yaw), {0.30, 0.08, 0.42}, yaw, 0.22, 1.0, body_color)
		case 12: // canards
			for side in 0..<2 {
				x := -body_half.x * 0.84
				if side != 0 { x = body_half.x * 0.84 }
				draw_oriented_box(world_from_local(position, {x, -0.04, -body_half.z - 0.03}, yaw), {0.18, 0.035, 0.22}, yaw, dark)
			}
		case 13: // tow hook
			rl.DrawSphere(car_visual_transform_point(world_from_local(position, {0.0, -0.10, -body_half.z - 0.12}, yaw)), 0.075, car_apply_draw_alpha({235, 55, 55, 255}))
		case 14: // mirrors
			for side in 0..<2 {
				x := -body_half.x - 0.13
				if side != 0 { x = body_half.x + 0.13 }
				rl.DrawSphere(car_visual_transform_point(world_from_local(position, {x, 0.36, -0.05}, yaw)), 0.10, car_apply_draw_alpha(body_color))
			}
		case 15: // rear louvre
			for slat in 0..<4 {
				z := body_half.z * 0.34 + f32(slat) * 0.12
				draw_oriented_box(world_from_local(position, {0, 0.40, z}, yaw), {body_half.x * 0.50, 0.025, 0.025}, yaw, dark)
			}
		case 16: // bumper bars
			draw_oriented_box(world_from_local(position, {0, 0.01, -body_half.z - 0.10}, yaw), {body_half.x * 0.72, 0.055, 0.055}, yaw, dark)
			draw_oriented_box(world_from_local(position, {0, 0.01, body_half.z + 0.10}, yaw), {body_half.x * 0.72, 0.055, 0.055}, yaw, dark)
		case 17: // plate
			draw_oriented_box(world_from_local(position, {0, -0.01, -body_half.z - 0.045}, yaw), {0.25, 0.09, 0.022}, yaw, {232, 235, 238, 255})
		case 18: // mud flaps
			for side in 0..<2 {
				x := -wheel_x
				if side != 0 { x = wheel_x }
				draw_oriented_box(world_from_local(position, {x, -0.28, wheel_rear + 0.28}, yaw), {0.13, 0.18, 0.035}, yaw, dark)
			}
		case 19: // side exhausts
			for side in 0..<2 {
				x := -body_half.x - 0.08
				if side != 0 { x = body_half.x + 0.08 }
				draw_oriented_box(world_from_local(position, {x, -0.10, body_half.z * 0.50}, yaw), {0.08, 0.07, 0.32}, yaw, {112, 116, 121, 255})
			}
		}
	}

	if show_nitro {
		forward := forward_from_yaw(yaw)
		for side in 0..<2 {
			x: f32 = -0.34
			if side != 0 { x = 0.34 }
			exhaust := car_visual_transform_point(world_from_local(position, {x, -0.02, body_half.z + 0.08}, yaw))
			rl.DrawLine3D(exhaust, exhaust - forward * 2.0, {80, 210, 255, 255})
			rl.DrawSphere(exhaust - forward * 0.55, 0.12, car_apply_draw_alpha(rl.WHITE))
		}
	}
}

draw_car :: proc() {
	position := car_position()
	position.y += visual_bounce_y(0.34)
	alpha: u8 = 255
	if car.recovery_blink_time > 0 {
		blink_step := int(car.recovery_blink_time * 10.0)
		if blink_step % 2 == 0 { alpha = 128 }
	}
	previous_alpha := car_draw_alpha_override
	car_draw_alpha_override = alpha
	draw_car_model(
		position,
		car.yaw,
		selected_car_body,
		selected_car_color,
		selected_car_parts,
		nitro_active(),
	)
	car_draw_alpha_override = previous_alpha
}
