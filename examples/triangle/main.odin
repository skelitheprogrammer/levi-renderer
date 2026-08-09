package main

import gpu "../../src/gpu/gpu"
import sdl "vendor:sdl3"

import levi "../../src"

POSITION_SLOT :: u32(0)
COLOR_SLOT :: u32(1)

Triangle_Root :: struct {
	positions: rawptr,
	colors:    rawptr,
}

Triangle_Pass :: struct {
	pool: ^levi.Geometry_Pool,
	vert: gpu.Shader,
	frag: gpu.Shader,
}

main :: proc() {
	ok: bool
	ok = sdl.Init({.VIDEO}); ensure(ok)
	window := sdl.CreateWindow(
		"triangle",
		800,
		600,
		{.VULKAN, .RESIZABLE, .HIGH_PIXEL_DENSITY},
	); ensure(window != nil)
	defer sdl.DestroyWindow(window)

	r: levi.Renderer
	levi.renderer_init(&r, window)
	defer levi.renderer_destroy(&r)


	positions := [?][3]f32{{-0.5, -0.5, 0.0}, {0.5, -0.5, 0.0}, {0.0, 0.5, 0.0}}

	colors := [?][4]f32{{1.0, 0.0, 0.0, 1.0}, {0.0, 1.0, 0.0, 1.0}, {0.0, 0.0, 1.0, 1.0}}

	indices := [?]u32{0, 1, 2}


	streams := []levi.Stream_Data {
		{
			slot = POSITION_SLOT,
			data = raw_data(positions[:]),
			count = len(positions),
			elem_size = size_of([3]f32),
			align = 16,
		},
		{
			slot = COLOR_SLOT,
			data = raw_data(colors[:]),
			count = len(colors),
			elem_size = size_of([4]f32),
			align = 16,
		},
	}

	geometries := []levi.Geometry_Meta {
		{
			first_vertex = 0,
			vertex_count = len(positions),
			first_index = 0,
			index_count = len(indices),
			bounds_min = {-0.5, -0.5, 0.0},
			bounds_max = {0.5, 0.5, 0.0},
			flags = 0,
		},
	}

	pool_desc := levi.Geometry_Pool_Desc {
		streams    = streams,
		indices    = indices[:],
		geometries = geometries,
		memory     = .GPU,
	}

	pool := levi.create_geometry_pool(&r, pool_desc)
	defer levi.destroy_geometry_pool(&r, &pool)

	vert := load_shader(.Vertex)
	frag := load_shader(.Fragment)

	defer {
		gpu.shader_destroy(vert)
		gpu.shader_destroy(frag)
	}

	pass_data := Triangle_Pass {
		pool = &pool,
		vert = vert,
		frag = frag,
	}

	passes := []levi.Pass{triangle_pass(&pass_data)}


	for {
		if !poll_events() do break
		levi.renderer_frame(&r, passes)
	}

	gpu.wait_idle()
}

poll_events :: proc() -> bool {
	evt: sdl.Event
	for sdl.PollEvent(&evt) {
		#partial switch evt.type {
		case .KEY_DOWN:
			if evt.key.scancode == .ESCAPE do return false
		case .QUIT:
			return false
		}
	}
	return true
}

triangle_pass :: proc(p: ^Triangle_Pass) -> levi.Pass {
	return levi.Pass {
		name = "triangle",
		consumes = .Raster_Color_Out,
		produces = .Raster_Color_Out,
		hazards = {},
		run = triangle_run,
		user = rawptr(p),
	}
}

triangle_run :: proc(frame: ^levi.Frame, user: rawptr) {
	p := cast(^Triangle_Pass)user

	if p.pool.indices.gpu.ptr == nil do return

	color_attachment: gpu.Render_Attachment
	color_attachment.texture = frame.swapchain
	color_attachment.load_op = .Clear
	color_attachment.store_op = .Store
	color_attachment.clear_color = {0.08, 0.08, 0.08, 1.0}

	attachments: [1]gpu.Render_Attachment
	attachments[0] = color_attachment

	render_pass_desc := gpu.Render_Pass_Desc {
		color_attachments = attachments[:],
	}

	gpu.cmd_begin_render_pass(frame.cmd, render_pass_desc)
	defer gpu.cmd_end_render_pass(frame.cmd)

	gpu.cmd_set_shaders(frame.cmd, p.vert, p.frag)

	gpu.cmd_set_raster_state(
		frame.cmd,
		gpu.Raster_State{topology = .Triangle_List, cull_mode = .None},
	)

	root := gpu.arena_alloc(frame.arena, Triangle_Root)

	root.cpu^ = Triangle_Root {
		positions = levi.geometry_pool_stream_ptr(p.pool, POSITION_SLOT),
		colors    = levi.geometry_pool_stream_ptr(p.pool, COLOR_SLOT),
	}

	gpu.cmd_draw_indexed(frame.cmd, root.gpu, {}, p.pool.indices, 1)
}

load_shader :: proc(type: gpu.Shader_Type_Graphics) -> gpu.Shader {
	data: []u32
	if type == .Vertex {
		data = #load("shaders/shader.vert.spv", []u32)
	} else if type == .Fragment {
		data = #load("shaders/shader.frag.spv", []u32)
	}

	shader := gpu.shader_create(data, type)
	assert(shader != nil, "failed to create shader")

	return shader
}
