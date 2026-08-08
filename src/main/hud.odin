package main

import rl "vendor:raylib"

world_to_map_rect :: proc(world: rl.Vector3, rect: rl.Rectangle) -> rl.Vector2 {
	x_ratio := (world.x - CITY_MIN_X) / (CITY_MAX_X - CITY_MIN_X)
	z_ratio := (world.z - CITY_MIN_Z) / (CITY_MAX_Z - CITY_MIN_Z)
	return {rect.x + x_ratio * rect.width, rect.y + z_ratio * rect.height}
}

point_in_rectangle :: proc(point: rl.Vector2, rect: rl.Rectangle) -> bool {
	return point.x >= rect.x && point.x <= rect.x + rect.width &&
	       point.y >= rect.y && point.y <= rect.y + rect.height
}

zone_preview_color :: proc(zone: Map_Zone, alpha: u8) -> rl.Color {
	color := map_zone_color(zone, alpha)
	if zone == .RIVER { color = {35, 112, 166, alpha} }
	return color
}

draw_finish_flag_2d :: proc(point: rl.Vector2, alpha: u8 = 255) {
	cell: i32 = 4
	x := i32(point.x) - cell
	y := i32(point.y) - cell
	for row in 0..<2 {
		for column in 0..<2 {
			color := rl.Color{240, 242, 244, alpha}
			if (row + column) % 2 != 0 { color = {12, 14, 18, alpha} }
			rl.DrawRectangle(x + i32(column) * cell, y + i32(row) * cell, cell, cell, color)
		}
	}
}


draw_start_marker_2d :: proc(rect: rl.Rectangle, alpha: u8) {
	point := world_to_map_rect(race_start_position, rect)
	route_tip_world := race_start_position + rl.Vector3{
		f32(route_direction_dx(route_start_direction)) * 7.0,
		0,
		f32(route_direction_dz(route_start_direction)) * 7.0,
	}
	tip := world_to_map_rect(route_tip_world, rect)
	rl.DrawCircleV(point, 5.2, {10, 18, 20, alpha})
	rl.DrawCircleV(point, 3.7, {78, 232, 126, alpha})
	rl.DrawLineEx(point, tip, 2.2, {228, 250, 235, alpha})
}

