package levi

import "core:testing"
import "gpu/gpu"

@(test)
test_grow_capacity :: proc(t: ^testing.T) {
	_ = t

	assert(grow_capacity(0, 10) == 10)
	assert(grow_capacity(8, 10) == 16)
	assert(grow_capacity(16, 10) == 16)
}

@(test)
test_geometry_validate_desc :: proc(t: ^testing.T) {
	_ = t

	strides := []u32{12, 8}

	pos: [36]byte
	uv: [24]byte
	indices := [3]u32{0, 1, 2}

	good := Geometry_Desc {
		vertex_count = 3,
		streams      = [][]u8{pos[:], uv[:]},
		indices      = indices[:],
		aabb_min     = {0, 0, 0},
		aabb_max     = {1, 1, 1},
	}

	assert(geometry_validate_desc(strides, good))

	bad_pos: [24]byte

	bad := Geometry_Desc {
		vertex_count = 3,
		streams      = [][]u8{bad_pos[:], uv[:]},
		indices      = indices[:],
		aabb_min     = {0, 0, 0},
		aabb_max     = {1, 1, 1},
	}

	assert(!geometry_validate_desc(strides, bad))

	no_indices := Geometry_Desc {
		vertex_count = 3,
		streams      = [][]u8{pos[:], uv[:]},
		indices      = nil,
		aabb_min     = {0, 0, 0},
		aabb_max     = {1, 1, 1},
	}

	assert(!geometry_validate_desc(strides, no_indices))
}

@(test)
test_handle_index :: proc(t: ^testing.T) {
	_ = t

	assert(handle_index(Geometry_Handle(1)) == 0)
	assert(handle_index(Geometry_Handle(2)) == 1)
}

@(test)
test_draw_command_prefix :: proc(t: ^testing.T) {
	_ = t

	d: Draw_Command


	assert(rawptr(&d) == rawptr(&d.cmd))

	assert(size_of(Draw_Command) >= size_of(gpu.Draw_Indexed_Indirect_Command))
}

@(test)
test_instance_handle_validity :: proc(t: ^testing.T) {
	_ = t

	assert(Invalid_Instance == Instance_Handle(0))
	assert(u32(Instance_Handle(1)) - 1 == 0)
	assert(u32(Instance_Handle(5)) - 1 == 4)
}

@(test)
test_instance_data_size :: proc(t: ^testing.T) {
	_ = t

	assert(size_of(Instance_Data) == 16 * 4 + 4 * 4)
	assert(size_of(Instance_Data) % 16 == 0)
}
