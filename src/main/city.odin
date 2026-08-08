package main

import rl "vendor:raylib"
import b3 "vendor:box3d"
import "core:math"

ROUTE_POINT_MAX :: MAX_ROUTE_STEPS + 2
GRID_NODE_COUNT :: ROAD_X_COUNT * ROAD_Z_COUNT

Route_Segment_Candidate :: struct {
	valid:          bool,
	step_count:     int,
	target_x:       int,
	target_z:       int,
	next_direction: int,
	score:          int,
}

CHECKPOINTS: [MAX_CHECKPOINT_COUNT]Checkpoint
ROUTE_POINTS: [ROUTE_POINT_MAX]rl.Vector3
route_point_count := 0

route_grid_points: [MAX_ROUTE_STEPS + 1]rl.Vector3
route_step_directions: [MAX_ROUTE_STEPS]int
route_gate_end_steps: [MAX_CHECKPOINT_COUNT]int
route_segment_steps: [MAX_CHECKPOINT_COUNT]int
route_node_visits: [GRID_NODE_COUNT]int
route_edge_visits: [GRID_NODE_COUNT][4]int

// The balanced planner fixes all segment lengths before choosing turns.
route_length_completion_memo: [MAX_CHECKPOINT_COUNT + 1][GRID_NODE_COUNT][4]i8
route_max_turn_steps_memo: [MAX_CHECKPOINT_COUNT + 1][GRID_NODE_COUNT][4]int
route_max_turn_steps_memo_ready := false
route_completion_memo: [MAX_CHECKPOINT_COUNT + 1][GRID_NODE_COUNT][4][MAX_ROUTE_STEPS + 1]i8

map_zone_color :: proc(zone: Map_Zone, alpha: u8 = 255) -> rl.Color {
	#partial switch zone {
	case .COMMERCIAL: return {74, 92, 120, alpha}
	case .CHINATOWN:  return {128, 62, 58, alpha}
	case .INDUSTRIAL: return {92, 82, 70, alpha}
	case .RESORT:     return {116, 101, 74, alpha}
	case .PARK:       return {54, 104, 67, alpha}
	case .RIVER:      return {42, 112, 158, alpha}
	}
	return {78, 91, 78, alpha}
}

MOUNTAIN_SLOPE_DEPTH      :: f32(54.0)
MOUNTAIN_MAX_ROAD_HEIGHT :: f32(5.4)
GATE_APPROACH_OFFSET      :: f32(4.8)
RIVER_HALF_WIDTH          :: f32(5.6)
RIVER_BANK_HALF_WIDTH     :: f32(0.34)
RIVER_BANK_HALF_HEIGHT    :: f32(0.48)
RIVER_RAIL_POST_SPACING   :: f32(2.8)
RIVER_RAIL_BASE_HEIGHT    :: f32(0.24)
RIVER_RAIL_POST_HEIGHT    :: f32(1.02)
NORMAL_BRIDGE_HALF_LENGTH  :: f32(7.6)
// Slightly enlarge the bank notch around every bridge so the approach stays
// fully driveable instead of leaving a tiny snagging lip at the bridge mouth.
BRIDGE_ENTRANCE_NOTCH_PADDING :: f32(1.2)
// Pull side rails/barriers back a little from each bridge end so the car does
// not catch an end cap while lining up for the crossing.
BRIDGE_SIDE_BARRIER_END_INSET :: f32(0.45)
CITY_OUTSKIRTS_DEPTH          :: f32(64.0)
CITY_EDGE_ROAD_EXTENSION_LENGTH :: f32(18.0)
CITY_EDGE_BARRIER_OFFSET      :: f32(8.5)
CITY_EDGE_BARRIER_HALF_SPAN   :: f32(4.3)
CITY_EDGE_BARRIER_HALF_THICKNESS :: f32(0.18)
CITY_EDGE_SHOULDER_BLOCK_HALF_WIDTH :: f32(1.55)
CITY_EDGE_SHOULDER_CLEARANCE        :: f32(0.42)
JUMP_BRIDGE_HALF_GAP       :: f32(2.7)
JUMP_BRIDGE_RAMP_LENGTH    :: f32(8.2)
JUMP_BRIDGE_BASE_HEIGHT    :: f32(0.01)
JUMP_BRIDGE_PEAK_HEIGHT    :: f32(0.92)

BEACH_SAND_COLOR        :: rl.Color{207, 184, 126, 255}
BEACH_TRACK_COLOR       :: rl.Color{174, 148, 94, 185}
COAST_PROMENADE_DEPTH   :: f32(10.0)
PARK_ROAD_COLOR         :: rl.Color{105, 101, 86, 255}
SEA_COLOR               :: rl.Color{24, 92, 145, 255}
JUMP_BRIDGE_RAMP_BOTTOM    :: f32(-0.55)

mountain_inward_distance :: proc(x, z: f32) -> f32 {
	switch mountain_edge {
	case 0: return z - CITY_MIN_Z
	case 1: return CITY_MAX_X - x
	case 2: return CITY_MAX_Z - z
	case:   return x - CITY_MIN_X
	}
}

mountain_height_for_distance :: proc(distance: f32) -> f32 {
	t := clamp(1.0 - distance / MOUNTAIN_SLOPE_DEPTH, 0.0, 1.0)
	// Smoothstep keeps the transition flat where the foothill rejoins the city.
	t = t * t * (3.0 - 2.0 * t)
	return t * MOUNTAIN_MAX_ROAD_HEIGHT
}

road_elevation_at :: proc(x, z: f32) -> f32 {
	// Gameplay physics uses one flat city plane. Older builds visually lifted roads
	// near Mt. Fuji without lifting the Box3D floor, creating floating streets the car
	// could drive underneath. Keep ordinary roads, blocks and route markers at ground
	// level; the mountain itself remains a separate off-map landmark.
	_ = x
	_ = z
	return 0.0
}

River_Cell :: struct {
	x: int,
	z: int,
}

River_Crossing :: struct {
	ix:        int,
	iz:        int,
	direction: int,
	bridge:    Bridge_Type,
}

river_path: [RIVER_PATH_MAX]River_Cell
river_path_count := 0
river_crossings: [RIVER_CROSSING_MAX]River_Crossing
river_crossing_count := 0
river_entry_bridge: River_Crossing
river_entry_bridge_valid := false
river_exit_bridge: River_Crossing
river_exit_bridge_valid := false
beach_river_bridge_index := -1
river_edge_crossed: [ROAD_X_COUNT][ROAD_Z_COUNT][4]bool
river_edge_bridge: [ROAD_X_COUNT][ROAD_Z_COUNT][4]Bridge_Type

coast_sample_count_for_edge :: proc(edge: int) -> int {
	if edge == 0 || edge == 2 {
		return (ROAD_X_COUNT - 1) * 2 + 1
	}
	return (ROAD_Z_COUNT - 1) * 2 + 1
}

coast_sample_along_bounds_for_edge :: proc(edge: int) -> (minimum, maximum: f32) {
	if edge == 0 || edge == 2 {
		return CITY_MIN_X, CITY_MAX_X
	}
	return CITY_MIN_Z, CITY_MAX_Z
}

coast_profile_count :: proc(secondary: bool) -> int {
	if secondary {
		return coast_sample_count_secondary
	}
	return coast_sample_count
}

coast_profile_inset :: proc(secondary: bool, sample: int) -> f32 {
	if secondary {
		return coast_insets_secondary[sample]
	}
	return coast_insets[sample]
}

set_coast_profile_inset :: proc(secondary: bool, sample: int, value: f32) {
	if secondary {
		coast_insets_secondary[sample] = value
	} else {
		coast_insets[sample] = value
	}
}

coast_inset_at_along_for_edge :: proc(edge: int, along: f32) -> f32 {
	secondary := edge == beach_edge_secondary
	count := coast_profile_count(secondary)
	if count <= 1 {
		return coast_profile_inset(secondary, 0)
	}
	minimum, maximum := coast_sample_along_bounds_for_edge(edge)
	ratio := clamp((along - minimum) / (maximum - minimum), 0.0, 1.0)
	position := ratio * f32(count - 1)
	lower := int(position)
	if lower >= count - 1 {
		return coast_profile_inset(secondary, count - 1)
	}
	fraction := position - f32(lower)
	return lerp_f32(
		coast_profile_inset(secondary, lower),
		coast_profile_inset(secondary, lower + 1),
		fraction,
	)
}

coast_inset_at_along :: proc(along: f32) -> f32 {
	return coast_inset_at_along_for_edge(beach_edge, along)
}

coast_inward_distance_for_edge :: proc(edge: int, x, z: f32) -> f32 {
	switch edge {
	case 0: return z - CITY_MIN_Z
	case 1: return CITY_MAX_X - x
	case 2: return CITY_MAX_Z - z
	case:   return x - CITY_MIN_X
	}
}

coast_inward_distance :: proc(x, z: f32) -> f32 {
	return coast_inward_distance_for_edge(beach_edge, x, z)
}

coast_land_for_edge :: proc(edge: int, x, z: f32) -> bool {
	along := x
	if edge == 1 || edge == 3 {
		along = z
	}
	return coast_inward_distance_for_edge(edge, x, z) >= coast_inset_at_along_for_edge(edge, along)
}

coast_shared_corner_position :: proc() -> rl.Vector3 {
	x := CITY_MIN_X
	z := CITY_MIN_Z
	if beach_edge == 1 || beach_edge_secondary == 1 { x = CITY_MAX_X }
	if beach_edge == 2 || beach_edge_secondary == 2 { z = CITY_MAX_Z }
	return {x, 0, z}
}

coast_corner_inset_for_edge :: proc(edge: int) -> f32 {
	secondary := edge == beach_edge_secondary
	count := coast_profile_count(secondary)
	index := 0
	if coast_edge_corner_sample_is_max(edge) {
		index = count - 1
	}
	return coast_profile_inset(secondary, index)
}

coast_other_beach_edge :: proc(edge: int) -> int {
	if edge == beach_edge {
		return beach_edge_secondary
	}
	return beach_edge
}

coast_corner_cutoff_for_edge :: proc(edge: int) -> f32 {
	other_edge := coast_other_beach_edge(edge)
	return coast_corner_inset_for_edge(other_edge) + COAST_CORNER_RADIUS
}

coast_corner_endpoint_for_edge :: proc(edge: int, secondary: bool) -> rl.Vector3 {
	_ = secondary
	corner := coast_shared_corner_position()
	other_edge := coast_other_beach_edge(edge)
	return corner +
	       coast_inward_vector_for_edge(edge) * coast_corner_inset_for_edge(edge) +
	       coast_inward_vector_for_edge(other_edge) * coast_corner_cutoff_for_edge(edge)
}

coast_corner_curve_point :: proc(segment: int, inward_offset: f32 = 0.0) -> rl.Vector3 {
	// All shoreline-parallel corner curves share one centre. Offsetting toward
	// land shrinks the radius; offsetting toward sea grows it. Moving the centre
	// itself (the old implementation) made the sand and sea arcs non-parallel and
	// created the triangular gaps visible at the shared beach corner.
	corner := coast_shared_corner_position()
	primary_inward := coast_inward_vector_for_edge(beach_edge)
	secondary_inward := coast_inward_vector_for_edge(beach_edge_secondary)
	primary_inset := coast_corner_inset_for_edge(beach_edge)
	secondary_inset := coast_corner_inset_for_edge(beach_edge_secondary)
	radius := COAST_CORNER_RADIUS - inward_offset

	center := corner +
	          primary_inward * (primary_inset + COAST_CORNER_RADIUS) +
	          secondary_inward * (secondary_inset + COAST_CORNER_RADIUS)
	t := f32(segment) / f32(COAST_CORNER_SEGMENTS)
	angle := rl.PI + t * rl.PI * 0.5
	return center +
	       primary_inward * (math.cos(angle) * radius) +
	       secondary_inward * (math.sin(angle) * radius)
}

coast_land_margin :: proc(x, z: f32) -> f32 {
	primary_along := x
	if beach_edge == 1 || beach_edge == 3 {
		primary_along = z
	}
	secondary_along := x
	if beach_edge_secondary == 1 || beach_edge_secondary == 3 {
		secondary_along = z
	}

	primary_margin :=
		coast_inward_distance_for_edge(beach_edge, x, z) -
		coast_inset_at_along_for_edge(beach_edge, primary_along)
	secondary_margin :=
		coast_inward_distance_for_edge(beach_edge_secondary, x, z) -
		coast_inset_at_along_for_edge(beach_edge_secondary, secondary_along)
	margin := min(primary_margin, secondary_margin)

	// The ordinary intersection above creates a hard 90-degree land corner.
	// Inside the shared corner square, replace that tip with the exact same
	// quarter-circle used by the visible shoreline and waterline colliders.
	primary_distance := coast_inward_distance_for_edge(beach_edge, x, z)
	secondary_distance := coast_inward_distance_for_edge(beach_edge_secondary, x, z)
	primary_inset := coast_corner_inset_for_edge(beach_edge)
	secondary_inset := coast_corner_inset_for_edge(beach_edge_secondary)
	center_primary := primary_inset + COAST_CORNER_RADIUS
	center_secondary := secondary_inset + COAST_CORNER_RADIUS
	if primary_distance < center_primary && secondary_distance < center_secondary {
		dp := primary_distance - center_primary
		ds := secondary_distance - center_secondary
		radial_margin := COAST_CORNER_RADIUS - math.sqrt(dp * dp + ds * ds)
		margin = min(margin, radial_margin)
	}

	return margin
}

coast_world_land_with_padding :: proc(x, z, padding: f32) -> bool {
	return coast_land_margin(x, z) >= padding
}

coast_world_land :: proc(x, z: f32) -> bool {
	return coast_land_margin(x, z) >= 0.0
}

coast_edge_corner_sample_is_max :: proc(edge: int) -> bool {
	corner := coast_shared_corner_position()
	if edge == 0 || edge == 2 {
		return corner.x == CITY_MAX_X
	}
	return corner.z == CITY_MAX_Z
}

smooth_coast_profile :: proc(secondary: bool) {
	count := coast_profile_count(secondary)
	for _ in 0..<2 {
		temp: [COAST_SAMPLE_MAX]f32
		for sample in 0..<count {
			if sample == 0 || sample == count - 1 {
				temp[sample] = coast_profile_inset(secondary, sample)
			} else {
				temp[sample] =
					(coast_profile_inset(secondary, sample - 1) +
					 coast_profile_inset(secondary, sample) * 2.0 +
					 coast_profile_inset(secondary, sample + 1)) * 0.25
			}
		}
		for sample in 0..<count {
			set_coast_profile_inset(secondary, sample, temp[sample])
		}
	}
}

smooth_coast_profile_into_corner :: proc(edge: int, secondary: bool) {
	count := coast_profile_count(secondary)
	blend_count := min(COAST_CORNER_BLEND_SAMPLES, count)
	flat_count := min(COAST_CORNER_FLAT_SAMPLES, blend_count)
	corner_at_max := coast_edge_corner_sample_is_max(edge)

	corner_index := 0
	if corner_at_max { corner_index = count - 1 }
	target := min(coast_profile_inset(secondary, corner_index), COAST_CORNER_INSET_MAX)
	target = max(target, 2.5)

	for offset in 0..<blend_count {
		index := offset
		if corner_at_max {
			index = count - 1 - offset
		}

		current := coast_profile_inset(secondary, index)
		if offset < flat_count {
			set_coast_profile_inset(secondary, index, target)
			continue
		}

		denominator := max(blend_count - flat_count, 1)
		u := f32(offset - flat_count + 1) / f32(denominator)
		u = clamp(u, 0.0, 1.0)
		smooth := u * u * (3.0 - 2.0 * u)
		set_coast_profile_inset(secondary, index, lerp_f32(target, current, smooth))
	}
}

generate_coastline_profile :: proc(edge: int, secondary: bool) {
	count := coast_sample_count_for_edge(edge)
	if secondary {
		coast_sample_count_secondary = count
	} else {
		coast_sample_count = count
	}

	base := f32(rl.GetRandomValue(2, 7))
	for sample in 0..<count {
		value := base + f32(rl.GetRandomValue(-2, 2)) * 0.45
		set_coast_profile_inset(secondary, sample, value)
	}

	// One or two broad bays carve each beach inward. Because coast_world_land()
	// intersects both profiles, the two beaches can form a large irregular bay corner.
	bay_count := int(rl.GetRandomValue(1, 2))
	for bay in 0..<bay_count {
		center := int(rl.GetRandomValue(2, i32(count - 3)))
		radius := int(rl.GetRandomValue(3, 7))
		depth := f32(rl.GetRandomValue(13, 28))
		for sample in 0..<count {
			distance := route_abs_int(sample - center)
			if distance > radius {
				continue
			}
			weight := 1.0 - f32(distance) / f32(radius + 1)
			value := coast_profile_inset(secondary, sample) + depth * weight
			set_coast_profile_inset(secondary, sample, value)
		}
	}

	for sample in 0..<count {
		value := clamp(coast_profile_inset(secondary, sample), 1.5, 31.0)
		set_coast_profile_inset(secondary, sample, value)
	}
}

generate_coastline :: proc() {
	generate_coastline_profile(beach_edge, false)
	generate_coastline_profile(beach_edge_secondary, true)
	smooth_coast_profile(false)
	smooth_coast_profile(true)
	smooth_coast_profile_into_corner(beach_edge, false)
	smooth_coast_profile_into_corner(beach_edge_secondary, true)
}

refresh_road_node_land :: proc() {
	for x in 0..<ROAD_X_COUNT {
		for z in 0..<ROAD_Z_COUNT {
			world_x := ROAD_ORIGIN_X + f32(x) * ROAD_SPACING
			world_z := ROAD_ORIGIN_Z + f32(z) * ROAD_SPACING
			road_node_land[x][z] = coast_world_land_with_padding(world_x, world_z, COAST_ROAD_CLEARANCE)
		}
	}
}

river_cell_in_path :: proc(x, z: int) -> bool {
	for index in 0..<river_path_count {
		if river_path[index].x == x && river_path[index].z == z {
			return true
		}
	}
	return false
}

append_river_cell :: proc(x, z: int) {
	if river_path_count >= RIVER_PATH_MAX {
		return
	}
	if river_path_count > 0 {
		last := river_path[river_path_count - 1]
		if last.x == x && last.z == z {
			return
		}
	}
	river_path[river_path_count] = {x = x, z = z}
	river_path_count += 1
}

clear_river_crossing_data :: proc() {
	river_crossing_count = 0
	river_entry_bridge_valid = false
	river_exit_bridge_valid = false
	beach_river_bridge_index = -1
	for x in 0..<ROAD_X_COUNT {
		for z in 0..<ROAD_Z_COUNT {
			for direction in 0..<4 {
				river_edge_crossed[x][z][direction] = false
				river_edge_bridge[x][z][direction] = .NONE
			}
		}
	}
}

register_river_crossing :: proc(ix, iz, direction: int) {
	if river_crossing_count >= RIVER_CROSSING_MAX {
		return
	}
	river_crossings[river_crossing_count] = {
		ix = ix,
		iz = iz,
		direction = direction,
		bridge = .NONE,
	}
	river_crossing_count += 1

	next_x := ix + route_direction_dx(direction)
	next_z := iz + route_direction_dz(direction)
	if ix >= 0 && ix < ROAD_X_COUNT && iz >= 0 && iz < ROAD_Z_COUNT &&
	   next_x >= 0 && next_x < ROAD_X_COUNT && next_z >= 0 && next_z < ROAD_Z_COUNT {
		river_edge_crossed[ix][iz][direction] = true
		river_edge_crossed[next_x][next_z][route_opposite_direction(direction)] = true
	}
}

build_river_crossings :: proc() {
	clear_river_crossing_data()
	for index in 1..<river_path_count {
		from := river_path[index - 1]
		to := river_path[index]
		if to.x > from.x {
			// River moves east through the vertical street at road x = to.x.
			register_river_crossing(to.x, from.z, 2)
		} else if to.x < from.x {
			register_river_crossing(from.x, from.z, 2)
		} else if to.z > from.z {
			// River moves south through the horizontal street at road z = to.z.
			register_river_crossing(from.x, to.z, 1)
		} else if to.z < from.z {
			register_river_crossing(from.x, from.z, 1)
		}
	}
}

// The river enters from the Mt. Fuji side before reaching its first block center.
// That short entry segment crosses the outermost city street, so treat it as a
// real normal bridge instead of letting the road pass through a decorative rail.
configure_river_entry_bridge :: proc() {
	river_entry_bridge_valid = false
	if river_path_count <= 0 { return }

	cell := river_path[0]
	crossing := River_Crossing{bridge = .NORMAL}
	switch river_entry_edge {
	case 0:
		crossing.ix = cell.x
		crossing.iz = 0
		crossing.direction = 1
	case 1:
		crossing.ix = ROAD_X_COUNT - 1
		crossing.iz = cell.z
		crossing.direction = 2
	case 2:
		crossing.ix = cell.x
		crossing.iz = ROAD_Z_COUNT - 1
		crossing.direction = 1
	case:
		crossing.ix = 0
		crossing.iz = cell.z
		crossing.direction = 2
	}

	next_x := crossing.ix + route_direction_dx(crossing.direction)
	next_z := crossing.iz + route_direction_dz(crossing.direction)
	if !route_grid_valid(crossing.ix, crossing.iz) || !route_grid_valid(next_x, next_z) {
		return
	}

	river_entry_bridge = crossing
	river_entry_bridge_valid = true
	river_edge_crossed[crossing.ix][crossing.iz][crossing.direction] = true
	river_edge_bridge[crossing.ix][crossing.iz][crossing.direction] = .NORMAL
	opposite := route_opposite_direction(crossing.direction)
	river_edge_crossed[next_x][next_z][opposite] = true
	river_edge_bridge[next_x][next_z][opposite] = .NORMAL
}

// The beach-side river tail ends at the generated shoreline, so its midpoint is
// not generally the outer road. When that outer road still exists on land, give
// the exact road/river intersection its own normal bridge instead of letting the
// final river-bank collider cut straight across a perfectly valid street.
configure_river_exit_bridge :: proc() {
	river_exit_bridge_valid = false
	if river_path_count <= 0 { return }

	cell := river_path[river_path_count - 1]
	crossing := River_Crossing{bridge = .NORMAL}
	switch river_exit_edge {
	case 0:
		crossing.ix = cell.x
		crossing.iz = 0
		crossing.direction = 1
	case 1:
		crossing.ix = ROAD_X_COUNT - 1
		crossing.iz = cell.z
		crossing.direction = 2
	case 2:
		crossing.ix = cell.x
		crossing.iz = ROAD_Z_COUNT - 1
		crossing.direction = 1
	case:
		crossing.ix = 0
		crossing.iz = cell.z
		crossing.direction = 2
	}

	next_x := crossing.ix + route_direction_dx(crossing.direction)
	next_z := crossing.iz + route_direction_dz(crossing.direction)
	if !route_grid_valid(crossing.ix, crossing.iz) || !route_grid_valid(next_x, next_z) {
		return
	}

	river_exit_bridge = crossing
	river_exit_bridge_valid = true
	river_edge_crossed[crossing.ix][crossing.iz][crossing.direction] = true
	river_edge_bridge[crossing.ix][crossing.iz][crossing.direction] = .NORMAL
	opposite := route_opposite_direction(crossing.direction)
	river_edge_crossed[next_x][next_z][opposite] = true
	river_edge_bridge[next_x][next_z][opposite] = .NORMAL
}

