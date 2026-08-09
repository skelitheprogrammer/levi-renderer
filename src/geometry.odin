package levi

import "gpu/gpu"

Attribute_Index :: distinct u32

Geometry_Handle :: distinct u32
Invalid_Geometry :: Geometry_Handle(0)

Geometry_Range :: struct {
	vertex_offset: u32,
	vertex_count:  u32,
	index_offset:  u32,
	index_count:   u32,
	aabb_min:      [3]f32,
	aabb_max:      [3]f32,
}


Geometry_Desc :: struct {
	vertex_count: u32,
	streams:      [][]u8,
	indices:      []u32,
	aabb_min:     [3]f32,
	aabb_max:     [3]f32,
}

Geometry_Storage :: struct {
	strides:         []u32,
	streams:         []gpu.slice_t(u8),
	vertex_used:     u64,
	vertex_capacity: u64,
	indices:         gpu.slice_t(u32),
	index_used:      u64,
	index_capacity:  u64,
	ranges:          [dynamic]Geometry_Range,
	gpu_ranges:      gpu.slice_t(Geometry_Range),
	handle_to_range: [dynamic]u32,
	free_handles:    [dynamic]u32,
	dead:            [dynamic]gpu.gpuptr,
	dirty:           bool,
}

Geometry_Upload_Stage :: struct {
	storage: ^Geometry_Storage,
	descs:   [dynamic]Geometry_Desc,
	handles: [dynamic]Geometry_Handle,
}

geometry_create :: proc(
	strides: []u32,
	initial_vertices: u64 = 1,
	initial_indices: u64 = 1,
) -> Geometry_Storage {
	assert(len(strides) > 0)

	g: Geometry_Storage

	g.strides = make([]u32, len(strides))
	copy(g.strides, strides)

	g.streams = make([]gpu.slice_t(u8), len(strides))

	g.vertex_capacity = max(initial_vertices, 1)

	for a in 0 ..< len(strides) {
		assert(strides[a] > 0)
		bytes := int(g.vertex_capacity * u64(strides[a]))
		g.streams[a] = gpu.mem_alloc_slice(u8, bytes, .GPU)
	}

	g.index_capacity = max(initial_indices, 1)
	g.indices = gpu.mem_alloc_slice(u32, int(g.index_capacity), .GPU)

	return g
}

geometry_destroy :: proc(g: ^Geometry_Storage) {
	if g == nil {
		return
	}

	for &s in g.streams {
		if s.gpu.ptr != nil {
			gpu.mem_free(s)
		}
	}

	if g.indices.gpu.ptr != nil {
		gpu.mem_free(g.indices)
	}

	if g.gpu_ranges.gpu.ptr != nil {
		gpu.mem_free(g.gpu_ranges)
	}

	for p in g.dead {
		gpu.mem_free_raw(p)
	}

	delete(g.strides)
	delete(g.streams)
	delete(g.ranges)
	delete(g.handle_to_range)
	delete(g.free_handles)
	delete(g.dead)

	g^ = {}
}

geometry_validate_desc :: proc(strides: []u32, desc: Geometry_Desc) -> bool {
	if desc.vertex_count == 0 {
		return false
	}

	if len(desc.indices) == 0 {
		return false
	}

	if len(strides) == 0 {
		return false
	}

	if len(desc.streams) != len(strides) {
		return false
	}

	for a in 0 ..< len(strides) {
		stride := strides[a]
		if stride == 0 {
			return false
		}

		expected := u64(desc.vertex_count) * u64(stride)
		if u64(len(desc.streams[a])) != expected {
			return false
		}
	}

	return true
}

grow_capacity :: proc(current: u64, needed: u64) -> u64 {
	if needed <= current {
		return current
	}

	doubled := current * 2
	if doubled == 0 || doubled < needed {
		return needed
	}

	return doubled
}

geometry_upload_begin :: proc(storage: ^Geometry_Storage) -> Geometry_Upload_Stage {
	assert(storage != nil)

	stage: Geometry_Upload_Stage
	stage.storage = storage
	return stage
}


geometry_upload_add :: proc(
	stage: ^Geometry_Upload_Stage,
	desc: Geometry_Desc,
) -> Geometry_Handle {
	assert(stage != nil)
	assert(stage.storage != nil)
	assert(geometry_validate_desc(stage.storage.strides, desc))

	h := allocate_handle(stage.storage)

	append(&stage.descs, desc)
	append(&stage.handles, h)

	return h
}