draw_map_base_2d :: proc(rect: rl.Rectangle, alpha: u8) {
	rl.DrawRectangleRec(rect, {17, 25, 30, alpha})

	for ix in 0..<BLOCK_X_COUNT {
		for iz in 0..<BLOCK_Z_COUNT {
			if !block_center_land(ix, iz) { continue }
			world_a := rl.Vector3{
				ROAD_ORIGIN_X + f32(ix) * ROAD_SPACING + ROAD_WIDTH * 0.5,
				0,
				ROAD_ORIGIN_Z + f32(iz) * ROAD_SPACING + ROAD_WIDTH * 0.5,
			}
			world_b := rl.Vector3{
				ROAD_ORIGIN_X + f32(ix + 1) * ROAD_SPACING - ROAD_WIDTH * 0.5,
				0,
				ROAD_ORIGIN_Z + f32(iz + 1) * ROAD_SPACING - ROAD_WIDTH * 0.5,
			}
			a := world_to_map_rect(world_a, rect)
			b := world_to_map_rect(world_b, rect)
			block_rect := rl.Rectangle{a.x, a.y, b.x - a.x, b.y - a.y}
			block_color := zone_preview_color(block_zones[ix][iz], alpha)
			block_center_x := ROAD_ORIGIN_X + (f32(ix) + 0.5) * ROAD_SPACING
			block_center_z := ROAD_ORIGIN_Z + (f32(iz) + 0.5) * ROAD_SPACING
			if coast_land_margin(block_center_x, block_center_z) <= BEACH_DRIVE_DEPTH + 4.0 {
				block_color = {194, 165, 107, alpha}
			}
			rl.DrawRectangleRec(block_rect, block_color)
		}
	}

	for i in 0..<building_count {
		building := buildings[i]
		world_a := building.center - rl.Vector3{building.half.x, 0, building.half.z}
		world_b := building.center + rl.Vector3{building.half.x, 0, building.half.z}
		a := world_to_map_rect(world_a, rect)
		b := world_to_map_rect(world_b, rect)
		building_alpha := u8(min(int(alpha) + 35, 255))
		building_color := rl.Color{30, 37, 43, building_alpha}
		if building.zone == .COMMERCIAL { building_color = {37, 48, 64, building_alpha} }
		if building.zone == .CHINATOWN { building_color = {82, 40, 38, building_alpha} }
		if building.zone == .INDUSTRIAL { building_color = {54, 46, 40, building_alpha} }
		if building.zone == .RESORT { building_color = {91, 76, 57, building_alpha} }
		rl.DrawRectangleRec({a.x, a.y, b.x - a.x, b.y - a.y}, building_color)
	}

	road_color := rl.Color{61, 65, 74, alpha}
	beach_road_color := rl.Color{190, 166, 113, alpha}
	road_thickness := max(1.0, rect.width * 0.015)
	for z in 0..<ROAD_Z_COUNT {
		for x in 0..<ROAD_X_COUNT {
			if x + 1 < ROAD_X_COUNT && route_edge_open(x, z, 1) {
				start := route_grid_position(x, z)
				finish := route_grid_position(x + 1, z)
				color := road_color
				if road_edge_park_surface(x, z, 1) { color = {91, 108, 78, alpha} }
				if road_edge_beach_surface(start, finish) { color = beach_road_color }
				a := world_to_map_rect(start, rect)
				b := world_to_map_rect(finish, rect)
				rl.DrawLineEx(a, b, road_thickness, color)
			}
			if z + 1 < ROAD_Z_COUNT && route_edge_open(x, z, 2) {
				start := route_grid_position(x, z)
				finish := route_grid_position(x, z + 1)
				color := road_color
				if road_edge_park_surface(x, z, 2) { color = {91, 108, 78, alpha} }
				if road_edge_beach_surface(start, finish) { color = beach_road_color }
				a := world_to_map_rect(start, rect)
				b := world_to_map_rect(finish, rect)
				rl.DrawLineEx(a, b, road_thickness, color)
			}
		}
	}

	river_color := rl.Color{38, 130, 184, alpha}
	if river_path_count > 0 {
		previous := world_to_map_rect(river_cell_world_center(river_path[0]), rect)
		for index in 1..<river_path_count {
			point := world_to_map_rect(river_cell_world_center(river_path[index]), rect)
			rl.DrawLineEx(previous, point, max(4.0, rect.width * 0.045), river_color)
			previous = point
		}
	}
	if river_entry_bridge_valid {
		crossing := river_entry_bridge
		center := river_crossing_world_center(crossing)
		axis := crossing_road_axis(crossing)
		a := world_to_map_rect(center - axis * 7.0, rect)
		b := world_to_map_rect(center + axis * 7.0, rect)
		rl.DrawLineEx(a, b, max(2.0, rect.width * 0.018), {185, 190, 194, alpha})
	}
	for index in 0..<river_crossing_count {
		crossing := river_crossings[index]
		if crossing.bridge == .NONE { continue }
		start := route_grid_position(crossing.ix, crossing.iz)
		finish := route_grid_position(
			crossing.ix + route_direction_dx(crossing.direction),
			crossing.iz + route_direction_dz(crossing.direction),
		)
		center := (start + finish) * 0.5
		axis := crossing_road_axis(crossing)
		a := world_to_map_rect(center - axis * 7.0, rect)
		b := world_to_map_rect(center + axis * 7.0, rect)
		bridge_color := rl.Color{185, 190, 194, alpha}
		if crossing.bridge == .JUMP { bridge_color = {242, 177, 56, alpha} }
		rl.DrawLineEx(a, b, max(2.0, rect.width * 0.018), bridge_color)
	}

	// Both curved beaches are shown directly, so bays in the preview match the
	// actual missing road nodes and physical shoreline.
	for sample in 0..<(coast_sample_count - 1) {
		world_a := coast_world_point(sample)
		world_b := coast_world_point(sample + 1)
		a := world_to_map_rect(world_a, rect)
		b := world_to_map_rect(world_b, rect)
		rl.DrawLineEx(a, b, max(4.0, rect.width * 0.030), {213, 189, 130, alpha})
		rl.DrawLineEx(a, b, max(1.5, rect.width * 0.010), {58, 144, 190, alpha})
	}
	for sample in 0..<(coast_sample_count_secondary - 1) {
		world_a := coast_world_point_secondary(sample)
		world_b := coast_world_point_secondary(sample + 1)
		a := world_to_map_rect(world_a, rect)
		b := world_to_map_rect(world_b, rect)
		rl.DrawLineEx(a, b, max(4.0, rect.width * 0.030), {213, 189, 130, alpha})
		rl.DrawLineEx(a, b, max(1.5, rect.width * 0.010), {58, 144, 190, alpha})
	}
	for segment in 0..<COAST_CORNER_SEGMENTS {
		a := world_to_map_rect(coast_corner_curve_point(segment), rect)
		b := world_to_map_rect(coast_corner_curve_point(segment + 1), rect)
		rl.DrawLineEx(a, b, max(4.0, rect.width * 0.030), {213, 189, 130, alpha})
		rl.DrawLineEx(a, b, max(1.5, rect.width * 0.010), {58, 144, 190, alpha})
	}

	mountain_point := rl.Vector2{rect.x + rect.width * 0.5, rect.y + 9}
	switch mountain_edge {
	case 1: mountain_point = {rect.x + rect.width - 9, rect.y + rect.height * 0.5}
	case 2: mountain_point = {rect.x + rect.width * 0.5, rect.y + rect.height - 9}
	case 3: mountain_point = {rect.x + 9, rect.y + rect.height * 0.5}
	}
	rl.DrawTriangle(
		mountain_point + rl.Vector2{0, -7},
		mountain_point + rl.Vector2{-8, 7},
		mountain_point + rl.Vector2{8, 7},
		{222, 229, 226, alpha},
	)
}