// Near the beach, always keep one usable street crossing over the river. The
// coastline can move far inland, so using the literal outermost map road is not
// reliable; instead choose the river crossing nearest the sea that still lies on
// valid land and force it to be a normal bridge.
configure_beach_river_bridge :: proc() {
	beach_river_bridge_index = -1
	// If the true outer beach road survives the coastline cut, the exit bridge is
	// already the closest possible crossing. Only fall back to an inland crossing
	// when a deep bay has removed that outer road entirely.
	if river_exit_bridge_valid { return }
	for offset in 0..<river_crossing_count {
		index := river_crossing_count - 1 - offset
		crossing := river_crossings[index]
		if !river_crossing_route_land(crossing) { continue }
		set_crossing_bridge(index, .NORMAL)
		beach_river_bridge_index = index
		return
	}
}

set_crossing_bridge :: proc(index: int, bridge: Bridge_Type) {
	if index < 0 || index >= river_crossing_count {
		return
	}
	crossing := &river_crossings[index]
	crossing.bridge = bridge
	river_edge_bridge[crossing.ix][crossing.iz][crossing.direction] = bridge
	next_x := crossing.ix + route_direction_dx(crossing.direction)
	next_z := crossing.iz + route_direction_dz(crossing.direction)
	river_edge_bridge[next_x][next_z][route_opposite_direction(crossing.direction)] = bridge
}

river_crossing_route_land :: proc(crossing: River_Crossing) -> bool {
	next_x := crossing.ix + route_direction_dx(crossing.direction)
	next_z := crossing.iz + route_direction_dz(crossing.direction)
	return route_grid_valid(crossing.ix, crossing.iz) && route_grid_valid(next_x, next_z)
}

assign_river_bridges :: proc() {
	if river_crossing_count <= 0 {
		return
	}
	bridge_target := clamp(river_crossing_count / 3, 5, 9)
	bridge_target = min(bridge_target, river_crossing_count)
	bridges_added := 0
	jump_added := 0
	for attempt in 0..<(river_crossing_count * 8 + 32) {
		if bridges_added >= bridge_target {
			break
		}
		index := int(rl.GetRandomValue(0, i32(river_crossing_count - 1)))
		if river_crossings[index].bridge != .NONE {
			continue
		}
		crossing := river_crossings[index]
		if !river_crossing_route_land(crossing) { continue }
		center := river_crossing_world_center(crossing)
		bridge: Bridge_Type = .NORMAL
		can_jump := road_elevation_at(center.x, center.z) < 0.12
		if can_jump && jump_added < 3 && rl.GetRandomValue(0, 99) < 34 {
			bridge = .JUMP
			jump_added += 1
		}
		set_crossing_bridge(index, bridge)
		bridges_added += 1
	}

	if jump_added == 0 {
		for index in 0..<river_crossing_count {
			if index == beach_river_bridge_index { continue }
			if river_crossings[index].bridge != .NORMAL || !river_crossing_route_land(river_crossings[index]) {
				continue
			}
			center := river_crossing_world_center(river_crossings[index])
			if road_elevation_at(center.x, center.z) < 0.12 {
				set_crossing_bridge(index, .JUMP)
				break
			}
		}
	}
}

generate_river_path :: proc() {
	river_path_count = 0
	// Keep the river meandering through the middle of the city. Its perpendicular
	// coordinate stays inside a central band, so the water divides the urban area
	// into two useful halves instead of hugging an outer boundary.
	river_exit_edge = beach_edge
	river_entry_edge = (beach_edge + 2) % 4

	if river_exit_edge == 0 || river_exit_edge == 2 {
		z_step := 1
		current_z := 0
		if river_exit_edge == 0 {
			z_step = -1
			current_z = BLOCK_Z_COUNT - 1
		}
		center_x := BLOCK_X_COUNT / 2
		band_min := max(1, center_x - 2)
		band_max := min(BLOCK_X_COUNT - 2, center_x + 2)
		current_x := int(rl.GetRandomValue(i32(band_min), i32(band_max)))
		append_river_cell(current_x, current_z)
		for row in 0..<(BLOCK_Z_COUNT - 1) {
			drift := int(rl.GetRandomValue(-2, 2))
			if current_x < center_x - 1 { drift = max(drift, 0) }
			if current_x > center_x + 1 { drift = min(drift, 0) }
			target_x := clamp(current_x + drift, band_min, band_max)
			for current_x != target_x {
				if current_x < target_x { current_x += 1 } else { current_x -= 1 }
				append_river_cell(current_x, current_z)
			}
			current_z += z_step
			append_river_cell(current_x, current_z)
		}
	} else {
		x_step := 1
		current_x := 0
		if river_exit_edge == 3 {
			x_step = -1
			current_x = BLOCK_X_COUNT - 1
		}
		center_z := BLOCK_Z_COUNT / 2
		band_min := max(1, center_z - 2)
		band_max := min(BLOCK_Z_COUNT - 2, center_z + 2)
		current_z := int(rl.GetRandomValue(i32(band_min), i32(band_max)))
		append_river_cell(current_x, current_z)
		for column in 0..<(BLOCK_X_COUNT - 1) {
			drift := int(rl.GetRandomValue(-2, 2))
			if current_z < center_z - 1 { drift = max(drift, 0) }
			if current_z > center_z + 1 { drift = min(drift, 0) }
			target_z := clamp(current_z + drift, band_min, band_max)
			for current_z != target_z {
				if current_z < target_z { current_z += 1 } else { current_z -= 1 }
				append_river_cell(current_x, current_z)
			}
			current_x += x_step
			append_river_cell(current_x, current_z)
		}
	}
	build_river_crossings()
	configure_river_entry_bridge()
	configure_river_exit_bridge()
	configure_beach_river_bridge()
	assign_river_bridges()
}

river_cell_world_center :: proc(cell: River_Cell) -> rl.Vector3 {
	return {
		ROAD_ORIGIN_X + (f32(cell.x) + 0.5) * ROAD_SPACING,
		0,
		ROAD_ORIGIN_Z + (f32(cell.z) + 0.5) * ROAD_SPACING,
	}
}

river_crossing_world_center :: proc(crossing: River_Crossing) -> rl.Vector3 {
	start := route_grid_position(crossing.ix, crossing.iz)
	finish := route_grid_position(
		crossing.ix + route_direction_dx(crossing.direction),
		crossing.iz + route_direction_dz(crossing.direction),
	)
	return (start + finish) * 0.5
}

// Unit vector along the road that crosses the river. Keeping this helper in
// city.odin makes the same crossing orientation available to gameplay, HUD,
// and bridge rendering without duplicating direction logic.
crossing_road_axis :: proc(crossing: River_Crossing) -> rl.Vector3 {
	return {
		f32(route_direction_dx(crossing.direction)),
		0,
		f32(route_direction_dz(crossing.direction)),
	}
}

point_segment_distance_sq_xz :: proc(point, start, finish: rl.Vector3) -> f32 {
	delta := finish - start
	length_sq := delta.x * delta.x + delta.z * delta.z
	if length_sq <= 0.0001 {
		dx := point.x - start.x
		dz := point.z - start.z
		return dx * dx + dz * dz
	}
	t := ((point.x - start.x) * delta.x + (point.z - start.z) * delta.z) / length_sq
	t = clamp(t, 0.0, 1.0)
	closest_x := start.x + delta.x * t
	closest_z := start.z + delta.z * t
	dx := point.x - closest_x
	dz := point.z - closest_z
	return dx * dx + dz * dz
}

point_inside_river_water :: proc(x, z: f32) -> bool {
	if river_path_count <= 0 { return false }
	point := rl.Vector3{x, 0, z}
	point_count := river_path_count + 2
	limit_sq := RIVER_HALF_WIDTH * RIVER_HALF_WIDTH
	for segment_index in 0..<(point_count - 1) {
		start := river_centerline_point(segment_index)
		finish := river_centerline_point(segment_index + 1)
		if point_segment_distance_sq_xz(point, start, finish) <= limit_sq {
			return true
		}
	}
	return false
}

point_inside_world_water :: proc(x, z: f32) -> bool {
	if !coast_world_land(x, z) { return true }
	return point_inside_river_water(x, z)
}

point_on_bridge_drive_surface_for_crossing :: proc(point: rl.Vector3, crossing: River_Crossing) -> bool {
	center := river_crossing_world_center(crossing)
	axis := crossing_road_axis(crossing)
	right := rl.Vector3{-axis.z, 0, axis.x}
	offset := point - center
	along := offset.x * axis.x + offset.z * axis.z
	across := offset.x * right.x + offset.z * right.z
	if abs_f32(across) > ROAD_WIDTH * 0.48 { return false }

	#partial switch crossing.bridge {
	case .NORMAL:
		return abs_f32(along) <= 7.7
	case .JUMP:
		distance := abs_f32(along)
		return distance >= JUMP_BRIDGE_HALF_GAP - 0.15 &&
		       distance <= JUMP_BRIDGE_HALF_GAP + JUMP_BRIDGE_RAMP_LENGTH + 0.25
	}
	return false
}

point_on_bridge_drive_surface :: proc(point: rl.Vector3) -> bool {
	if river_entry_bridge_valid && point_on_bridge_drive_surface_for_crossing(point, river_entry_bridge) {
		return true
	}
	if river_exit_bridge_valid && point_on_bridge_drive_surface_for_crossing(point, river_exit_bridge) {
		return true
	}
	for index in 0..<river_crossing_count {
		if river_crossings[index].bridge == .NONE { continue }
		if point_on_bridge_drive_surface_for_crossing(point, river_crossings[index]) {
			return true
		}
	}
	return false
}

route_edge_open :: proc(ix, iz, direction: int) -> bool {
	next_x := ix + route_direction_dx(direction)
	next_z := iz + route_direction_dz(direction)
	if !route_grid_valid(ix, iz) || !route_grid_valid(next_x, next_z) {
		return false
	}

	// Keep the full road width away from the shoreline, not just its centre point.
	// Sampling the complete edge prevents a curved bay from clipping a visually
	// driveable street or trapping a start position against the invisible waterline.
	start := route_grid_position(ix, iz)
	finish := route_grid_position(next_x, next_z)
	for sample in 0..=4 {
		t := f32(sample) / 4.0
		point := start + (finish - start) * t
		if !coast_world_land_with_padding(point.x, point.z, COAST_ROAD_CLEARANCE) {
			return false
		}
	}

	if river_edge_crossed[ix][iz][direction] {
		return river_edge_bridge[ix][iz][direction] != .NONE
	}
	return true
}

invalidate_route_memos :: proc() {
	route_max_turn_steps_memo_ready = false
	clear_route_completion_memo()
	clear_route_length_completion_memo()
}

block_center_land :: proc(x, z: int) -> bool {
	world_x := ROAD_ORIGIN_X + (f32(x) + 0.5) * ROAD_SPACING
	world_z := ROAD_ORIGIN_Z + (f32(z) + 0.5) * ROAD_SPACING
	return coast_world_land(world_x, world_z)
}

set_zone_rect :: proc(min_x, min_z, width, height: int, zone: Map_Zone) {
	for x in min_x..<(min_x + width) {
		for z in min_z..<(min_z + height) {
			if x >= 0 && x < BLOCK_X_COUNT && z >= 0 && z < BLOCK_Z_COUNT &&
		   !river_cell_in_path(x, z) && block_center_land(x, z) {
				block_zones[x][z] = zone
			}
		}
	}
}

generate_map_layout :: proc() {
	map_generation_count += 1
	beach_edge = int(rl.GetRandomValue(0, 3))
	coast_turn := 1
	if rl.GetRandomValue(0, 1) == 0 {
		coast_turn = 3
	}
	beach_edge_secondary = (beach_edge + coast_turn) % 4
	// The mountain occupies the inland side opposite the primary beach, so it
	// never competes with either of the two coastal edges.
	mountain_edge = (beach_edge + 2) % 4

	generate_coastline()
	refresh_road_node_land()
	generate_river_path()

	for x in 0..<BLOCK_X_COUNT {
		for z in 0..<BLOCK_Z_COUNT {
			block_zones[x][z] = .RESIDENTIAL
		}
	}

	center_x := BLOCK_X_COUNT / 2 - 1
	center_z := BLOCK_Z_COUNT / 2 - 1

	industrial_corner = int(rl.GetRandomValue(0, 3))
	industrial_x := 0
	industrial_z := 0
	if industrial_corner == 1 || industrial_corner == 2 { industrial_x = BLOCK_X_COUNT - 3 }
	if industrial_corner >= 2 { industrial_z = BLOCK_Z_COUNT - 3 }
	set_zone_rect(industrial_x, industrial_z, 3, 3, .INDUSTRIAL)

	park_width := 3
	park_height := 4
	park_min_x = int(rl.GetRandomValue(1, i32(BLOCK_X_COUNT - park_width - 1)))
	park_min_z = int(rl.GetRandomValue(1, i32(BLOCK_Z_COUNT - park_height - 1)))
	set_zone_rect(park_min_x, park_min_z, park_width, park_height, .PARK)

	// Two distinct commercial districts. Tokyo stays near the dense centre.
	set_zone_rect(center_x, center_z, 4, 3, .COMMERCIAL)

	// Chinatown is a narrow street district rather than a square super-block.
	// Use a 2x3 or 3x2 footprint, randomly rotated, while keeping it toward the
	// inland corner opposite the two beach edges.
	chinatown_width := 2
	chinatown_height := 3
	if rl.GetRandomValue(0, 1) != 0 {
		chinatown_width = 3
		chinatown_height = 2
	}
	chinatown_x := 1
	chinatown_z := 1
	if beach_edge == 3 || beach_edge_secondary == 3 {
		chinatown_x = BLOCK_X_COUNT - chinatown_width - 1
	}
	if beach_edge == 0 || beach_edge_secondary == 0 {
		chinatown_z = BLOCK_Z_COUNT - chinatown_height - 1
	}
	set_zone_rect(chinatown_x, chinatown_z, chinatown_width, chinatown_height, .CHINATOWN)

	// Resort follows the actual curved coast rather than a fixed outer row.
	for x in 0..<BLOCK_X_COUNT {
		for z in 0..<BLOCK_Z_COUNT {
			if river_cell_in_path(x, z) || !block_center_land(x, z) {
				continue
			}
			world_x := ROAD_ORIGIN_X + (f32(x) + 0.5) * ROAD_SPACING
			world_z := ROAD_ORIGIN_Z + (f32(z) + 0.5) * ROAD_SPACING
			along_primary := world_x
			if beach_edge == 1 || beach_edge == 3 { along_primary = world_z }
			along_secondary := world_x
			if beach_edge_secondary == 1 || beach_edge_secondary == 3 { along_secondary = world_z }
			primary_inward := coast_inward_distance_for_edge(beach_edge, world_x, world_z)
			primary_coast := coast_inset_at_along_for_edge(beach_edge, along_primary)
			primary_distance := primary_inward - primary_coast
			secondary_inward := coast_inward_distance_for_edge(beach_edge_secondary, world_x, world_z)
			secondary_coast := coast_inset_at_along_for_edge(beach_edge_secondary, along_secondary)
			secondary_distance := secondary_inward - secondary_coast
			if min(primary_distance, secondary_distance) < 31.0 &&
			   block_zones[x][z] != .COMMERCIAL &&
			   block_zones[x][z] != .CHINATOWN {
				block_zones[x][z] = .RESORT
			}
		}
	}

	for index in 0..<river_path_count {
		cell := river_path[index]
		block_zones[cell.x][cell.z] = .RIVER
	}
	invalidate_route_memos()
}

route_direction_dx :: proc(direction: int) -> int {
	switch direction {
	case 1: return 1
	case 3: return -1
	case:   return 0
	}
}

route_direction_dz :: proc(direction: int) -> int {
	switch direction {
	case 0: return -1
	case 2: return 1
	case:   return 0
	}
}

route_direction_yaw :: proc(direction: int) -> f32 {
	switch direction {
	case 0: return 0.0
	case 1: return rl.PI * 0.5
	case 2: return rl.PI
	case:   return -rl.PI * 0.5
	}
}

route_left_direction :: proc(direction: int) -> int {
	return (direction + 3) % 4
}

route_right_direction :: proc(direction: int) -> int {
	return (direction + 1) % 4
}

route_opposite_direction :: proc(direction: int) -> int {
	return (direction + 2) % 4
}

route_grid_position :: proc(ix, iz: int) -> rl.Vector3 {
	x := ROAD_ORIGIN_X + f32(ix) * ROAD_SPACING
	z := ROAD_ORIGIN_Z + f32(iz) * ROAD_SPACING
	return {x, road_elevation_at(x, z) + 0.08, z}
}

route_grid_valid :: proc(ix, iz: int) -> bool {
	if ix < 0 || ix >= ROAD_X_COUNT || iz < 0 || iz >= ROAD_Z_COUNT {
		return false
	}
	return road_node_land[ix][iz]
}

route_node_index :: proc(ix, iz: int) -> int {
	return iz * ROAD_X_COUNT + ix
}

route_abs_int :: proc(value: int) -> int {
	if value < 0 {
		return -value
	}
	return value
}

route_steps_to_boundary :: proc(ix, iz, direction: int) -> int {
	steps := 0
	x := ix
	z := iz
	for route_edge_open(x, z, direction) {
		x += route_direction_dx(direction)
		z += route_direction_dz(direction)
		steps += 1
	}
	return steps
}

append_route_point :: proc(position: rl.Vector3) {
	if route_point_count >= ROUTE_POINT_MAX {
		return
	}
	ROUTE_POINTS[route_point_count] = position
	route_point_count += 1
}

clear_route_visit_data :: proc() {
	for node in 0..<GRID_NODE_COUNT {
		route_node_visits[node] = 0
		for direction in 0..<4 {
			route_edge_visits[node][direction] = 0
		}
	}
}

// Route nodes may be revisited, but an undirected street edge may only be used once.
// This allows crossings and two different corners to share the same intersection
// without ever sending the player down the same straight road twice.
route_segment_edges_unused :: proc(current_x, current_z, direction, length: int) -> bool {
	x := current_x
	z := current_z
	for _ in 0..<length {
		if !route_edge_open(x, z, direction) {
			return false
		}
		current_node := route_node_index(x, z)
		if route_edge_visits[current_node][direction] != 0 {
			return false
		}
		x += route_direction_dx(direction)
		z += route_direction_dz(direction)
	}
	return true
}

route_open_edge_count :: proc() -> int {
	count := 0
	for z in 0..<ROAD_Z_COUNT {
		for x in 0..<ROAD_X_COUNT {
			// Count each undirected edge once: east and south only.
			if route_edge_open(x, z, 1) { count += 1 }
			if route_edge_open(x, z, 2) { count += 1 }
		}
	}
	return count
}

clear_route_length_completion_memo :: proc() {
	for segment_index in 0..=MAX_CHECKPOINT_COUNT {
		for node in 0..<GRID_NODE_COUNT {
			for direction in 0..<4 {
				route_length_completion_memo[segment_index][node][direction] = -1
			}
		}
	}
}

prepare_balanced_route_lengths :: proc(total_steps, segment_count, phase: int) {
	base_length := total_steps / segment_count
	extra_steps := total_steps % segment_count
	accumulator := phase % segment_count

	// Error diffusion spreads the longer sections across the whole race instead of
	// putting all remainder steps at the beginning or end.
	for segment_index in 0..<segment_count {
		length := base_length
		accumulator += extra_steps
		if accumulator >= segment_count {
			length += 1
			accumulator -= segment_count
		}
		route_segment_steps[segment_index] = length
	}
}

route_lengths_can_complete :: proc(
	segment_index,
	current_x,
	current_z,
	direction: int,
) -> bool {
	if segment_index >= active_checkpoint_count {
		return true
	}
	if !route_grid_valid(current_x, current_z) {
		return false
	}

	node := route_node_index(current_x, current_z)
	memo := &route_length_completion_memo[segment_index][node][direction]
	if memo^ >= 0 {
		return memo^ == 1
	}

	length := route_segment_steps[segment_index]
	if length <= 0 || length > route_steps_to_boundary(current_x, current_z, direction) {
		memo^ = 0
		return false
	}

	target_x := current_x + route_direction_dx(direction) * length
	target_z := current_z + route_direction_dz(direction) * length
	if segment_index == active_checkpoint_count - 1 {
		memo^ = 1
		return true
	}

	possible := false
	left_direction := route_left_direction(direction)
	if route_steps_to_boundary(target_x, target_z, left_direction) > 0 &&
	   route_lengths_can_complete(segment_index + 1, target_x, target_z, left_direction) {
		possible = true
	}
	if !possible {
		right_direction := route_right_direction(direction)
		if route_steps_to_boundary(target_x, target_z, right_direction) > 0 &&
		   route_lengths_can_complete(segment_index + 1, target_x, target_z, right_direction) {
			possible = true
		}
	}

	if possible {
		memo^ = 1
	} else {
		memo^ = 0
	}
	return possible
}

ensure_route_max_turn_steps_memo :: proc() {
	if route_max_turn_steps_memo_ready {
		return
	}
	for gates_left in 0..=MAX_CHECKPOINT_COUNT {
		for node in 0..<GRID_NODE_COUNT {
			for direction in 0..<4 {
				route_max_turn_steps_memo[gates_left][node][direction] = -2
			}
		}
	}
	route_max_turn_steps_memo_ready = true
}

// Maximum honest route length when every checkpoint is a corner. A segment is
// always straight, and the direction changes left or right at every gate.
maximum_turn_route_steps :: proc(gates_left, current_x, current_z, direction: int) -> int {
	if gates_left <= 0 {
		return 0
	}
	if !route_grid_valid(current_x, current_z) {
		return -1
	}

	ensure_route_max_turn_steps_memo()
	node := route_node_index(current_x, current_z)
	memo := &route_max_turn_steps_memo[gates_left][node][direction]
	if memo^ != -2 {
		return memo^
	}

	best := -1
	maximum_forward := route_steps_to_boundary(current_x, current_z, direction)
	if maximum_forward <= 0 {
		memo^ = -1
		return -1
	}
	for length in 1..=maximum_forward {
		target_x := current_x + route_direction_dx(direction) * length
		target_z := current_z + route_direction_dz(direction) * length

		if gates_left == 1 {
			best = max(best, length)
			continue
		}

		left_direction := route_left_direction(direction)
		if route_steps_to_boundary(target_x, target_z, left_direction) > 0 {
			future := maximum_turn_route_steps(
				gates_left - 1,
				target_x,
				target_z,
				left_direction,
			)
			if future >= 0 {
				best = max(best, length + future)
			}
		}

		right_direction := route_right_direction(direction)
		if route_steps_to_boundary(target_x, target_z, right_direction) > 0 {
			future := maximum_turn_route_steps(
				gates_left - 1,
				target_x,
				target_z,
				right_direction,
			)
			if future >= 0 {
				best = max(best, length + future)
			}
		}
	}

	memo^ = best
	return best
}

