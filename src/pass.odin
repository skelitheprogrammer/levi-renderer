package levi

import "gpu/gpu"

Graphics_Targets :: struct {
	color:     []gpu.Render_Attachment,
	depth:     gpu.Render_Attachment,
	has_depth: bool,
}

Pass_State :: struct {
	raster: gpu.Raster_State,
	depth:  gpu.Depth_State,
	blend:  gpu.Blend_State,
}


graphics :: proc(
	f: ^Frame,
	targets: Graphics_Targets,
	shaders: [gpu.Shader_Type_Graphics]gpu.Shader,
	state: Pass_State,
	record: proc(f: ^Frame),
) {
	assert(f != nil)

	desc: gpu.Render_Pass_Desc
	desc.color_attachments = targets.color

	if targets.has_depth {
		desc.depth_attachment = targets.depth
	}

	gpu.cmd_begin_render_pass(f.cmd, desc)

	gpu.cmd_set_shaders(f.cmd, shaders[.Vertex], shaders[.Fragment])

	gpu.cmd_set_raster_state(f.cmd, state.raster)
	gpu.cmd_set_depth_state(f.cmd, state.depth)
	gpu.cmd_set_blend_state(f.cmd, state.blend)

	if record != nil {
		record(f)
	}

	gpu.cmd_end_render_pass(f.cmd)
}

compute :: proc(
	f: ^Frame,
	shader: gpu.Shader,
	data: gpu.gpuptr,
	group_x: u32,
	group_y: u32 = 1,
	group_z: u32 = 1,
) {
	assert(f != nil)
	gpu.cmd_set_compute_shader(f.cmd, shader)
	gpu.cmd_dispatch(f.cmd, data, group_x, group_y, group_z)
}