draw_route_2d :: proc(rect: rl.Rectangle, alpha: u8, show_car: bool) {
	marker_alpha := alpha
	if show_car && marker_alpha < 235 { marker_alpha = 235 }
	if route_point_count > 0 {
		previous := world_to_map_rect(ROUTE_POINTS[0], rect)
		for i in 1..<route_point_count {
			point := world_to_map_rect(ROUTE_POINTS[i], rect)
			width: f32 = 2.8
			route_color := rl.Color{76, 232, 255, marker_alpha}
			if show_car {
				width = 4.2
				route_color = {92, 244, 255, 255}
			}
			rl.DrawLineEx(previous, point, width, route_color)
			previous = point
		}
		draw_start_marker_2d(rect, marker_alpha)
	}

	// During a live run, passed gates disappear completely like pellets that have
	// been eaten. The current target is deliberately much brighter than later gates.
	first_visible_gate := 0
	if show_car && race.started {
		first_visible_gate = clamp(race.checkpoint, 0, active_checkpoint_count - 1)
	}
	for i in first_visible_gate..<active_checkpoint_count {
		point := world_to_map_rect(CHECKPOINTS[i].position, rect)
		is_next := show_car && race.started && i == race.checkpoint
		is_finish := i == active_checkpoint_count - 1
		if is_finish {
			draw_finish_flag_2d(point, marker_alpha)
			if is_next {
				rl.DrawCircleV(point, 8.0, {245, 250, 252, 255})
				rl.DrawCircleV(point, 5.8, {24, 42, 48, 255})
				draw_finish_flag_2d(point, 255)
			}
		} else if is_next {
			rl.DrawCircleV(point, 8.2, {245, 250, 252, 255})
			rl.DrawCircleV(point, 6.0, {46, 239, 255, 255})
			rl.DrawCircleV(point, 3.3, {255, 223, 76, 255})
		} else {
			radius: f32 = 3.2
			gate_alpha := marker_alpha
			if show_car {
				radius = 3.4
				gate_alpha = 150
			}
			rl.DrawCircleV(point, radius, {255, 211, 72, gate_alpha})
		}
	}

	if show_car {
		// Draw a short navigation cue from the player toward the next uneaten gate.
		center := world_to_map_rect(car_position(), rect)
		center.x = clamp(center.x, rect.x + 9.0, rect.x + rect.width - 9.0)
		center.y = clamp(center.y, rect.y + 9.0, rect.y + rect.height - 9.0)
		if race.started && !race.completed && race.checkpoint < active_checkpoint_count {
			target := world_to_map_rect(CHECKPOINTS[race.checkpoint].position, rect)
			target.x = clamp(target.x, rect.x + 7.0, rect.x + rect.width - 7.0)
			target.y = clamp(target.y, rect.y + 7.0, rect.y + rect.height - 7.0)
			rl.DrawLineEx(center, target, 1.8, {108, 245, 255, 205})
		}

		// Draw the player last as a large, high-contrast screen-space arrow.
		forward := forward_from_yaw(car.yaw)
		direction := rl.Vector2{forward.x, forward.z}
		side := rl.Vector2{-direction.y, direction.x}
		tip := center + direction * 10.0
		back := center - direction * 5.5
		left := back + side * 5.8
		right_point := back - side * 5.8
		fill := rl.Color{70, 244, 255, 255}
		outline := rl.Color{255, 255, 255, 255}
		rl.DrawTriangle(tip, left, right_point, fill)
		rl.DrawTriangle(tip, right_point, left, fill)
		rl.DrawLineEx(tip, left, 2.0, outline)
		rl.DrawLineEx(left, right_point, 2.0, outline)
		rl.DrawLineEx(right_point, tip, 2.0, outline)
	}
}