maximum_turn_route_steps_any_start :: proc(segment_count: int) -> int {
	best := -1
	for z in 0..<ROAD_Z_COUNT {
		for x in 0..<ROAD_X_COUNT {
			for direction in 0..<4 {
				steps := maximum_turn_route_steps(segment_count, x, z, direction)
				best = max(best, steps)
			}
		}
	}
	return best
}

route_can_complete_any_start :: proc(segment_count, steps: int) -> bool {
	clear_route_completion_memo()
	for z in 0..<ROAD_Z_COUNT {
		for x in 0..<ROAD_X_COUNT {
			for direction in 0..<4 {
				if route_can_complete(segment_count, x, z, direction, steps) {
					return true
				}
			}
		}
	}
	return false
}

set_route_start :: proc(x, z, direction: int) {
	route_start_x = x
	route_start_z = z
	route_start_direction = direction
	grid_position := route_grid_position(x, z)
	race_start_position = {grid_position.x, grid_position.y + 0.47, grid_position.z}
	race_start_yaw = route_direction_yaw(direction)
}

find_random_balanced_route_start :: proc(target_steps, phase: int) -> (x, z, direction: int, found: bool) {
	prepare_balanced_route_lengths(target_steps, active_checkpoint_count, phase)
	clear_route_length_completion_memo()

	state_count := GRID_NODE_COUNT * 4
	start_state := int(rl.GetRandomValue(0, i32(state_count - 1)))
	for offset in 0..<state_count {
		state := (start_state + offset) % state_count
		direction = state % 4
		node := state / 4
		x = node % ROAD_X_COUNT
		z = node / ROAD_X_COUNT
		if route_lengths_can_complete(0, x, z, direction) {
			found = true
			return
		}
	}
	return
}

find_random_relaxed_route_start :: proc(target_steps: int) -> (x, z, direction: int, found: bool) {
	clear_route_completion_memo()
	state_count := GRID_NODE_COUNT * 4
	start_state := int(rl.GetRandomValue(0, i32(state_count - 1)))
	for offset in 0..<state_count {
		state := (start_state + offset) % state_count
		direction = state % 4
		node := state / 4
		x = node % ROAD_X_COUNT
		z = node / ROAD_X_COUNT
		if route_can_complete(active_checkpoint_count, x, z, direction, target_steps) {
			found = true
			return
		}
	}
	return
}

clear_route_completion_memo :: proc() {
	for gates_left in 0..=MAX_CHECKPOINT_COUNT {
		for node in 0..<GRID_NODE_COUNT {
			for direction in 0..<4 {
				for steps in 0..=MAX_ROUTE_STEPS {
					route_completion_memo[gates_left][node][direction][steps] = -1
				}
			}
		}
	}
}

route_can_complete :: proc(
	gates_left,
	current_x,
	current_z,
	direction,
	steps_remaining: int,
) -> bool {
	if gates_left <= 0 {
		return steps_remaining == 0
	}
	if steps_remaining < gates_left || steps_remaining > MAX_ROUTE_STEPS {
		return false
	}
	if !route_grid_valid(current_x, current_z) {
		return false
	}

	node := route_node_index(current_x, current_z)
	memo := &route_completion_memo[gates_left][node][direction][steps_remaining]
	if memo^ >= 0 {
		return memo^ == 1
	}

	possible := false
	maximum_forward := min(
		route_steps_to_boundary(current_x, current_z, direction),
		steps_remaining,
	)
	if maximum_forward <= 0 {
		memo^ = 0
		return false
	}
	for length in 1..=maximum_forward {
		target_x := current_x + route_direction_dx(direction) * length
		target_z := current_z + route_direction_dz(direction) * length
		remaining_after := steps_remaining - length

		if gates_left == 1 {
			if remaining_after == 0 {
				possible = true
				break
			}
			continue
		}

		left_direction := route_left_direction(direction)
		if route_steps_to_boundary(target_x, target_z, left_direction) > 0 &&
		   route_can_complete(
				gates_left - 1,
				target_x,
				target_z,
				left_direction,
				remaining_after,
			) {
			possible = true
			break
		}

		right_direction := route_right_direction(direction)
		if route_steps_to_boundary(target_x, target_z, right_direction) > 0 &&
		   route_can_complete(
				gates_left - 1,
				target_x,
				target_z,
				right_direction,
				remaining_after,
			) {
			possible = true
			break
		}
	}

	if possible {
		memo^ = 1
	} else {
		memo^ = 0
	}
	return possible
}

score_route_segment :: proc(
	current_x,
	current_z,
	direction,
	length,
	next_direction,
	desired_steps: int,
) -> int {
	score := -route_abs_int(length - desired_steps) * 100_000
	score += int(rl.GetRandomValue(0, 599))

	x := current_x
	z := current_z
	for _ in 0..<length {
		current_node := route_node_index(x, z)
		next_x := x + route_direction_dx(direction)
		next_z := z + route_direction_dz(direction)
		next_node := route_node_index(next_x, next_z)

		if route_node_visits[next_node] == 0 {
			score += 2_100
		} else {
			score -= route_node_visits[next_node] * 230
		}
		if route_edge_visits[current_node][direction] == 0 {
			score += 1_300
		} else {
			score -= route_edge_visits[current_node][direction] * 360
		}

		x = next_x
		z = next_z
	}

	destination_node := route_node_index(x, z)
	if route_node_visits[destination_node] == 0 {
		score += 2_700
	}

	// Prefer corners farther from the centre so short races spread across the city.
	score += (route_abs_int(x - ROAD_X_COUNT / 2) + route_abs_int(z - ROAD_Z_COUNT / 2)) * 42
	if next_direction == route_left_direction(direction) {
		score += int(rl.GetRandomValue(0, 80))
	}
	return score
}

choose_route_segment :: proc(
	current_x,
	current_z,
	direction,
	remaining_steps,
	segments_left: int,
) -> Route_Segment_Candidate {
	invalid: Route_Segment_Candidate
	invalid.score = -1_000_000_000
	if segments_left <= 0 {
		return invalid
	}

	maximum_forward := min(
		route_steps_to_boundary(current_x, current_z, direction),
		remaining_steps,
	)
	if maximum_forward <= 0 {
		return invalid
	}

	// Balanced integer partitioning: at every stage, prefer the rounded average of
	// the remaining length. Search the mathematically even floor/ceil band first;
	// only widen it when the city boundary makes that band impossible.
	average_floor := remaining_steps / segments_left
	average_ceil := (remaining_steps + segments_left - 1) / segments_left
	desired_steps := max(1, (remaining_steps + segments_left / 2) / segments_left)

	for tolerance in 0..=MAX_ROUTE_SEGMENT_STEPS {
		best := invalid
		minimum_length := max(1, average_floor - tolerance)
		maximum_length := min(maximum_forward, average_ceil + tolerance)
		if minimum_length > maximum_length {
			continue
		}

		for length in minimum_length..=maximum_length {
			target_x := current_x + route_direction_dx(direction) * length
			target_z := current_z + route_direction_dz(direction) * length
			remaining_after := remaining_steps - length

			if segments_left == 1 {
				if remaining_after != 0 {
					continue
				}
				candidate := Route_Segment_Candidate{
					valid = true,
					step_count = length,
					target_x = target_x,
					target_z = target_z,
					next_direction = direction,
				}
				candidate.score = score_route_segment(
					current_x,
					current_z,
					direction,
					length,
					direction,
					desired_steps,
				)
				if !best.valid || candidate.score > best.score {
					best = candidate
				}
				continue
			}

			for turn_index in 0..<2 {
				next_direction := route_left_direction(direction)
				if turn_index == 1 {
					next_direction = route_right_direction(direction)
				}
				if route_steps_to_boundary(target_x, target_z, next_direction) <= 0 {
					continue
				}
				if !route_can_complete(
					segments_left - 1,
					target_x,
					target_z,
					next_direction,
					remaining_after,
				) {
					continue
				}

				candidate := Route_Segment_Candidate{
					valid = true,
					step_count = length,
					target_x = target_x,
					target_z = target_z,
					next_direction = next_direction,
				}
				candidate.score = score_route_segment(
					current_x,
					current_z,
					direction,
					length,
					next_direction,
					desired_steps,
				)
				if !best.valid || candidate.score > best.score {
					best = candidate
				}
			}
		}

		if best.valid {
			return best
		}
	}

	return invalid
}

commit_route_segment :: proc(
	candidate: Route_Segment_Candidate,
	current_x,
	current_z,
	direction: int,
	global_step: ^int,
) -> (next_x, next_z: int) {
	x := current_x
	z := current_z

	for _ in 0..<candidate.step_count {
		current_node := route_node_index(x, z)
		next_grid_x := x + route_direction_dx(direction)
		next_grid_z := z + route_direction_dz(direction)
		next_node := route_node_index(next_grid_x, next_grid_z)

		route_step_directions[global_step^] = direction
		route_edge_visits[current_node][direction] += 1
		route_edge_visits[next_node][route_opposite_direction(direction)] += 1
		route_node_visits[next_node] += 1

		x = next_grid_x
		z = next_grid_z
		global_step^ += 1
		route_grid_points[global_step^] = route_grid_position(x, z)
	}

	return x, z
}

undo_route_segment :: proc(
	current_x,
	current_z,
	direction,
	step_count: int,
	global_step: ^int,
) {
	x := current_x
	z := current_z
	for _ in 0..<step_count {
		current_node := route_node_index(x, z)
		next_x := x + route_direction_dx(direction)
		next_z := z + route_direction_dz(direction)
		next_node := route_node_index(next_x, next_z)

		route_edge_visits[current_node][direction] -= 1
		route_edge_visits[next_node][route_opposite_direction(direction)] -= 1
		route_node_visits[next_node] -= 1

		x = next_x
		z = next_z
	}
	global_step^ -= step_count
}

score_turn_direction :: proc(x, z, direction: int) -> int {
	score := int(rl.GetRandomValue(0, 399))
	look_x := x
	look_z := z
	for _ in 0..<3 {
		if !route_edge_open(look_x, look_z, direction) {
			break
		}
		current_node := route_node_index(look_x, look_z)
		if route_edge_visits[current_node][direction] != 0 {
			score -= 8_000
			break
		}
		next_x := look_x + route_direction_dx(direction)
		next_z := look_z + route_direction_dz(direction)
		next_node := route_node_index(next_x, next_z)
		if route_node_visits[next_node] == 0 {
			score += 1_200
		} else {
			score += 120
		}
		look_x = next_x
		look_z = next_z
	}
	return score
}

build_balanced_unique_route :: proc(
	segment_index,
	current_x,
	current_z,
	direction: int,
	global_step: ^int,
) -> bool {
	if segment_index >= active_checkpoint_count {
		return true
	}

	length := route_segment_steps[segment_index]
	if length <= 0 || !route_segment_edges_unused(current_x, current_z, direction, length) {
		return false
	}

	target_x := current_x + route_direction_dx(direction) * length
	target_z := current_z + route_direction_dz(direction) * length

	if segment_index == active_checkpoint_count - 1 {
		candidate := Route_Segment_Candidate{
			valid = true,
			step_count = length,
			target_x = target_x,
			target_z = target_z,
			next_direction = direction,
		}
		_, _ = commit_route_segment(candidate, current_x, current_z, direction, global_step)
		route_gate_end_steps[segment_index] = global_step^
		return true
	}

	left_direction := route_left_direction(direction)
	right_direction := route_right_direction(direction)
	directions := [2]int{left_direction, right_direction}
	scores := [2]int{
		score_turn_direction(target_x, target_z, left_direction),
		score_turn_direction(target_x, target_z, right_direction),
	}
	if scores[1] > scores[0] {
		directions[0], directions[1] = directions[1], directions[0]
	}

	for option in 0..<2 {
		next_direction := directions[option]
		if route_steps_to_boundary(target_x, target_z, next_direction) <= 0 {
			continue
		}
		// Cheap topology-only lookahead prunes dead branches before the edge-aware
		// backtracking search commits this segment.
		if !route_lengths_can_complete(
			segment_index + 1,
			target_x,
			target_z,
			next_direction,
		) {
			continue
		}

		candidate := Route_Segment_Candidate{
			valid = true,
			step_count = length,
			target_x = target_x,
			target_z = target_z,
			next_direction = next_direction,
		}
		_, _ = commit_route_segment(candidate, current_x, current_z, direction, global_step)
		route_gate_end_steps[segment_index] = global_step^

		if build_balanced_unique_route(
			segment_index + 1,
			target_x,
			target_z,
			next_direction,
			global_step,
		) {
			return true
		}

		undo_route_segment(current_x, current_z, direction, length, global_step)
	}

	return false
}

build_route_geometry :: proc(total_steps: int) -> u64 {
	route_point_count = 0
	append_route_point(race_start_position)
	for step_index in 0..=total_steps {
		append_route_point(route_grid_points[step_index])
	}

	signature: u64 = u64(active_checkpoint_count * 100_000 + total_steps)
	signature ~= u64((route_start_z * ROAD_X_COUNT + route_start_x) * 4 + route_start_direction + 1)
	for step_index in 0..<total_steps {
		signature = (signature << 5) | (signature >> 59)
		signature ~= u64(route_step_directions[step_index] + 1)
	}

	for gate_index in 0..<active_checkpoint_count {
		end_step := route_gate_end_steps[gate_index]
		incoming_direction := route_step_directions[end_step - 1]
		next_direction := incoming_direction
		if gate_index < active_checkpoint_count - 1 {
			next_direction = route_step_directions[end_step]
		}

		// Turn gates sit at the end of the incoming street, before the intersection.
		// The player therefore crosses the full-width gate before starting the corner,
		// instead of being able to clip around a gate placed at the junction centre.
		gate_position := route_grid_points[end_step]
		if gate_index < active_checkpoint_count - 1 {
			gate_position.x -= f32(route_direction_dx(incoming_direction)) * GATE_APPROACH_OFFSET
			gate_position.z -= f32(route_direction_dz(incoming_direction)) * GATE_APPROACH_OFFSET
			gate_position.y = road_elevation_at(gate_position.x, gate_position.z) + 0.08
		}
		CHECKPOINTS[gate_index] = {
			position = gate_position,
			yaw = route_direction_yaw(incoming_direction),
			next_yaw = route_direction_yaw(next_direction),
		}

		signature = (signature << 7) | (signature >> 57)
		signature ~= u64(end_step)
	}

	return signature
}

choose_balanced_next_direction :: proc(
	segment_index,
	current_x,
	current_z,
	direction,
	length: int,
) -> int {
	if segment_index == active_checkpoint_count - 1 {
		return direction
	}

	target_x := current_x + route_direction_dx(direction) * length
	target_z := current_z + route_direction_dz(direction) * length
	best_direction := -1
	best_score := -1_000_000_000

	for turn_index in 0..<2 {
		next_direction := route_left_direction(direction)
		if turn_index == 1 {
			next_direction = route_right_direction(direction)
		}
		if route_steps_to_boundary(target_x, target_z, next_direction) <= 0 {
			continue
		}
		if !route_lengths_can_complete(
			segment_index + 1,
			target_x,
			target_z,
			next_direction,
		) {
			continue
		}

		score := score_route_segment(
			current_x,
			current_z,
			direction,
			length,
			next_direction,
			length,
		)
		if best_direction < 0 || score > best_score {
			best_direction = next_direction
			best_score = score
		}
	}

	return best_direction
}

generate_balanced_route_once :: proc(
	target_steps,
	phase,
	start_x,
	start_z,
	start_direction: int,
) -> (signature: u64, actual_steps: int, success: bool) {
	prepare_balanced_route_lengths(target_steps, active_checkpoint_count, phase)
	clear_route_visit_data()
	clear_route_length_completion_memo()

	set_route_start(start_x, start_z, start_direction)
	global_step := 0
	route_grid_points[0] = route_grid_position(start_x, start_z)
	route_node_visits[route_node_index(start_x, start_z)] = 1

	success = build_balanced_unique_route(
		0,
		start_x,
		start_z,
		start_direction,
		&global_step,
	)
	if !success {
		return 0, global_step, false
	}

	actual_steps = global_step
	signature = build_route_geometry(actual_steps)
	success = actual_steps == target_steps
	return
}

nearest_compatible_route_steps :: proc(requested_steps, segment_count: int) -> int {
	minimum_steps := max(segment_count, 1)
	maximum_steps := maximum_turn_route_steps_any_start(segment_count)
	clamped_steps := clamp(requested_steps, minimum_steps, maximum_steps)

	if route_can_complete_any_start(segment_count, clamped_steps) {
		return clamped_steps
	}

	for offset in 1..=MAX_ROUTE_STEPS {
		lower := clamped_steps - offset
		if lower >= minimum_steps && route_can_complete_any_start(segment_count, lower) {
			return lower
		}
		upper := clamped_steps + offset
		if upper <= maximum_steps && route_can_complete_any_start(segment_count, upper) {
			return upper
		}
	}
	return minimum_steps
}

generate_relaxed_route_once :: proc(target_steps, start_x, start_z, start_direction: int) -> (signature: u64, actual_steps: int) {
	clear_route_visit_data()
	clear_route_completion_memo()

	current_x := start_x
	current_z := start_z
	current_direction := start_direction
	set_route_start(current_x, current_z, current_direction)
	global_step := 0
	route_grid_points[0] = route_grid_position(current_x, current_z)
	route_node_visits[route_node_index(current_x, current_z)] = 1
	remaining_steps := target_steps

	for gate_index in 0..<active_checkpoint_count {
		gates_left := active_checkpoint_count - gate_index
		candidate := choose_route_segment(
			current_x,
			current_z,
			current_direction,
			remaining_steps,
			gates_left,
		)
		if !candidate.valid {
			break
		}

		current_x, current_z = commit_route_segment(
			candidate,
			current_x,
			current_z,
			current_direction,
			&global_step,
		)
		route_gate_end_steps[gate_index] = global_step
		remaining_steps -= candidate.step_count
		current_direction = candidate.next_direction
	}

	actual_steps = global_step
	signature = build_route_geometry(actual_steps)
	return
}

generate_route :: proc() {
	minimum_steps := max(active_checkpoint_count, 1)
	maximum_steps := min(
		maximum_turn_route_steps_any_start(active_checkpoint_count),
		route_open_edge_count(),
	)
	requested_steps := selected_route_length / ROAD_SPACING_METERS
	requested_steps = clamp(requested_steps, minimum_steps, maximum_steps)

	signature: u64
	actual_steps := 0
	generated := false
	chosen_steps := requested_steps

	// Search the requested length first. If the current river/bridge layout cannot
	// support an edge-simple route with this many turns, shorten by one block at a
	// time rather than reusing a street.
	for length_offset in 0..<(requested_steps - minimum_steps + 1) {
		target_steps := requested_steps - length_offset
		phase_start := int(rl.GetRandomValue(0, i32(active_checkpoint_count - 1)))
		attempt_limit := max(96, active_checkpoint_count * 10)

		for attempt in 0..<attempt_limit {
			phase := (phase_start + attempt) % active_checkpoint_count
			start_x, start_z, start_direction, start_found := find_random_balanced_route_start(
				target_steps,
				phase,
			)
			if !start_found {
				continue
			}

			candidate_signature, candidate_steps, success := generate_balanced_route_once(
				target_steps,
				phase,
				start_x,
				start_z,
				start_direction,
			)
			if !success {
				continue
			}

			signature = candidate_signature
			actual_steps = candidate_steps
			chosen_steps = target_steps
			generated = true
			break
		}

		if generated {
			break
		}
	}

	if generated {
		selected_route_length = chosen_steps * ROAD_SPACING_METERS
		previous_route_signature = signature
		route_generation_count += 1
	} else {
		// This should be rare; keep a valid zero-length preview rather than silently
		// falling back to a route that repeats roads.
		route_point_count = 0
	}
}

create_static_rotated_box :: proc(center, half: rl.Vector3, rotation: b3.Quat) -> b3.BodyId {
	body_def := b3.DefaultBodyDef()
	body_def.position = {center.x, center.y, center.z}
	body_def.rotation = rotation
	body_id := b3.CreateBody(world_id, body_def)
	hull := b3.MakeBoxHull(half.x, half.y, half.z)
	shape_def := b3.DefaultShapeDef()
	// The car uses zero material friction, so this does not alter its handling.
	// A little static friction does let knocked-down props settle instead of skating forever.
	shape_def.baseMaterial.friction = 0.22
	_ = b3.CreateHullShape(body_id, shape_def, &hull.base)
	return body_id
}

create_static_box :: proc(center, half: rl.Vector3) -> b3.BodyId {
	return create_static_rotated_box(center, half, b3.Quat_identity)
}

add_building :: proc(center, half: rl.Vector3, color: rl.Color, zone: Map_Zone) {
	if building_count >= BUILDING_MAX { return }
	visual_center := center
	visual_center.y += road_elevation_at(center.x, center.z)
	buildings[building_count] = {center = visual_center, half = half, color = color, zone = zone}
	building_count += 1
	collision_half := rl.Vector3{
		max(half.x - BUILDING_COLLISION_INSET, 0.20),
		half.y,
		max(half.z - BUILDING_COLLISION_INSET, 0.20),
	}
	// Physics remains top-down and flat; only rendering receives the foothill lift.
	_ = create_static_box(center, collision_half)
}

zone_building_color :: proc(zone: Map_Zone, variant: int) -> rl.Color {
	#partial switch zone {
	case .COMMERCIAL:
		switch variant % 3 { case 0: return {54, 72, 94, 255}; case 1: return {72, 88, 112, 255}; case: return {63, 79, 104, 255} }
	case .CHINATOWN:
		switch variant % 3 { case 0: return {112, 54, 48, 255}; case 1: return {92, 61, 50, 255}; case: return {126, 72, 52, 255} }
	case .INDUSTRIAL:
		switch variant % 3 { case 0: return {88, 74, 62, 255}; case 1: return {78, 82, 77, 255}; case: return {101, 86, 67, 255} }
	case .RESORT:
		switch variant % 3 { case 0: return {180, 151, 112, 255}; case 1: return {153, 174, 173, 255}; case: return {196, 180, 143, 255} }
	case:
		switch variant % 4 { case 0: return {62, 72, 72, 255}; case 1: return {72, 62, 76, 255}; case 2: return {70, 77, 63, 255}; case: return {78, 69, 64, 255} }
	}
}

random_building_height :: proc(zone: Map_Zone) -> f32 {
	#partial switch zone {
	case .COMMERCIAL: return f32(rl.GetRandomValue(9, 18))
	case .CHINATOWN:  return f32(rl.GetRandomValue(5, 12))
	case .INDUSTRIAL: return f32(rl.GetRandomValue(4, 8))
	case .RESORT:     return f32(rl.GetRandomValue(4, 9))
	case:             return f32(rl.GetRandomValue(5, 12))
	}
}

