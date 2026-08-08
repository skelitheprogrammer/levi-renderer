package levi

import "gpu/gpu"

// Per-instance data is separate from geometry.
// This matches glTF's separation of mesh primitives from node transforms [[1]]
// and DOD's principle of separating data by access pattern [[2]].
//
// Instances are GPU-resident and streamable.
// Culling compute shaders read this buffer directly.
// Draw commands reference instances by index, not by pointer.

Instance_Handle :: distinct u32
Invalid_Instance :: Instance_Handle(0)

// Default instance layout.
// Users can define their own struct and use instance_storage_create_custom.
Instance_Data :: struct {
	transform:   [16]f32,
	material_id: u32,
	geometry_id: u32,
	flags:       u32,
	pad:         u32,
}

Instance_Storage :: struct {
	data:      gpu.slice_t(byte),
	stride:    u32,
	count:     u32,
	capacity:  u32,
	free_list: [dynamic]u32,
	dirty:     bool,

	// ponytail: old GPU buffers from growth are parked here and freed at destroy.
	dead:      [dynamic]gpu.gpuptr,
}

// Create instance storage with a known element type.
instance_storage_create :: proc($T: typeid, initial_capacity: u32) -> Instance_Storage {
	assert(initial_capacity > 0)

	s: Instance_Storage
	s.stride = u32(size_of(T))
	s.capacity = initial_capacity
	s.data = gpu.mem_alloc_slice(byte, int(s.capacity * s.stride), .GPU)

	return s
}

// Create instance storage with a custom stride.
// Useful when the user-defined struct is not visible to this package.
instance_storage_create_custom :: proc(stride: u32, initial_capacity: u32) -> Instance_Storage {
	assert(stride > 0)
	assert(initial_capacity > 0)

	s: Instance_Storage
	s.stride = stride
	s.capacity = initial_capacity
	s.data = gpu.mem_alloc_slice(byte, int(s.capacity * stride), .GPU)

	return s
}

instance_storage_destroy :: proc(s: ^Instance_Storage) {
	if s == nil {
		return
	}

	if s.data.gpu.ptr != nil {
		gpu.mem_free(s.data)
	}

	for p in s.dead {
		gpu.mem_free_raw(p)
	}

	delete(s.free_list)
	delete(s.dead)

	s^ = {}
}

// Upload a batch of instances into contiguous slots.
// Returns the base handle for the first uploaded instance.
// Handles are dense: base, base+1, ..., base+count-1.
instance_upload :: proc(
	s: ^Instance_Storage,
	src: []byte,
	cmd: gpu.Command_Buffer,
	arena: ^gpu.Arena,
) -> Instance_Handle {
	assert(s != nil)
	assert(arena != nil)
	assert(s.stride > 0)

	if len(src) == 0 {
		return Invalid_Instance
	}

	element_count := u32(len(src) / int(s.stride))
	assert(element_count > 0)
	assert(len(src) == int(element_count) * int(s.stride))

	base_slot := find_contiguous_slots(s, element_count)
	ensure_instance_capacity(s, base_slot + element_count, cmd)

	staging := gpu.arena_alloc_slice(arena, byte, len(src))
	copy(staging.cpu, src)

	byte_offset := i64(base_slot) * i64(s.stride)
	dst := gpu.subslice(s.data, byte_offset, byte_offset + i64(len(src)))
	gpu.cmd_mem_copy(cmd, dst, staging)

	if base_slot + element_count > s.count {
		s.count = base_slot + element_count
	}

	s.dirty = true

	return Instance_Handle(base_slot + 1)
}

// Upload a typed slice of instances.
instance_upload_typed :: proc(
	s: ^Instance_Storage,
	$T: typeid,
	instances: []T,
	cmd: gpu.Command_Buffer,
	arena: ^gpu.Arena,
) -> Instance_Handle {
	assert(size_of(T) == int(s.stride))

	raw := transmute([]byte)instances
	return instance_upload(s, raw, cmd, arena)
}

// Remove an instance by handle.
// Marks the slot as free for reuse.
// ponytail: does not compact. Add compaction when fragmentation matters.
instance_remove :: proc(s: ^Instance_Storage, h: Instance_Handle) {
	if s == nil || h == Invalid_Instance {
		return
	}

	slot := u32(h) - 1
	if slot >= s.count {
		return
	}

	append(&s.free_list, slot)
	s.dirty = true
}

// Get GPU pointer to the instance buffer.
// Pass this to culling compute shaders and draw passes.
instance_gpu_ptr :: proc(s: ^Instance_Storage) -> gpu.gpuptr {
	if s == nil {
		return {}
	}
	return s.data.gpu
}

// Get current live instance count.
// Note: this includes removed-but-not-compacted slots.
// For GPU culling, pass the capacity or maintain a separate alive mask.
instance_count :: proc(s: ^Instance_Storage) -> u32 {
	if s == nil {
		return 0
	}
	return s.count
}

instance_stride :: proc(s: ^Instance_Storage) -> u32 {
	if s == nil {
		return 0
	}
	return s.stride
}

find_contiguous_slots :: proc(s: ^Instance_Storage, count: u32) -> u32 {
	// ponytail: linear scan of free list for contiguous block.
	// Replace with a proper free-list/buddy allocator when fragmentation matters.
	if count == 1 && len(s.free_list) > 0 {
		return pop(&s.free_list)
	}

	// Fall back to appending at end.
	return s.count
}

ensure_instance_capacity :: proc(s: ^Instance_Storage, needed: u32, cmd: gpu.Command_Buffer) {
	if needed <= s.capacity {
		return
	}

	new_cap := u32(grow_capacity(u64(s.capacity), u64(needed)))
	new_bytes := int(new_cap) * int(s.stride)
	new_buf := gpu.mem_alloc_slice(byte, new_bytes, .GPU)

	if s.count > 0 {
		old_bytes := i64(s.count) * i64(s.stride)
		old_slice := gpu.subslice(s.data, 0, old_bytes)
		new_slice := gpu.subslice(new_buf, 0, old_bytes)
		gpu.cmd_mem_copy(cmd, new_slice, old_slice)
	}

	if s.data.gpu.ptr != nil {
		append(&s.dead, s.data.gpu)
	}

	s.data = new_buf
	s.capacity = new_cap
}