draw_map_panel :: proc(rect: rl.Rectangle, alpha: u8, show_car: bool) {
	draw_map_base_2d(rect, alpha)
	rl.DrawRectangleLinesEx(rect, 2, {120, 178, 198, alpha})
	draw_route_2d(rect, alpha, show_car)
}

menu_car_rect :: proc() -> rl.Rectangle { return {14, 92, 250, 315} }
menu_map_rect :: proc() -> rl.Rectangle { return {276, 92, 250, 315} }

menu_body_left_rect :: proc() -> rl.Rectangle { return {18, 438, 42, 42} }
menu_body_right_rect :: proc() -> rl.Rectangle { return {218, 438, 42, 42} }
menu_color_left_rect :: proc() -> rl.Rectangle { return {18, 493, 42, 42} }
menu_color_right_rect :: proc() -> rl.Rectangle { return {218, 493, 42, 42} }
menu_parts_rect :: proc() -> rl.Rectangle { return {44, 548, 190, 48} }
menu_car_random_rect :: proc() -> rl.Rectangle { return {44, 610, 190, 48} }

menu_part_toggle_rect :: proc(part: int) -> rl.Rectangle {
	column := part / 10
	row := part % 10
	x: f32 = 22
	if column != 0 { x = 276 }
	return {x, 132 + f32(row) * 47, 242, 39}
}
menu_parts_clear_rect :: proc() -> rl.Rectangle { return {28, 630, 140, 48} }
menu_parts_all_rect :: proc() -> rl.Rectangle { return {200, 630, 140, 48} }
menu_parts_done_rect :: proc() -> rl.Rectangle { return {372, 630, 140, 48} }

menu_gate_minus_rect :: proc() -> rl.Rectangle { return {282, 438, 42, 42} }
menu_gate_plus_rect :: proc() -> rl.Rectangle { return {478, 438, 42, 42} }
menu_length_minus_rect :: proc() -> rl.Rectangle { return {282, 493, 42, 42} }
menu_length_plus_rect :: proc() -> rl.Rectangle { return {478, 493, 42, 42} }
menu_regen_rect :: proc() -> rl.Rectangle { return {306, 556, 190, 48} }
menu_bounce_rect :: proc() -> rl.Rectangle { return {306, 618, 190, 40} }
menu_scale_rect :: proc() -> rl.Rectangle { return {12, 24, 48, 26} }
menu_start_rect :: proc() -> rl.Rectangle { return {90, 700, 360, 64} }

