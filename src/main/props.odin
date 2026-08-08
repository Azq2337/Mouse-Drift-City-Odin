package main

import rl "vendor:raylib"
import b3 "vendor:box3d"

prop_half_extents :: proc(kind: Destructible_Prop_Type, scale: f32) -> rl.Vector3 {
	switch kind {
	case .TREE:
		return {0.34 * scale, 0.74 * scale, 0.34 * scale}
	case .PALM:
		return {0.40 * scale, 1.58 * scale, 0.40 * scale}
	case .CHERRY:
		return {0.36 * scale, 0.84 * scale, 0.36 * scale}
	case .LAMP:
		return {0.24 * scale, 1.55 * scale, 0.24 * scale}
	case .UMBRELLA:
		return {0.26 * scale, 0.92 * scale, 0.26 * scale}
	case .LOUNGER:
		return {0.88 * scale, 0.26 * scale, 0.42 * scale}
	}
	return {0.10, 0.70, 0.10}
}

prop_density :: proc(kind: Destructible_Prop_Type) -> f32 {
	switch kind {
	case .TREE:     return 2.4
	case .PALM:     return 1.8
	case .CHERRY:   return 2.0
	case .LAMP:     return 3.2
	case .UMBRELLA: return 1.2
	case .LOUNGER:  return 1.0
	}
	return 2.0
}


prop_clear_of_buildings :: proc(x, z, margin: f32) -> bool {
	for index in 0..<building_count {
		building := buildings[index]
		if abs_f32(x - building.center.x) <= building.half.x + margin &&
		   abs_f32(z - building.center.z) <= building.half.z + margin {
			return false
		}
	}
	return true
}

prop_initial_rotation :: proc(yaw: f32) -> b3.Quat {
	if abs_f32(yaw) < 0.0001 {
		return b3.Quat_identity
	}
	return b3.MakeQuatFromAxisAngle({0, 1, 0}, yaw)
}

prop_water_clearance_radius :: proc(kind: Destructible_Prop_Type, scale: f32) -> f32 {
	switch kind {
	case .TREE:     return 0.95 * scale
	case .PALM:     return 0.72 * scale
	case .CHERRY:   return 1.00 * scale
	case .LAMP:     return 0.34 * scale
	case .UMBRELLA: return 0.88 * scale
	case .LOUNGER:  return 0.80 * scale
	}
	return 0.50 * scale
}

prop_clear_of_water :: proc(kind: Destructible_Prop_Type, position: rl.Vector3, scale: f32) -> bool {
	radius := prop_water_clearance_radius(kind, scale) + 0.30
	if point_inside_world_water(position.x, position.z) { return false }
	offsets := [8][2]f32{
		{ 1.0,  0.0}, {-1.0,  0.0}, { 0.0,  1.0}, { 0.0, -1.0},
		{ 0.707,  0.707}, {-0.707,  0.707}, { 0.707, -0.707}, {-0.707, -0.707},
	}
	for offset in offsets {
		x := position.x + offset[0] * radius
		z := position.z + offset[1] * radius
		if point_inside_world_water(x, z) { return false }
	}
	return true
}

add_destructible_prop :: proc(
	kind: Destructible_Prop_Type,
	ground_position: rl.Vector3,
	scale: f32,
	yaw: f32 = 0,
	variant: int = 0,
) {
	if destructible_prop_count >= DESTRUCTIBLE_PROP_MAX {
		return
	}

	half := prop_half_extents(kind, scale)
	if !prop_clear_of_water(kind, ground_position, scale) {
		return
	}
	if !prop_clear_of_buildings(ground_position.x, ground_position.z, max(half.x, half.z) + 0.18) {
		return
	}
	initial_position := rl.Vector3{ground_position.x, half.y, ground_position.z}
	initial_rotation := prop_initial_rotation(yaw)

	body_def := b3.DefaultBodyDef()
	body_def.type = .staticBody
	body_def.position = {initial_position.x, initial_position.y, initial_position.z}
	body_def.rotation = initial_rotation
	body_def.linearDamping = 1.15
	body_def.angularDamping = 0.78
	body_def.enableSleep = true
	body_def.isAwake = false
	body_def.enableContactRecycling = false

	body_id := b3.CreateBody(world_id, body_def)
	hull := b3.MakeBoxHull(half.x, half.y, half.z)
	shape_def := b3.DefaultShapeDef()
	shape_def.density = prop_density(kind)
	shape_def.baseMaterial.friction = 0.72
	shape_def.baseMaterial.restitution = 0.04
	_ = b3.CreateHullShape(body_id, shape_def, &hull.base)

	destructible_props[destructible_prop_count] = {
		body_id = body_id,
		kind = kind,
		scale = scale,
		variant = variant,
		initial_position = initial_position,
		initial_yaw = yaw,
		dynamic_active = false,
		physics_active = false,
	}
	destructible_prop_count += 1
}

reset_destructible_props :: proc() {
	for index in 0..<destructible_prop_count {
		prop := &destructible_props[index]
		if !b3.Body_IsValid(prop.body_id) {
			continue
		}
		if prop.physics_active || prop.dynamic_active {
			b3.Body_SetLinearVelocity(prop.body_id, {0, 0, 0})
			b3.Body_SetAngularVelocity(prop.body_id, {0, 0, 0})
			b3.Body_SetType(prop.body_id, .staticBody)
		}
		rotation := prop_initial_rotation(prop.initial_yaw)
		b3.Body_SetTransform(
			prop.body_id,
			{prop.initial_position.x, prop.initial_position.y, prop.initial_position.z},
			rotation,
		)
		prop.dynamic_active = false
		prop.physics_active = false
	}
}

activate_destructible_prop :: proc(prop: ^Destructible_Prop) {
	if prop.physics_active || !b3.Body_IsValid(prop.body_id) {
		return
	}
	b3.Body_SetType(prop.body_id, .dynamicBody)
	b3.Body_SetAwake(prop.body_id, true)
	prop.dynamic_active = true
	prop.physics_active = true
}

