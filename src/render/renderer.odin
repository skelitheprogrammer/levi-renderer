package render

import "../gpu"
import "core:c"
import "core:log"
import "core:math"
import "core:math/linalg"
import sdl "vendor:sdl3"

Config :: struct {
	title:        string,
	width:        int,
	height:       int,
	window_flags: sdl.WindowFlags,
	shader_dir:   string, // resolved path; caller decides where shaders live
}

Renderer :: struct {
	state:      Render_State,
	scene:      Scene,
	shaders:    Shader_Registry,
	camera:     Camera,
	pipeline:   []Pass,
	window:     ^sdl.Window,
	next_frame: u64,
}

renderer_init :: proc(r: ^Renderer, cfg: Config, allocator := context.allocator) {
	ok := sdl.Init({.VIDEO}); ensure(ok, "sdl init failed")

	title := cstring(raw_data(cfg.title))
	r.window = sdl.CreateWindow(title, c.int(cfg.width), c.int(cfg.height), cfg.window_flags)
	ensure(r.window != nil, "failed to create window")

	render_init(&r.state, r.window)
	shader_registry_scan(&r.shaders, cfg.shader_dir, allocator)

	w, h: c.int
	sdl.GetWindowSize(r.window, &w, &h)
	r.camera = Camera {
		pos = {0, 0, -2},
		rot = linalg.QUATERNIONF32_IDENTITY,
		proj = Perspective{fov = math.to_radians_f32(60)},
		near = 0.01,
		far = 100,
		aspect = f32(w) / f32(h),
	}

	r.pipeline = default_pipeline(&r.shaders, "triangle_indirect_unlit", allocator)
	r.next_frame = 1

	log.infof(
		"renderer ready: %dx%d, %d shaders, %d passes",
		w,
		h,
		len(r.shaders.entries),
		len(r.pipeline),
	)
}

renderer_set_scene :: proc(
	r: ^Renderer,
	meshes: []Mesh,
	models: []matrix[4, 4]f32,
	allocator := context.allocator,
) {
	if len(meshes) == 0 {
		tri := prim_triangle(allocator)
		upload_scene(&r.scene, []Mesh{tri}, []matrix[4, 4]f32{linalg.MATRIX4F32_IDENTITY})
		return
	}
	upload_scene(&r.scene, meshes, models)
}

renderer_frame :: proc(r: ^Renderer) {
	renderer_check_resize(r)

	ctx: Frame_Ctx
	ctx.scene = &r.scene
	ctx.view_proj = transmute([16]f32)camera_view_proj(r.camera)

	render_frame(&r.state, &ctx, r.pipeline, r.next_frame)
	r.next_frame += 1
}

renderer_destroy :: proc(r: ^Renderer) {
	gpu.wait_idle()

	delete(r.pipeline)
	scene_destroy(&r.scene)
	shader_registry_destroy(&r.shaders)
	render_destroy(&r.state)

	sdl.DestroyWindow(r.window)
	r.window = nil
	sdl.Quit()
}

default_pipeline :: proc(
	shaders: ^Shader_Registry,
	shader_name: string,
	allocator := context.allocator,
) -> []Pass {
	passes := make([]Pass, 1, allocator)
	passes[0] = Pass {
		run     = pass_opaque,
		shaders = resolve_shader_pair(shaders, shader_name),
		barrier = .Raster_Color_Out,
	}
	return passes
}

@(private)
renderer_check_resize :: proc(r: ^Renderer) {
	w, h: c.int
	sdl.GetWindowSize(r.window, &w, &h)
	if w == 0 || h == 0 do return
	r.camera.aspect = f32(w) / f32(h)
}