generate_block_buildings :: proc(ix, iz: int, zone: Map_Zone) {
	if zone == .PARK || zone == .RIVER { return }
	left_road_x := ROAD_ORIGIN_X + f32(ix) * ROAD_SPACING
	top_road_z := ROAD_ORIGIN_Z + f32(iz) * ROAD_SPACING
	block_x := left_road_x + ROAD_SPACING * 0.5
	block_z := top_road_z + ROAD_SPACING * 0.5
	if !coast_world_land(block_x, block_z) { return }
	// Keep a broad open strip of real drivable sand between the waterfront buildings
	// and the waterline. The Box3D floor continues underneath; only the waterline
	// collider stops the car, so the player can freely leave the asphalt here.
	if coast_land_margin(block_x, block_z) <= BEACH_DRIVE_DEPTH + 8.0 { return }
	pattern := int(rl.GetRandomValue(0, 2))

	if zone == .INDUSTRIAL {
		height := random_building_height(zone)
		add_building({block_x, 0.18 + height * 0.5, block_z}, {6.4, height * 0.5, 6.2}, zone_building_color(zone, ix + iz), zone)
		return
	}
	if (zone == .COMMERCIAL || zone == .CHINATOWN) && pattern == 0 {
		height := random_building_height(zone)
		add_building({block_x, 0.18 + height * 0.5, block_z}, {5.6, height * 0.5, 5.6}, zone_building_color(zone, ix + iz), zone)
		return
	}

	switch pattern {
	case 0:
		height := random_building_height(zone)
		add_building({block_x, 0.18 + height * 0.5, block_z}, {5.9, height * 0.5, 5.9}, zone_building_color(zone, ix + iz), zone)
	case 1:
		for sub in 0..<2 {
			height := random_building_height(zone)
			offset_x: f32 = -3.6
			if sub != 0 { offset_x = 3.6 }
			add_building({block_x + offset_x, 0.18 + height * 0.5, block_z}, {2.7, height * 0.5, 5.8}, zone_building_color(zone, ix + iz + sub), zone)
		}
	case:
		for sub in 0..<4 {
			height := random_building_height(zone)
			offset_x: f32 = -3.5
			if sub % 2 != 0 { offset_x = 3.5 }
			offset_z: f32 = -3.5
			if sub >= 2 { offset_z = 3.5 }
			add_building({block_x + offset_x, 0.18 + height * 0.5, block_z + offset_z}, {2.5, height * 0.5, 2.5}, zone_building_color(zone, ix + iz + sub), zone)
		}
	}
}

coast_world_point_for_edge :: proc(edge: int, secondary: bool, sample: int) -> rl.Vector3 {
	count := coast_profile_count(secondary)
	minimum, maximum := coast_sample_along_bounds_for_edge(edge)
	t := f32(sample) / f32(max(count - 1, 1))
	along := lerp_f32(minimum, maximum, t)
	inset := coast_profile_inset(secondary, sample)

	// Stop each independent shoreline before the shared map corner. The rounded
	// quarter-circle owns the remaining corner; letting the edge continue all the
	// way to the map corner is what produced the persistent pointed wedge.
	corner := coast_shared_corner_position()
	corner_along: f32 = corner.x
	if edge == 1 || edge == 3 {
		corner_along = corner.z
	}
	distance_from_corner := abs_f32(along - corner_along)
	cutoff := coast_corner_cutoff_for_edge(edge)
	if distance_from_corner <= cutoff {
		return coast_corner_endpoint_for_edge(edge, secondary)
	}

	position: rl.Vector3
	switch edge {
	case 0: position = {along, 0, CITY_MIN_Z + inset}
	case 1: position = {CITY_MAX_X - inset, 0, along}
	case 2: position = {along, 0, CITY_MAX_Z - inset}
	case:   position = {CITY_MIN_X + inset, 0, along}
	}
	return position
}

coast_world_point :: proc(sample: int) -> rl.Vector3 {
	return coast_world_point_for_edge(beach_edge, false, sample)
}

coast_world_point_secondary :: proc(sample: int) -> rl.Vector3 {
	return coast_world_point_for_edge(beach_edge_secondary, true, sample)
}

create_coast_boundary_colliders_for_edge :: proc(edge: int, secondary: bool) {
	count := coast_profile_count(secondary)
	for sample in 0..<(count - 1) {
		start := coast_world_point_for_edge(edge, secondary, sample)
		finish := coast_world_point_for_edge(edge, secondary, sample + 1)
		delta := finish - start
		length := horizontal_length(delta)
		if length <= 0.01 { continue }

		// A low invisible wall sits at the waterline. It follows the same curved
		// profile as the beach, so the physical seaside boundary matches the map.
		yaw := b3.Atan2(delta.z, delta.x)
		center := (start + finish) * 0.5
		center.y = 0.42
		_ = create_static_rotated_box(
			center,
			{length * 0.5 + 0.08, 0.42, 0.22},
			b3.MakeQuatFromAxisAngle({0, 1, 0}, -yaw),
		)
	}
}

create_coast_corner_boundary_colliders :: proc() {
	for segment in 0..<COAST_CORNER_SEGMENTS {
		start := coast_corner_curve_point(segment)
		finish := coast_corner_curve_point(segment + 1)
		delta := finish - start
		length := horizontal_length(delta)
		if length <= 0.01 { continue }
		yaw := b3.Atan2(delta.z, delta.x)
		center := (start + finish) * 0.5
		center.y = 0.42
		_ = create_static_rotated_box(
			center,
			{length * 0.5 + 0.08, 0.42, 0.22},
			b3.MakeQuatFromAxisAngle({0, 1, 0}, -yaw),
		)
	}
}

create_coast_boundary_colliders :: proc() {
	// Beaches are driveable all the way to the water. Falling into the water is
	// handled by the water-recovery rule; do not put an invisible wall on the
	// shoreline, because that also blocks ordinary roads that reach the beach.
}

create_boundary_colliders :: proc() {
	half_x := (CITY_MAX_X - CITY_MIN_X) * 0.5 + 22.0
	half_z := (CITY_MAX_Z - CITY_MIN_Z) * 0.5 + 22.0
	city_exit_edge := city_edge()
	for edge in 0..<4 {
		if edge == beach_edge || edge == beach_edge_secondary || edge == city_exit_edge {
			continue
		}
		switch edge {
		case 0:
			_ = create_static_box({0, 0.75, CITY_MIN_Z - 1.0}, {half_x, 0.75, 0.45})
		case 1:
			_ = create_static_box({CITY_MAX_X + 1.0, 0.75, 0}, {0.45, 0.75, half_z})
		case 2:
			_ = create_static_box({0, 0.75, CITY_MAX_Z + 1.0}, {half_x, 0.75, 0.45})
		case:
			_ = create_static_box({CITY_MIN_X - 1.0, 0.75, 0}, {0.45, 0.75, half_z})
		}
	}
	create_city_exit_barrier_colliders()
}

create_river_bank_span_collider :: proc(start, finish: rl.Vector3) {
	delta := finish - start
	length := horizontal_length(delta)
	if length <= 0.01 { return }
	tangent := delta / length
	center := (start + finish) * 0.5
	center.y = RIVER_BANK_HALF_HEIGHT
	yaw := b3.Atan2(tangent.z, tangent.x)
	_ = create_static_rotated_box(
		center,
		{length * 0.5 + 0.05, RIVER_BANK_HALF_HEIGHT, RIVER_BANK_HALF_WIDTH},
		b3.MakeQuatFromAxisAngle({0, 1, 0}, -yaw),
	)
}

river_corner_inner_side_sign :: proc(previous, corner, next: rl.Vector3) -> (bool, f32) {
	in_delta := corner - previous
	out_delta := next - corner
	in_length := horizontal_length(in_delta)
	out_length := horizontal_length(out_delta)
	if in_length <= 0.01 || out_length <= 0.01 { return false, 0 }

	in_tangent := in_delta / in_length
	out_tangent := out_delta / out_length
	direction_dot := in_tangent.x * out_tangent.x + in_tangent.z * out_tangent.z
	if direction_dot > 0.99 { return false, 0 }

	turn_cross := in_tangent.x * out_tangent.z - in_tangent.z * out_tangent.x
	inner_sign: f32 = -1
	if turn_cross > 0 { inner_sign = 1 }
	return true, inner_sign
}

river_bank_side_endpoints :: proc(
	start, finish: rl.Vector3,
	side_sign, start_inner_sign, finish_inner_sign: f32,
) -> (rl.Vector3, rl.Vector3) {
	delta := finish - start
	length := horizontal_length(delta)
	if length <= 0.01 { return start, finish }

	tangent := delta / length
	right := rl.Vector3{-tangent.z, 0, tangent.x}
	bank_start := start + right * (RIVER_HALF_WIDTH * side_sign)
	bank_finish := finish + right * (RIVER_HALF_WIDTH * side_sign)

	// Inner bends are a plain 90-degree inside corner. Do not add any arc,
	// chamfer or miter geometry into the water. Instead trim both straight
	// bank spans back until their offset lines meet at the true inner corner.
	if start_inner_sign != 0 && side_sign == start_inner_sign {
		bank_start += tangent * RIVER_HALF_WIDTH
	}
	if finish_inner_sign != 0 && side_sign == finish_inner_sign {
		bank_finish -= tangent * RIVER_HALF_WIDTH
	}

	return bank_start, bank_finish
}

create_river_bank_side_segment :: proc(
	start, finish: rl.Vector3,
	side_sign, start_inner_sign, finish_inner_sign: f32,
	bridge: Bridge_Type,
	bridge_center: rl.Vector3,
	open_to_finish: bool,
) {
	delta := finish - start
	length := horizontal_length(delta)
	if length <= 0.01 { return }
	tangent := delta / length
	right := rl.Vector3{-tangent.z, 0, tangent.x}
	bank_start, bank_finish := river_bank_side_endpoints(
		start,
		finish,
		side_sign,
		start_inner_sign,
		finish_inner_sign,
	)

	if bridge == .NONE {
		if open_to_finish {
			// Leave the river mouth fully open: no last-segment bank collider.
			return
		}
		create_river_bank_span_collider(bank_start, bank_finish)
		return
	}

	opening_half := ROAD_WIDTH * 0.5 + BRIDGE_ENTRANCE_NOTCH_PADDING
	opening_center := bridge_center + right * (RIVER_HALF_WIDTH * side_sign)
	left_finish := opening_center - tangent * opening_half
	right_start := opening_center + tangent * opening_half
	left_length := (left_finish.x - bank_start.x) * tangent.x + (left_finish.z - bank_start.z) * tangent.z
	right_length := (bank_finish.x - right_start.x) * tangent.x + (bank_finish.z - right_start.z) * tangent.z
	if left_length > 0.05 {
		create_river_bank_span_collider(bank_start, left_finish)
	}
	if !open_to_finish && right_length > 0.05 {
		create_river_bank_span_collider(right_start, bank_finish)
	}
}

create_river_segment_banks :: proc(
	start, finish: rl.Vector3,
	bridge: Bridge_Type,
	start_inner_sign, finish_inner_sign: f32,
	bridge_center: rl.Vector3,
	open_to_finish: bool,
) {
	for side in 0..<2 {
		sign: f32 = -1
		if side != 0 { sign = 1 }
		create_river_bank_side_segment(
			start,
			finish,
			sign,
			start_inner_sign,
			finish_inner_sign,
			bridge,
			bridge_center,
			open_to_finish,
		)
	}
}

create_river_corner_bank_colliders :: proc(previous, corner, next: rl.Vector3) {
	has_turn, inner_sign := river_corner_inner_side_sign(previous, corner, next)
	if !has_turn { return }

	in_delta := corner - previous
	out_delta := next - corner
	in_tangent := in_delta / horizontal_length(in_delta)
	out_tangent := out_delta / horizontal_length(out_delta)
	in_right := rl.Vector3{-in_tangent.z, 0, in_tangent.x}
	out_right := rl.Vector3{-out_tangent.z, 0, out_tangent.x}
	outer_sign := -inner_sign

	// Only the OUTER radius gets a chamfer. The inner radius is formed solely
	// by the trimmed straight spans above and receives no extra corner piece.
	outer_start := corner + in_right * (RIVER_HALF_WIDTH * outer_sign)
	outer_finish := corner + out_right * (RIVER_HALF_WIDTH * outer_sign)
	create_river_bank_span_collider(outer_start, outer_finish)
}

river_centerline_point :: proc(point_index: int) -> rl.Vector3 {
	if point_index <= 0 {
		return river_endpoint_for_edge(river_path[0], river_entry_edge, false)
	}
	if point_index >= river_path_count + 1 {
		return river_endpoint_for_edge(river_path[river_path_count - 1], river_exit_edge, true)
	}
	return river_cell_world_center(river_path[point_index - 1])
}

river_bridge_for_segment :: proc(segment_index: int) -> Bridge_Type {
	if segment_index == 0 {
		if river_entry_bridge_valid { return .NORMAL }
		return .NONE
	}
	if segment_index < river_path_count {
		return river_crossings[segment_index - 1].bridge
	}
	if segment_index == river_path_count && river_exit_bridge_valid {
		return .NORMAL
	}
	return .NONE
}

river_bridge_opening_center_for_segment :: proc(segment_index: int) -> rl.Vector3 {
	if segment_index == 0 && river_entry_bridge_valid {
		return river_crossing_world_center(river_entry_bridge)
	}
	if segment_index > 0 && segment_index < river_path_count {
		crossing := river_crossings[segment_index - 1]
		if crossing.bridge != .NONE {
			return river_crossing_world_center(crossing)
		}
	}
	if segment_index == river_path_count && river_exit_bridge_valid {
		return river_crossing_world_center(river_exit_bridge)
	}
	start := river_centerline_point(segment_index)
	finish := river_centerline_point(segment_index + 1)
	return (start + finish) * 0.5
}

create_river_bank_colliders :: proc() {
	if river_path_count <= 0 { return }
	point_count := river_path_count + 2

	for segment_index in 0..<(point_count - 1) {
		start := river_centerline_point(segment_index)
		finish := river_centerline_point(segment_index + 1)
		start_inner_sign: f32 = 0
		finish_inner_sign: f32 = 0

		if segment_index > 0 {
			has_turn, inner_sign := river_corner_inner_side_sign(
				river_centerline_point(segment_index - 1),
				start,
				finish,
			)
			if has_turn { start_inner_sign = inner_sign }
		}
		if segment_index + 2 < point_count {
			has_turn, inner_sign := river_corner_inner_side_sign(
				start,
				finish,
				river_centerline_point(segment_index + 2),
			)
			if has_turn { finish_inner_sign = inner_sign }
		}

		create_river_segment_banks(
			start,
			finish,
			river_bridge_for_segment(segment_index),
			start_inner_sign,
			finish_inner_sign,
			river_bridge_opening_center_for_segment(segment_index),
			segment_index == point_count - 2,
		)
	}

	for corner_index in 1..<(point_count - 1) {
		create_river_corner_bank_colliders(
			river_centerline_point(corner_index - 1),
			river_centerline_point(corner_index),
			river_centerline_point(corner_index + 1),
		)
	}
}

create_jump_bridge_collision :: proc(crossing: River_Crossing) {
	center := river_crossing_world_center(crossing)

	// The car controller keeps chassis pitch locked for stable top-down handling, so
	// a physical wedge only gives the contact solver a vertical lip to fight. Ramp
	// height is handled by the car's arcade suspension support instead. Keep only a
	// low centre blocker: a properly launched car clears it, a car that never reaches
	// the ramp lip cannot simply drive through the visual gap on the global floor.
	gap_y: f32 = 0.26
	if crossing.direction == 1 || crossing.direction == 3 {
		_ = create_static_box(center + rl.Vector3{0, gap_y, 0}, {JUMP_BRIDGE_HALF_GAP, gap_y, ROAD_WIDTH * 0.46})
	} else {
		_ = create_static_box(center + rl.Vector3{0, gap_y, 0}, {ROAD_WIDTH * 0.46, gap_y, JUMP_BRIDGE_HALF_GAP})
	}
}

create_bridge_side_barrier_span :: proc(
	crossing: River_Crossing,
	along_offset, half_length, half_height: f32,
) {
	center := river_crossing_world_center(crossing)
	axis := crossing_road_axis(crossing)
	right := rl.Vector3{-axis.z, 0, axis.x}
	yaw := b3.Atan2(axis.z, axis.x)
	for side in 0..<2 {
		sign: f32 = -1
		if side != 0 { sign = 1 }
		barrier_center := center + axis * along_offset + right * (ROAD_WIDTH * 0.50 * sign)
		barrier_center.y = half_height
		_ = create_static_rotated_box(
			barrier_center,
			{half_length, half_height, 0.13},
			b3.MakeQuatFromAxisAngle({0, 1, 0}, -yaw),
		)
	}
}

create_bridge_side_colliders :: proc(crossing: River_Crossing) {
	#partial switch crossing.bridge {
	case .NORMAL:
		create_bridge_side_barrier_span(crossing, 0, NORMAL_BRIDGE_HALF_LENGTH - BRIDGE_SIDE_BARRIER_END_INSET, 0.48)
	case .JUMP:
		// Keep the dangerous inner half of each jump ramp fenced, but leave the
		// outer approach shoulder open so a level, non-rolling arcade car can still
		// climb onto the ramp from the side instead of snagging on a rail.
		ramp_half_length := max(JUMP_BRIDGE_RAMP_LENGTH * 0.22, 0.20)
		ramp_center := JUMP_BRIDGE_HALF_GAP + ramp_half_length + 0.55
		create_bridge_side_barrier_span(crossing, -ramp_center, ramp_half_length, 0.82)
		create_bridge_side_barrier_span(crossing, ramp_center, ramp_half_length, 0.82)
	}
}

generate_city :: proc() {
	building_count = 0
	// The floor extends beneath the beach so the shoreline, rather than the old
	// city rectangle, becomes the physical edge on that side.
	half_x := (CITY_MAX_X - CITY_MIN_X) * 0.5 + 22.0
	half_z := (CITY_MAX_Z - CITY_MIN_Z) * 0.5 + 22.0
	_ = create_static_box({0, -0.25, 0}, {half_x, 0.25, half_z})
	create_boundary_colliders()

	for ix in 0..<BLOCK_X_COUNT {
		for iz in 0..<BLOCK_Z_COUNT {
			generate_block_buildings(ix, iz, block_zones[ix][iz])
		}
	}

	create_river_bank_colliders()
	if river_entry_bridge_valid {
		create_bridge_side_colliders(river_entry_bridge)
	}
	if river_exit_bridge_valid {
		create_bridge_side_colliders(river_exit_bridge)
	}
	for index in 0..<river_crossing_count {
		if river_crossings[index].bridge == .JUMP {
			create_jump_bridge_collision(river_crossings[index])
		}
		if river_crossings[index].bridge != .NONE {
			create_bridge_side_colliders(river_crossings[index])
		}
	}

	generate_destructible_props()
}

draw_quad_double_sided :: proc(a, b, c, d: rl.Vector3, color: rl.Color) {
	rl.DrawTriangle3D(a, b, c, color)
	rl.DrawTriangle3D(a, c, d, color)
	rl.DrawTriangle3D(c, b, a, color)
	rl.DrawTriangle3D(d, c, a, color)
}

draw_elevated_strip :: proc(start, finish: rl.Vector3, width: f32, color: rl.Color) {
	delta := finish - start
	length := horizontal_length(delta)
	if length <= 0.001 {
		return
	}
	right := rl.Vector3{-delta.z / length, 0, delta.x / length} * (width * 0.5)
	a := start - right
	b := start + right
	c := finish + right
	d := finish - right
	draw_quad_double_sided(a, b, c, d, color)
}

draw_mountain_foothills :: proc() {
	ground := rl.Color{64, 84, 61, 255}
	sample_count := 18
	for sample in 0..<sample_count {
		d0 := MOUNTAIN_SLOPE_DEPTH * f32(sample) / f32(sample_count)
		d1 := MOUNTAIN_SLOPE_DEPTH * f32(sample + 1) / f32(sample_count)
		h0 := mountain_height_for_distance(d0)
		h1 := mountain_height_for_distance(d1)

		if mountain_edge == 0 || mountain_edge == 2 {
			z0 := CITY_MIN_Z + d0
			z1 := CITY_MIN_Z + d1
			if mountain_edge == 2 {
				z0 = CITY_MAX_Z - d0
				z1 = CITY_MAX_Z - d1
			}
			draw_quad_double_sided(
				{CITY_MIN_X - 8, h0, z0},
				{CITY_MAX_X + 8, h0, z0},
				{CITY_MAX_X + 8, h1, z1},
				{CITY_MIN_X - 8, h1, z1},
				ground,
			)
		} else {
			x0 := CITY_MAX_X - d0
			x1 := CITY_MAX_X - d1
			if mountain_edge == 3 {
				x0 = CITY_MIN_X + d0
				x1 = CITY_MIN_X + d1
			}
			draw_quad_double_sided(
				{x0, h0, CITY_MIN_Z - 8},
				{x0, h0, CITY_MAX_Z + 8},
				{x1, h1, CITY_MAX_Z + 8},
				{x1, h1, CITY_MIN_Z - 8},
				ground,
			)
		}
	}
}

road_edge_beach_surface :: proc(start, finish: rl.Vector3) -> bool {
	// Kept for systems that need a coarse edge-level test. Rendering below uses
	// per-segment coast distance so a road can fade naturally into the sand.
	midpoint := (start + finish) * 0.5
	return coast_land_margin(midpoint.x, midpoint.z) <= BEACH_DRIVE_DEPTH + 8.0
}

point_inside_bridge_visual_zone :: proc(point: rl.Vector3) -> bool {
	for index in 0..<river_crossing_count {
		crossing := river_crossings[index]
		if crossing.bridge == .NONE { continue }
		center := river_crossing_world_center(crossing)
		axis := crossing_road_axis(crossing)
		right := rl.Vector3{-axis.z, 0, axis.x}
		offset := point - center
		along := abs_f32(offset.x * axis.x + offset.z * axis.z)
		across := abs_f32(offset.x * right.x + offset.z * right.z)
		half_length: f32 = 8.6
		if crossing.bridge == .JUMP {
			half_length = JUMP_BRIDGE_HALF_GAP + JUMP_BRIDGE_RAMP_LENGTH + 0.8
		}
		if along <= half_length && across <= ROAD_WIDTH * 0.72 {
			return true
		}
	}
	return false
}

mix_road_color :: proc(a, b: rl.Color, t: f32) -> rl.Color {
	amount := clamp(t, 0.0, 1.0)
	return {
		u8(clamp(f32(a[0]) + (f32(b[0]) - f32(a[0])) * amount, 0.0, 255.0)),
		u8(clamp(f32(a[1]) + (f32(b[1]) - f32(a[1])) * amount, 0.0, 255.0)),
		u8(clamp(f32(a[2]) + (f32(b[2]) - f32(a[2])) * amount, 0.0, 255.0)),
		255,
	}
}

beach_road_sand_mix :: proc(point: rl.Vector3) -> f32 {
	// Full sand inside the beach proper, then a soft 8 m carry-over where sand
	// dragged by tyres fades back into city asphalt.
	margin := coast_land_margin(point.x, point.z)
	return clamp((BEACH_DRIVE_DEPTH + 8.0 - margin) / 10.0, 0.0, 1.0)
}