freeze_destructible_prop :: proc(prop: ^Destructible_Prop) {
	if !prop.physics_active || !b3.Body_IsValid(prop.body_id) { return }
	b3.Body_SetLinearVelocity(prop.body_id, {0, 0, 0})
	b3.Body_SetAngularVelocity(prop.body_id, {0, 0, 0})
	b3.Body_SetType(prop.body_id, .staticBody)
	// Keep dynamic_active=true: the current fallen/displaced transform stays visible.
	prop.physics_active = false
}

update_destructible_props :: proc() {
	// Only a moving bubble around the car participates in expensive dynamic
	// physics. Props that the player already knocked down freeze in their current
	// pose once far away, and can become dynamic again if the player returns.
	car_pos := car_physics_position()
	activation_radius_sq: f32 = 9.0 * 9.0
	freeze_radius_sq: f32 = 20.0 * 20.0
	for index in 0..<destructible_prop_count {
		prop := &destructible_props[index]
		if !b3.Body_IsValid(prop.body_id) { continue }

		position := prop.initial_position
		if prop.dynamic_active {
			body_position := b3.Body_GetPosition(prop.body_id)
			position = {f32(body_position.x), f32(body_position.y), f32(body_position.z)}
		}
		dx := position.x - car_pos.x
		dz := position.z - car_pos.z
		distance_sq := dx * dx + dz * dz

		if prop.physics_active {
			if distance_sq > freeze_radius_sq {
				freeze_destructible_prop(prop)
			}
			continue
		}
		if distance_sq <= activation_radius_sq {
			activate_destructible_prop(prop)
		}
	}
}

prop_clear_of_drive_lane :: proc(x, z: f32, margin: f32 = 1.15) -> bool {
	clearance := ROAD_WIDTH * 0.5 + margin
	for road in 0..<ROAD_X_COUNT {
		road_x := ROAD_ORIGIN_X + f32(road) * ROAD_SPACING
		if abs_f32(x - road_x) < clearance {
			return false
		}
	}
	for road in 0..<ROAD_Z_COUNT {
		road_z := ROAD_ORIGIN_Z + f32(road) * ROAD_SPACING
		if abs_f32(z - road_z) < clearance {
			return false
		}
	}
	return true
}

beach_sand_or_water :: proc(x, z: f32) -> bool {
	if !coast_world_land(x, z) { return true }
	return coast_land_margin(x, z) <= BEACH_DRIVE_DEPTH + 1.8
}

add_lamp_if_land :: proc(x, z, yaw: f32, variant: int) {
	if beach_sand_or_water(x, z) { return }
	add_destructible_prop(.LAMP, {x, 0, z}, 0.90 + f32(variant % 3) * 0.035, yaw, variant)
}

scatter_unit :: proc(seed: int) -> f32 {
	value := (seed * seed * 37 + seed * 97 + 193) % 1009
	if value < 0 { value = -value }
	return f32(value) / 1008.0
}

scatter_signed :: proc(seed: int) -> f32 {
	return scatter_unit(seed) * 2.0 - 1.0
}

generate_block_destructible_props :: proc() {
	for ix in 0..<BLOCK_X_COUNT {
		left_road_x := ROAD_ORIGIN_X + f32(ix) * ROAD_SPACING
		block_x := left_road_x + ROAD_SPACING * 0.5
		for iz in 0..<BLOCK_Z_COUNT {
			top_road_z := ROAD_ORIGIN_Z + f32(iz) * ROAD_SPACING
			block_z := top_road_z + ROAD_SPACING * 0.5
			zone := block_zones[ix][iz]
			if zone == .RIVER || !coast_world_land(block_x, block_z) {
				continue
			}
			coastal_block := coast_land_margin(block_x, block_z) <= BEACH_DRIVE_DEPTH + COAST_PROMENADE_DEPTH

			if coastal_block && zone != .RESORT {
				continue
			}

			if zone == .PARK {
				target_count := 9 + ((ix * 5 + iz * 7) % 5)
				accepted: [18]rl.Vector3
				accepted_count := 0
				for candidate in 0..<52 {
					if accepted_count >= target_count { break }
					seed := ix * 1301 + iz * 787 + candidate * 97
					// Independent hashes plus rejection spacing produce a loose grove, not
					// diagonal hatching or a hidden grid.
					x := block_x + scatter_signed(seed + 17) * 6.7
					z := block_z + scatter_signed(seed * 5 + 53) * 6.7
					if !prop_clear_of_drive_lane(x, z, 0.48) { continue }
					too_close := false
					for placed_index in 0..<accepted_count {
						dx := accepted[placed_index].x - x
						dz := accepted[placed_index].z - z
						minimum_spacing := 2.3 + scatter_unit(seed + placed_index * 31) * 1.2
						if dx * dx + dz * dz < minimum_spacing * minimum_spacing {
							too_close = true
							break
						}
					}
					if too_close { continue }
					scale := 0.58 + scatter_unit(seed + 83) * 0.60
					if !prop_clear_of_water(.TREE, {x, 0, z}, scale) { continue }
					accepted[accepted_count] = {x, 0, z}
					accepted_count += 1
					add_destructible_prop(.TREE, {x, 0, z}, scale, scatter_signed(seed + 121) * 0.8, seed % 4)
				}
			} else if zone == .RESORT {
				// Dedicated beach scattering owns palms close to the shoreline. Resort
				// blocks farther inland may still carry a couple of palms.
				if coastal_block { continue }
				for palm in 0..<1 {
					seed := ix * 71 + iz * 43 + palm * 29
					x := block_x + scatter_signed(seed + 7) * 5.8
					z := block_z + scatter_signed(seed + 31) * 5.8
					scale := 1.05 + scatter_unit(seed + 59) * 0.22
					add_destructible_prop(.PALM, {x, 0, z}, scale, scatter_signed(seed + 89) * 1.4, seed % 4)
				}
			} else if zone == .RESIDENTIAL {
				for tree in 0..<2 {
					x := block_x + 6.4
					z := block_z - 5.8 + f32(tree) * 11.2
					if tree == 1 && (ix + iz) % 2 != 0 { continue }
					if beach_sand_or_water(x, z) { continue }
					scale := 0.62 + f32((ix * 3 + iz + tree) % 6) * 0.085
					add_destructible_prop(.TREE, {x, 0, z}, scale, 0, (ix + iz + tree) % 4)
				}
			} else if (zone == .COMMERCIAL || zone == .CHINATOWN) && (ix + iz) % 2 == 0 {
				x := block_x - 6.5
				z := block_z + 5.8
				if !beach_sand_or_water(x, z) {
					add_destructible_prop(.TREE, {x, 0, z}, 0.58 + f32((ix + iz) % 3) * 0.07, 0, (ix + iz) % 4)
				}
			}

			// Two lamps on each represented street edge: roughly one every half block.
			// Blocks share roads, so using the left and top edges gives dense coverage
			// without double-spawning both sidewalks of the same segment.
			for lamp in 0..<2 {
				t := 0.27 + f32(lamp) * 0.46
				vertical_x := left_road_x + ROAD_WIDTH * 0.5 + 1.05
				vertical_z := top_road_z + ROAD_SPACING * t
				add_lamp_if_land(vertical_x, vertical_z, rl.PI, ix * 17 + iz * 7 + lamp)

				horizontal_x := left_road_x + ROAD_SPACING * t
				horizontal_z := top_road_z + ROAD_WIDTH * 0.5 + 1.05
				add_lamp_if_land(horizontal_x, horizontal_z, -rl.PI * 0.5, ix * 11 + iz * 13 + lamp)
			}
		}
	}
}

