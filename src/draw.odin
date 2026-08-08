package levi

import "gpu/gpu"

Draw_Command_User :: struct {
	material: u32,
	instance: u32,
	flags:    u32,
	pad:      u32,
}

Draw_Command :: struct {
	using cmd: gpu.Draw_Indexed_Indirect_Command,
	user:      Draw_Command_User,
}

Draw_List :: struct {
	commands: gpu.slice_t(Draw_Command),
	count:    gpu.ptr_t(u32),
	capacity: u32,
}

draw_list_create :: proc(capacity: u32) -> Draw_List {
	assert(capacity > 0)

	l: Draw_List
	l.commands = gpu.mem_alloc_slice(Draw_Command, int(capacity), .GPU)
	l.count = gpu.mem_alloc_ptr(u32, .GPU)
	l.capacity = capacity

	return l
}

draw_list_destroy :: proc(l: ^Draw_List) {
	if l == nil {
		return
	}

	if l.commands.gpu.ptr != nil {
		gpu.mem_free(l.commands)
	}

	if l.count.gpu.ptr != nil {
		gpu.mem_free(l.count)
	}

	l^ = {}
}

// ponytail: CPU zeroes one u32.
// If you want fully GPU-driven reset, clear the counter in a compute pass.
draw_list_reset :: proc(f: ^Frame, l: Draw_List) {
	assert(f != nil)

	zero := gpu.arena_alloc(f.arena, u32)
	zero.cpu^ = 0

	gpu.cmd_mem_copy(f.cmd, l.count, zero)
}

execute_draw_list :: proc(
	f: ^Frame,
	vertex_data: gpu.gpuptr,
	fragment_data: gpu.gpuptr,
	indices: gpu.slice_t(u32),
	l: Draw_List,
) {
	assert(f != nil)

	gpu.cmd_draw_indexed_indirect_multi(
		f.cmd,
		vertex_data,
		fragment_data,
		indices,
		l.commands,
		l.count,
	)
}
