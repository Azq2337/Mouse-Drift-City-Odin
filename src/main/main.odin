package main

import rl "vendor:raylib"
import b3 "vendor:box3d"

ui_scale_value :: proc() -> f32 {
	switch ui_scale_index {
	case 1: return 1.5
	case 2: return 2.0
	case:   return 1.0
	}
}

ui_scale_label :: proc() -> cstring {
	switch ui_scale_index {
	case 1: return "1.5X"
	case 2: return "2X"
	case:   return "1X"
	}
}

bounce_mode_label :: proc() -> cstring {
	if bounce_mode { return "BOUNCE  ON" }
	return "BOUNCE  OFF"
}

ui_mouse_position :: proc() -> rl.Vector2 {
	mouse := rl.GetMousePosition()
	screen_width := f32(rl.GetScreenWidth())
	screen_height := f32(rl.GetScreenHeight())
	if screen_width <= 0.0 || screen_height <= 0.0 { return mouse }
	return {
		mouse.x * f32(WINDOW_WIDTH) / screen_width,
		mouse.y * f32(WINDOW_HEIGHT) / screen_height,
	}
}

ui_mouse_delta :: proc() -> rl.Vector2 {
	delta := rl.GetMouseDelta()
	scale := ui_scale_value()
	return delta * (1.0 / scale)
}

ui_set_mouse_position :: proc(x, y: i32) {
	scale := ui_scale_value()
	rl.SetMousePosition(i32(f32(x) * scale), i32(f32(y) * scale))
}

apply_ui_scale :: proc() {
	scale := ui_scale_value()
	rl.SetWindowSize(
		i32(f32(WINDOW_WIDTH) * scale),
		i32(f32(WINDOW_HEIGHT) * scale),
	)
}

cycle_ui_scale :: proc() {
	ui_scale_index = (ui_scale_index + 1) % 3
	apply_ui_scale()
}

create_world_for_current_map :: proc() {
	if b3.World_IsValid(world_id) {
		b3.DestroyWorld(world_id)
	}
	world_def := b3.DefaultWorldDef()
	world_def.gravity = {0, -16.0, 0}
	world_id = b3.CreateWorld(world_def)
	generate_city()
	car = create_car()
	camera_ready = false
}

regenerate_route_preview :: proc() {
	active_checkpoint_count = selected_gate_count + 1
	clamp_selected_route_length()
	generate_route()
	map_preview_ready = true
}

regenerate_map_preview :: proc() {
	generate_map_layout()
	create_world_for_current_map()
	regenerate_route_preview()
	race = {}
	paused = false
	finish_cursor_released = false
}

init_game :: proc() {
	rl.SetConfigFlags({.VSYNC_HINT})
	rl.InitWindow(WINDOW_WIDTH, WINDOW_HEIGHT, "Mouse Drift City - Odin Prototype")
	rl.SetTargetFPS(FRAMERATE)
	rl.SetExitKey(.KEY_NULL)
	rl.EnableCursor()

	menu_car_target = rl.LoadRenderTexture(MENU_CAR_RT_WIDTH, MENU_CAR_RT_HEIGHT)
	menu_car_target_ready = rl.IsRenderTextureValid(menu_car_target)
	frame_target = rl.LoadRenderTexture(WINDOW_WIDTH, WINDOW_HEIGHT)
	frame_target_ready = rl.IsRenderTextureValid(frame_target)
	// Keep the default SKY starter body, but give every fresh launch its own
	// small random set of visible parts so the garage never opens on a bare car.
	randomize_car_parts(2, 6)
	generate_map_layout()
	create_world_for_current_map()
	regenerate_route_preview()
	update_camera()
}

shutdown_game :: proc() {
	if frame_target_ready {
		rl.UnloadRenderTexture(frame_target)
	}
	if menu_car_target_ready {
		rl.UnloadRenderTexture(menu_car_target)
	}
	if b3.World_IsValid(world_id) {
		b3.DestroyWorld(world_id)
	}
	rl.CloseWindow()
}