edge_outside_point :: proc(edge: int, along, distance: f32) -> rl.Vector3 {
	x := along
	z := CITY_MIN_Z - distance
	if edge == 1 {
		x = CITY_MAX_X + distance
		z = along
	} else if edge == 2 {
		x = along
		z = CITY_MAX_Z + distance
	} else if edge == 3 {
		x = CITY_MIN_X - distance
		z = along
	}
	return {x, 0, z}
}

generate_city_edge_trees :: proc() {
	edge := city_edge()
	minimum, maximum := coast_sample_along_bounds_for_edge(edge)
	for row in 0..<3 {
		row_distance := 8.0 + f32(row) * 6.0
		stride := 8.0 - f32(row) * 0.6
		count := int((maximum - minimum) / stride)
		for index in 0..<count {
			base_along := minimum + 4.0 + f32(index) * stride
			jitter := f32(((index * 19 + row * 23) % 9) - 4) * 0.9
			along := clamp(base_along + jitter, minimum + 2.0, maximum - 2.0)
			lateral := f32(((index * 13 + row * 7) % 5) - 2) * 0.75
			position := edge_outside_point(edge, along, row_distance)
			if edge == 0 || edge == 2 { position.x += lateral } else { position.z += lateral }
			if !prop_clear_of_drive_lane(position.x, position.z, 0.95) { continue }
			scale := 0.72 + f32((index + row * 3) % 6) * 0.07
			variant := (index * 3 + row) % 4
			add_destructible_prop(.TREE, {position.x, 0, position.z}, scale, 0, variant)
		}
	}
}

generate_mountain_cherry_props :: proc() {
	minimum, maximum := coast_sample_along_bounds_for_edge(mountain_edge)
	outward := city_edge_outward_axis(mountain_edge)
	for item in 0..<52 {
		along := lerp_f32(minimum + 3.0, maximum - 3.0, scatter_unit(item * 47 + 13))
		inward := 4.0 + scatter_unit(item * 61 + 29) * 20.0
		position: rl.Vector3
		switch mountain_edge {
		case 0: position = {along, 0, CITY_MIN_Z + inward}
		case 1: position = {CITY_MAX_X - inward, 0, along}
		case 2: position = {along, 0, CITY_MAX_Z - inward}
		case:   position = {CITY_MIN_X + inward, 0, along}
		}
		_ = outward
		if beach_sand_or_water(position.x, position.z) { continue }
		if !prop_clear_of_drive_lane(position.x, position.z, 0.40) { continue }
		scale := 0.58 + scatter_unit(item * 89 + 41) * 0.50
		add_destructible_prop(.CHERRY, position, scale, 0, item % 4)
	}
}

generate_riverfront_lamps :: proc() {
	if river_path_count <= 0 { return }
	point_count := river_path_count + 2
	for segment_index in 0..<(point_count - 1) {
		if segment_index == point_count - 2 { continue } // keep the sea mouth open
		start := river_centerline_point(segment_index)
		finish := river_centerline_point(segment_index + 1)
		start_inner_sign: f32 = 0
		finish_inner_sign: f32 = 0
		if segment_index > 0 {
			has_turn, inner_sign := river_corner_inner_side_sign(river_centerline_point(segment_index - 1), start, finish)
			if has_turn { start_inner_sign = inner_sign }
		}
		if segment_index + 2 < point_count {
			has_turn, inner_sign := river_corner_inner_side_sign(start, finish, river_centerline_point(segment_index + 2))
			if has_turn { finish_inner_sign = inner_sign }
		}
		delta := finish - start
		length := horizontal_length(delta)
		if length <= 8.0 { continue }
		tangent := delta / length
		right := rl.Vector3{-tangent.z, 0, tangent.x}
		for side in 0..<2 {
			sign: f32 = -1
			if side != 0 { sign = 1 }
			bank_start, bank_finish := river_bank_side_endpoints(start, finish, sign, start_inner_sign, finish_inner_sign)
			lamp_start := bank_start + right * (1.8 * sign)
			lamp_finish := bank_finish + right * (1.8 * sign)
			usable := horizontal_length(lamp_finish - lamp_start)
			count := int(usable / 7.0)
			if count <= 0 { continue }
			for lamp in 0..<count {
				t := (f32(lamp) + 0.5) / f32(count)
				position := rl.Vector3{
					lerp_f32(lamp_start.x, lamp_finish.x, t),
					0,
					lerp_f32(lamp_start.z, lamp_finish.z, t),
				}
				if beach_sand_or_water(position.x, position.z) { continue }
				if !prop_clear_of_drive_lane(position.x, position.z, 0.55) { continue }
				add_destructible_prop(.LAMP, position, 1.05, b3.Atan2(tangent.z, tangent.x), 100 + (lamp + side * 3 + segment_index) % 8)
			}
		}
	}
}

