package main

import rl "vendor:raylib"
import b3 "vendor:box3d"

WINDOW_WIDTH  :: 540
WINDOW_HEIGHT :: 960
FRAMERATE     :: 60
TIME_STEP     :: f32(1.0 / f32(FRAMERATE))
SUB_STEPS     :: 4

CITY_MIN_X :: f32(-132.0)
CITY_MAX_X :: f32(132.0)
CITY_MIN_Z :: f32(-156.0)
CITY_MAX_Z :: f32(156.0)

ROAD_SPACING_METERS :: 24
ROAD_SPACING        :: f32(ROAD_SPACING_METERS)
ROAD_WIDTH          :: f32(8.0)
ROAD_X_COUNT        :: 11
ROAD_Z_COUNT        :: 13
ROAD_ORIGIN_X       :: f32(-120.0)
ROAD_ORIGIN_Z       :: f32(-144.0)
BLOCK_X_COUNT       :: ROAD_X_COUNT - 1
BLOCK_Z_COUNT       :: ROAD_Z_COUNT - 1

COAST_CORNER_SEGMENTS       :: 24
COAST_CORNER_BLEND_SAMPLES  :: 5
COAST_CORNER_FLAT_SAMPLES   :: 2
COAST_CORNER_INSET_MAX      :: f32(10.0)
COAST_CORNER_RADIUS         :: f32(36.0)
COAST_ROAD_CLEARANCE        :: f32(2.5)
BEACH_DRIVE_DEPTH           :: f32(20.0)

BUILDING_MAX :: 720
SMOKE_MAX    :: 96
SKID_MAX     :: 320

MIN_GATE_COUNT     :: 1
MAX_GATE_COUNT     :: 20
DEFAULT_GATE_COUNT :: 10
MAX_CHECKPOINT_COUNT :: MAX_GATE_COUNT + 1

ROUTE_LENGTH_STEP    :: ROAD_SPACING_METERS * 4 // 96 m, roughly 100 m per click
DEFAULT_ROUTE_LENGTH :: 600
MAX_ROUTE_SEGMENT_STEPS :: ROAD_Z_COUNT - 1
MAX_ROUTE_STEPS         :: MAX_CHECKPOINT_COUNT * MAX_ROUTE_SEGMENT_STEPS

CHECKPOINT_HALF_WIDTH :: f32(5.10)
CHECKPOINT_RADIUS     :: f32(6.20)

CAR_HALF_HEIGHT :: f32(0.32)
BUILDING_COLLISION_INSET :: f32(0.06)

BASE_TOP_SPEED     :: f32(34.0)
NITRO_TOP_SPEED    :: f32(46.0)
REVERSE_TOP_SPEED  :: f32(10.0)
ENGINE_ACCEL       :: f32(22.0)
NITRO_ACCEL        :: f32(24.0)
REVERSE_ACCEL      :: f32(16.0)
BRAKE_DECEL        :: f32(40.0)
COAST_DECEL        :: f32(3.0)
BASE_LATERAL_GRIP  :: f32(9.5)
DRIFT_LATERAL_GRIP :: f32(1.55)
NITRO_FULL_BURN_SECONDS    :: f32(2.0)
NITRO_DRIFT_REFILL_PER_SEC :: f32(1.0) // legacy; active drift now refills instantly
HANDBRAKE_DURATION          :: f32(1.0)
RECOVER_BLINK_DURATION      :: f32(1.8)

CAR_BODY_COUNT  :: 20
CAR_COLOR_COUNT :: 20
CAR_PART_COUNT  :: 20

MENU_CAR_RT_WIDTH  :: 250
MENU_CAR_RT_HEIGHT :: 310

Map_Zone :: enum {
	RESIDENTIAL,
	COMMERCIAL,
	CHINATOWN,
	INDUSTRIAL,
	RESORT,
	PARK,
	RIVER,
}

Bridge_Type :: enum {
	NONE,
	NORMAL,
	JUMP,
}

Destructible_Prop_Type :: enum {
	TREE,
	PALM,
	CHERRY,
	LAMP,
	UMBRELLA,
	LOUNGER,
}

DESTRUCTIBLE_PROP_MAX :: 1280

Destructible_Prop :: struct {
	body_id:          b3.BodyId,
	kind:             Destructible_Prop_Type,
	scale:            f32,
	variant:          int,
	initial_position: rl.Vector3,
	initial_yaw:      f32,
	// dynamic_active means this prop has been physically disturbed at least once,
	// so drawing keeps using its Box3D transform even after it is frozen again.
	dynamic_active:   bool,
	// physics_active is the expensive state: only nearby props are dynamic bodies.
	physics_active:   bool,
}

Building :: struct {
	center: rl.Vector3,
	half:   rl.Vector3,
	color:  rl.Color,
	zone:   Map_Zone,
}

Checkpoint :: struct {
	position: rl.Vector3,
	yaw:      f32,
	next_yaw: f32,
}