pause_continue_button_rect :: proc() -> rl.Rectangle { return {110, 405, 320, 58} }
pause_recover_button_rect :: proc() -> rl.Rectangle { return {110, 477, 320, 58} }
pause_restart_button_rect :: proc() -> rl.Rectangle { return {110, 549, 320, 58} }
pause_main_menu_button_rect :: proc() -> rl.Rectangle { return {110, 621, 320, 58} }
finish_restart_button_rect :: proc() -> rl.Rectangle { return {110, 525, 320, 60} }
finish_main_menu_button_rect :: proc() -> rl.Rectangle { return {110, 605, 320, 60} }

button_fill :: proc(rect: rl.Rectangle) -> (fill, border: rl.Color) {
	fill = {20, 35, 48, 245}
	border = {80, 190, 225, 255}
	if point_in_rectangle(ui_mouse_position(), rect) {
		fill = {35, 65, 82, 250}
		border = {70, 225, 255, 255}
	}
	return
}

draw_menu_button :: proc(rect: rl.Rectangle, label: cstring, font_size: i32 = 20) {
	fill, border := button_fill(rect)
	rl.DrawRectangleRec(rect, fill)
	rl.DrawRectangleLinesEx(rect, 2, border)
	width := rl.MeasureText(label, font_size)
	rl.DrawText(label, i32(rect.x + (rect.width - f32(width)) * 0.5), i32(rect.y + (rect.height - f32(font_size)) * 0.5), font_size, rl.WHITE)
}

draw_option_value :: proc(label, value: cstring, center_x, y: i32) {
	label_width := rl.MeasureText(label, 12)
	rl.DrawText(label, center_x - label_width / 2, y, 12, {145, 185, 205, 255})
	value_width := rl.MeasureText(value, 16)
	rl.DrawText(value, center_x - value_width / 2, y + 19, 16, rl.WHITE)
}

render_menu_car_preview_texture :: proc() {
	if !menu_car_target_ready { return }
	rl.BeginTextureMode(menu_car_target)
	rl.ClearBackground({11, 17, 24, 255})
	preview_camera := rl.Camera3D{
		position = {5.4, 3.6, 5.4},
		target = {0, 0.38, 0},
		up = {0, 1, 0},
		fovy = 42,
		projection = .PERSPECTIVE,
	}
	rl.BeginMode3D(preview_camera)
	rl.DrawCube({0, -0.12, 0}, 8.0, 0.18, 8.0, {31, 37, 44, 255})
	preview_car_position := rl.Vector3{0, 0.46 + visual_bounce_y(0.34), 0}
	draw_car_model(preview_car_position, menu_car_rotation, selected_car_body, selected_car_color, selected_car_parts, false)
	rl.EndMode3D()
	rl.EndTextureMode()
}

draw_menu_car_preview :: proc() {
	if !menu_car_target_ready { return }
	rect := menu_car_rect()
	source := rl.Rectangle{0, 0, f32(MENU_CAR_RT_WIDTH), -f32(MENU_CAR_RT_HEIGHT)}
	rl.DrawTexturePro(menu_car_target.texture, source, rect, {0, 0}, 0, rl.WHITE)
	rl.DrawRectangleLinesEx(rect, 2, {120, 178, 198, 255})
}

draw_parts_menu :: proc() {
	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {4, 7, 12, 238})
	rl.DrawText("MIX + MATCH PARTS", 111, 42, 28, rl.WHITE)
	count_text := rl.TextFormat("%d / 20 ACTIVE", car_part_enabled_count(selected_car_parts))
	count_width := rl.MeasureText(count_text, 14)
	rl.DrawText(count_text, (WINDOW_WIDTH - count_width) / 2, 83, 14, {120, 205, 225, 255})

	for part in 0..<CAR_PART_COUNT {
		rect := menu_part_toggle_rect(part)
		active := car_part_enabled(selected_car_parts, part)
		fill := rl.Color{20, 35, 48, 248}
		border := rl.Color{74, 115, 135, 255}
		if active {
			fill = {28, 86, 76, 250}
			border = {82, 235, 168, 255}
		}
		if point_in_rectangle(ui_mouse_position(), rect) {
			border = {80, 225, 255, 255}
		}
		rl.DrawRectangleRec(rect, fill)
		rl.DrawRectangleLinesEx(rect, 2, border)
		label := car_part_name(part)
		width := rl.MeasureText(label, 14)
		rl.DrawText(label, i32(rect.x + (rect.width - f32(width)) * 0.5), i32(rect.y + 12), 14, rl.WHITE)
	}
	 draw_menu_button(menu_parts_clear_rect(), "CLEAR", 17)
	 draw_menu_button(menu_parts_all_rect(), "ALL", 17)
	 draw_menu_button(menu_parts_done_rect(), "DONE", 17)
}