generate_inner_edge_tree_strip :: proc(edge: int, cherry: bool) {
	minimum, maximum := coast_sample_along_bounds_for_edge(edge)
	for item in 0..<30 {
		seed := edge * 1201 + item * 67 + 17
		t := (f32(item) + 0.25 + scatter_unit(seed + 7) * 0.50) / 30.0
		along := lerp_f32(minimum + 2.0, maximum - 2.0, t)
		along += scatter_signed(seed + 23) * 2.2
		inward := 2.2 + scatter_unit(seed + 41) * 7.0
		position := edge_outside_point(edge, along, -inward)
		if beach_sand_or_water(position.x, position.z) { continue }
		if !prop_clear_of_drive_lane(position.x, position.z, 0.85) { continue }
		scale := 0.68 + scatter_unit(seed + 59) * 0.50
		if cherry {
			add_destructible_prop(.CHERRY, position, scale, scatter_signed(seed + 73) * 0.25, item % 4)
		} else {
			add_destructible_prop(.TREE, position, scale, scatter_signed(seed + 73) * 0.30, item % 4)
		}
	}
}

generate_city_edge_roadside_trees :: proc() {
	edge := city_edge()
	outward := city_edge_outward_axis(edge)
	right := rl.Vector3{-outward.z, 0, outward.x}
	for index in 0..<city_edge_road_count(edge) {
		node := city_edge_exit_node(edge, index)
		tree_count := 8 + (index % 4)
		for sample in 0..<tree_count {
			seed := index * 97 + sample * 41
			sign: f32 = -1
			if sample % 2 != 0 { sign = 1 }
			// Mix a near-road collision row with a second row deeper toward the edge.
			lane_group := sample / 2
			inward := 1.45 + f32(lane_group) * (2.10 + scatter_unit(seed + 13) * 0.90)
			lateral := ROAD_WIDTH * 0.50 + 0.30 + scatter_unit(seed + 31) * 1.55
			position := node - outward * inward + right * (lateral * sign)
			if beach_sand_or_water(position.x, position.z) { continue }
			if !prop_clear_of_drive_lane(position.x, position.z, 0.08) { continue }
			scale := 0.72 + scatter_unit(seed + 59) * 0.45
			add_destructible_prop(.TREE, {position.x, 0, position.z}, scale, scatter_signed(seed + 71) * 0.35, (index + sample * 3) % 4)
		}
	}
}

generate_mountain_roadside_cherries :: proc() {
	edge := mountain_edge
	outward := city_edge_outward_axis(edge)
	right := rl.Vector3{-outward.z, 0, outward.x}
	for index in 0..<city_edge_road_count(edge) {
		valid_node := false
		switch edge {
		case 0: valid_node = route_grid_valid(index, 0)
		case 1: valid_node = route_grid_valid(ROAD_X_COUNT - 1, index)
		case 2: valid_node = route_grid_valid(index, ROAD_Z_COUNT - 1)
		case:   valid_node = route_grid_valid(0, index)
		}
		if !valid_node { continue }
		node := city_edge_exit_node(edge, index)
		tree_count := 8 + ((index + 1) % 4)
		for sample in 0..<tree_count {
			seed := index * 109 + sample * 43
			sign: f32 = -1
			if sample % 2 == 0 { sign = 1 }
			lane_group := sample / 2
			inward := 1.35 + f32(lane_group) * (2.00 + scatter_unit(seed + 17) * 0.95)
			lateral := ROAD_WIDTH * 0.52 + 0.28 + scatter_unit(seed + 37) * 1.45
			position := node - outward * inward + right * (lateral * sign)
			if beach_sand_or_water(position.x, position.z) { continue }
			if !prop_clear_of_drive_lane(position.x, position.z, 0.08) { continue }
			scale := 0.66 + scatter_unit(seed + 61) * 0.44
			add_destructible_prop(.CHERRY, {position.x, 0, position.z}, scale, scatter_signed(seed + 79) * 0.30, (index + sample * 2) % 4)
		}
	}
}

generate_beach_edge_props :: proc(edge: int, secondary: bool) {
	count := coast_profile_count(secondary)
	if count <= 2 { return }
	inward := coast_inward_vector_for_edge(edge)
	sample_offset := 0
	if secondary { sample_offset = 5 }
	for item in 0..<34 {
		sample := 1 + ((item * 7 + sample_offset) % max(count - 2, 1))
		shore := coast_world_point_for_edge(edge, secondary, sample)
		along_jitter := scatter_signed(item * 43 + edge * 17) * 2.8
		if edge == 0 || edge == 2 { shore.x += along_jitter } else { shore.z += along_jitter }
		depth := 5.2 + scatter_unit(item * 59 + edge * 31) * 10.4
		position := shore + inward * depth
		if coast_land_margin(position.x, position.z) > BEACH_DRIVE_DEPTH - 0.6 { continue }
		if !prop_clear_of_drive_lane(position.x, position.z, 0.18) { continue }

		pattern := item % 8
		if pattern == 0 {
			scale := 1.08 + scatter_unit(item * 71 + edge * 23) * 0.26
			yaw := scatter_signed(item * 113 + edge * 47) * 1.2
			add_destructible_prop(.PALM, position, scale, yaw, item % 4)
		} else if pattern == 1 || pattern == 5 {
			scale := 0.84 + scatter_unit(item * 79 + edge * 37) * 0.18
			add_destructible_prop(.UMBRELLA, position, scale, scatter_signed(item * 97 + edge) * 0.7, item % 4)
		} else {
			scale := 0.86 + scatter_unit(item * 67 + edge * 41) * 0.24
			add_destructible_prop(.LOUNGER, position, scale, scatter_signed(item * 107 + edge * 19) * 1.6, item % 4)
		}
	}
}

