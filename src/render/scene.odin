package render

import "../gpu/gpu"
import "core:testing"

Attribute_Type :: enum {
	Position,
	Normal,
	UV0,
	Color,
}


ATTRIBUTE_STRIDES := [Attribute_Type]int {
	.Position = size_of([3]f32),
	.Normal   = size_of([3]f32),
	.UV0      = size_of([2]f32),
	.Color    = size_of([4]f32),
}


Mesh :: struct {
	streams:    [Attribute_Type][]u8,
	indices:    []u32,
	base_color: [4]f32,
	aabb_min:   [3]f32,
	aabb_max:   [3]f32,
}

mesh_vertex_count :: proc(m: ^Mesh) -> int {
	return len(m.streams[.Position]) / ATTRIBUTE_STRIDES[.Position]
}

@(private)
Mesh_Meta :: struct {
	vertex_offset: i32,
	index_offset:  u32,
	index_count:   u32,
}

Indirect_Draw :: struct {
	using cmd: gpu.Draw_Indexed_Indirect_Command,
	model:     [16]f32,
	color:     [4]f32,
}

Scene :: struct {
	streams:  [Attribute_Type]gpu.slice_t(u8),
	indices:  gpu.slice_t(u32),
	indirect: gpu.slice_t(Indirect_Draw),
	count:    gpu.slice_t(u32),
}

upload_scene :: proc(s: ^Scene, meshes: []Mesh, models: []matrix[4, 4]f32) {
	assert(len(meshes) == len(models))
	if len(meshes) == 0 do return


	present: [Attribute_Type]bool
	for a in Attribute_Type do present[a] = len(meshes[0].streams[a]) > 0
	assert(present[.Position], "mesh without positions")
	for &m in meshes {
		verts := mesh_vertex_count(&m)
		for a in Attribute_Type {
			has := len(m.streams[a]) > 0
			assert(has == present[a], "mixed attribute layouts in one scene")
			if has do assert(len(m.streams[a]) == verts * ATTRIBUTE_STRIDES[a])
		}
		assert(len(m.indices) > 0)
	}

	arena := gpu.arena_create()
	defer gpu.arena_destroy(&arena)

	metas := make([]Mesh_Meta, len(meshes))
	defer delete(metas)

	total_bytes: [Attribute_Type]int
	total_verts: int
	total_indices: int
	for &m in meshes {
		total_verts += mesh_vertex_count(&m)
		total_indices += len(m.indices)
		for a in Attribute_Type do total_bytes[a] += len(m.streams[a])
	}

	staging: [Attribute_Type]gpu.slice_t(u8)
	for a in Attribute_Type {
		if present[a] do staging[a] = gpu.arena_alloc(&arena, u8, total_bytes[a])
	}
	i_staging := gpu.arena_alloc(&arena, u32, total_indices)

	offsets: [Attribute_Type]int
	v_off: int
	i_off: int
	for &m, i in meshes {
		metas[i] = Mesh_Meta {
			vertex_offset = i32(v_off),
			index_offset  = u32(i_off),
			index_count   = u32(len(m.indices)),
		}
		for a in Attribute_Type {
			if !present[a] do continue
			copy(staging[a].cpu[offsets[a]:], m.streams[a])
			offsets[a] += len(m.streams[a])
		}
		copy(i_staging.cpu[i_off:], m.indices)
		v_off += mesh_vertex_count(&m)
		i_off += len(m.indices)
	}

	cmd := gpu.commands_begin(.Main)

	for a in Attribute_Type {
		if !present[a] do continue
		s.streams[a] = gpu.mem_alloc(u8, total_bytes[a], GPU)
		gpu.cmd_mem_copy(cmd, s.streams[a], staging[a])
	}
	s.indices = gpu.mem_alloc(u32, total_indices, GPU)
	gpu.cmd_mem_copy(cmd, s.indices, i_staging)

	indirect := gpu.arena_alloc(&arena, Indirect_Draw, len(meshes))
	for i in 0 ..< len(meshes) {
		indirect.cpu[i] = Indirect_Draw {
			cmd = gpu.Draw_Indexed_Indirect_Command {
				index_count = metas[i].index_count,
				instance_count = 1,
				first_index = metas[i].index_offset,
				vertex_offset = metas[i].vertex_offset,
				first_instance = u32(i),
			},
			model = transmute([16]f32)models[i],
			color = meshes[i].base_color,
		}
	}
	s.indirect = gpu.mem_alloc(Indirect_Draw, len(meshes), GPU)
	gpu.cmd_mem_copy(cmd, s.indirect, indirect)

	count := gpu.arena_alloc(&arena, u32)
	count.cpu^ = u32(len(meshes))
	s.count = gpu.mem_alloc(u32, 1, GPU)
	gpu.cmd_mem_copy(cmd, gpu.slice_to_ptr(s.count), count)

	gpu.cmd_barrier(cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {cmd})
	gpu.wait_idle()
}

scene_destroy :: proc(s: ^Scene) {
	if s.indices.gpu.ptr == nil do return
	for a in Attribute_Type {
		if s.streams[a].gpu.ptr != nil do gpu.mem_free(s.streams[a])
	}
	gpu.mem_free(s.indices)
	gpu.mem_free(s.indirect)
	gpu.mem_free(s.count)
	s^ = {}
}
