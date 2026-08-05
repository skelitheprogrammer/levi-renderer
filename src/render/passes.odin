package render

import "../gpu"

Pass :: struct {
	run:     proc(pass: ^Pass, cmd: gpu.Command_Buffer, ctx: ^Frame_Ctx),
	name:    string,
	shaders: Shader_Pair,
	barrier: gpu.Stage,
}

pass_opaque :: proc(pass: ^Pass, cmd: gpu.Command_Buffer, ctx: ^Frame_Ctx) {
	gpu.cmd_begin_render_pass(
		cmd,
		{color_attachments = {{texture = ctx.targets[.Swapchain], clear_color = {.1, .1, .1, 1}}}},
	)
	defer gpu.cmd_end_render_pass(cmd)

	gpu.cmd_set_shaders(cmd, pass.shaders[.Vertex], pass.shaders[.Fragment])
	gpu.cmd_set_raster_state(cmd, {topology = .Triangle_List, cull_mode = .None})

	s := ctx.scene
	root := gpu.arena_alloc(ctx.arena, Draw_Root)
	root.cpu.vertices = s.gpu_verts.gpu.ptr
	root.cpu.view_proj = ctx.view_proj
	gpu.cmd_draw_indexed_indirect_multi(
		cmd,
		root.gpu,
		{},
		s.gpu_indices,
		s.gpu_indirect,
		gpu.slice_to_ptr(s.gpu_count),
	)
}