generate_beach_props :: proc() {
	generate_beach_edge_props(beach_edge, false)
	generate_beach_edge_props(beach_edge_secondary, true)
}

generate_destructible_props :: proc() {
	destructible_prop_count = 0
	generate_block_destructible_props()
	generate_beach_props()
	generate_inner_edge_tree_strip(city_edge(), false)
	generate_city_edge_roadside_trees()
	generate_mountain_cherry_props()
	generate_inner_edge_tree_strip(mountain_edge, true)
	generate_mountain_roadside_cherries()
	generate_riverfront_lamps()
}

draw_background_tree_simple :: proc(position: rl.Vector3, scale: f32, cherry: bool) {
	trunk := rl.Color{91, 62, 43, 255}
	crown := rl.Color{42, 108, 58, 255}
	if cherry { crown = {232, 142, 178, 255} }
	previous_active := world_visual_deform_active
	previous_anchor := world_visual_deform_anchor
	world_visual_deform_active = bounce_mode
	world_visual_deform_anchor = position
	rotation := prop_initial_rotation(0)
	draw_quat_box(position + rl.Vector3{0, 0.75 * scale, 0}, {0.15 * scale, 0.75 * scale, 0.15 * scale}, rotation, trunk)
	// Background forest used to spend hundreds of sphere tessellations per frame.
	// Chunky box canopies fit the low-poly style and squash/stretch cheaply too.
	draw_quat_box(position + rl.Vector3{0, 1.70 * scale, 0}, {0.66 * scale, 0.525 * scale, 0.61 * scale}, rotation, crown)
	if cherry {
		draw_quat_box(position + rl.Vector3{0.42 * scale, 1.60 * scale, 0.08 * scale}, {0.37 * scale, 0.31 * scale, 0.36 * scale}, rotation, {247, 174, 201, 255})
	}
	world_visual_deform_active = previous_active
	world_visual_deform_anchor = previous_anchor
}

draw_background_edge_forest :: proc(edge: int, cherry_mix: bool) {
	viewer := car_position()
	minimum, maximum := coast_sample_along_bounds_for_edge(edge)
	for row in 0..<5 {
		count := 22 + row * 5
		distance := 6.5 + f32(row) * 4.8
		for item in 0..<count {
			seed := edge * 1009 + row * 233 + item * 61
			t := (f32(item) + 0.25 + scatter_unit(seed + 7) * 0.5) / f32(count)
			along := lerp_f32(minimum + 1.0, maximum - 1.0, t)
			along += scatter_signed(seed + 29) * 2.0
			position := edge_outside_point(edge, along, distance + scatter_signed(seed + 53) * 1.8)
			if horizontal_distance(position, viewer) > 190.0 { continue }
			scale := 0.72 + scatter_unit(seed + 83) * 0.62
			cherry := cherry_mix && ((item + row) % 3 != 0)
			kind: Destructible_Prop_Type = .TREE
			if cherry { kind = .CHERRY }
			if !prop_clear_of_water(kind, position, scale) { continue }
			position.y = road_elevation_at(position.x, position.z)
			draw_background_tree_simple(position, scale, cherry)
		}
	}
}

draw_background_forests :: proc() {
	draw_background_edge_forest(city_edge(), false)
	draw_background_edge_forest(mountain_edge, true)
}

quat_rotate_v3 :: proc(rotation: b3.Quat, local: rl.Vector3) -> rl.Vector3 {
	return rotate_v3_quat(rotation, local)
}

prop_visual_center :: proc(prop: Destructible_Prop) -> rl.Vector3 {
	center := prop.initial_position
	if prop.dynamic_active {
		position := b3.Body_GetPosition(prop.body_id)
		center = {f32(position.x), f32(position.y), f32(position.z)}
	}
	center.y += road_elevation_at(center.x, center.z)
	return center
}

draw_quat_box :: proc(center, half: rl.Vector3, rotation: b3.Quat, color: rl.Color) {
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
	for index in 0..<8 {
		point := center + quat_rotate_v3(rotation, local[index])
		points[index] = world_visual_transform_point(point)
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
			color,
		)
	}
}