draw_main_menu :: proc() {
	rl.ClearBackground({8, 13, 20, 255})
	rl.DrawText("MOUSE DRIFT CITY", 73, 24, 31, rl.WHITE)
	rl.DrawText("ARCADE RUN SELECT", 181, 61, 14, {128, 185, 205, 255})

	draw_menu_car_preview()
	draw_map_panel(menu_map_rect(), 255, false)
	rl.DrawText("GARAGE", 99, 412, 15, {80, 210, 240, 255})
	rl.DrawText("CITY + ROUTE", 350, 412, 15, {80, 210, 240, 255})

	draw_menu_button(menu_body_left_rect(), "<")
	draw_menu_button(menu_body_right_rect(), ">")
	draw_option_value("BODY", car_body_name(selected_car_body), 139, 433)
	draw_menu_button(menu_color_left_rect(), "<")
	draw_menu_button(menu_color_right_rect(), ">")
	draw_option_value("COLOR", car_color_name(selected_car_color), 139, 488)
	parts_label := rl.TextFormat("PARTS  %d/20", car_part_enabled_count(selected_car_parts))
	draw_menu_button(menu_parts_rect(), parts_label, 17)
	draw_menu_button(menu_car_random_rect(), "RANDOM CAR", 18)

	draw_menu_button(menu_gate_minus_rect(), "-")
	draw_menu_button(menu_gate_plus_rect(), "+")
	draw_option_value("TURN GATES", rl.TextFormat("%d", selected_gate_count), 401, 433)
	draw_menu_button(menu_length_minus_rect(), "-")
	draw_menu_button(menu_length_plus_rect(), "+")
	draw_option_value("ROUTE LENGTH", rl.TextFormat("%d m", selected_route_length), 401, 488)
	draw_menu_button(menu_regen_rect(), "REGEN MAP", 18)
	draw_menu_button(menu_bounce_rect(), bounce_mode_label(), 15)
	draw_menu_button(menu_scale_rect(), ui_scale_label(), 11)

	draw_menu_button(menu_start_rect(), "START RUN", 25)
	rl.DrawText("AUTO THROTTLE   LMB NITRO   RMB BRAKE / DRIFT / REVERSE", 37, 794, 13, rl.WHITE)
	rl.DrawText("MOVE MOUSE LEFT / RIGHT TO STEER    MMB PAUSE", 75, 823, 13, {145, 185, 205, 255})
	rl.DrawText("REGEN changes districts, river topology, bridge types, bays, mountain and route.", 45, 875, 12, {110, 150, 170, 255})
	if garage_parts_open {
		draw_parts_menu()
	}
}

draw_minimap :: proc() {
	rect := rl.Rectangle{330, 0, 190, 245}
	draw_map_panel(rect, 118, true)
}

