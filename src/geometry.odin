package levi

import "core:slice"
import gpu "gpu/gpu"

Stream_Data :: struct {
	slot:      u32,
	data:      rawptr,
	count:     int,
	elem_size: int,
	align:     int,
}

Geometry_Meta :: struct {
	first_vertex: int,
	vertex_count: int,
	first_index:  int,
	index_count:  int,
	bounds_min:   [3]f32,
	bounds_max:   [3]f32,
	flags:        u32,
}

Geometry_Pool_Desc :: struct {
	streams:    []Stream_Data,
	indices:    []u32,
	geometries: []Geometry_Meta,
	memory:     gpu.Memory,
}

Geometry_Pool :: struct {
	stream_buffers: [MAX_STREAMS]gpu.slice_t(u8),
	stream_slots:   [MAX_STREAMS]u32,
	stream_strides: [MAX_STREAMS]u32,
	stream_counts:  [MAX_STREAMS]u32,
	stream_count:   int,
	indices:        gpu.slice_t(u32),
	geometries:     gpu.slice_t(Geometry_Record),
	geometry_count: gpu.ptr_t(u32),
}

create_geometry_pool :: proc(r: ^Renderer, desc: Geometry_Pool_Desc) -> Geometry_Pool {
	validate_geometry_pool_desc(desc)

	pool: Geometry_Pool
	pool.stream_count = len(desc.streams)

	temp := gpu.arena_create(r.config.arena_block_size)
	defer gpu.arena_destroy(&temp)

	cmd := gpu.commands_begin(.Main)

	for i in 0 ..< len(desc.streams) {
		s := desc.streams[i]

		bytes := s.count * s.elem_size

		align := 16
		if s.align > 0 {
			align = s.align
		}

		staging := gpu.arena_alloc_raw(&temp, 1, bytes, i32(align))
		assert(staging.cpu != nil)

		dst := slice.from_ptr(cast(^u8)staging.cpu, bytes)
		src := slice.from_ptr(cast(^u8)s.data, bytes)
		copy(dst, src)

		buffer := gpu.mem_alloc(u8, i32(bytes), desc.memory)

		gpu.cmd_mem_copy_raw(cmd, buffer.gpu, staging.gpu, i64(bytes))

		pool.stream_buffers[i] = buffer
		pool.stream_slots[i] = s.slot
		pool.stream_strides[i] = u32(s.elem_size)
		pool.stream_counts[i] = u32(s.count)
	}

	{
		staging := gpu.arena_alloc(&temp, u32, len(desc.indices))
		copy(staging.cpu, desc.indices)

		pool.indices = gpu.mem_alloc(u32, i32(len(desc.indices)), desc.memory)
		gpu.cmd_mem_copy(cmd, pool.indices, staging)
	}

	{
		staging := gpu.arena_alloc(&temp, Geometry_Record, len(desc.geometries))

		for i in 0 ..< len(desc.geometries) {
			m := desc.geometries[i]

			staging.cpu[i] = Geometry_Record {
				bounds_min    = m.bounds_min,
				bounds_max    = m.bounds_max,
				vertex_offset = i32(m.first_vertex),
				vertex_count  = u32(m.vertex_count),
				first_index   = u32(m.first_index),
				index_count   = u32(m.index_count),
				flags         = m.flags,
			}
		}

		pool.geometries = gpu.mem_alloc(Geometry_Record, i32(len(desc.geometries)), desc.memory)
		gpu.cmd_mem_copy(cmd, pool.geometries, staging)
	}

	{
		staging := gpu.arena_alloc(&temp, u32)
		staging.cpu^ = u32(len(desc.geometries))

		pool.geometry_count = gpu.slice_to_ptr(gpu.mem_alloc(u32, 1, desc.memory))
		gpu.cmd_mem_copy_ptr(cmd, pool.geometry_count, staging)
	}

	gpu.cmd_barrier(cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {cmd})

	gpu.wait_idle()

	return pool
}

destroy_geometry_pool :: proc(r: ^Renderer, pool: ^Geometry_Pool) {
	for i in 0 ..< pool.stream_count {
		if pool.stream_buffers[i].gpu.ptr != nil {
			gpu.mem_free_slice(pool.stream_buffers[i])
		}
	}

	if pool.indices.gpu.ptr != nil {
		gpu.mem_free_slice(pool.indices)
	}

	if pool.geometries.gpu.ptr != nil {
		gpu.mem_free_slice(pool.geometries)
	}

	if pool.geometry_count.gpu.ptr != nil {
		gpu.mem_free_ptr(pool.geometry_count)
	}

	pool^ = {}
}

geometry_pool_has_stream :: proc(pool: ^Geometry_Pool, slot: u32) -> bool {
	for i in 0 ..< pool.stream_count {
		if pool.stream_slots[i] == slot {
			return true
		}
	}
	return false
}

geometry_pool_stream_ptr :: proc(pool: ^Geometry_Pool, slot: u32) -> rawptr {
	for i in 0 ..< pool.stream_count {
		if pool.stream_slots[i] == slot {
			return pool.stream_buffers[i].gpu.ptr
		}
	}
	return nil
}

geometry_pool_stream_stride :: proc(pool: ^Geometry_Pool, slot: u32) -> u32 {
	for i in 0 ..< pool.stream_count {
		if pool.stream_slots[i] == slot {
			return pool.stream_strides[i]
		}
	}
	return 0
}

geometry_pool_stream_count :: proc(pool: ^Geometry_Pool, slot: u32) -> u32 {
	for i in 0 ..< pool.stream_count {
		if pool.stream_slots[i] == slot {
			return pool.stream_counts[i]
		}
	}
	return 0
}

validate_geometry_pool_desc :: proc(desc: Geometry_Pool_Desc) {
	assert(len(desc.streams) > 0)
	assert(len(desc.streams) <= MAX_STREAMS)
	assert(len(desc.indices) > 0)
	assert(len(desc.geometries) > 0)

	vertex_count := desc.streams[0].count
	assert(vertex_count > 0)

	for i in 0 ..< len(desc.streams) {
		s := desc.streams[i]

		assert(s.data != nil)
		assert(s.count > 0)
		assert(s.elem_size > 0)
		assert(s.count == vertex_count)

		for j in 0 ..< i {
			assert(desc.streams[j].slot != s.slot)
		}
	}

	for i in 0 ..< len(desc.geometries) {
		m := desc.geometries[i]

		assert(m.first_vertex >= 0)
		assert(m.vertex_count > 0)
		assert(m.first_vertex + m.vertex_count <= vertex_count)

		assert(m.first_index >= 0)
		assert(m.index_count > 0)
		assert(m.first_index + m.index_count <= len(desc.indices))
	}
}