draw_tree_prop :: proc(center: rl.Vector3, rotation: b3.Quat, scale: f32, variant: int) {
	half := prop_half_extents(.TREE, scale)
	draw_quat_box(center, half, rotation, {86, 61, 42, 255})
	if bounce_mode {
		green := rl.Color{46, 116, 62, 255}
		if variant % 2 != 0 { green = {52, 126, 66, 255} }
		crown := center + quat_rotate_v3(rotation, {0, 1.62 * scale, 0})
		draw_quat_box(crown, {0.72 * scale, 0.58 * scale, 0.68 * scale}, rotation, green)
		return
	}
	green_a := rl.Color{46, 116, 62, 255}
	green_b := rl.Color{57, 132, 69, 255}
	green_c := rl.Color{38, 101, 55, 255}

	switch variant % 4 {
	case 0: // broad round crown
		rl.DrawSphere(center + quat_rotate_v3(rotation, {0, 1.58 * scale, 0}), 0.78 * scale, green_a)
		rl.DrawSphere(center + quat_rotate_v3(rotation, {0.42 * scale, 1.42 * scale, 0.06 * scale}), 0.52 * scale, green_b)
	case 1: // tall narrow tree
		rl.DrawSphere(center + quat_rotate_v3(rotation, {0, 1.48 * scale, 0}), 0.58 * scale, green_c)
		rl.DrawSphere(center + quat_rotate_v3(rotation, {0, 2.02 * scale, 0}), 0.50 * scale, green_a)
		rl.DrawSphere(center + quat_rotate_v3(rotation, {0.18 * scale, 1.75 * scale, 0}), 0.42 * scale, green_b)
	case 2: // low spreading canopy
		for crown in 0..<3 {
			x := -0.55 * scale + f32(crown) * 0.55 * scale
			z := 0.14 * scale
			if crown == 1 { z = -0.18 * scale }
			rl.DrawSphere(center + quat_rotate_v3(rotation, {x, 1.45 * scale, z}), 0.56 * scale, green_a)
		}
	case: // asymmetric old street tree
		rl.DrawSphere(center + quat_rotate_v3(rotation, {-0.30 * scale, 1.55 * scale, 0.10 * scale}), 0.68 * scale, green_c)
		rl.DrawSphere(center + quat_rotate_v3(rotation, {0.38 * scale, 1.72 * scale, -0.12 * scale}), 0.62 * scale, green_b)
		rl.DrawSphere(center + quat_rotate_v3(rotation, {0.08 * scale, 2.02 * scale, 0.16 * scale}), 0.46 * scale, green_a)
	}
}

draw_palm_prop :: proc(center: rl.Vector3, rotation: b3.Quat, scale: f32, variant: int) {
	trunk := rl.Color{112, 79, 47, 255}
	leaf := rl.Color{43, 120, 58, 255}
	if bounce_mode {
		half := prop_half_extents(.PALM, scale)
		draw_quat_box(center, half, rotation, trunk)
		crown := center + quat_rotate_v3(rotation, {0, 1.65 * scale, 0})
		draw_quat_box(crown, {0.78 * scale, 0.34 * scale, 0.78 * scale}, rotation, leaf)
		return
	}
	lean_sign: f32 = -1
	if variant % 2 != 0 { lean_sign = 1 }
	lean_x := (0.16 + f32(variant % 3) * 0.03) * scale * lean_sign
	lean_z := (0.07 + f32((variant + 1) % 3) * 0.02) * scale
	segment_height := 0.60 * scale
	base := center - quat_rotate_v3(rotation, {0, prop_half_extents(.PALM, scale).y, 0})
	for segment in 0..<5 {
		t := f32(segment) + 0.5
		offset := quat_rotate_v3(rotation, {lean_x * t, segment_height * t, lean_z * t})
		segment_center := base + offset
		draw_quat_box(segment_center, {0.14 * scale, segment_height * 0.50, 0.14 * scale}, rotation, trunk)
	}
	top := base + quat_rotate_v3(rotation, {lean_x * 5.2, segment_height * 5.05, lean_z * 5.2})
	rl.DrawSphere(top, 0.38 * scale, leaf)
	for frond in 0..<6 {
		x: f32 = 0
		z: f32 = 0
		if frond == 0 { x = 0.78 * scale }
		if frond == 1 { x = -0.78 * scale }
		if frond == 2 { z = 0.78 * scale }
		if frond == 3 { z = -0.78 * scale }
		if frond == 4 { x = 0.54 * scale; z = 0.54 * scale }
		if frond == 5 { x = -0.54 * scale; z = -0.54 * scale }
		rl.DrawSphere(top + quat_rotate_v3(rotation, {x, -0.05 * scale, z}), 0.31 * scale, leaf)
	}
}

draw_cherry_prop :: proc(center: rl.Vector3, rotation: b3.Quat, scale: f32, variant: int) {
	half := prop_half_extents(.CHERRY, scale)
	draw_quat_box(center, half, rotation, {91, 58, 48, 255})
	if bounce_mode {
		crown := center + quat_rotate_v3(rotation, {0, 1.28 * scale, 0})
		draw_quat_box(crown, {0.80 * scale, 0.62 * scale, 0.76 * scale}, rotation, {247, 163, 194, 255})
		return
	}
	pink_a := rl.Color{244, 149, 184, 255}
	pink_b := rl.Color{255, 190, 209, 255}
	spread := 0.32 + f32(variant % 3) * 0.07
	height_bias := f32((variant / 2) % 2) * 0.16
	offset_a := quat_rotate_v3(rotation, {-spread * scale, (1.04 + height_bias) * scale, 0})
	offset_b := quat_rotate_v3(rotation, {spread * scale, (1.08 + height_bias * 0.5) * scale, 0.08 * scale})
	offset_c := quat_rotate_v3(rotation, {0, (1.38 + height_bias) * scale, -0.18 * scale})
	rl.DrawSphere(center + offset_a, 0.70 * scale, pink_a)
	rl.DrawSphere(center + offset_b, 0.68 * scale, pink_b)
	rl.DrawSphere(center + offset_c, 0.72 * scale, pink_a)
}