beach_track_alpha :: proc(point: rl.Vector3) -> u8 {
	mix := beach_road_sand_mix(point)
	return u8(clamp(mix * 150.0, 0.0, 150.0))
}

block_is_park :: proc(ix, iz: int) -> bool {
	return ix >= 0 && ix < BLOCK_X_COUNT && iz >= 0 && iz < BLOCK_Z_COUNT &&
	       block_zones[ix][iz] == .PARK
}

road_edge_park_surface :: proc(ix, iz, direction: int) -> bool {
	// Park paving is intentionally rare: it only appears on the internal cross
	// of a complete 2x2 PARK cluster. Two park blocks merely touching are not
	// enough, otherwise isolated park-road fragments appear around the boundary.
	if direction == 1 {
		// East-west edge between the block row above and below. This edge belongs
		// to a 2x2 park square only when the same north/south pair also exists in
		// either neighbouring block column.
		if !block_is_park(ix, iz - 1) || !block_is_park(ix, iz) {
			return false
		}
		left_pair := block_is_park(ix - 1, iz - 1) && block_is_park(ix - 1, iz)
		right_pair := block_is_park(ix + 1, iz - 1) && block_is_park(ix + 1, iz)
		return left_pair || right_pair
	}
	if direction == 2 {
		// North-south edge between the block column to the west and east. Require
		// the same west/east pair in the neighbouring block row to form 2x2.
		if !block_is_park(ix - 1, iz) || !block_is_park(ix, iz) {
			return false
		}
		north_pair := block_is_park(ix - 1, iz - 1) && block_is_park(ix, iz - 1)
		south_pair := block_is_park(ix - 1, iz + 1) && block_is_park(ix, iz + 1)
		return north_pair || south_pair
	}
	return false
}

road_node_park_surface :: proc(ix, iz: int) -> bool {
	// A junction belongs to the park only when all four surrounding blocks are
	// PARK. This is the exact centre shared by a 2x2 group of park blocks.
	return block_is_park(ix - 1, iz - 1) &&
	       block_is_park(ix, iz - 1) &&
	       block_is_park(ix - 1, iz) &&
	       block_is_park(ix, iz)
}

road_node_has_open_edge :: proc(ix, iz: int) -> bool {
	for direction in 0..<4 {
		if route_edge_open(ix, iz, direction) { return true }
	}
	return false
}

draw_road_node_surface :: proc(ix, iz: int) {
	if !route_grid_valid(ix, iz) || !road_node_has_open_edge(ix, iz) { return }
	center := route_grid_position(ix, iz)
	if point_inside_bridge_visual_zone(center) { return }

	color := rl.Color{31, 34, 42, 255}
	if road_node_park_surface(ix, iz) {
		color = PARK_ROAD_COLOR
	}
	sand_mix := beach_road_sand_mix(center)
	if sand_mix > 0.0 {
		color = mix_road_color(color, BEACH_SAND_COLOR, sand_mix)
	}

	half := ROAD_WIDTH * 0.5
	y := f32(0.030)
	draw_quad_double_sided(
		{center.x - half, y, center.z - half},
		{center.x + half, y, center.z - half},
		{center.x + half, y, center.z + half},
		{center.x - half, y, center.z + half},
		color,
	)
}

draw_road_edge_surface :: proc(start, finish: rl.Vector3, park_surface: bool) {
	SEGMENTS :: 24
	asphalt := rl.Color{31, 34, 42, 255}
	full_delta := finish - start
	full_length := horizontal_length(full_delta)
	if full_length <= ROAD_WIDTH { return }
	tangent := full_delta / full_length
	// Every road node owns one ROAD_WIDTH square junction surface. Trim the long
	// edge back to that square instead of stacking several coplanar strips there.
	edge_start := start + tangent * (ROAD_WIDTH * 0.5)
	edge_finish := finish - tangent * (ROAD_WIDTH * 0.5)
	delta := edge_finish - edge_start
	for segment in 0..<SEGMENTS {
		t0 := f32(segment) / f32(SEGMENTS)
		t1 := f32(segment + 1) / f32(SEGMENTS)
		a := edge_start + delta * t0
		b := edge_start + delta * t1
		midpoint := (a + b) * 0.5
		if point_inside_bridge_visual_zone(midpoint) { continue }

		color := asphalt
		if park_surface {
			color = PARK_ROAD_COLOR
		}

		sand_mix := beach_road_sand_mix(midpoint)
		if sand_mix > 0.0 {
			color = mix_road_color(color, BEACH_SAND_COLOR, sand_mix)
		}
		a.y = 0.027
		b.y = 0.027
		draw_elevated_strip(a, b, ROAD_WIDTH, color)

		// Two subtle tyre-worn bands appear only where sand meaningfully mixes
		// into the road. They sit above the surface so there is no z-fighting.
		if sand_mix > 0.18 {
			track_alpha := beach_track_alpha(midpoint)
			track_color := BEACH_TRACK_COLOR
			track_color[3] = track_alpha
			segment_delta := b - a
			segment_length := horizontal_length(segment_delta)
			if segment_length > 0.01 {
				tangent := segment_delta / segment_length
				right := rl.Vector3{-tangent.z, 0, tangent.x}
				for side in 0..<2 {
					sign: f32 = -1
					if side != 0 { sign = 1 }
					ta := a + right * (ROAD_WIDTH * 0.24 * sign)
					tb := b + right * (ROAD_WIDTH * 0.24 * sign)
					ta.y = 0.082
					tb.y = 0.082
					draw_elevated_strip(ta, tb, 0.50, track_color)
				}
			}
		}
	}
}

draw_roads :: proc() {
	for z in 0..<ROAD_Z_COUNT {
		for x in 0..<ROAD_X_COUNT {
			for direction in 1..=2 {
				next_x := x + route_direction_dx(direction)
				next_z := z + route_direction_dz(direction)
				if !route_edge_open(x, z, direction) { continue }
				// River crossings are drawn by the bridge renderer. A bridged crossing is
				// topologically open, but its deck replaces the ordinary road strip.
				if river_edge_crossed[x][z][direction] { continue }
				start := route_grid_position(x, z)
				finish := route_grid_position(next_x, next_z)
				draw_road_edge_surface(start, finish, road_edge_park_surface(x, z, direction))
			}
		}
	}

	// Junctions are a single authoritative surface. This removes the coplanar
	// overlap that was most visible where beach sand transitions met a crossroads,
	// and also lets a 2x2 park centre receive the correct park paving.
	for z in 0..<ROAD_Z_COUNT {
		for x in 0..<ROAD_X_COUNT {
			draw_road_node_surface(x, z)
		}
	}
}

draw_road_markings :: proc() {
	line_color := rl.Color{238, 201, 78, 190}
	for z in 0..<ROAD_Z_COUNT {
		for x in 0..<ROAD_X_COUNT {
			for direction in 1..=2 {
				next_x := x + route_direction_dx(direction)
				next_z := z + route_direction_dz(direction)
				if !route_edge_open(x, z, direction) { continue }
				if river_edge_crossed[x][z][direction] { continue }
				start := route_grid_position(x, z)
				finish := route_grid_position(next_x, next_z)
				// Park paving has no city centre line. Beach transitions are tested per
				// dash so markings fade out as the asphalt itself disappears into sand.
				if road_edge_park_surface(x, z, direction) { continue }
				delta := finish - start
				for dash in 0..<3 {
					t0 := 0.12 + f32(dash) * 0.31
					t1 := min(t0 + 0.14, 0.92)
					a := start + delta * t0
					b := start + delta * t1
					midpoint := (a + b) * 0.5
					if beach_road_sand_mix(midpoint) > 0.28 { continue }
					a.y = 0.077
					b.y = 0.077
					draw_elevated_strip(a, b, 0.18, line_color)
				}
			}
		}
	}
}

draw_blocks_and_props :: proc() {
	for ix in 0..<BLOCK_X_COUNT {
		left_road_x := ROAD_ORIGIN_X + f32(ix) * ROAD_SPACING
		block_x := left_road_x + ROAD_SPACING * 0.5
		for iz in 0..<BLOCK_Z_COUNT {
			top_road_z := ROAD_ORIGIN_Z + f32(iz) * ROAD_SPACING
			block_z := top_road_z + ROAD_SPACING * 0.5
			zone := block_zones[ix][iz]
			if zone == .RIVER || !coast_world_land(block_x, block_z) { continue }
			base_y := road_elevation_at(block_x, block_z)
			coast_margin := coast_land_margin(block_x, block_z)
			// Block tiles are coarse 16 m squares, so classify by an extra half-block
			// margin. This keeps a square city/park tile from poking into the curved beach.
			beach_block := coast_margin <= BEACH_DRIVE_DEPTH + 8.0
			promenade_block := !beach_block && coast_margin <= BEACH_DRIVE_DEPTH + COAST_PROMENADE_DEPTH + 8.0
			base_color := map_zone_color(zone)
			if promenade_block {
				// Do not leave a mystery green belt between the city and the sand.
				// Near-coast blocks read as one continuous beach / sand promenade.
				base_color = {202, 181, 132, 255}
			}
			if !beach_block {
				rl.DrawCube({block_x, base_y + 0.07, block_z}, 16.0, 0.14, 16.0, base_color)
				if promenade_block {
					rl.DrawCubeWires({block_x, base_y + 0.07, block_z}, 16.0, 0.14, 16.0, {178, 160, 120, 120})
				} else {
					rl.DrawCubeWires({block_x, base_y + 0.07, block_z}, 16.0, 0.14, 16.0, {118, 124, 126, 170})
				}
			}

			if zone == .PARK && !beach_block && !promenade_block {
				// Trees are rendered from Box3D-backed destructible prop bodies.
				rl.DrawCube({block_x, base_y + 0.16, block_z}, 2.2, 0.04, 13.0, {185, 170, 132, 255})
			} else if zone == .INDUSTRIAL {
				x := block_x + 5.2
				z := block_z - 5.2
				rl.DrawCube({x, road_elevation_at(x, z) + 1.0, z}, 1.4, 2.0, 1.4, {110, 117, 119, 255})
			}
		}
	}
}


find_chinatown_rect :: proc() -> (min_x, min_z, max_x, max_z: int, found: bool) {
	min_x = BLOCK_X_COUNT
	min_z = BLOCK_Z_COUNT
	max_x = -1
	max_z = -1
	for ix in 0..<BLOCK_X_COUNT {
		for iz in 0..<BLOCK_Z_COUNT {
			if block_zones[ix][iz] != .CHINATOWN { continue }
			if ix < min_x { min_x = ix }
			if iz < min_z { min_z = iz }
			if ix > max_x { max_x = ix }
			if iz > max_z { max_z = iz }
		}
	}
	return min_x, min_z, max_x, max_z, max_x >= min_x && max_z >= min_z
}

draw_chinatown_gate :: proc(center: rl.Vector3, street_vertical: bool, scale: f32 = 1.0) {
	gate_center := center
	deep_red := rl.Color{150, 31, 31, 255}
	lacquer_red := rl.Color{196, 48, 39, 255}
	gold := rl.Color{239, 189, 61, 255}
	jade := rl.Color{41, 102, 76, 255}
	dark_blue := rl.Color{38, 54, 82, 255}

	// Reference shape: Yokohama-style paifang. The street passes through one large
	// central opening. Four columns are still present, but they are two close pairs
	// on the sidewalks (front/rear depth), never four posts spread across the road.
	street_axis := rl.Vector3{1, 0, 0}
	side_axis := rl.Vector3{0, 0, 1}
	roof_yaw: f32 = rl.PI * 0.5
	if street_vertical {
		street_axis = {0, 0, 1}
		side_axis = {1, 0, 0}
		roof_yaw = 0
	}
	previous_world_active := world_visual_deform_active
	previous_world_anchor := world_visual_deform_anchor
	world_visual_deform_active = bounce_mode
	world_visual_deform_anchor = gate_center
	defer {
		world_visual_deform_active = previous_world_active
		world_visual_deform_anchor = previous_world_anchor
	}

	// The carriageway is 8 m wide. Put the paired columns only a little outside the
	// road edge so the gate frames the street instead of becoming a huge flat beam.
	side_offset := ROAD_WIDTH * 0.5 + 1.35
	depth_offset := 0.34 * scale
	pillar_half := rl.Vector3{0.24 * scale, 1.95 * scale, 0.24 * scale}
	for side in 0..<2 {
		side_sign: f32 = -1
		if side != 0 { side_sign = 1 }
		for depth in 0..<2 {
			depth_sign: f32 = -1
			if depth != 0 { depth_sign = 1 }
			base := gate_center + side_axis * (side_offset * side_sign) + street_axis * (depth_offset * depth_sign)
			draw_oriented_box(base + rl.Vector3{0, pillar_half.y, 0}, pillar_half, roof_yaw, lacquer_red)
			draw_oriented_box(base + rl.Vector3{0, 0.12 * scale, 0}, {0.34 * scale, 0.12 * scale, 0.34 * scale}, roof_yaw, gold)
			draw_oriented_box(base + rl.Vector3{0, 3.70 * scale, 0}, {0.30 * scale, 0.10 * scale, 0.30 * scale}, roof_yaw, jade)
		}
	}

	// The decorated lintel is slim; most of the silhouette comes from three roofs.
	span := side_offset + 0.34 * scale
	draw_oriented_box(gate_center + rl.Vector3{0, 3.34 * scale, 0}, {span, 0.14 * scale, 0.30 * scale}, roof_yaw, deep_red)
	draw_oriented_box(gate_center + rl.Vector3{0, 3.57 * scale, 0}, {span - 0.24 * scale, 0.10 * scale, 0.23 * scale}, roof_yaw, gold)

	// Central plaque, deliberately large and dark like a real Chinatown street gate.
	draw_oriented_box(gate_center + rl.Vector3{0, 3.77 * scale, 0}, {1.24 * scale, 0.38 * scale, 0.13 * scale}, roof_yaw, gold)
	draw_oriented_box(gate_center + rl.Vector3{0, 3.77 * scale, -0.015}, {1.02 * scale, 0.28 * scale, 0.15 * scale}, roof_yaw, dark_blue)

	// High centre roof.
	for layer in 0..<3 {
		y := 4.18 * scale + f32(layer) * 0.16 * scale
		half_span := (2.45 + f32(layer) * 0.28) * scale
		depth := (0.48 + f32(layer) * 0.10) * scale
		color := jade
		if layer == 1 { color = lacquer_red }
		if layer == 2 { color = gold }
		draw_oriented_box(gate_center + rl.Vector3{0, y, 0}, {half_span, 0.08 * scale, depth}, roof_yaw, color)
	}

	// Lower side roofs sit over each column pair, leaving the central roof dominant.
	for side in 0..<2 {
		sign: f32 = -1
		if side != 0 { sign = 1 }
		wing_center := gate_center + side_axis * (side_offset * 0.78 * sign)
		draw_oriented_box(wing_center + rl.Vector3{0, 3.94 * scale, 0}, {1.45 * scale, 0.09 * scale, 0.42 * scale}, roof_yaw, jade)
		draw_oriented_box(wing_center + rl.Vector3{0, 4.10 * scale, 0}, {1.68 * scale, 0.08 * scale, 0.52 * scale}, roof_yaw, gold)
	}
}

draw_chinatown_entrances :: proc() {
	min_x, min_z, max_x, max_z, found := find_chinatown_rect()
	if !found { return }
	width := max_x - min_x + 1
	height := max_z - min_z + 1

	if height >= width {
		// 2x3 district: the Chinatown main street is the road exactly between the
		// two block columns. Put one gate at each end of that SAME road.
		street_x := ROAD_ORIGIN_X + f32(min_x + 1) * ROAD_SPACING
		top_z := ROAD_ORIGIN_Z + f32(min_z) * ROAD_SPACING + 1.8
		bottom_z := ROAD_ORIGIN_Z + f32(max_z + 1) * ROAD_SPACING - 1.8
		if coast_world_land(street_x, top_z) {
			draw_chinatown_gate({street_x, road_elevation_at(street_x, top_z) + 0.02, top_z}, true, 1.18)
		}
		if coast_world_land(street_x, bottom_z) {
			draw_chinatown_gate({street_x, road_elevation_at(street_x, bottom_z) + 0.02, bottom_z}, true, 1.18)
		}
		return
	}

	// 3x2 district: same idea, rotated 90 degrees. Both gates are on one continuous
	// east-west main street, so looking through one points directly at the other.
	street_z := ROAD_ORIGIN_Z + f32(min_z + 1) * ROAD_SPACING
	left_x := ROAD_ORIGIN_X + f32(min_x) * ROAD_SPACING + 1.8
	right_x := ROAD_ORIGIN_X + f32(max_x + 1) * ROAD_SPACING - 1.8
	if coast_world_land(left_x, street_z) {
		draw_chinatown_gate({left_x, road_elevation_at(left_x, street_z) + 0.02, street_z}, false, 1.18)
	}
	if coast_world_land(right_x, street_z) {
		draw_chinatown_gate({right_x, road_elevation_at(right_x, street_z) + 0.02, street_z}, false, 1.18)
	}
}

neon_color_for :: proc(index: int) -> rl.Color {
	switch index % 8 {
	case 0: return {255, 58, 118, 255}
	case 1: return {255, 126, 38, 255}
	case 2: return {255, 225, 64, 255}
	case 3: return {82, 235, 118, 255}
	case 4: return {58, 225, 238, 255}
	case 5: return {70, 128, 255, 255}
	case 6: return {174, 80, 255, 255}
	case:   return {255, 76, 224, 255}
	}
}

building_face_half_length :: proc(building: Building, side: int) -> f32 {
	if side == 0 || side == 2 {
		return building.half.x
	}
	return building.half.z
}

draw_building_face_panel :: proc(
	building: Building,
	side: int,
	along_offset,
	y,
	length,
	height,
	depth: f32,
	color: rl.Color,
) {
	switch side {
	case 0:
		rl.DrawCube(
			{building.center.x + along_offset, y, building.center.z - building.half.z - depth * 0.5},
			length,
			height,
			depth,
			color,
		)
	case 1:
		rl.DrawCube(
			{building.center.x + building.half.x + depth * 0.5, y, building.center.z + along_offset},
			depth,
			height,
			length,
			color,
		)
	case 2:
		rl.DrawCube(
			{building.center.x + along_offset, y, building.center.z + building.half.z + depth * 0.5},
			length,
			height,
			depth,
			color,
		)
	case:
		rl.DrawCube(
			{building.center.x - building.half.x - depth * 0.5, y, building.center.z + along_offset},
			depth,
			height,
			length,
			color,
		)
	}
}

draw_building_face_light :: proc(building: Building, side: int, along_offset, y: f32, color: rl.Color) {
	face_half := building_face_half_length(building, side)
	panel_length := max(0.16, face_half * 0.10)
	draw_building_face_panel(building, side, along_offset, y, panel_length, 0.16, 0.10, color)
}

building_face_visible_from :: proc(building: Building, side: int, viewer: rl.Vector3) -> bool {
	dx := viewer.x - building.center.x
	dz := viewer.z - building.center.z
	switch side {
	case 0: return dz <= 0
	case 1: return dx >= 0
	case 2: return dz >= 0
	case:   return dx <= 0
	}
}

draw_commercial_facade :: proc(building: Building, index: int) {
	ground_y := building.center.y - building.half.y
	dark_glass := rl.Color{18, 30, 42, 255}
	warm_glass := rl.Color{255, 201, 106, 255}
	floor_count := clamp(int(building.half.y / 1.4), 2, 6)

	viewer := car_position()
	for side in 0..<4 {
		if !building_face_visible_from(building, side, viewer) { continue }
		face_half := building_face_half_length(building, side)
		accent := neon_color_for(index + side * 2)
		accent_two := neon_color_for(index + side * 2 + 3)
		store_width := max(face_half * 1.55, 1.5)

		// Every street-facing side gets an occupied ground floor and signage.
		draw_building_face_panel(building, side, 0, ground_y + 0.78, store_width, 1.30, 0.08, dark_glass)
		draw_building_face_panel(building, side, 0, ground_y + 1.62, store_width * 0.92, 0.34, 0.10, accent)

		for sign in 0..<3 {
			along := -face_half * 0.58 + f32(sign) * face_half * 0.58
			sign_color := neon_color_for(index + side * 5 + sign + 1)
			draw_building_face_panel(
				building,
				side,
				along,
				ground_y + 2.28 + f32(sign % 2) * 0.56,
				max(0.48, face_half * 0.34),
				0.34,
				0.11,
				sign_color,
			)
		}

		for floor in 0..<floor_count {
			y := ground_y + 3.15 + f32(floor) * 1.55
			if y >= building.center.y + building.half.y - 0.6 {
				break
			}
			for window in 0..<3 {
				along := -face_half * 0.55 + f32(window) * face_half * 0.55
				window_color := dark_glass
				if (index + side + floor + window) % 4 == 0 {
					window_color = warm_glass
				}
				draw_building_face_panel(
					building,
					side,
					along,
					y,
					max(0.42, face_half * 0.28),
					0.58,
					0.06,
					window_color,
				)
			}
		}

		// One vertical lightbox per face keeps the skyline lively from oblique views.
		draw_building_face_panel(
			building,
			side,
			face_half * 0.72,
			ground_y + 3.15,
			max(0.30, face_half * 0.18),
			1.55,
			0.12,
			accent_two,
		)
	}
}