Race_State :: struct {
	started:       bool,
	completed:     bool,
	elapsed:       f32,
	finish_time:   f32,
	checkpoint:    int,
	gate_armed:    bool,
	intro_visible: bool,
}

Car_State :: struct {
	body_id: b3.BodyId,
	yaw:     f32,
	steer:   f32,
	nitro_charge:   f32,
	handbrake_time: f32,
	recovery_blink_time: f32,
	jump_launch_cooldown: f32,
	water_recovery_time: f32,
	ignore_mouse_frames: int,
	smoke_timer:         f32,
	last_rear_left:  rl.Vector3,
	last_rear_right: rl.Vector3,
	has_last_rear:   bool,
}

Smoke_Particle :: struct {
	active:   bool,
	position: rl.Vector3,
	velocity: rl.Vector3,
	life:     f32,
	max_life: f32,
	radius:   f32,
}

Skid_Segment :: struct {
	active:  bool,
	left_a:  rl.Vector3,
	left_b:  rl.Vector3,
	right_a: rl.Vector3,
	right_b: rl.Vector3,
}

world_id: b3.WorldId
car: Car_State
race: Race_State
camera: rl.Camera3D
camera_ready := false
paused := false
running := true
setup_active := true
finish_cursor_released := false
map_preview_ready := false

selected_gate_count := DEFAULT_GATE_COUNT
selected_route_length := DEFAULT_ROUTE_LENGTH
active_checkpoint_count := DEFAULT_GATE_COUNT + 1
selected_car_body := 0
selected_car_color := 11
selected_car_parts: u32 = 0
garage_parts_open := false
menu_car_rotation: f32
menu_car_target: rl.RenderTexture2D
menu_car_target_ready := false
frame_target: rl.RenderTexture2D
frame_target_ready := false
ui_scale_index := 0
bounce_mode := false
bounce_clock: f32
bounce_wave: f32

buildings: [BUILDING_MAX]Building
building_count := 0
destructible_props: [DESTRUCTIBLE_PROP_MAX]Destructible_Prop
destructible_prop_count := 0
smoke_particles: [SMOKE_MAX]Smoke_Particle
smoke_cursor := 0
skid_segments: [SKID_MAX]Skid_Segment
skid_cursor := 0

previous_route_signature: u64
route_generation_count := 0
map_generation_count := 0

// The route generator chooses these on every preview regeneration.
// The car is spawned on the chosen road node, facing the first route segment.
route_start_x := 4
route_start_z := 8
route_start_direction := 0
race_start_position := rl.Vector3{0, 0.55, 72}
race_start_yaw := f32(0.0)

block_zones: [BLOCK_X_COUNT][BLOCK_Z_COUNT]Map_Zone
RIVER_PATH_MAX :: BLOCK_X_COUNT * BLOCK_Z_COUNT
RIVER_CROSSING_MAX :: RIVER_PATH_MAX
COAST_SAMPLE_MAX :: 32

road_node_land: [ROAD_X_COUNT][ROAD_Z_COUNT]bool
coast_insets: [COAST_SAMPLE_MAX]f32
coast_insets_secondary: [COAST_SAMPLE_MAX]f32
coast_sample_count := (ROAD_X_COUNT - 1) * 2 + 1
coast_sample_count_secondary := (ROAD_Z_COUNT - 1) * 2 + 1
river_entry_edge := 0
river_exit_edge := 2
beach_edge := 2
beach_edge_secondary := 1
mountain_edge := 0
park_min_x := 2
park_min_z := 3
industrial_corner := 0

snap_route_length_to_grid :: proc(distance: int) -> int {
	steps := max(1, (distance + ROAD_SPACING_METERS / 2) / ROAD_SPACING_METERS)
	return steps * ROAD_SPACING_METERS
}

minimum_route_length_for_gates :: proc(gate_count: int) -> int {
	segment_count := clamp(gate_count, MIN_GATE_COUNT, MAX_GATE_COUNT) + 1
	return segment_count * ROAD_SPACING_METERS
}

maximum_route_length_for_gates :: proc(gate_count: int) -> int {
	segment_count := clamp(gate_count, MIN_GATE_COUNT, MAX_GATE_COUNT) + 1
	turn_steps := maximum_turn_route_steps_any_start(segment_count)
	// Revisited intersections are legal, but each undirected street edge can only
	// appear once in a race. The UI therefore never advertises more distance than
	// the generated road graph physically contains.
	steps := min(turn_steps, route_open_edge_count())
	return max(steps, segment_count) * ROAD_SPACING_METERS
}

clamp_selected_route_length :: proc() {
	minimum_length := minimum_route_length_for_gates(selected_gate_count)
	maximum_length := maximum_route_length_for_gates(selected_gate_count)
	selected_route_length = clamp(selected_route_length, minimum_length, maximum_length)
}
