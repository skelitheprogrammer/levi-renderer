package levi

import gpu "gpu/gpu"

Indirect_List :: struct {
	commands: gpu.slice_t(gpu.Draw_Indexed_Indirect_Command),
	count:    gpu.ptr_t(u32),
	capacity: int,
}

create_indirect_list :: proc(r: ^Renderer, capacity: int) -> Indirect_List {
	assert(capacity > 0)

	l: Indirect_List
	l.capacity = capacity
	l.commands = gpu.mem_alloc(gpu.Draw_Indexed_Indirect_Command, i32(capacity), gpu.Memory.GPU)
	l.count = gpu.slice_to_ptr(gpu.mem_alloc(u32, 1, gpu.Memory.Default))

	assert(l.count.cpu != nil, "indirect count must be CPU-visible for simple clear")

	l.count.cpu^ = 0

	return l
}

destroy_indirect_list :: proc(r: ^Renderer, l: ^Indirect_List) {
	if l.commands.gpu.ptr != nil {
		gpu.mem_free_slice(l.commands)
	}

	if l.count.gpu.ptr != nil {
		gpu.mem_free_ptr(l.count)
	}

	l^ = {}
}

indirect_list_clear :: proc(l: ^Indirect_List) {
	if l.count.cpu != nil {
		l.count.cpu^ = 0
	}
}