adjust_selected_gate_count :: proc(delta: int) {
	old_gate_count := selected_gate_count
	new_gate_count := clamp(selected_gate_count + delta, MIN_GATE_COUNT, MAX_GATE_COUNT)
	if new_gate_count == old_gate_count {
		return
	}

	// Preserve the current distance-per-gate feel when the player changes gate count.
	// Route distances must still land on the 24 m road grid, so snap after scaling.
	scaled_length := (selected_route_length * new_gate_count + old_gate_count / 2) / old_gate_count
	selected_gate_count = new_gate_count
	selected_route_length = snap_route_length_to_grid(scaled_length)
	clamp_selected_route_length()
	regenerate_route_preview()
}

adjust_selected_route_length :: proc(delta: int) {
	selected_route_length += delta * ROUTE_LENGTH_STEP
	clamp_selected_route_length()
	regenerate_route_preview()
}

cycle_car_body :: proc(delta: int) {
	selected_car_body = (selected_car_body + delta + CAR_BODY_COUNT) % CAR_BODY_COUNT
}

cycle_car_color :: proc(delta: int) {
	selected_car_color = (selected_car_color + delta + CAR_COLOR_COUNT) % CAR_COLOR_COUNT
}

toggle_car_part :: proc(part: int) {
	if part < 0 || part >= CAR_PART_COUNT { return }
	selected_car_parts ~= u32(1) << u32(part)
}

clear_car_parts :: proc() {
	selected_car_parts = 0
}

enable_all_car_parts :: proc() {
	selected_car_parts = (u32(1) << u32(CAR_PART_COUNT)) - 1
}

randomize_car_parts :: proc(minimum_parts, maximum_parts: int) {
	minimum := clamp(minimum_parts, 0, CAR_PART_COUNT)
	maximum := clamp(maximum_parts, minimum, CAR_PART_COUNT)
	selected_car_parts = 0
	target_parts := int(rl.GetRandomValue(i32(minimum), i32(maximum)))
	for car_part_enabled_count(selected_car_parts) < target_parts {
		part := int(rl.GetRandomValue(0, CAR_PART_COUNT - 1))
		selected_car_parts |= u32(1) << u32(part)
	}
}

randomize_car :: proc() {
	selected_car_body = int(rl.GetRandomValue(0, CAR_BODY_COUNT - 1))
	selected_car_color = int(rl.GetRandomValue(0, CAR_COLOR_COUNT - 1))
	randomize_car_parts(0, CAR_PART_COUNT)
}

handle_parts_menu_click :: proc(mouse: rl.Vector2) {
	for part in 0..<CAR_PART_COUNT {
		if point_in_rectangle(mouse, menu_part_toggle_rect(part)) {
			toggle_car_part(part)
			return
		}
	}
	if point_in_rectangle(mouse, menu_parts_clear_rect()) { clear_car_parts(); return }
	if point_in_rectangle(mouse, menu_parts_all_rect()) { enable_all_car_parts(); return }
	if point_in_rectangle(mouse, menu_parts_done_rect()) { garage_parts_open = false; return }
}

handle_main_menu_click :: proc() {
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	mouse := ui_mouse_position()

	if garage_parts_open {
		handle_parts_menu_click(mouse)
		return
	}

	if point_in_rectangle(mouse, menu_body_left_rect()) { cycle_car_body(-1); return }
	if point_in_rectangle(mouse, menu_body_right_rect()) { cycle_car_body(1); return }
	if point_in_rectangle(mouse, menu_color_left_rect()) { cycle_car_color(-1); return }
	if point_in_rectangle(mouse, menu_color_right_rect()) { cycle_car_color(1); return }
	if point_in_rectangle(mouse, menu_parts_rect()) { garage_parts_open = true; return }
	if point_in_rectangle(mouse, menu_car_random_rect()) { randomize_car(); return }

	if point_in_rectangle(mouse, menu_gate_minus_rect()) { adjust_selected_gate_count(-1); return }
	if point_in_rectangle(mouse, menu_gate_plus_rect()) { adjust_selected_gate_count(1); return }
	if point_in_rectangle(mouse, menu_length_minus_rect()) { adjust_selected_route_length(-1); return }
	if point_in_rectangle(mouse, menu_length_plus_rect()) { adjust_selected_route_length(1); return }
	if point_in_rectangle(mouse, menu_regen_rect()) { regenerate_map_preview(); return }
	if point_in_rectangle(mouse, menu_bounce_rect()) { bounce_mode = !bounce_mode; return }
	if point_in_rectangle(mouse, menu_scale_rect()) { cycle_ui_scale(); return }
	if point_in_rectangle(mouse, menu_start_rect()) { start_selected_race(); return }
}