draw_chinatown_facade :: proc(building: Building, index: int) {
	ground_y := building.center.y - building.half.y
	deep_red := rl.Color{126, 34, 34, 255}
	lacquer_red := rl.Color{190, 48, 42, 255}
	gold := rl.Color{244, 190, 68, 255}
	jade := rl.Color{36, 104, 76, 255}
	warm_glass := rl.Color{255, 188, 92, 255}
	dark_glass := rl.Color{33, 30, 34, 255}
	floor_count := clamp(int(building.half.y / 1.25), 2, 6)

	viewer := car_position()
	for side in 0..<4 {
		if !building_face_visible_from(building, side, viewer) { continue }
		face_half := building_face_half_length(building, side)

		// Shopfronts use red lacquer framing, gold signboards and green awnings.
		draw_building_face_panel(building, side, 0, ground_y + 0.80, face_half * 1.48, 1.24, 0.08, dark_glass)
		draw_building_face_panel(building, side, 0, ground_y + 1.62, face_half * 1.34, 0.34, 0.11, deep_red)
		draw_building_face_panel(building, side, 0, ground_y + 1.65, face_half * 0.92, 0.14, 0.13, gold)
		draw_building_face_panel(building, side, 0, ground_y + 2.02, face_half * 1.30, 0.10, 0.28, jade)

		// Keep Chinatown expressive without tanking performance: only decorate two
		// sides, and use tiny box lanterns instead of many spheres.
		if side % 2 == 0 {
			for lantern in 0..<2 {
				along := -face_half * 0.42 + f32(lantern) * face_half * 0.84
				lantern_y := ground_y + 2.24 + f32((lantern + side) % 2) * 0.10
				lantern_half := rl.Vector3{0.11, 0.13, 0.11}
				switch side {
				case 0:
					draw_oriented_box({building.center.x + along, lantern_y, building.center.z - building.half.z - 0.18}, lantern_half, 0, lacquer_red)
				case 1:
					draw_oriented_box({building.center.x + building.half.x + 0.18, lantern_y, building.center.z + along}, lantern_half, 0, lacquer_red)
				case 2:
					draw_oriented_box({building.center.x + along, lantern_y, building.center.z + building.half.z + 0.18}, lantern_half, 0, lacquer_red)
				case:
					draw_oriented_box({building.center.x - building.half.x - 0.18, lantern_y, building.center.z + along}, lantern_half, 0, lacquer_red)
				}
			}
		}

		for floor in 0..<floor_count {
			y := ground_y + 3.0 + f32(floor) * 1.42
			if y >= building.center.y + building.half.y - 0.5 {
				break
			}
			for window in 0..<3 {
				along := -face_half * 0.55 + f32(window) * face_half * 0.55
				color := dark_glass
				if (index + side + floor + window) % 3 != 0 {
					color = warm_glass
				}
				draw_building_face_panel(
					building,
					side,
					along,
					y,
					max(0.40, face_half * 0.25),
					0.52,
					0.06,
					color,
				)
			}
			// Thin red balcony rails / horizontal trim.
			draw_building_face_panel(building, side, 0, y - 0.42, face_half * 1.35, 0.07, 0.20, deep_red)
		}

		// Vertical gold-on-red signboard.
		draw_building_face_panel(
			building,
			side,
			face_half * 0.73,
			ground_y + 3.05,
			max(0.30, face_half * 0.18),
			1.50,
			0.12,
			lacquer_red,
		)
		draw_building_face_panel(
			building,
			side,
			face_half * 0.73,
			ground_y + 3.05,
			max(0.12, face_half * 0.07),
			1.15,
			0.135,
			gold,
		)
	}
}

draw_residential_facade :: proc(building: Building, index: int) {
	ground_y := building.center.y - building.half.y
	glass_dark := rl.Color{31, 48, 61, 255}
	glass_warm := rl.Color{246, 194, 112, 255}
	floor_count := clamp(int(building.half.y / 1.15), 2, 7)

	viewer := car_position()
	for side in 0..<4 {
		if !building_face_visible_from(building, side, viewer) { continue }
		face_half := building_face_half_length(building, side)
		for floor in 0..<floor_count {
			y := ground_y + 1.15 + f32(floor) * 1.35
			if y >= building.center.y + building.half.y - 0.45 {
				break
			}
			for window in 0..<3 {
				along := -face_half * 0.55 + f32(window) * face_half * 0.55
				color := glass_dark
				if (index * 3 + side + floor + window) % 3 != 0 {
					color = glass_warm
				}
				draw_building_face_panel(
					building,
					side,
					along,
					y,
					max(0.40, face_half * 0.25),
					0.48,
					0.06,
					color,
				)
			}
			if floor % 2 == 1 {
				draw_building_face_panel(
					building,
					side,
					0,
					y - 0.42,
					face_half * 1.25,
					0.07,
					0.20,
					{95, 100, 102, 255},
				)
			}
		}

		// Doors and small porch lights alternate faces so houses do not read like
		// copied four-sided storefronts, but every wall still has signs of occupancy.
		if side == 0 || side == 2 {
			draw_building_face_panel(
				building,
				side,
				0,
				ground_y + 0.72,
				max(0.55, face_half * 0.24),
				1.18,
				0.08,
				{44, 54, 62, 255},
			)
		}
		draw_building_face_light(building, side, face_half * 0.34, ground_y + 1.42, {255, 220, 145, 255})
	}
}

draw_industrial_facade :: proc(building: Building, index: int) {
	ground_y := building.center.y - building.half.y
	steel := rl.Color{46, 58, 64, 255}
	lit := rl.Color{174, 216, 224, 255}
	warning := rl.Color{238, 177, 52, 255}

	viewer := car_position()
	for side in 0..<4 {
		if !building_face_visible_from(building, side, viewer) { continue }
		face_half := building_face_half_length(building, side)
		door_width := max(1.8, face_half * 0.72)
		if side == 0 || side == 2 {
			draw_building_face_panel(building, side, 0, ground_y + 1.25, door_width, 2.25, 0.08, steel)
		} else {
			draw_building_face_panel(building, side, 0, ground_y + 1.05, face_half * 1.25, 1.05, 0.07, {60, 67, 68, 255})
		}

		for window in 0..<4 {
			along := -face_half * 0.68 + f32(window) * face_half * 0.45
			color := rl.Color{56, 74, 80, 255}
			if (index + side + window) % 3 == 0 {
				color = lit
			}
			draw_building_face_panel(
				building,
				side,
				along,
				ground_y + 3.25,
				max(0.46, face_half * 0.22),
				0.50,
				0.06,
				color,
			)
		}
		draw_building_face_panel(building, side, 0, ground_y + 0.16, door_width * 1.10, 0.11, 0.10, warning)
		draw_building_face_light(building, side, face_half * 0.70, ground_y + 2.15, {238, 72, 52, 255})
	}
}

draw_resort_facade :: proc(building: Building, index: int) {
	ground_y := building.center.y - building.half.y
	glass := rl.Color{62, 138, 167, 255}
	warm := rl.Color{255, 215, 145, 255}
	floor_count := clamp(int(building.half.y / 1.25), 2, 6)

	viewer := car_position()
	for side in 0..<4 {
		if !building_face_visible_from(building, side, viewer) { continue }
		face_half := building_face_half_length(building, side)
		for floor in 0..<floor_count {
			y := ground_y + 1.15 + f32(floor) * 1.45
			if y >= building.center.y + building.half.y - 0.45 {
				break
			}
			draw_building_face_panel(building, side, 0, y, face_half * 1.38, 0.62, 0.06, glass)
			draw_building_face_panel(building, side, 0, y - 0.43, face_half * 1.46, 0.06, 0.24, {219, 211, 185, 255})
		}
		awning := neon_color_for(index + side + 2)
		draw_building_face_panel(building, side, 0, ground_y + 1.55, face_half * 1.28, 0.12, 0.34, awning)
		draw_building_face_light(building, side, -face_half * 0.55, ground_y + 1.95, warm)
		draw_building_face_light(building, side, face_half * 0.55, ground_y + 1.95, warm)
	}
}

building_view_sides :: proc(building: Building, viewer: rl.Vector3) -> (int, int) {
	x_side := 3
	if viewer.x >= building.center.x { x_side = 1 }
	z_side := 0
	if viewer.z >= building.center.z { z_side = 2 }
	return x_side, z_side
}

draw_mid_distance_windows :: proc(building: Building, index: int, viewer: rl.Vector3) {
	// Medium LOD for roughly the third visible city block: keep windows on the two
	// faces pointing toward the player, but omit expensive signs, lanterns and trim.
	side_a, side_b := building_view_sides(building, viewer)
	ground_y := building.center.y - building.half.y
	floor_count := clamp(int(building.half.y / 1.65), 2, 5)
	for pass in 0..<2 {
		side := side_a
		if pass != 0 { side = side_b }
		face_half := building_face_half_length(building, side)
		for floor in 0..<floor_count {
			y := ground_y + 1.35 + f32(floor) * 1.72
			if y >= building.center.y + building.half.y - 0.45 { break }
			for window in 0..<3 {
				along := -face_half * 0.56 + f32(window) * face_half * 0.56
				window_color := rl.Color{31, 48, 61, 255}
				if (index + side + floor + window) % 3 != 0 {
					window_color = {242, 190, 105, 255}
				}
				if building.zone == .CHINATOWN && (index + floor + window) % 2 == 0 {
					window_color = {244, 172, 80, 255}
				}
				draw_building_face_panel(building, side, along, y, max(0.42, face_half * 0.24), 0.48, 0.055, window_color)
			}
		}
	}
}

draw_buildings :: proc() {
	viewer := car_position()
	for i in 0..<building_count {
		building := buildings[i]
		distance := horizontal_distance(building.center, viewer)
		// Real city blocks behind the player do not need to remain resident all the
		// way across this 300 m map; the dedicated skyline still carries the horizon.
		if distance > 125.0 { continue }

		size := building.half * 2
		rl.DrawCube(building.center, size.x, size.y, size.z, building.color)
		roof_color := rl.Color{92, 124, 145, 255}
		if building.zone == .INDUSTRIAL { roof_color = {126, 105, 77, 255} }
		if building.zone == .RESORT { roof_color = {215, 205, 165, 255} }
		if building.zone == .CHINATOWN { roof_color = {94, 45, 39, 255} }
		roof_y := building.center.y + building.half.y + 0.08
		rl.DrawCube({building.center.x, roof_y, building.center.z}, size.x * 0.82, 0.14, size.z * 0.82, roof_color)

		// Keep two to three blocks of windows visible. Full facade detail stays near
		// the player; the third block uses only the two player-facing window faces.
		if distance > 78.0 { continue }
		if distance > 50.0 {
			draw_mid_distance_windows(building, i, viewer)
			continue
		}
		if distance <= 28.0 {
			rl.DrawCubeWires(building.center, size.x, size.y, size.z, {27, 31, 39, 220})
		}

		#partial switch building.zone {
		case .COMMERCIAL:
			draw_commercial_facade(building, i)
		case .CHINATOWN:
			draw_chinatown_facade(building, i)
		case .RESIDENTIAL:
			draw_residential_facade(building, i)
		case .INDUSTRIAL:
			draw_industrial_facade(building, i)
		case .RESORT:
			draw_resort_facade(building, i)
		}
	}
}

draw_waterfront_rail_span :: proc(start, finish: rl.Vector3) {
	delta := finish - start
	length := horizontal_length(delta)
	if length <= 0.02 { return }
	tangent := delta / length
	center := (start + finish) * 0.5
	base_y := road_elevation_at(center.x, center.z)
	yaw := b3.Atan2(tangent.z, tangent.x)

	// NYC-style waterfront promenade: continuous low stone curb, dark steel
	// uprights, and two slim rails. Only bridge openings intentionally break it.
	stone := rl.Color{104, 108, 109, 255}
	stone_cap := rl.Color{139, 143, 143, 255}
	iron := rl.Color{24, 34, 40, 255}

	draw_oriented_box(
		center + rl.Vector3{0, base_y + RIVER_RAIL_BASE_HEIGHT * 0.5, 0},
		{length * 0.5, RIVER_RAIL_BASE_HEIGHT * 0.5, 0.28},
		yaw,
		stone,
	)
	draw_oriented_box(
		center + rl.Vector3{0, base_y + RIVER_RAIL_BASE_HEIGHT + 0.035, 0},
		{length * 0.5, 0.035, 0.33},
		yaw,
		stone_cap,
	)

	post_count := max(2, int(length / RIVER_RAIL_POST_SPACING) + 1)
	for post in 0..<post_count {
		t: f32 = 0
		if post_count > 1 {
			t = f32(post) / f32(post_count - 1)
		}
		position := start + delta * t
		post_base_y := road_elevation_at(position.x, position.z)
		position.y = post_base_y + RIVER_RAIL_BASE_HEIGHT + RIVER_RAIL_POST_HEIGHT * 0.5
		draw_oriented_box(position, {0.070, RIVER_RAIL_POST_HEIGHT * 0.5, 0.070}, yaw, iron)
	}

	for rail in 0..<2 {
		rail_y := base_y + RIVER_RAIL_BASE_HEIGHT + 0.42
		if rail != 0 { rail_y = base_y + RIVER_RAIL_BASE_HEIGHT + 0.88 }
		draw_oriented_box(
			center + rl.Vector3{0, rail_y, 0},
			{length * 0.5, 0.045, 0.045},
			yaw,
			iron,
		)
	}
}

draw_river_bank_side_segment :: proc(
	start, finish: rl.Vector3,
	side_sign, start_inner_sign, finish_inner_sign: f32,
	bridge: Bridge_Type,
	bridge_center: rl.Vector3,
	open_to_finish: bool,
) {
	delta := finish - start
	length := horizontal_length(delta)
	if length <= 0.01 { return }
	tangent := delta / length
	right := rl.Vector3{-tangent.z, 0, tangent.x}
	bank_start, bank_finish := river_bank_side_endpoints(
		start,
		finish,
		side_sign,
		start_inner_sign,
		finish_inner_sign,
	)

	if bridge == .NONE {
		if open_to_finish {
			// No rails at the river mouth.
			return
		}
		draw_waterfront_rail_span(bank_start, bank_finish)
		return
	}

	opening_half := ROAD_WIDTH * 0.5 + BRIDGE_ENTRANCE_NOTCH_PADDING
	opening_center := bridge_center + right * (RIVER_HALF_WIDTH * side_sign)
	left_finish := opening_center - tangent * opening_half
	right_start := opening_center + tangent * opening_half
	left_length := (left_finish.x - bank_start.x) * tangent.x + (left_finish.z - bank_start.z) * tangent.z
	right_length := (bank_finish.x - right_start.x) * tangent.x + (bank_finish.z - right_start.z) * tangent.z
	if left_length > 0.05 {
		draw_waterfront_rail_span(bank_start, left_finish)
	}
	if !open_to_finish && right_length > 0.05 {
		draw_waterfront_rail_span(right_start, bank_finish)
	}
}

draw_river_segment_banks :: proc(
	start, finish: rl.Vector3,
	bridge: Bridge_Type,
	start_inner_sign, finish_inner_sign: f32,
	bridge_center: rl.Vector3,
	open_to_finish: bool,
) {
	for side in 0..<2 {
		sign: f32 = -1
		if side != 0 { sign = 1 }
		draw_river_bank_side_segment(
			start,
			finish,
			sign,
			start_inner_sign,
			finish_inner_sign,
			bridge,
			bridge_center,
			open_to_finish,
		)
	}
}

// A river turn has exactly one extra corner piece: the OUTER chamfer.
// The inner radius is a plain right-angle bank created by trimming the two
// adjacent straight spans; do not draw any inner arc/chamfer/miter here.
draw_river_corner_banks :: proc(previous, corner, next: rl.Vector3) {
	has_turn, inner_sign := river_corner_inner_side_sign(previous, corner, next)
	if !has_turn { return }

	in_delta := corner - previous
	out_delta := next - corner
	in_tangent := in_delta / horizontal_length(in_delta)
	out_tangent := out_delta / horizontal_length(out_delta)
	in_right := rl.Vector3{-in_tangent.z, 0, in_tangent.x}
	out_right := rl.Vector3{-out_tangent.z, 0, out_tangent.x}
	outer_sign := -inner_sign

	outer_start := corner + in_right * (RIVER_HALF_WIDTH * outer_sign)
	outer_finish := corner + out_right * (RIVER_HALF_WIDTH * outer_sign)
	draw_waterfront_rail_span(outer_start, outer_finish)
}

draw_river_banks :: proc() {
	if river_path_count <= 0 { return }
	point_count := river_path_count + 2

	for segment_index in 0..<(point_count - 1) {
		start := river_centerline_point(segment_index)
		finish := river_centerline_point(segment_index + 1)
		start_inner_sign: f32 = 0
		finish_inner_sign: f32 = 0

		if segment_index > 0 {
			has_turn, inner_sign := river_corner_inner_side_sign(
				river_centerline_point(segment_index - 1),
				start,
				finish,
			)
			if has_turn { start_inner_sign = inner_sign }
		}
		if segment_index + 2 < point_count {
			has_turn, inner_sign := river_corner_inner_side_sign(
				start,
				finish,
				river_centerline_point(segment_index + 2),
			)
			if has_turn { finish_inner_sign = inner_sign }
		}

		draw_river_segment_banks(
			start,
			finish,
			river_bridge_for_segment(segment_index),
			start_inner_sign,
			finish_inner_sign,
			river_bridge_opening_center_for_segment(segment_index),
			segment_index == point_count - 2,
		)
	}

	for corner_index in 1..<(point_count - 1) {
		draw_river_corner_banks(
			river_centerline_point(corner_index - 1),
			river_centerline_point(corner_index),
			river_centerline_point(corner_index + 1),
		)
	}
}

river_endpoint_for_edge :: proc(cell: River_Cell, edge: int, coast: bool) -> rl.Vector3 {
	center := river_cell_world_center(cell)
	switch edge {
	case 0:
		center.z = CITY_MIN_Z
		if coast { center.z += coast_inset_at_along_for_edge(edge, center.x) }
	case 1:
		center.x = CITY_MAX_X
		if coast { center.x -= coast_inset_at_along_for_edge(edge, center.z) }
	case 2:
		center.z = CITY_MAX_Z
		if coast { center.z -= coast_inset_at_along_for_edge(edge, center.x) }
	case:
		center.x = CITY_MIN_X
		if coast { center.x += coast_inset_at_along_for_edge(edge, center.z) }
	}
	return center
}

draw_normal_bridge :: proc(crossing: River_Crossing) {
	center := river_crossing_world_center(crossing)
	axis := crossing_road_axis(crossing)
	right := rl.Vector3{-axis.z, 0, axis.x}
	base_y := road_elevation_at(center.x, center.z)
	deck := rl.Color{72, 74, 79, 255}
	parapet := rl.Color{178, 174, 161, 255}
	yaw := b3.Atan2(axis.z, axis.x)
	draw_oriented_box(center + rl.Vector3{0, base_y + 0.15, 0}, {NORMAL_BRIDGE_HALF_LENGTH, 0.13, ROAD_WIDTH * 0.5}, yaw, deck)
	for side in 0..<2 {
		sign: f32 = -1
		if side != 0 { sign = 1 }
		position := center + right * (ROAD_WIDTH * 0.49 * sign) + rl.Vector3{0, base_y + 0.44, 0}
		draw_oriented_box(position, {NORMAL_BRIDGE_HALF_LENGTH - BRIDGE_SIDE_BARRIER_END_INSET, 0.25, 0.11}, yaw, parapet)
	}
	draw_oriented_box(center + rl.Vector3{0, base_y + 0.30, 0}, {NORMAL_BRIDGE_HALF_LENGTH - 0.4, 0.018, 0.09}, yaw, {224, 214, 171, 220})
}

draw_jump_bridge :: proc(crossing: River_Crossing) {
	center := river_crossing_world_center(crossing)
	axis := crossing_road_axis(crossing)
	right := rl.Vector3{-axis.z, 0, axis.x}
	base_y := road_elevation_at(center.x, center.z)
	ramp_color := rl.Color{73, 79, 88, 255}
	hazard := rl.Color{245, 180, 48, 255}

	left_outer := center - axis * (JUMP_BRIDGE_HALF_GAP + JUMP_BRIDGE_RAMP_LENGTH)
	left_inner := center - axis * JUMP_BRIDGE_HALF_GAP
	right_inner := center + axis * JUMP_BRIDGE_HALF_GAP
	right_outer := center + axis * (JUMP_BRIDGE_HALF_GAP + JUMP_BRIDGE_RAMP_LENGTH)
	left_outer.y = base_y + JUMP_BRIDGE_BASE_HEIGHT
	left_inner.y = base_y + JUMP_BRIDGE_PEAK_HEIGHT
	right_outer.y = base_y + JUMP_BRIDGE_BASE_HEIGHT
	right_inner.y = base_y + JUMP_BRIDGE_PEAK_HEIGHT

	draw_elevated_strip(left_outer, left_inner, ROAD_WIDTH, ramp_color)
	draw_elevated_strip(right_outer, right_inner, ROAD_WIDTH, ramp_color)

	yaw := b3.Atan2(axis.z, axis.x)
	for inner_index in 0..<2 {
		inner := left_inner
		if inner_index != 0 { inner = right_inner }
		draw_oriented_box(inner + rl.Vector3{0, 0.05, 0}, {0.12, 0.05, ROAD_WIDTH * 0.5}, yaw, hazard)
	}
	for side in 0..<2 {
		sign: f32 = -1
		if side != 0 { sign = 1 }
		offset := right * (ROAD_WIDTH * 0.48 * sign)
		draw_elevated_strip(left_outer + offset + rl.Vector3{0, 0.06, 0}, left_inner + offset + rl.Vector3{0, 0.06, 0}, 0.16, hazard)
		draw_elevated_strip(right_outer + offset + rl.Vector3{0, 0.06, 0}, right_inner + offset + rl.Vector3{0, 0.06, 0}, 0.16, hazard)

		// Only guard the inner half near the river gap. The outer flank stays open so
		// the player can still side-enter the jump ramp from the road shoulder.
		rail_color := rl.Color{31, 39, 43, 255}
		ramp_guard_length := JUMP_BRIDGE_RAMP_LENGTH * 0.44
		left_guard_start := left_inner - axis * ramp_guard_length
		right_guard_end := right_inner + axis * ramp_guard_length
		draw_elevated_strip(left_guard_start + offset + rl.Vector3{0, 0.58, 0}, left_inner + offset + rl.Vector3{0, 0.58, 0}, 0.11, rail_color)
		draw_elevated_strip(right_inner + offset + rl.Vector3{0, 0.58, 0}, right_guard_end + offset + rl.Vector3{0, 0.58, 0}, 0.11, rail_color)
	}
}

draw_river_and_bridges :: proc() {
	if river_path_count <= 0 { return }
	water := rl.Color{31, 111, 164, 238}

	entry := river_endpoint_for_edge(river_path[0], river_entry_edge, false)
	first := river_cell_world_center(river_path[0])
	draw_elevated_strip(entry + rl.Vector3{0, 0.05, 0}, first + rl.Vector3{0, 0.05, 0}, RIVER_HALF_WIDTH * 2.0, water)
	for index in 1..<river_path_count {
		start := river_cell_world_center(river_path[index - 1])
		finish := river_cell_world_center(river_path[index])
		start.y = road_elevation_at(start.x, start.z) + 0.05
		finish.y = road_elevation_at(finish.x, finish.z) + 0.05
		draw_elevated_strip(start, finish, RIVER_HALF_WIDTH * 2.0, water)
	}
	last := river_cell_world_center(river_path[river_path_count - 1])
	exit := river_endpoint_for_edge(river_path[river_path_count - 1], river_exit_edge, true)
	draw_elevated_strip(last + rl.Vector3{0, 0.05, 0}, exit + rl.Vector3{0, 0.05, 0}, RIVER_HALF_WIDTH * 2.0, water)

	// Round-ish pools at grid corners keep the orthogonal river path from looking
	// like disconnected rectangles while preserving the readable low-poly style.
	for index in 0..<river_path_count {
		center := river_cell_world_center(river_path[index])
		center.y = road_elevation_at(center.x, center.z) + 0.02
		rl.DrawCylinder(center, RIVER_HALF_WIDTH, RIVER_HALF_WIDTH, 0.06, 14, water)
	}

	draw_river_banks()
	if river_entry_bridge_valid {
		draw_normal_bridge(river_entry_bridge)
	}
	if river_exit_bridge_valid {
		draw_normal_bridge(river_exit_bridge)
	}
	for index in 0..<river_crossing_count {
		#partial switch river_crossings[index].bridge {
		case .NORMAL:
			draw_normal_bridge(river_crossings[index])
		case .JUMP:
			draw_jump_bridge(river_crossings[index])
		}
	}
}