draw_hud :: proc() {
	screen_width := i32(WINDOW_WIDTH)
	rl.DrawRectangle(0, 0, screen_width, 82, {6, 9, 14, 205})

	speed_kmh := i32(car_speed() * 3.6)
	rl.DrawText(rl.TextFormat("%03d", speed_kmh), 18, 12, 42, rl.WHITE)
	rl.DrawText("KM/H", 22, 55, 15, {140, 195, 215, 255})
	time_value := race.elapsed
	if race.completed { time_value = race.finish_time }
	rl.DrawText(rl.TextFormat("TIME  %06.2f", time_value), 150, 15, 20, rl.WHITE)
	if race.checkpoint < selected_gate_count {
		rl.DrawText(rl.TextFormat("TURN  %d/%d", race.checkpoint + 1, selected_gate_count), 150, 44, 17, {140, 195, 215, 255})
	} else {
		rl.DrawText("FINISH", 150, 44, 17, {140, 195, 215, 255})
	}

	bar_x: i32 = 18
	bar_y: i32 = 86
	bar_w: i32 = 250
	bar_h: i32 = 12
	rl.DrawRectangle(bar_x, bar_y, bar_w, bar_h, {10, 14, 21, 210})
	nitro_ratio := nitro_charge_ratio()
	rl.DrawRectangle(bar_x, bar_y, i32(f32(bar_w) * nitro_ratio), bar_h, {55, 205, 255, 240})
	rl.DrawRectangleLines(bar_x, bar_y, bar_w, bar_h, {120, 190, 220, 255})
	rl.DrawText("LMB NITRO", bar_x, bar_y + 16, 13, {180, 220, 235, 255})
	forward_speed := car_forward_speed()
	if handbrake_active() {
		if forward_speed < -0.35 {
			rl.DrawText("REVERSE", 18, 126, 20, {120, 210, 255, 255})
		} else if forward_speed > 2.0 {
			rl.DrawText("BRAKE DRIFT", 18, 126, 20, {255, 192, 62, 255})
		} else {
			rl.DrawText("BRAKE", 18, 126, 20, {255, 192, 62, 255})
		}
	}

	draw_minimap()
	bottom := i32(WINDOW_HEIGHT) - 108
	rl.DrawRectangle(0, bottom, screen_width, 108, {6, 9, 14, 190})
	steer_left: i32 = 8
	steer_right: i32 = screen_width - 8
	steer_y: i32 = bottom + 18
	rl.DrawLine(steer_left, steer_y, steer_right, steer_y, {90, 105, 120, 230})
	rl.DrawLine(screen_width / 2, steer_y - 7, screen_width / 2, steer_y + 7, {140, 165, 180, 230})
	steer_half_width := f32(steer_right - steer_left) * 0.5
	steer_x := screen_width / 2 + i32(car.steer * steer_half_width)
	rl.DrawCircle(steer_x, steer_y, 7, rl.WHITE)
	rl.DrawText("AUTO THROTTLE    LMB NITRO    RMB BRAKE / DRIFT / REVERSE", 14, bottom + 39, 13, rl.WHITE)
	rl.DrawText("MOVE MOUSE X TO STEER    MMB PAUSE", 105, bottom + 70, 13, {150, 195, 215, 255})

	if race.intro_visible && !race.completed {
		rl.DrawRectangle(62, 365, screen_width - 124, 82, {4, 7, 12, 205})
		message := rl.TextFormat("PASS %d CORNER GATES, THEN FINISH", selected_gate_count)
		message_width := rl.MeasureText(message, 19)
		rl.DrawText(message, (screen_width - message_width) / 2, 386, 19, rl.WHITE)
		rl.DrawText("THE BRIGHT GATE IS NEXT; TWO FAINT GATES PREVIEW AHEAD", 73, 418, 11, {55, 205, 255, 255})
	}
}

draw_pause_overlay :: proc() {
	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {3, 5, 9, 226})
	rl.DrawText("PAUSED", 195, 315, 38, rl.WHITE)
	draw_menu_button(pause_continue_button_rect(), "CONTINUE", 23)
	draw_menu_button(pause_recover_button_rect(), "RECOVER", 23)
	draw_menu_button(pause_restart_button_rect(), "RESTART RUN", 23)
	draw_menu_button(pause_main_menu_button_rect(), "MAIN MENU", 23)
}

draw_finish_overlay :: proc() {
	rl.DrawRectangle(0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, {3, 5, 9, 226})
	rl.DrawText("RUN COMPLETE", 102, 340, 31, rl.WHITE)
	text := rl.TextFormat("TIME  %.2f s", race.finish_time)
	width := rl.MeasureText(text, 25)
	rl.DrawText(text, (WINDOW_WIDTH - width) / 2, 395, 25, {55, 205, 255, 255})
	draw_menu_button(finish_restart_button_rect(), "RESTART RUN", 24)
	draw_menu_button(finish_main_menu_button_rect(), "MAIN MENU", 24)
}