start_selected_race :: proc() {
	garage_parts_open = false
	active_checkpoint_count = selected_gate_count + 1
	reset_car(true)
	reset_destructible_props()
	race.started = true
	race.intro_visible = true
	paused = false
	setup_active = false
	finish_cursor_released = false
	rl.DisableCursor()
	car.ignore_mouse_frames = 3
}

pause_game :: proc() {
	if setup_active || paused || race.completed { return }
	paused = true
	rl.EnableCursor()
}

resume_game :: proc() {
	if !paused { return }
	paused = false
	rl.DisableCursor()
	car.ignore_mouse_frames = 3
}

restart_race :: proc() {
	start_selected_race()
}

recover_car :: proc() {
	if !b3.Body_IsValid(car.body_id) { return }

	position := race_start_position
	yaw := race_start_yaw
	if race.checkpoint > 0 {
		last_gate := CHECKPOINTS[race.checkpoint - 1]
		position = last_gate.position
		yaw = last_gate.next_yaw
	}

	b3.Body_SetTransform(
		car.body_id,
		{position.x, CAR_PHYSICS_HALF_HEIGHT + 0.04, position.z},
		b3.Quat_identity,
	)
	b3.Body_SetLinearVelocity(car.body_id, {0, 0, 0})
	b3.Body_SetAngularVelocity(car.body_id, {0, 0, 0})
	car.yaw = yaw
	car.steer = 0
	car.handbrake_time = 0
	car.recovery_blink_time = RECOVER_BLINK_DURATION
	car.jump_launch_cooldown = 0
	car.water_recovery_time = 0
	car.ignore_mouse_frames = 3
	car.has_last_rear = false

	for i in 0..<SMOKE_MAX { smoke_particles[i].active = false }
	for i in 0..<SKID_MAX { skid_segments[i].active = false }

	// The target checkpoint itself is unchanged. Recover only repositions the car;
	// it never rewinds race progress or elapsed time.
	race.gate_armed = true
	camera_ready = false
	resume_game()
}

car_whole_body_in_water :: proc() -> bool {
	if !b3.Body_IsValid(car.body_id) { return false }
	position := car_physics_position()

	// Crossing above the river is safe. Only a car that has fallen back down onto
	// the flat world floor can be considered submerged.
	if position.y > CAR_PHYSICS_HALF_HEIGHT + 0.34 { return false }
	if point_on_bridge_drive_surface(position) { return false }

	// Test almost the complete physics footprint, not just the car centre. A nose
	// or one wheel touching water is fine; all four corners must be in water.
	local_samples := [4]rl.Vector3{
		{-0.70, 0, -0.88},
		{ 0.70, 0, -0.88},
		{ 0.70, 0,  0.88},
		{-0.70, 0,  0.88},
	}
	for sample in local_samples {
		world := world_from_local({position.x, 0, position.z}, sample, car.yaw)
		if !point_inside_world_water(world.x, world.z) {
			return false
		}
	}
	return true
}

update_water_recovery :: proc() {
	if car_whole_body_in_water() {
		car.water_recovery_time += TIME_STEP
	} else {
		car.water_recovery_time = 0
	}

	// A few frames of confirmation prevents a single edge-contact frame from
	// recovering the car. This is a fall-in-water rule, not a touch-water rule.
	if car.water_recovery_time >= 0.16 {
		recover_car()
	}
}

return_to_main_menu :: proc() {
	garage_parts_open = false
	setup_active = true
	paused = false
	race = {}
	finish_cursor_released = false
	rl.EnableCursor()
	reset_car(false)
}