draw_lamp_prop :: proc(center: rl.Vector3, rotation: b3.Quat, scale: f32, variant: int) {
	half := prop_half_extents(.LAMP, scale)
	metal := rl.Color{52, 57, 64, 255}
	light := rl.Color{255, 227, 147, 255}
	draw_quat_box(center, half, rotation, metal)

	if variant >= 100 {
		accent := rl.Color{72, 154, 184, 255}
		crown := center + quat_rotate_v3(rotation, {0, 1.52 * scale, 0})
		draw_quat_box(crown, {0.58 * scale, 0.06 * scale, 0.06 * scale}, rotation, metal)
		draw_quat_box(center + quat_rotate_v3(rotation, {0, 1.18 * scale, 0}), {0.10 * scale, 0.10 * scale, 0.10 * scale}, rotation, accent)
		for side in 0..<2 {
			sign: f32 = -1
			if side != 0 { sign = 1 }
			arm := center + quat_rotate_v3(rotation, {0.42 * scale * sign, 1.42 * scale, 0})
			draw_quat_box(arm, {0.20 * scale, 0.045 * scale, 0.045 * scale}, rotation, metal)
			head := center + quat_rotate_v3(rotation, {0.68 * scale * sign, 1.30 * scale, 0})
			draw_quat_box(head, {0.15 * scale, 0.10 * scale, 0.14 * scale}, rotation, light)
		}
		return
	}

	arm_center := center + quat_rotate_v3(rotation, {0.34 * scale, 1.42 * scale, 0})
	draw_quat_box(arm_center, {0.38 * scale, 0.055 * scale, 0.055 * scale}, rotation, metal)
	lamp_center := center + quat_rotate_v3(rotation, {0.72 * scale, 1.34 * scale, 0})
	draw_quat_box(lamp_center, {0.20 * scale, 0.10 * scale, 0.16 * scale}, rotation, light)
}

draw_umbrella_prop :: proc(center: rl.Vector3, rotation: b3.Quat, scale: f32, variant: int) {
	pole := rl.Color{109, 87, 60, 255}
	canopies := [4]rl.Color{
		{238, 78, 72, 255},
		{247, 207, 79, 255},
		{79, 181, 209, 255},
		{240, 130, 172, 255},
	}
	draw_quat_box(center, {0.055 * scale, 0.90 * scale, 0.055 * scale}, rotation, pole)
	canopy_center := center + quat_rotate_v3(rotation, {0, 0.72 * scale, 0})
	draw_quat_box(canopy_center, {0.78 * scale, 0.075 * scale, 0.78 * scale}, rotation, canopies[variant % 4])
	draw_quat_box(canopy_center + quat_rotate_v3(rotation, {0, 0.08 * scale, 0}), {0.34 * scale, 0.07 * scale, 0.34 * scale}, rotation, {246, 238, 210, 255})
}

draw_lounger_prop :: proc(center: rl.Vector3, rotation: b3.Quat, scale: f32, variant: int) {
	frame := rl.Color{225, 221, 205, 255}
	fabrics := [4]rl.Color{
		{65, 157, 190, 255}, {235, 102, 90, 255}, {242, 196, 74, 255}, {96, 174, 126, 255},
	}
	cloth := fabrics[variant % 4]
	draw_quat_box(center + quat_rotate_v3(rotation, {0, 0.08 * scale, 0}), {0.72 * scale, 0.07 * scale, 0.30 * scale}, rotation, frame)
	draw_quat_box(center + quat_rotate_v3(rotation, {0.06 * scale, 0.18 * scale, 0}), {0.58 * scale, 0.055 * scale, 0.27 * scale}, rotation, cloth)
	back := center + quat_rotate_v3(rotation, {-0.54 * scale, 0.40 * scale, 0})
	draw_quat_box(back, {0.28 * scale, 0.045 * scale, 0.27 * scale}, rotation, cloth)
	for leg in 0..<2 {
		sign: f32 = -1
		if leg != 0 { sign = 1 }
		leg_center := center + quat_rotate_v3(rotation, {0.42 * scale * sign, -0.10 * scale, 0})
		draw_quat_box(leg_center, {0.055 * scale, 0.14 * scale, 0.24 * scale}, rotation, frame)
	}
}

draw_destructible_prop_lod :: proc(prop: Destructible_Prop, center: rl.Vector3, rotation: b3.Quat) {
	switch prop.kind {
	case .TREE:
		half := prop_half_extents(.TREE, prop.scale)
		draw_quat_box(center, half, rotation, {86, 61, 42, 255})
		green := rl.Color{46, 116, 62, 255}
		if prop.variant % 2 != 0 { green = {52, 126, 66, 255} }
		crown := center + quat_rotate_v3(rotation, {0, 1.62 * prop.scale, 0})
		draw_quat_box(crown, {0.66 * prop.scale, 0.52 * prop.scale, 0.61 * prop.scale}, rotation, green)
	case .PALM:
		half := prop_half_extents(.PALM, prop.scale)
		draw_quat_box(center, half, rotation, {112, 79, 47, 255})
		crown := center + quat_rotate_v3(rotation, {0, 1.16 * prop.scale, 0})
		draw_quat_box(crown, {0.42 * prop.scale, 0.32 * prop.scale, 0.42 * prop.scale}, rotation, {46, 117, 57, 255})
	case .CHERRY:
		half := prop_half_extents(.CHERRY, prop.scale)
		draw_quat_box(center, half, rotation, {91, 58, 48, 255})
		crown := center + quat_rotate_v3(rotation, {0, 1.24 * prop.scale, 0})
		draw_quat_box(crown, {0.70 * prop.scale, 0.56 * prop.scale, 0.68 * prop.scale}, rotation, {247, 163, 194, 255})
	case .LAMP:
		half := prop_half_extents(.LAMP, prop.scale)
		draw_quat_box(center, half, rotation, {52, 57, 64, 255})
		if prop.variant >= 100 {
			left := center + quat_rotate_v3(rotation, {-0.30 * prop.scale, 1.40 * prop.scale, 0})
			right := center + quat_rotate_v3(rotation, {0.30 * prop.scale, 1.40 * prop.scale, 0})
			draw_quat_box(left, {0.12 * prop.scale, 0.07 * prop.scale, 0.10 * prop.scale}, rotation, {255, 227, 147, 255})
			draw_quat_box(right, {0.12 * prop.scale, 0.07 * prop.scale, 0.10 * prop.scale}, rotation, {255, 227, 147, 255})
		} else {
			lamp_center := center + quat_rotate_v3(rotation, {0.32 * prop.scale, 1.42 * prop.scale, 0})
			draw_quat_box(lamp_center, {0.18 * prop.scale, 0.08 * prop.scale, 0.12 * prop.scale}, rotation, {255, 227, 147, 255})
		}
	case .UMBRELLA:
		draw_umbrella_prop(center, rotation, prop.scale, prop.variant)
	case .LOUNGER:
		draw_lounger_prop(center, rotation, prop.scale, prop.variant)
	}
}

