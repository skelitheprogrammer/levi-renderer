package render

import "../gpu"

Mesh :: struct {
	pos:     [][4]f32,
	col:     [][4]f32,
	indices: []u32,
}

@(private)
Mesh_Meta :: struct {
	vertex_offset: i32,
	index_offset:  u32,
	index_count:   u32,
}

Vertex_GPU :: struct #align (16) {
	pos: [4]f32,
	col: [4]f32,
}

Draw_Root :: struct {
	vertices:  rawptr,
	view_proj: [16]f32,
}

Indirect_Draw :: struct {
	using cmd: gpu.Draw_Indexed_Indirect_Command,
	model:     [16]f32,
	color:     [4]f32,
}

Scene :: struct {
	gpu_verts:    gpu.slice_t(Vertex_GPU),
	gpu_indices:  gpu.slice_t(u32),
	gpu_indirect: gpu.slice_t(Indirect_Draw),
	gpu_count:    gpu.slice_t(u32),
}

upload_scene :: proc(s: ^Scene, meshes: []Mesh, models: []matrix[4, 4]f32) {
	arena := gpu.arena_create()
	defer gpu.arena_destroy(&arena)

	meshes_meta := make([]Mesh_Meta, len(meshes))
	defer delete(meshes_meta)

	total_verts: i32
	total_indices: u32
	for &m, i in meshes {
		meshes_meta[i] = Mesh_Meta {
			vertex_offset = total_verts,
			index_offset  = total_indices,
			index_count   = u32(len(m.indices)),
		}
		total_verts += i32(len(m.pos))
		total_indices += u32(len(m.indices))
	}

	v_staging := gpu.arena_alloc(&arena, Vertex_GPU, int(total_verts))
	i_staging := gpu.arena_alloc(&arena, u32, int(total_indices))
	v_off: int
	i_off: int
	for &m in meshes {
		for k in 0 ..< len(m.pos) {
			v_staging.cpu[v_off + k] = Vertex_GPU {
				pos = m.pos[k],
				col = m.col[k],
			}
		}
		copy(i_staging.cpu[i_off:], m.indices)
		v_off += len(m.pos)
		i_off += len(m.indices)
	}

	s.gpu_verts = gpu.mem_alloc(Vertex_GPU, int(total_verts), GPU)
	s.gpu_indices = gpu.mem_alloc(u32, int(total_indices), GPU)

	cmd := gpu.commands_begin(.Main)
	gpu.cmd_mem_copy(cmd, s.gpu_verts, v_staging)
	gpu.cmd_mem_copy(cmd, s.gpu_indices, i_staging)

	indirect := gpu.arena_alloc(&arena, Indirect_Draw, len(meshes))
	for i in 0 ..< len(meshes) {
		meta := meshes_meta[i]
		indirect.cpu[i] = Indirect_Draw {
			cmd = gpu.Draw_Indexed_Indirect_Command {
				index_count = meta.index_count,
				instance_count = 1,
				first_index = meta.index_offset,
				vertex_offset = meta.vertex_offset,
				first_instance = u32(i),
			},
			model = transmute([16]f32)models[i],
			color = {1, 1, 1, 1},
		}
	}
	s.gpu_indirect = gpu.mem_alloc(Indirect_Draw, len(meshes), GPU)
	gpu.cmd_mem_copy(cmd, s.gpu_indirect, indirect)

	count := gpu.arena_alloc(&arena, u32)
	count.cpu^ = u32(len(meshes))
	s.gpu_count = gpu.mem_alloc(u32, 1, GPU)
	gpu.cmd_mem_copy(cmd, gpu.slice_to_ptr(s.gpu_count), count)

	gpu.cmd_barrier(cmd, .Transfer, .All, {})
	gpu.queue_submit(.Main, {cmd})
	gpu.wait_idle()
}

scene_destroy :: proc(s: ^Scene) {
	gpu.mem_free(s.gpu_verts)
	gpu.mem_free(s.gpu_indices)
	gpu.mem_free(s.gpu_indirect)
	gpu.mem_free(s.gpu_count)
}
