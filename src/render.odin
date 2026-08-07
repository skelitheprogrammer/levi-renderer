package render

import "../gpu/gpu"
import "core:c"
import "core:log"
import "core:math"
import "core:math/linalg"
import sdl "vendor:sdl3"

Window_Flags :: sdl.WindowFlags // alias: window config without importing sdl

Renderer :: struct {
	state:      Render_State,
	scene:      Scene,
	shaders:    Shader_Registry,
	camera:     Camera,
	pipeline:   []Pass,
	window:     ^sdl.Window,
	next_frame: u64,
}

// Receives an already-created window and resolved shader directories.
// Asset/path resolution is not the renderer's concern.
renderer_init :: proc(
	r: ^Renderer,
	window: ^sdl.Window,
	shader_dirs: []string,
	allocator := context.allocator,
) {
	ensure(window != nil, "nil window")
	r.window = window

	render_init(&r.state, r.window)
	for dir in shader_dirs do shader_registry_scan(&r.shaders, dir, allocator)

	w, h := renderer_size(r)
	r.camera = Camera {
		pos = {0, 0, -2},
		rot = linalg.QUATERNIONF32_IDENTITY,
		proj = Perspective{fov = math.to_radians_f32(60)},
		near = 0.01,
		far = 100,
		aspect = f32(w) / f32(h),
	}

	r.pipeline = default_pipeline(&r.shaders, "lit", allocator)
	r.next_frame = 1

	log.infof(
		"renderer ready: %dx%d, %d shaders, %d passes",
		w,
		h,
		len(r.shaders.entries),
		len(r.pipeline),
	)
}

renderer_set_scene :: proc(r: ^Renderer, meshes: []Mesh, models: []matrix[4, 4]f32) {
	scene_destroy(&r.scene) // root cause: re-set used to leak every GPU buffer
	if len(meshes) == 0 do return // empty scene draws nothing
	upload_scene(&r.scene, meshes, models)
}

renderer_set_camera :: proc(r: ^Renderer, cam: Camera) {
	r.camera = cam
}

renderer_set_pipeline :: proc(r: ^Renderer, pipeline: []Pass, allocator := context.allocator) {
	delete(r.pipeline)
	r.pipeline = append(make([]Pass, 0, len(pipeline), allocator), ..pipeline)
}

renderer_size :: proc(r: ^Renderer) -> (w, h: int) {
	cw, ch: c.int
	sdl.GetWindowSize(r.window, &cw, &ch)
	return int(cw), int(ch)
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

	// window is app-owned: never destroy what you did not create
	r.window = nil
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