geometry_upload_commit :: proc(
	stage: ^Geometry_Upload_Stage,
	cmd: gpu.Command_Buffer,
	arena: ^gpu.Arena,
) {
	assert(stage != nil)
	assert(arena != nil)

	storage := stage.storage
	assert(storage != nil)

	if len(stage.descs) == 0 {
		return
	}

	attr_count := len(storage.strides)
	assert(attr_count > 0)

	total_vertices: u64
	total_indices: u64

	for desc in stage.descs {
		assert(geometry_validate_desc(storage.strides, desc))
		total_vertices += u64(desc.vertex_count)
		total_indices += u64(len(desc.indices))
	}

	assert(total_vertices > 0)
	assert(total_indices > 0)

	base_vertex := storage.vertex_used
	base_index := storage.index_used

	ensure_vertex_capacity(storage, base_vertex + total_vertices, cmd)
	ensure_index_capacity(storage, base_index + total_indices, cmd)

	staging_streams := make([]gpu.slice_t(u8), attr_count)
	defer delete(staging_streams)

	for a in 0 ..< attr_count {
		bytes := total_vertices * u64(storage.strides[a])
		staging_streams[a] = gpu.arena_alloc_slice(arena, u8, int(bytes))
	}

	vertex_cursor: u64

	for desc in stage.descs {
		for a in 0 ..< attr_count {
			stride := u64(storage.strides[a])
			start := int(vertex_cursor * stride)
			end := start + len(desc.streams[a])
			copy(staging_streams[a].cpu[start:end], desc.streams[a])
		}
		vertex_cursor += u64(desc.vertex_count)
	}

	for a in 0 ..< attr_count {
		stride := u64(storage.strides[a])
		start := i64(base_vertex * stride)
		end := i64((base_vertex + total_vertices) * stride)

		dst := gpu.subslice(storage.streams[a], start, end)
		gpu.cmd_mem_copy(cmd, dst, staging_streams[a])
	}

	istaging := gpu.arena_alloc_slice(arena, u32, int(total_indices))

	index_cursor: u64

	for desc in stage.descs {
		count := len(desc.indices)
		start := int(index_cursor)
		copy(istaging.cpu[start:start + count], desc.indices)
		index_cursor += u64(count)
	}

	idst := gpu.subslice(storage.indices, i64(base_index), i64(base_index + total_indices))
	gpu.cmd_mem_copy(cmd, idst, istaging)

	v := base_vertex
	i := base_index

	for desc, idx in stage.descs {
		range_idx := len(storage.ranges)

		append(
			&storage.ranges,
			Geometry_Range {
				vertex_offset = u32(v),
				vertex_count = desc.vertex_count,
				index_offset = u32(i),
				index_count = u32(len(desc.indices)),
				aabb_min = desc.aabb_min,
				aabb_max = desc.aabb_max,
			},
		)

		h := stage.handles[idx]
		storage.handle_to_range[handle_index(h)] = u32(range_idx + 1)

		v += u64(desc.vertex_count)
		i += u64(len(desc.indices))
	}

	storage.vertex_used += total_vertices
	storage.index_used += total_indices
	storage.dirty = true
}

geometry_upload_destroy :: proc(stage: ^Geometry_Upload_Stage) {
	if stage == nil {
		return
	}

	delete(stage.descs)
	delete(stage.handles)
	stage^ = {}
}


geometry_upload_submit :: proc(stage: ^Geometry_Upload_Stage) {
	assert(stage != nil)

	if len(stage.descs) == 0 {
		geometry_upload_destroy(stage)
		return
	}

	arena := gpu.arena_create()
	defer gpu.arena_destroy(&arena)

	cmd := gpu.commands_begin(.Main)

	geometry_upload_commit(stage, cmd, &arena)
	gpu.cmd_barrier(cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {cmd})
	gpu.wait_idle()

	geometry_upload_destroy(stage)
}


geometry_add_immediate :: proc(g: ^Geometry_Storage, desc: Geometry_Desc) -> Geometry_Handle {
	stage := geometry_upload_begin(g)
	h := geometry_upload_add(&stage, desc)
	geometry_upload_submit(&stage)
	return h
}