draw_destructible_prop_far_lod :: proc(prop: Destructible_Prop, center: rl.Vector3) {
	// Extremely cheap silhouettes keep vegetation present far ahead of a fast car.
	// At this distance rotation/fallen pose detail is irrelevant; avoiding pop-in is
	// more important than matching the full mesh exactly.
	switch prop.kind {
	case .TREE:
		draw_quat_box(center, {(0.34 * prop.scale) * 0.5, (1.35 * prop.scale) * 0.5, (0.34 * prop.scale) * 0.5}, prop_initial_rotation(0), {86, 61, 42, 255})
		draw_quat_box(center + rl.Vector3{0, 1.30 * prop.scale, 0}, {(1.28 * prop.scale) * 0.5, (0.90 * prop.scale) * 0.5, (1.18 * prop.scale) * 0.5}, prop_initial_rotation(0), {46, 116, 62, 255})
	case .CHERRY:
		draw_quat_box(center, {(0.34 * prop.scale) * 0.5, (1.42 * prop.scale) * 0.5, (0.34 * prop.scale) * 0.5}, prop_initial_rotation(0), {91, 58, 48, 255})
		draw_quat_box(center + rl.Vector3{0, 1.28 * prop.scale, 0}, {(1.35 * prop.scale) * 0.5, (0.92 * prop.scale) * 0.5, (1.28 * prop.scale) * 0.5}, prop_initial_rotation(0), {244, 159, 190, 255})
	case .PALM:
		draw_quat_box(center, {(0.26 * prop.scale) * 0.5, (2.45 * prop.scale) * 0.5, (0.26 * prop.scale) * 0.5}, prop_initial_rotation(0), {112, 79, 47, 255})
		draw_quat_box(center + rl.Vector3{0, 1.95 * prop.scale, 0}, {(1.20 * prop.scale) * 0.5, (0.48 * prop.scale) * 0.5, (1.20 * prop.scale) * 0.5}, prop_initial_rotation(0), {43, 120, 58, 255})
	case .LAMP:
		draw_quat_box(center, {(0.16 * prop.scale) * 0.5, (2.80 * prop.scale) * 0.5, (0.16 * prop.scale) * 0.5}, prop_initial_rotation(0), {52, 57, 64, 255})
	case .UMBRELLA:
		draw_quat_box(center + rl.Vector3{0, 0.55 * prop.scale, 0}, {(1.25 * prop.scale) * 0.5, (0.12 * prop.scale) * 0.5, (1.25 * prop.scale) * 0.5}, prop_initial_rotation(0), {238, 120, 110, 255})
	case .LOUNGER:
		draw_quat_box(center, {(1.15 * prop.scale) * 0.5, (0.18 * prop.scale) * 0.5, (0.55 * prop.scale) * 0.5}, prop_initial_rotation(0), {225, 221, 205, 255})
	}
}

draw_destructible_props :: proc() {
	viewer := car_position()
	for index in 0..<destructible_prop_count {
		prop := destructible_props[index]
		if !b3.Body_IsValid(prop.body_id) {
			continue
		}

		rough := prop.initial_position
		if prop.dynamic_active {
			position := b3.Body_GetPosition(prop.body_id)
			rough = {f32(position.x), f32(position.y), f32(position.z)}
		}
		dx := rough.x - viewer.x
		dz := rough.z - viewer.z
		distance_sq := dx * dx + dz * dz
		visible_radius: f32 = 105.0
		if prop.kind == .TREE || prop.kind == .CHERRY || prop.kind == .PALM {
			visible_radius = 165.0
		} else if prop.kind == .LAMP {
			visible_radius = 120.0
		}
		if distance_sq > visible_radius * visible_radius {
			continue
		}

		center := prop_visual_center(prop)
		rotation := prop_initial_rotation(prop.initial_yaw)
		if prop.dynamic_active {
			rotation = b3.Body_GetRotation(prop.body_id)
		}

		previous_active := world_visual_deform_active
		previous_anchor := world_visual_deform_anchor
		world_visual_deform_active = bounce_mode
		world_visual_deform_anchor = center - rl.Vector3{0, prop_half_extents(prop.kind, prop.scale).y, 0}

		// Three-level visual LOD. Far vegetation stays visible long before the car
		// arrives, while only near objects pay for spheres and detailed geometry.
		if distance_sq > 62.0 * 62.0 {
			draw_destructible_prop_far_lod(prop, center)
		} else if distance_sq > 30.0 * 30.0 {
			draw_destructible_prop_lod(prop, center, rotation)
		} else {
			switch prop.kind {
			case .TREE:
				draw_tree_prop(center, rotation, prop.scale, prop.variant)
			case .PALM:
				draw_palm_prop(center, rotation, prop.scale, prop.variant)
			case .CHERRY:
				draw_cherry_prop(center, rotation, prop.scale, prop.variant)
			case .LAMP:
				draw_lamp_prop(center, rotation, prop.scale, prop.variant)
			case .UMBRELLA:
				draw_umbrella_prop(center, rotation, prop.scale, prop.variant)
			case .LOUNGER:
				draw_lounger_prop(center, rotation, prop.scale, prop.variant)
			}
		}
		world_visual_deform_active = previous_active
		world_visual_deform_anchor = previous_anchor
	}
}