handle_pause_click :: proc() {
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	mouse := ui_mouse_position()
	if point_in_rectangle(mouse, pause_continue_button_rect()) {
		resume_game()
	} else if point_in_rectangle(mouse, pause_recover_button_rect()) {
		recover_car()
	} else if point_in_rectangle(mouse, pause_restart_button_rect()) {
		restart_race()
	} else if point_in_rectangle(mouse, pause_main_menu_button_rect()) {
		return_to_main_menu()
	}
}

handle_finish_click :: proc() {
	if !rl.IsMouseButtonPressed(.LEFT) { return }
	mouse := ui_mouse_position()
	if point_in_rectangle(mouse, finish_restart_button_rect()) {
		restart_race()
	} else if point_in_rectangle(mouse, finish_main_menu_button_rect()) {
		return_to_main_menu()
	}
}

update_game :: proc() {
	update_visual_bounce()
	if setup_active {
		menu_car_rotation += TIME_STEP * 0.72
		handle_main_menu_click()
		return
	}

	if rl.IsMouseButtonPressed(.MIDDLE) {
		if paused { resume_game() } else if !race.completed { pause_game() }
		return
	}

	if !rl.IsWindowFocused() && !paused && !race.completed {
		pause_game()
	}
	if paused {
		handle_pause_click()
		return
	}

	if race.completed {
		if !finish_cursor_released {
			rl.EnableCursor()
			ui_set_mouse_position(32, 32)
			finish_cursor_released = true
		}
		handle_finish_click()
		return
	}

	if car.recovery_blink_time > 0 {
		car.recovery_blink_time = max(0.0, car.recovery_blink_time - TIME_STEP)
	}
	update_destructible_props()
	update_car_physics()
	b3.World_Step(world_id, TIME_STEP, SUB_STEPS)
	update_water_recovery()
	update_smoke()
	update_race()
	update_camera()

	position := car_position()
	physics_position := car_physics_position()
	if physics_position.y < -4 ||
	   position.x < CITY_MIN_X - 20 || position.x > CITY_MAX_X + 20 ||
	   position.z < CITY_MIN_Z - 20 || position.z > CITY_MAX_Z + 20 {
		reset_car(false)
	}
}

draw_virtual_game :: proc() {
	rl.ClearBackground({6, 10, 24, 255})

	if setup_active {
		draw_main_menu()
		return
	}

	draw_night_sky_background()
	rl.BeginMode3D(camera)
	{
		defer rl.EndMode3D()
		draw_city()
		draw_skid_marks()
		draw_checkpoint()
		draw_car()
		draw_smoke()
	}

	draw_hud()
	if paused {
		draw_pause_overlay()
	} else if race.completed {
		draw_finish_overlay()
	}
}

draw_game :: proc() {
	// The game always renders at its 540x960 logical resolution. The window scale
	// only enlarges that complete frame, keeping every menu coordinate, HUD element,
	// 3D view and mouse hit-box in sync on high-DPI displays.
	if setup_active {
		render_menu_car_preview_texture()
	}

	if frame_target_ready {
		rl.BeginTextureMode(frame_target)
		draw_virtual_game()
		rl.EndTextureMode()

		rl.BeginDrawing()
		defer rl.EndDrawing()
		rl.ClearBackground({2, 4, 8, 255})
		source := rl.Rectangle{0, 0, f32(WINDOW_WIDTH), -f32(WINDOW_HEIGHT)}
		destination := rl.Rectangle{0, 0, f32(rl.GetScreenWidth()), f32(rl.GetScreenHeight())}
		rl.DrawTexturePro(frame_target.texture, source, destination, {0, 0}, 0, rl.WHITE)
		return
	}

	// Fallback if render-texture creation ever fails.
	rl.BeginDrawing()
	defer rl.EndDrawing()
	draw_virtual_game()
}

main :: proc() {
	init_game()
	defer shutdown_game()
	for running && !rl.WindowShouldClose() {
		update_game()
		draw_game()
	}
}