geometry_sync :: proc(g: ^Geometry_Storage, cmd: gpu.Command_Buffer, arena: ^gpu.Arena) {
	assert(g != nil)
	assert(arena != nil)

	if !g.dirty {
		return
	}

	count := len(g.ranges)
	if count == 0 {
		g.dirty = false
		return
	}

	if g.gpu_ranges.gpu.ptr == nil || i64(count) > gpu.slice_len(g.gpu_ranges) {
		if g.gpu_ranges.gpu.ptr != nil {
			append(&g.dead, g.gpu_ranges.gpu)
		}
		g.gpu_ranges = gpu.mem_alloc_slice(Geometry_Range, count, .GPU)
	}

	staging := gpu.arena_alloc_slice(arena, Geometry_Range, count)
	copy(staging.cpu, g.ranges[:])

	gpu.cmd_mem_copy(cmd, g.gpu_ranges, staging)

	g.dirty = false
}


geometry_remove :: proc(g: ^Geometry_Storage, h: Geometry_Handle) {
	if g == nil || h == Invalid_Geometry {
		return
	}

	idx := handle_index(h)
	if idx < 0 || idx >= len(g.handle_to_range) {
		return
	}

	range_ref := g.handle_to_range[idx]
	if range_ref == 0 {
		return
	}

	range_idx := int(range_ref - 1)
	if range_idx < 0 || range_idx >= len(g.ranges) {
		return
	}

	g.ranges[range_idx].vertex_count = 0
	g.ranges[range_idx].index_count = 0

	g.handle_to_range[idx] = 0
	append(&g.free_handles, u32(h))

	g.dirty = true
}

geometry_handle_alive :: proc(g: ^Geometry_Storage, h: Geometry_Handle) -> bool {
	if g == nil || h == Invalid_Geometry {
		return false
	}

	idx := handle_index(h)
	if idx < 0 || idx >= len(g.handle_to_range) {
		return false
	}

	return g.handle_to_range[idx] != 0
}

allocate_handle :: proc(g: ^Geometry_Storage) -> Geometry_Handle {
	assert(g != nil)

	if len(g.free_handles) > 0 {
		return Geometry_Handle(pop(&g.free_handles))
	}

	append(&g.handle_to_range, 0)
	return Geometry_Handle(u32(len(g.handle_to_range)))
}

handle_index :: proc(h: Geometry_Handle) -> int {
	return int(u32(h) - 1)
}

ensure_vertex_capacity :: proc(g: ^Geometry_Storage, needed: u64, cmd: gpu.Command_Buffer) {
	if needed <= g.vertex_capacity {
		return
	}

	new_cap := grow_capacity(g.vertex_capacity, needed)

	for a in 0 ..< len(g.strides) {
		new_bytes := int(new_cap * u64(g.strides[a]))
		new_buf := gpu.mem_alloc_slice(u8, new_bytes, .GPU)

		if g.vertex_used > 0 {
			old_bytes := i64(g.vertex_used * u64(g.strides[a]))
			old_slice := gpu.subslice(g.streams[a], 0, old_bytes)
			new_slice := gpu.subslice(new_buf, 0, old_bytes)
			gpu.cmd_mem_copy(cmd, new_slice, old_slice)
		}

		if g.streams[a].gpu.ptr != nil {
			append(&g.dead, g.streams[a].gpu)
		}

		g.streams[a] = new_buf
	}

	g.vertex_capacity = new_cap
}

ensure_index_capacity :: proc(g: ^Geometry_Storage, needed: u64, cmd: gpu.Command_Buffer) {
	if needed <= g.index_capacity {
		return
	}

	new_cap := grow_capacity(g.index_capacity, needed)
	new_buf := gpu.mem_alloc_slice(u32, int(new_cap), .GPU)

	if g.index_used > 0 {
		old_slice := gpu.subslice(g.indices, 0, i64(g.index_used))
		new_slice := gpu.subslice(new_buf, 0, i64(g.index_used))
		gpu.cmd_mem_copy(cmd, new_slice, old_slice)
	}

	if g.indices.gpu.ptr != nil {
		append(&g.dead, g.indices.gpu)
	}

	g.indices = new_buf
	g.index_capacity = new_cap
}