coast_inward_vector_for_edge :: proc(edge: int) -> rl.Vector3 {
	switch edge {
	case 0: return {0, 0, 1}
	case 1: return {-1, 0, 0}
	case 2: return {0, 0, -1}
	case:   return {1, 0, 0}
	}
}

draw_beach_edge :: proc(edge: int, secondary: bool) {
	sand := BEACH_SAND_COLOR
	sea := SEA_COLOR
	foam := rl.Color{232, 240, 232, 220}
	inward := coast_inward_vector_for_edge(edge)
	count := coast_profile_count(secondary)
	for sample in 0..<(count - 1) {
		p0 := coast_world_point_for_edge(edge, secondary, sample)
		p1 := coast_world_point_for_edge(edge, secondary, sample + 1)
		sea0 := p0 - inward * 46.0
		sea1 := p1 - inward * 46.0
		sand0 := p0 + inward * BEACH_DRIVE_DEPTH
		sand1 := p1 + inward * BEACH_DRIVE_DEPTH
		promenade0 := p0 + inward * (BEACH_DRIVE_DEPTH + COAST_PROMENADE_DEPTH)
		promenade1 := p1 + inward * (BEACH_DRIVE_DEPTH + COAST_PROMENADE_DEPTH)
		p0.y = 0.018
		p1.y = 0.018
		sea0.y = 0.010
		sea1.y = 0.010
		sand0.y = 0.018
		sand1.y = 0.018
		promenade0.y = 0.019
		promenade1.y = 0.019
		draw_quad_double_sided(sea0, sea1, p1, p0, sea)
		draw_quad_double_sided(p0, p1, sand1, sand0, sand)
		draw_quad_double_sided(sand0, sand1, promenade1, promenade0, {201, 181, 136, 255})
		draw_elevated_strip(p0 + rl.Vector3{0, 0.025, 0}, p1 + rl.Vector3{0, 0.025, 0}, 0.70, foam)
	}
}

draw_beach_corner :: proc() {
	sea := SEA_COLOR
	sand := BEACH_SAND_COLOR
	foam := rl.Color{232, 240, 232, 220}
	for segment in 0..<COAST_CORNER_SEGMENTS {
		shore0 := coast_corner_curve_point(segment)
		shore1 := coast_corner_curve_point(segment + 1)
		sea0 := coast_corner_curve_point(segment, -46.0)
		sea1 := coast_corner_curve_point(segment + 1, -46.0)
		sand0 := coast_corner_curve_point(segment, BEACH_DRIVE_DEPTH)
		sand1 := coast_corner_curve_point(segment + 1, BEACH_DRIVE_DEPTH)
		promenade0 := coast_corner_curve_point(segment, BEACH_DRIVE_DEPTH + COAST_PROMENADE_DEPTH)
		promenade1 := coast_corner_curve_point(segment + 1, BEACH_DRIVE_DEPTH + COAST_PROMENADE_DEPTH)
		shore0.y = 0.018
		shore1.y = 0.018
		sea0.y = 0.010
		sea1.y = 0.010
		sand0.y = 0.018
		sand1.y = 0.018
		promenade0.y = 0.019
		promenade1.y = 0.019
		draw_quad_double_sided(sea0, sea1, shore1, shore0, sea)
		draw_quad_double_sided(shore0, shore1, sand1, sand0, sand)
		draw_quad_double_sided(sand0, sand1, promenade1, promenade0, {201, 181, 136, 255})
		draw_elevated_strip(shore0 + rl.Vector3{0, 0.020, 0}, shore1 + rl.Vector3{0, 0.020, 0}, 0.70, foam)
	}
}

draw_ocean_base_for_edge :: proc(edge: int) {
	depth := f32(180.0)
	if edge == 0 {
		rl.DrawCube({0, -0.035, CITY_MIN_Z - depth * 0.5}, CITY_MAX_X - CITY_MIN_X, 0.02, depth, SEA_COLOR)
	} else if edge == 1 {
		rl.DrawCube({CITY_MAX_X + depth * 0.5, -0.035, 0}, depth, 0.02, CITY_MAX_Z - CITY_MIN_Z, SEA_COLOR)
	} else if edge == 2 {
		rl.DrawCube({0, -0.035, CITY_MAX_Z + depth * 0.5}, CITY_MAX_X - CITY_MIN_X, 0.02, depth, SEA_COLOR)
	} else {
		rl.DrawCube({CITY_MIN_X - depth * 0.5, -0.035, 0}, depth, 0.02, CITY_MAX_Z - CITY_MIN_Z, SEA_COLOR)
	}
}

draw_ocean_corner_base :: proc() {
	corner := coast_shared_corner_position()
	primary_out := coast_inward_vector_for_edge(beach_edge) * -1.0
	secondary_out := coast_inward_vector_for_edge(beach_edge_secondary) * -1.0
	depth := f32(90.0)
	center := corner + primary_out * (depth * 0.5) + secondary_out * (depth * 0.5)
	rl.DrawCube(center + rl.Vector3{0, -0.035, 0}, depth, 0.02, depth, SEA_COLOR)
}

draw_ocean_base :: proc() {
	// This is a coastal corner: exactly two adjacent sides are ocean. The Fuji
	// side and the city-continuation side always remain land.
	draw_ocean_base_for_edge(beach_edge)
	draw_ocean_base_for_edge(beach_edge_secondary)
	draw_ocean_corner_base()
}

draw_beach_and_sea :: proc() {
	draw_beach_edge(beach_edge, false)
	draw_beach_edge(beach_edge_secondary, true)
	draw_beach_corner()
}

mountain_world_position :: proc() -> rl.Vector3 {
	position := rl.Vector3{0, 0, CITY_MIN_Z - 78}
	switch mountain_edge {
	case 1: position = {CITY_MAX_X + 78, 0, 0}
	case 2: position = {0, 0, CITY_MAX_Z + 78}
	case 3: position = {CITY_MIN_X - 78, 0, 0}
	}
	return position
}

mountain_mesh_radius :: proc(base_radius: f32, ring, segment: int) -> f32 {
	angle := f32(segment) * 1.73 + f32(ring) * 0.61
	wobble := 1.0 + math.sin(angle) * 0.065 + math.sin(angle * 2.17 + 0.8) * 0.032
	return base_radius * wobble
}

mountain_surface_color :: proc(ring, segment: int) -> rl.Color {
	rock_dark := rl.Color{55, 62, 64, 255}
	rock := rl.Color{70, 78, 78, 255}
	rock_light := rl.Color{83, 90, 88, 255}
	snow_shadow := rl.Color{198, 211, 216, 255}
	snow := rl.Color{239, 242, 239, 255}
	if ring >= 4 {
		if (segment + ring) % 4 == 0 { return snow_shadow }
		return snow
	}
	if ring == 3 && segment % 3 != 0 {
		return snow_shadow
	}
	if segment % 5 == 0 { return rock_dark }
	if segment % 3 == 0 { return rock_light }
	return rock
}

draw_mountain_foothill_ground :: proc() {
	// Mt. Fuji should rise from land, not from a flat glacier sheet sitting on
	// the ocean. Give the off-map mountain side a broad earthy foreground apron
	// so the cone feels anchored to terrain.
	grass := rl.Color{92, 110, 84, 255}
	grass_shadow := rl.Color{74, 88, 69, 255}
	rock := rl.Color{110, 114, 108, 255}
	sample_count := 7
	for sample in 0..<sample_count {
		t0 := f32(sample) / f32(sample_count)
		t1 := f32(sample + 1) / f32(sample_count)
		d0 := t0 * 44.0
		d1 := t1 * 44.0
		y0 := 0.02 + t0 * 0.70
		y1 := 0.02 + t1 * 0.70
		color := grass
		if sample % 2 != 0 { color = grass_shadow }
		if sample >= sample_count - 2 { color = rock }

		switch mountain_edge {
		case 0:
			draw_quad_double_sided(
				{CITY_MIN_X, y0, CITY_MIN_Z - d0},
				{CITY_MAX_X, y0, CITY_MIN_Z - d0},
				{CITY_MAX_X, y1, CITY_MIN_Z - d1},
				{CITY_MIN_X, y1, CITY_MIN_Z - d1},
				color,
			)
		case 1:
			draw_quad_double_sided(
				{CITY_MAX_X + d0, y0, CITY_MIN_Z},
				{CITY_MAX_X + d0, y0, CITY_MAX_Z},
				{CITY_MAX_X + d1, y1, CITY_MAX_Z},
				{CITY_MAX_X + d1, y1, CITY_MIN_Z},
				color,
			)
		case 2:
			draw_quad_double_sided(
				{CITY_MIN_X, y0, CITY_MAX_Z + d0},
				{CITY_MAX_X, y0, CITY_MAX_Z + d0},
				{CITY_MAX_X, y1, CITY_MAX_Z + d1},
				{CITY_MIN_X, y1, CITY_MAX_Z + d1},
				color,
			)
		case:
			draw_quad_double_sided(
				{CITY_MIN_X - d0, y0, CITY_MIN_Z},
				{CITY_MIN_X - d0, y0, CITY_MAX_Z},
				{CITY_MIN_X - d1, y1, CITY_MAX_Z},
				{CITY_MIN_X - d1, y1, CITY_MIN_Z},
				color,
			)
		}
	}
}

mountain_edge_ground_point :: proc(along, inward: f32) -> rl.Vector3 {
	x: f32 = along
	z := CITY_MIN_Z + inward
	if mountain_edge == 1 {
		x = CITY_MAX_X - inward
		z = along
	} else if mountain_edge == 2 {
		x = along
		z = CITY_MAX_Z - inward
	} else if mountain_edge == 3 {
		x = CITY_MIN_X + inward
		z = along
	}
	return {x, road_elevation_at(x, z) + 0.12, z}
}

draw_mountain_cherry_grove :: proc() {
	// Petal scatter should feel wind-blown and irregular rather than arranged in
	// a tidy strip. Keep it deterministic, but vary width, depth and rotation cues.
	minimum, maximum := coast_sample_along_bounds_for_edge(mountain_edge)
	sample_span := max(1, int(maximum - minimum - 4.0))
	for petal in 0..<156 {
		base := minimum + 2.0 + f32((petal * 23) % sample_span)
		along := clamp(base + f32(((petal * 19) % 9) - 4) * 0.9, minimum + 1.0, maximum - 1.0)
		inward := 3.5 + f32((petal * 17 + petal * petal) % 38) * 0.85
		position := mountain_edge_ground_point(along, inward)
		if mountain_edge == 0 || mountain_edge == 2 {
			position.x += f32(((petal * 7) % 7) - 3) * 0.20
		} else {
			position.z += f32(((petal * 7) % 7) - 3) * 0.20
		}
		petal_color := rl.Color{248, 164, 192, 220}
		if petal % 3 == 0 { petal_color = {255, 205, 217, 220} }
		if petal % 5 == 0 { petal_color = {242, 147, 184, 210} }
		width := 0.18 + f32(petal % 4) * 0.09
		depth := 0.10 + f32((petal * 3) % 4) * 0.06
		rl.DrawCube(position + rl.Vector3{0, 0.018, 0}, width, 0.025, depth, petal_color)
	}
}

draw_torii_gate :: proc(position: rl.Vector3, yaw, scale: f32) {
	gate_position := position
	previous_world_active := world_visual_deform_active
	previous_world_anchor := world_visual_deform_anchor
	world_visual_deform_active = bounce_mode
	world_visual_deform_anchor = gate_position
	defer {
		world_visual_deform_active = previous_world_active
		world_visual_deform_anchor = previous_world_anchor
	}
	red := rl.Color{185, 42, 34, 255}
	dark := rl.Color{68, 42, 33, 255}
	right := right_from_yaw(yaw)
	post_offset := ROAD_WIDTH * 0.44
	left_post := gate_position - right * post_offset + rl.Vector3{0, 1.55 * scale, 0}
	right_post := gate_position + right * post_offset + rl.Vector3{0, 1.55 * scale, 0}
	draw_oriented_box(left_post, {0.16 * scale, 1.55 * scale, 0.16 * scale}, yaw, red)
	draw_oriented_box(right_post, {0.16 * scale, 1.55 * scale, 0.16 * scale}, yaw, red)
	draw_oriented_box(gate_position + rl.Vector3{0, 2.75 * scale, 0}, {post_offset + 0.65 * scale, 0.18 * scale, 0.22 * scale}, yaw, red)
	draw_oriented_box(gate_position + rl.Vector3{0, 3.18 * scale, 0}, {post_offset + 1.05 * scale, 0.14 * scale, 0.26 * scale}, yaw, red)
	draw_oriented_box(gate_position + rl.Vector3{0, 2.44 * scale, 0}, {post_offset * 0.72, 0.10 * scale, 0.18 * scale}, yaw, dark)
}

draw_mountain_torii_road :: proc() {
	forward := rl.Vector3{0, 0, 1}
	yaw: f32 = 0
	switch mountain_edge {
	case 0:
		forward = {0, 0, 1}
		yaw = 0
	case 1:
		forward = {-1, 0, 0}
		yaw = rl.PI * 0.5
	case 2:
		forward = {0, 0, -1}
		yaw = 0
	case:
		forward = {1, 0, 0}
		yaw = rl.PI * 0.5
	}
	first := mountain_edge_ground_point(0, 3.5)
	last := mountain_edge_ground_point(0, 43.0)
	first.y = 0.032
	last.y = 0.032
	draw_elevated_strip(first, last, ROAD_WIDTH * 0.92, rl.Color{38, 41, 48, 255})
	for gate in 0..<5 {
		inward := 7.0 + f32(gate) * 9.0
		position := mountain_edge_ground_point(0, inward)
		position = position + forward * 0.15
		draw_torii_gate(position, yaw, 0.92 - f32(gate) * 0.025)
	}
}

mountain_edge_outside_point :: proc(along, distance: f32) -> rl.Vector3 {
	x := along
	z := CITY_MIN_Z - distance
	if mountain_edge == 1 {
		x = CITY_MAX_X + distance
		z = along
	} else if mountain_edge == 2 {
		x = along
		z = CITY_MAX_Z + distance
	} else if mountain_edge == 3 {
		x = CITY_MIN_X - distance
		z = along
	}
	return {x, 0, z}
}

draw_foothill_house :: proc(position: rl.Vector3, index: int, yaw: f32) {
	width := 4.8 + f32(index % 4) * 0.75
	depth := 4.4 + f32((index * 3) % 4) * 0.60
	height := 2.7 + f32(index % 3) * 0.55
	body_colors := [5]rl.Color{
		{196, 190, 174, 255},
		{174, 168, 153, 255},
		{151, 143, 132, 255},
		{184, 174, 157, 255},
		{136, 139, 134, 255},
	}
	body := body_colors[index % len(body_colors)]
	roof := rl.Color{62, 64, 62, 255}
	if index % 3 == 0 { roof = {74, 66, 58, 255} }

	center := position + rl.Vector3{0, height * 0.5, 0}
	draw_oriented_box(center, {width * 0.5, height * 0.5, depth * 0.5}, yaw, body)
	// A shallow dark roof reads as the low tiled/sloped roofline common around
	// Fujiyoshida/Fujinomiya without adding a heavy mesh system.
	draw_oriented_box(position + rl.Vector3{0, height + 0.18, 0}, {width * 0.56, 0.18, depth * 0.58}, yaw, roof)

	front := position + forward_from_yaw(yaw) * (depth * 0.505)
	front.y = height * 0.56
	window := rl.Color{37, 55, 66, 255}
	for pane in 0..<2 {
		sign: f32 = -1
		if pane != 0 { sign = 1 }
		pane_center := front + right_from_yaw(yaw) * (width * 0.22 * sign)
		draw_oriented_box(pane_center, {0.52, 0.40, 0.035}, yaw, window)
	}
}

draw_mountain_foothill_town :: proc() {
	// Reference silhouette: low detached homes and small shop-like buildings flank
	// the view toward Fuji, leaving a central visual corridor to the mountain.
	yaw: f32 = 0
	if mountain_edge == 1 || mountain_edge == 3 { yaw = rl.PI * 0.5 }
	minimum, maximum := coast_sample_along_bounds_for_edge(mountain_edge)
	for row in 0..<2 {
		distance := 9.0 + f32(row) * 12.0
		for index in 0..<11 {
			t := (f32(index) + 0.5) / 11.0
			along := lerp_f32(minimum + 3.0, maximum - 3.0, t)
			if abs_f32(along) < 10.0 { continue }
			position := mountain_edge_outside_point(along, distance)
			position.y = 0.05 + distance / 44.0 * 0.70
			draw_foothill_house(position, index + row * 11, yaw)
		}
	}

	// Sparse utility poles are as important to the Fuji-foot streetscape as the
	// buildings themselves, but keep them low-poly and decorative.
	pole_color := rl.Color{77, 73, 67, 255}
	for pole in 0..<7 {
		t := (f32(pole) + 0.5) / 7.0
		along := lerp_f32(minimum + 7.0, maximum - 7.0, t)
		if abs_f32(along) < 8.0 { continue }
		position := mountain_edge_outside_point(along, 5.5)
		position.y = 2.2
		rl.DrawCube(position, 0.16, 4.4, 0.16, pole_color)
		bar_y := position.y + 1.55
		if mountain_edge == 0 || mountain_edge == 2 {
			rl.DrawCube({position.x, bar_y, position.z}, 1.3, 0.10, 0.10, pole_color)
		} else {
			rl.DrawCube({position.x, bar_y, position.z}, 0.10, 0.10, 1.3, pole_color)
		}
	}
}

draw_mountain :: proc() {
	position := mountain_world_position()
	ring_heights := [7]f32{0, 9, 23, 39, 55, 69, 82}
	ring_radii := [7]f32{68, 64, 54, 41, 28, 15, 5.5}
	segment_count := 28

	// Hand-built low-poly rings give the mountain shoulders, ridges and an
	// irregular snow line instead of one perfect primitive cone.
	for ring in 0..<6 {
		for segment in 0..<segment_count {
			next_segment := (segment + 1) % segment_count
			angle_a := f32(segment) * (rl.PI * 2.0 / f32(segment_count))
			angle_b := f32(next_segment) * (rl.PI * 2.0 / f32(segment_count))
			r0a := mountain_mesh_radius(ring_radii[ring], ring, segment)
			r0b := mountain_mesh_radius(ring_radii[ring], ring, next_segment)
			r1a := mountain_mesh_radius(ring_radii[ring + 1], ring + 1, segment)
			r1b := mountain_mesh_radius(ring_radii[ring + 1], ring + 1, next_segment)

			a := position + rl.Vector3{math.cos(angle_a) * r0a, ring_heights[ring], math.sin(angle_a) * r0a}
			b := position + rl.Vector3{math.cos(angle_b) * r0b, ring_heights[ring], math.sin(angle_b) * r0b}
			c := position + rl.Vector3{math.cos(angle_b) * r1b, ring_heights[ring + 1], math.sin(angle_b) * r1b}
			d := position + rl.Vector3{math.cos(angle_a) * r1a, ring_heights[ring + 1], math.sin(angle_a) * r1a}
			draw_quad_double_sided(a, b, c, d, mountain_surface_color(ring, segment))
		}
	}

	// Dark crater lip keeps the top from reading as another pointed triangle.
	rl.DrawCylinder(position + rl.Vector3{0, 81.6, 0}, 4.2, 5.0, 1.0, 18, {48, 55, 57, 255})
	draw_mountain_foothill_ground()
	draw_mountain_foothill_town()
	draw_mountain_cherry_grove()
	draw_mountain_torii_road()
}

city_edge :: proc() -> int {
	for edge in 0..<4 {
		if edge != beach_edge && edge != beach_edge_secondary && edge != mountain_edge {
			return edge
		}
	}
	return 0
}

city_edge_outward_axis :: proc(edge: int) -> rl.Vector3 {
	switch edge {
	case 0: return {0, 0, -1}
	case 1: return {1, 0, 0}
	case 2: return {0, 0, 1}
	case:  return {-1, 0, 0}
	}
}

city_edge_road_count :: proc(edge: int) -> int {
	if edge == 0 || edge == 2 { return ROAD_X_COUNT }
	return ROAD_Z_COUNT
}

city_edge_exit_node :: proc(edge, index: int) -> rl.Vector3 {
	switch edge {
	case 0:
		return route_grid_position(index, 0)
	case 1:
		return route_grid_position(ROAD_X_COUNT - 1, index)
	case 2:
		return route_grid_position(index, ROAD_Z_COUNT - 1)
	case:
		return route_grid_position(0, index)
	}
}

city_edge_exit_open :: proc(edge, index: int) -> bool {
	// The city-facing side visually continues beyond the playable map. Every
	// boundary street that actually exists on land is therefore an exit street.
	// Do NOT test the inward route edge here: that previously made some visible
	// streets receive an invisible wall but no matching visible barricade.
	switch edge {
	case 0:
		return route_grid_valid(index, 0)
	case 1:
		return route_grid_valid(ROAD_X_COUNT - 1, index)
	case 2:
		return route_grid_valid(index, ROAD_Z_COUNT - 1)
	case:
		return route_grid_valid(0, index)
	}
}

draw_city_outskirts_ground :: proc() {
	edge := city_edge()
	ground := rl.Color{70, 82, 74, 255}
	roadside := rl.Color{90, 97, 90, 255}
	switch edge {
	case 0:
		center_z := CITY_MIN_Z - CITY_OUTSKIRTS_DEPTH * 0.5
		rl.DrawCube({0, -0.03, center_z}, CITY_MAX_X - CITY_MIN_X, 0.18, CITY_OUTSKIRTS_DEPTH, ground)
		rl.DrawCube({0, 0.015, CITY_MIN_Z - 4.2}, CITY_MAX_X - CITY_MIN_X, 0.04, 7.8, roadside)
	case 1:
		center_x := CITY_MAX_X + CITY_OUTSKIRTS_DEPTH * 0.5
		rl.DrawCube({center_x, -0.03, 0}, CITY_OUTSKIRTS_DEPTH, 0.18, CITY_MAX_Z - CITY_MIN_Z, ground)
		rl.DrawCube({CITY_MAX_X + 4.2, 0.015, 0}, 7.8, 0.04, CITY_MAX_Z - CITY_MIN_Z, roadside)
	case 2:
		center_z := CITY_MAX_Z + CITY_OUTSKIRTS_DEPTH * 0.5
		rl.DrawCube({0, -0.03, center_z}, CITY_MAX_X - CITY_MIN_X, 0.18, CITY_OUTSKIRTS_DEPTH, ground)
		rl.DrawCube({0, 0.015, CITY_MAX_Z + 4.2}, CITY_MAX_X - CITY_MIN_X, 0.04, 7.8, roadside)
	case:
		center_x := CITY_MIN_X - CITY_OUTSKIRTS_DEPTH * 0.5
		rl.DrawCube({center_x, -0.03, 0}, CITY_OUTSKIRTS_DEPTH, 0.18, CITY_MAX_Z - CITY_MIN_Z, ground)
		rl.DrawCube({CITY_MIN_X - 4.2, 0.015, 0}, 7.8, 0.04, CITY_MAX_Z - CITY_MIN_Z, roadside)
	}
}

