package render

import "../gpu/gpu"

Pass :: struct {
	run:     proc(pass: ^Pass, cmd: gpu.Command_Buffer, ctx: ^Frame_Ctx),
	shaders: Shader_Pair,
	barrier: gpu.Stage,
}

Lit_Root :: struct {
	positions: rawptr,
	normals:   rawptr,
	view_proj: [16]f32,
}

pass_opaque :: proc(pass: ^Pass, cmd: gpu.Command_Buffer, ctx: ^Frame_Ctx) {
	gpu.cmd_begin_render_pass(
		cmd,
		{color_attachments = {{texture = ctx.targets[.Swapchain], clear_color = {.1, .1, .1, 1}}}},
	)
	defer gpu.cmd_end_render_pass(cmd)

	s := ctx.scene
	if s.count.gpu.ptr == nil do return
	assert(s.streams[.Normal].gpu.ptr != nil, "lit pass requires the Normal stream")

	gpu.cmd_set_shaders(cmd, pass.shaders[.Vertex], pass.shaders[.Fragment])
	gpu.cmd_set_raster_state(cmd, {topology = .Triangle_List, cull_mode = .None})

	root := gpu.arena_alloc(ctx.arena, Lit_Root)
	root.cpu.positions = s.streams[.Position].gpu.ptr
	root.cpu.normals = s.streams[.Normal].gpu.ptr
	root.cpu.view_proj = ctx.view_proj

	gpu.cmd_draw_indexed_indirect_multi(
		cmd,
		root.gpu,
		{},
		s.indices,
		s.indirect,
		gpu.slice_to_ptr(s.count),
	)
}
