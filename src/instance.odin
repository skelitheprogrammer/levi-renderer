package levi

import gpu "gpu/gpu"

Instance_Record :: struct {
	model:          [16]f32,
	geometry_index: u32,
	flags:          u32,
	_pad:           [2]u32,
}

Instance_Table :: struct {
	records:   gpu.slice_t(Instance_Record),
	count:     gpu.ptr_t(u32),
	capacity:  int,
	cpu_count: int,
}

create_instance_table :: proc(r: ^Renderer, capacity: int) -> Instance_Table {
	assert(capacity > 0)

	t: Instance_Table
	t.capacity = capacity
	t.cpu_count = 0
	t.records = gpu.mem_alloc(Instance_Record, i32(capacity), gpu.Memory.GPU)
	t.count = gpu.slice_to_ptr(gpu.mem_alloc(u32, 1, gpu.Memory.GPU))

	return t
}

destroy_instance_table :: proc(r: ^Renderer, t: ^Instance_Table) {
	if t.records.gpu.ptr != nil {
		gpu.mem_free_slice(t.records)
	}

	if t.count.gpu.ptr != nil {
		gpu.mem_free_ptr(t.count)
	}

	t^ = {}
}

update_instances :: proc(r: ^Renderer, t: ^Instance_Table, records: []Instance_Record) {
	assert(t.records.gpu.ptr != nil)
	assert(len(records) <= t.capacity)

	t.cpu_count = len(records)

	temp := gpu.arena_create(r.config.arena_block_size)
	defer gpu.arena_destroy(&temp)

	cmd := gpu.commands_begin(.Main)

	if len(records) > 0 {
		staging := gpu.arena_alloc(&temp, Instance_Record, len(records))
		copy(staging.cpu, records)

		// Copies min(dst.len, src.len), so this writes the first len(records) entries.
		gpu.cmd_mem_copy(cmd, t.records, staging)
	}

	{
		staging := gpu.arena_alloc(&temp, u32)
		staging.cpu^ = u32(len(records))

		gpu.cmd_mem_copy_ptr(cmd, t.count, staging)
	}

	gpu.cmd_barrier(cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {cmd})

	// ponytail: wait_idle instance upload.
	// Upgrade path: per-frame instance buffers or timeline semaphore versions.
	gpu.wait_idle()
}