draw_city_edge_road_extensions :: proc() {
	edge := city_edge()
	outward := city_edge_outward_axis(edge)
	asphalt := rl.Color{31, 34, 42, 255}
	for index in 0..<city_edge_road_count(edge) {
		if !city_edge_exit_open(edge, index) { continue }
		start := city_edge_exit_node(edge, index) + outward * (ROAD_WIDTH * 0.5)
		finish := city_edge_exit_node(edge, index) + outward * CITY_EDGE_ROAD_EXTENSION_LENGTH
		start.y = 0.027
		finish.y = 0.027
		draw_elevated_strip(start, finish, ROAD_WIDTH, asphalt)
		stripe_a := city_edge_exit_node(edge, index) + outward * 5.8
		stripe_b := city_edge_exit_node(edge, index) + outward * 10.8
		stripe_a.y = 0.08
		stripe_b.y = 0.08
		draw_elevated_strip(stripe_a, stripe_b, 0.28, {224, 204, 108, 220})
	}
}

draw_city_exit_barrier :: proc(edge, index: int) {
	center := city_edge_exit_node(edge, index) + city_edge_outward_axis(edge) * CITY_EDGE_BARRIER_OFFSET
	center.y = 0.52
	previous_world_active := world_visual_deform_active
	previous_world_anchor := world_visual_deform_anchor
	world_visual_deform_active = bounce_mode
	world_visual_deform_anchor = {center.x, 0, center.z}
	defer {
		world_visual_deform_active = previous_world_active
		world_visual_deform_anchor = previous_world_anchor
	}
	road_axis := city_edge_outward_axis(edge)
	barrier_axis := rl.Vector3{-road_axis.z, 0, road_axis.x}
	yaw := b3.Atan2(barrier_axis.z, barrier_axis.x)
	white := rl.Color{236, 235, 229, 255}
	red := rl.Color{205, 48, 48, 255}
	dark := rl.Color{68, 72, 76, 255}
	draw_oriented_box(center, {CITY_EDGE_BARRIER_HALF_SPAN, 0.18, CITY_EDGE_BARRIER_HALF_THICKNESS}, yaw, white)
	for marker in 0..<3 {
		offset := (f32(marker) - 1.0) * 2.15
		marker_center := center + barrier_axis * offset - road_axis * 0.19 + rl.Vector3{0, 0.01, 0}
		draw_oriented_box(marker_center, {0.75, 0.10, 0.04}, yaw, red)
	}
	for side in 0..<2 {
		sign: f32 = -1
		if side != 0 { sign = 1 }
		leg := center + barrier_axis * (CITY_EDGE_BARRIER_HALF_SPAN * 0.70 * sign) + rl.Vector3{0, -0.28, 0}
		draw_oriented_box(leg, {0.08, 0.26, 0.08}, yaw, dark)
	}
}

draw_city_exit_barriers :: proc() {
	edge := city_edge()
	for index in 0..<city_edge_road_count(edge) {
		if city_edge_exit_open(edge, index) {
			draw_city_exit_barrier(edge, index)
		}
	}
}

create_city_outskirts_block_span :: proc(edge: int, along_start, along_end: f32) {
	if along_end - along_start <= ROAD_WIDTH + 0.25 { return }
	half_along := (along_end - along_start) * 0.5
	center_along := (along_start + along_end) * 0.5
	half_depth := CITY_OUTSKIRTS_DEPTH * 0.5 - 0.35
	center_depth := CITY_OUTSKIRTS_DEPTH * 0.5
	switch edge {
	case 0:
		_ = create_static_box({center_along, 0.80, CITY_MIN_Z - center_depth}, {half_along, 0.80, half_depth})
	case 1:
		_ = create_static_box({CITY_MAX_X + center_depth, 0.80, center_along}, {half_depth, 0.80, half_along})
	case 2:
		_ = create_static_box({center_along, 0.80, CITY_MAX_Z + center_depth}, {half_along, 0.80, half_depth})
	case:
		_ = create_static_box({CITY_MIN_X - center_depth, 0.80, center_along}, {half_depth, 0.80, half_along})
	}
}

create_city_outskirts_blockers :: proc(edge: int) {
	gap_half := ROAD_WIDTH * 0.56
	minimum, maximum := coast_sample_along_bounds_for_edge(edge)
	cursor := minimum
	for index in 0..<city_edge_road_count(edge) {
		if !city_edge_exit_open(edge, index) { continue }
		center := city_edge_exit_node(edge, index)
		along := center.x
		if edge == 1 || edge == 3 { along = center.z }
		gap_start := max(along - gap_half, minimum)
		gap_end := min(along + gap_half, maximum)
		create_city_outskirts_block_span(edge, cursor, gap_start)
		cursor = max(cursor, gap_end)
	}
	create_city_outskirts_block_span(edge, cursor, maximum)
}

create_city_exit_barrier_collider :: proc(edge, index: int) {
	center := city_edge_exit_node(edge, index) + city_edge_outward_axis(edge) * CITY_EDGE_BARRIER_OFFSET
	center.y = 0.52
	road_axis := city_edge_outward_axis(edge)
	barrier_axis := rl.Vector3{-road_axis.z, 0, road_axis.x}
	yaw := b3.Atan2(barrier_axis.z, barrier_axis.x)
	_ = create_static_rotated_box(
		center,
		{CITY_EDGE_BARRIER_HALF_SPAN, 0.22, CITY_EDGE_BARRIER_HALF_THICKNESS + 0.08},
		b3.MakeQuatFromAxisAngle({0, 1, 0}, -yaw),
	)
}

create_city_exit_shoulder_blockers :: proc(edge, index: int) {
	node := city_edge_exit_node(edge, index)
	road_axis := city_edge_outward_axis(edge)
	right := rl.Vector3{-road_axis.z, 0, road_axis.x}
	center := node + road_axis * (CITY_EDGE_BARRIER_OFFSET * 0.5)
	center.y = 0.75
	half_length := max((CITY_EDGE_BARRIER_OFFSET - ROAD_WIDTH * 0.25) * 0.5, 0.40)
	shoulder_offset := ROAD_WIDTH * 0.5 + CITY_EDGE_SHOULDER_CLEARANCE + CITY_EDGE_SHOULDER_BLOCK_HALF_WIDTH
	for side in 0..<2 {
		sign: f32 = -1
		if side != 0 { sign = 1 }
		_ = create_static_rotated_box(
			center + right * (shoulder_offset * sign),
			{half_length, 0.75, CITY_EDGE_SHOULDER_BLOCK_HALF_WIDTH},
			b3.MakeQuatFromAxisAngle({0, 1, 0}, -b3.Atan2(road_axis.z, road_axis.x)),
		)
	}
}

create_city_exit_barrier_colliders :: proc() {
	edge := city_edge()

	// Solid green outskirts are blocked in the spans BETWEEN exit roads. Each
	// road itself remains physically free until the visible white/red barricade.
	create_city_outskirts_blockers(edge)

	for index in 0..<city_edge_road_count(edge) {
		if !city_edge_exit_open(edge, index) { continue }
		create_city_exit_barrier_collider(edge, index)
	}
}


draw_mountain_guardrail_edge :: proc(edge: int) {
	wood := rl.Color{106, 78, 51, 255}
	metal := rl.Color{196, 194, 177, 255}
	post_count := 30
	for post in 0..=post_count {
		t := f32(post) / f32(post_count)
		switch edge {
		case 0:
			x := lerp_f32(CITY_MIN_X, CITY_MAX_X, t)
			z := CITY_MIN_Z - 1.0
			y := road_elevation_at(x, z) + 0.58
			rl.DrawCube({x, y, z}, 0.20, 1.16, 0.20, wood)
		case 2:
			x := lerp_f32(CITY_MIN_X, CITY_MAX_X, t)
			z := CITY_MAX_Z + 1.0
			y := road_elevation_at(x, z) + 0.58
			rl.DrawCube({x, y, z}, 0.20, 1.16, 0.20, wood)
		case:
			z := lerp_f32(CITY_MIN_Z, CITY_MAX_Z, t)
			x := CITY_MIN_X - 1.0
			if edge == 1 { x = CITY_MAX_X + 1.0 }
			y := road_elevation_at(x, z) + 0.58
			rl.DrawCube({x, y, z}, 0.20, 1.16, 0.20, wood)
		}
	}

	// Two continuous pale rails read as a scenic mountain-road guardrail rather
	// than the old generic hard wall.
	if edge == 0 || edge == 2 {
		z := CITY_MIN_Z - 1.0
		if edge == 2 { z = CITY_MAX_Z + 1.0 }
		y := road_elevation_at(0, z)
		rl.DrawCube({0, y + 0.55, z}, CITY_MAX_X - CITY_MIN_X, 0.14, 0.18, metal)
		rl.DrawCube({0, y + 0.95, z}, CITY_MAX_X - CITY_MIN_X, 0.14, 0.18, metal)
	} else {
		x := CITY_MIN_X - 1.0
		if edge == 1 { x = CITY_MAX_X + 1.0 }
		y := road_elevation_at(x, 0)
		rl.DrawCube({x, y + 0.55, 0}, 0.18, 0.14, CITY_MAX_Z - CITY_MIN_Z, metal)
		rl.DrawCube({x, y + 0.95, 0}, 0.18, 0.14, CITY_MAX_Z - CITY_MIN_Z, metal)
	}
}

draw_boundary_barriers :: proc() {
	draw_mountain_guardrail_edge(mountain_edge)
}

draw_night_sky_background :: proc() {
	// Layered bands avoid depending on a gradient helper and keep the sky deterministic.
	for band in 0..<24 {
		t := f32(band) / 23.0
		r := u8(5.0 + t * 11.0)
		g := u8(9.0 + t * 16.0)
		b := u8(24.0 + t * 27.0)
		y0 := i32(f32(WINDOW_HEIGHT) * f32(band) / 24.0)
		y1 := i32(f32(WINDOW_HEIGHT) * f32(band + 1) / 24.0)
		rl.DrawRectangle(0, y0, WINDOW_WIDTH, y1 - y0 + 1, {r, g, b, 255})
	}

	// Treat the 2D star field as a cylindrical panorama. Stars slide with
	// camera yaw instead of being glued to one screen coordinate.
	view := camera.target - camera.position
	view_yaw := b3.Atan2(view.x, -view.z)
	pan := view_yaw / (2.0 * rl.PI) * f32(WINDOW_WIDTH)

	for star in 0..<72 {
		x := f32((star * 83 + star * star * 7 + 31) % WINDOW_WIDTH) - pan
		for x < 0.0 { x += f32(WINDOW_WIDTH) }
		for x >= f32(WINDOW_WIDTH) { x -= f32(WINDOW_WIDTH) }
		y := i32((star * 47 + star * star * 3 + 19) % 510)
		radius: f32 = 1.0
		if star % 11 == 0 { radius = 1.7 }
		brightness := u8(150 + (star * 37) % 106)
		rl.DrawCircle(i32(x), y, radius, {brightness, brightness, 225, 220})
	}


	for glow in 0..<6 {
		alpha := u8(34 - glow * 5)
		y := i32(500 + glow * 24)
		rl.DrawRectangle(0, y, WINDOW_WIDTH, 25, {74, 55, 102, alpha})
	}
}

draw_distant_tower :: proc(edge, index: int, along, distance, height, width: f32) {
	dark := rl.Color{18, 24, 38, 255}
	if index % 3 == 1 { dark = {23, 29, 43, 255} }
	if index % 3 == 2 { dark = {28, 27, 42, 255} }
	center := rl.Vector3{along, height * 0.5, CITY_MIN_Z - distance}
	half_x := width * 0.5
	half_z := width * 0.42
	if edge == 1 {
		center = {CITY_MAX_X + distance, height * 0.5, along}
	} else if edge == 2 {
		center = {along, height * 0.5, CITY_MAX_Z + distance}
	} else if edge == 3 {
		center = {CITY_MIN_X - distance, height * 0.5, along}
	}
	rl.DrawCube(center, half_x * 2.0, height, half_z * 2.0, dark)

	// A few bright bands are enough to read as occupied distant towers.
	for floor in 0..<3 {
		if (floor + index) % 3 == 0 { continue }
		y := 3.0 + f32(floor) * max(2.6, height / 7.0)
		if y > height - 1.5 { break }
		light := rl.Color{236, 184, 96, 210}
		if (floor + index) % 4 == 0 { light = {104, 184, 232, 210} }
		switch edge {
		case 0:
			rl.DrawCube({center.x, y, center.z + half_z + 0.04}, width * 0.58, 0.32, 0.08, light)
		case 1:
			rl.DrawCube({center.x - half_x - 0.04, y, center.z}, 0.08, 0.32, width * 0.58, light)
		case 2:
			rl.DrawCube({center.x, y, center.z - half_z - 0.04}, width * 0.58, 0.32, 0.08, light)
		case 3:
			rl.DrawCube({center.x + half_x + 0.04, y, center.z}, 0.08, 0.32, width * 0.58, light)
		}
	}
}

draw_distant_city_skyline :: proc() {
	for edge in 0..<4 {
		if edge == mountain_edge || edge == beach_edge || edge == beach_edge_secondary { continue }
		for row in 0..<4 {
			row_distance := 10.0 + f32(row) * 8.0
			row_count := 12 + row * 4
			for tower in 0..<row_count {
				t := (f32(tower) + 0.5) / f32(row_count)
				along := lerp_f32(CITY_MIN_X + 1.5, CITY_MAX_X - 1.5, t)
				if edge == 1 || edge == 3 {
					along = lerp_f32(CITY_MIN_Z + 1.5, CITY_MAX_Z - 1.5, t)
				}
				along += f32(((tower * 7 + row * 5) % 7) - 3) * 0.85
				height := 10.0 + f32((tower * 17 + row * 23 + edge * 13) % 42)
				if row == 0 { height += 10.0 }
				if row == 1 && tower % 3 == 0 { height += 8.0 }
				width := 5.5 + f32((tower * 11 + row * 7 + edge * 5) % 7)
				distance := row_distance + f32((tower * 5 + edge * 3) % 5)
				draw_distant_tower(edge, tower + row * 100 + edge * 500, along, distance, height, width)
			}
		}
	}
}

draw_city :: proc() {
	draw_ocean_base()
	draw_city_outskirts_ground()
	draw_background_forests()
	draw_distant_city_skyline()
	rl.DrawCube({0, -0.12, 0}, CITY_MAX_X - CITY_MIN_X, 0.24, CITY_MAX_Z - CITY_MIN_Z, {54, 73, 58, 255})
	draw_beach_and_sea()
	draw_mountain()
	// Do not drape a visual-only foothill slope across the flat Box3D city floor.
	// Keeping the mountain outside the gameplay plane avoids floating roads.
	draw_roads()
	draw_city_edge_road_extensions()
	draw_road_markings()
	draw_blocks_and_props()
	draw_buildings()
	// Chinatown gates are world landmarks and must be drawn after the buildings so
	// their red silhouettes cannot disappear behind facade geometry.
	draw_chinatown_entrances()
	draw_destructible_props()
	draw_river_and_bridges()
	draw_boundary_barriers()
	draw_city_exit_barriers()
}

draw_checkpoint_arrow_yaw :: proc(index: int) -> f32 {
	return CHECKPOINTS[index].next_yaw
}

draw_arrow_triangle :: proc(a, b, c: rl.Vector3, color: rl.Color) {
	// The gate frame/stem uses draw_oriented_box(), which already applies the
	// world bounce transform. Apply the exact same transform to the raw triangle
	// vertices so the arrow head squashes/stretches with the rest of the gate.
	ta := world_visual_transform_point(a)
	tb := world_visual_transform_point(b)
	tc := world_visual_transform_point(c)
	// Draw both windings so the arrow stays visible from either side of the gate.
	rl.DrawTriangle3D(ta, tb, tc, color)
	rl.DrawTriangle3D(tc, tb, ta, color)
}

draw_horizontal_gate_arrow :: proc(
	origin,
	right,
	normal: rl.Vector3,
	yaw,
	direction: f32,
	color: rl.Color,
	scale: f32,
	depth_offset: f32,
) {
	facing_offset := normal * depth_offset
	stem_center := origin + right * (-0.28 * direction * scale) + facing_offset
	draw_oriented_box(stem_center, {0.92 * scale, 0.24 * scale, 0.08}, yaw, color)

	base_center := origin + right * (0.48 * direction * scale) + facing_offset
	tip := origin + right * (1.58 * direction * scale) + facing_offset
	upper := base_center + rl.Vector3{0, 0.78 * scale, 0}
	lower := base_center - rl.Vector3{0, 0.78 * scale, 0}
	draw_arrow_triangle(upper, lower, tip, color)
}

draw_straight_gate_arrow :: proc(
	origin,
	normal: rl.Vector3,
	yaw: f32,
	color: rl.Color,
	scale: f32,
	depth_offset: f32,
) {
	facing_offset := normal * depth_offset
	stem_center := origin + rl.Vector3{0, -0.25 * scale, 0} + facing_offset
	draw_oriented_box(stem_center, {0.24 * scale, 0.90 * scale, 0.08}, yaw, color)

	base_center := origin + rl.Vector3{0, 0.48 * scale, 0} + facing_offset
	tip := origin + rl.Vector3{0, 1.60 * scale, 0} + facing_offset
	right := right_from_yaw(yaw)
	left_base := base_center - right * (0.78 * scale)
	right_base := base_center + right * (0.78 * scale)
	draw_arrow_triangle(left_base, right_base, tip, color)
}

gate_layer_colors :: proc(layer: int) -> (fill, outline: rl.Color) {
	switch layer {
	case 0:
		return {60, 225, 255, 255}, {4, 7, 11, 255}
	case 1:
		return {60, 225, 255, 100}, {4, 7, 11, 135}
	case:
		return {60, 225, 255, 32}, {4, 7, 11, 64}
	}
}

draw_checkpoint_arrow :: proc(index, layer: int) {
	checkpoint := CHECKPOINTS[index]
		current_forward := forward_from_yaw(checkpoint.yaw)
	current_right := right_from_yaw(checkpoint.yaw)
	origin := checkpoint.position + rl.Vector3{0, 5.20, 0}

	turn_amount: f32 = 0
	if index < active_checkpoint_count - 1 {
		next_yaw := draw_checkpoint_arrow_yaw(index)
		next_forward := forward_from_yaw(next_yaw)
		turn_amount = current_right.x * next_forward.x + current_right.z * next_forward.z
	}

	fill, outline := gate_layer_colors(layer)
	if turn_amount > 0.45 {
		draw_horizontal_gate_arrow(origin, current_right, current_forward, checkpoint.yaw, 1, outline, 1.18, 0)
		draw_horizontal_gate_arrow(origin, current_right, current_forward, checkpoint.yaw, 1, fill, 1.0, -0.035)
	} else if turn_amount < -0.45 {
		draw_horizontal_gate_arrow(origin, current_right, current_forward, checkpoint.yaw, -1, outline, 1.18, 0)
		draw_horizontal_gate_arrow(origin, current_right, current_forward, checkpoint.yaw, -1, fill, 1.0, -0.035)
	} else {
		draw_straight_gate_arrow(origin, current_forward, checkpoint.yaw, outline, 1.18, 0)
		draw_straight_gate_arrow(origin, current_forward, checkpoint.yaw, fill, 1.0, -0.035)
	}
}

draw_finish_gate :: proc(checkpoint: Checkpoint, layer: int) {
	previous_world_active := world_visual_deform_active
	previous_world_anchor := world_visual_deform_anchor
	world_visual_deform_active = bounce_mode
	world_visual_deform_anchor = checkpoint.position
	defer {
		world_visual_deform_active = previous_world_active
		world_visual_deform_anchor = previous_world_anchor
	}
	right := right_from_yaw(checkpoint.yaw)
	alpha: u8 = 255
	if layer == 1 {
		alpha = 105
	} else if layer >= 2 {
		alpha = 38
	}
	white := rl.Color{238, 240, 242, alpha}
	black := rl.Color{12, 14, 18, alpha}
	gate_half_width := CHECKPOINT_HALF_WIDTH

	left_post := checkpoint.position - right * gate_half_width + rl.Vector3{0, 1.42, 0}
	right_post := checkpoint.position + right * gate_half_width + rl.Vector3{0, 1.42, 0}
	draw_oriented_box(left_post, {0.16, 1.5, 0.16}, checkpoint.yaw, white)
	draw_oriented_box(right_post, {0.16, 1.5, 0.16}, checkpoint.yaw, white)

	cell_width := gate_half_width * 2.0 / 10.0
	cell_half_width := cell_width * 0.5
	cell_half_height: f32 = 0.24
	for row in 0..<2 {
		for column in 0..<10 {
			color := white
			if (row + column) % 2 != 0 {
				color = black
			}

			x_offset := -gate_half_width + cell_half_width + f32(column) * cell_width
			y_offset := 2.68 + f32(row) * 0.48
			cell_center := checkpoint.position + right * x_offset + rl.Vector3{0, y_offset, 0}
			draw_oriented_box(cell_center, {cell_half_width, cell_half_height, 0.10}, checkpoint.yaw, color)
		}
	}
}

draw_route_gate :: proc(index, layer: int) {
	checkpoint := CHECKPOINTS[index]
		if index == active_checkpoint_count - 1 {
		draw_finish_gate(checkpoint, layer)
		return
	}

	previous_world_active := world_visual_deform_active
	previous_world_anchor := world_visual_deform_anchor
	world_visual_deform_active = bounce_mode
	world_visual_deform_anchor = checkpoint.position
	defer {
		world_visual_deform_active = previous_world_active
		world_visual_deform_anchor = previous_world_anchor
	}

	fill, _ := gate_layer_colors(layer)
	right := right_from_yaw(checkpoint.yaw)
	gate_half_width := CHECKPOINT_HALF_WIDTH
	left_post := checkpoint.position - right * gate_half_width + rl.Vector3{0, 1.42, 0}
	right_post := checkpoint.position + right * gate_half_width + rl.Vector3{0, 1.42, 0}
	top_bar := checkpoint.position + rl.Vector3{0, 2.92, 0}

	draw_oriented_box(left_post, {0.13, 1.5, 0.13}, checkpoint.yaw, fill)
	draw_oriented_box(right_post, {0.13, 1.5, 0.13}, checkpoint.yaw, fill)
	draw_oriented_box(top_bar, {gate_half_width + 0.13, 0.13, 0.13}, checkpoint.yaw, fill)
	draw_checkpoint_arrow(index, layer)
}

draw_checkpoint :: proc() {
	if setup_active || race.completed || active_checkpoint_count <= 0 {
		return
	}

	// Draw the current target fully, then two previews with rapidly decreasing opacity.
	// Rendering far previews first gives the active gate the cleanest silhouette.
	for reverse_layer in 0..<3 {
		layer := 2 - reverse_layer
		index := race.checkpoint + layer
		if index >= active_checkpoint_count {
			continue
		}
		draw_route_gate(index, layer)
	}
}
