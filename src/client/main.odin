package client

import "../asset_management"
import "../render"
import "core:log"
import "core:os"
import sdl "vendor:sdl3"

main :: proc() {
	logger := log.create_console_logger()
	defer log.destroy_console_logger(logger)
	context.logger = logger

	shader_dir, scene_path := resolve_project_paths()

	r: render.Renderer
	render.renderer_init(
		&r,
		{
			title = "check",
			width = 800,
			height = 600,
			window_flags = sdl.WindowFlags{.RESIZABLE},
			shader_dir = shader_dir,
		},
	)
	defer render.renderer_destroy(&r)

	set_scene_from_path(&r, scene_path)

	for {
		if !poll_events() do break
		render.renderer_frame(&r)
	}
}

poll_events :: proc() -> bool {
	event: sdl.Event

	for sdl.PollEvent(&event) {
		#partial switch event.type {
		case .KEY_DOWN:
			if event.key.scancode == .ESCAPE do return false
		}
	}

	return true
}

resolve_project_paths :: proc() -> (shader_dir, scene_path: string) {
	exe_dir, err := os.get_executable_directory(context.temp_allocator)
	ensure(err == os.ERROR_NONE)
	shader_dir, _ = os.join_path({exe_dir, "shaders"}, context.temp_allocator)
	if len(os.args) >= 2 {
		scene_path, _ = os.join_path({exe_dir, os.args[1]}, context.temp_allocator)
	}
	return
}

set_scene_from_path :: proc(r: ^render.Renderer, path: string) {
	if path == "" {
		render.renderer_set_scene(r, nil, nil) // built-in triangle
		return
	}
	loaded := asset_management.load_scene_data(path)
	ensure(len(loaded.meshes) > 0, "no meshes in scene")
	render.renderer_set_scene(r, loaded.meshes[:], loaded.models[:])
	delete(loaded.meshes)
	delete(loaded.models)
}
