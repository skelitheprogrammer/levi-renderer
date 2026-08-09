package levi

import "core:c"
import gpu "gpu/gpu"
import sdl "vendor:sdl3"

MAX_FRAMES :: 3

MAX_STREAMS :: 8

AABB :: struct {
	min: [3]f32,
	max: [3]f32,
}

Geometry_Record :: struct {
	bounds_min:    [3]f32,
	bounds_max:    [3]f32,
	vertex_offset: i32,
	vertex_count:  u32,
	first_index:   u32,
	index_count:   u32,
	flags:         u32,
	_pad:          u32,
}


Config :: struct {
	frames_in_flight: u32,
	create_depth:     bool,
	depth_format:     gpu.Texture_Format,
	arena_block_size: i64,
}

Default_Config :: Config {
	frames_in_flight = 3,
	create_depth     = true,
	depth_format     = .D32_Float,
	arena_block_size = 4 * 1024 * 1024,
}

Renderer :: struct {
	window:       ^sdl.Window,
	config:       Config,
	frame_sem:    gpu.Semaphore,
	frame_arenas: [MAX_FRAMES]gpu.Arena,
	frame_index:  u64,
	size:         [2]u32,
	depth:        gpu.Owned_Texture,
	depth_valid:  bool,
	initialized:  bool,
}

renderer_init :: proc(r: ^Renderer, window: ^sdl.Window, config: Config = Default_Config) {
	assert(r != nil)
	assert(window != nil)
	assert(config.frames_in_flight > 0 && config.frames_in_flight <= MAX_FRAMES)

	r.window = window
	r.config = config
	r.frame_index = 0

	ok := gpu.init()
	assert(ok, "gpu.init failed")

	gpu.swapchain_create_from_sdl(window, config.frames_in_flight)

	r.frame_sem = gpu.semaphore_create()

	for i in 0 ..< MAX_FRAMES {
		r.frame_arenas[i] = gpu.arena_create(config.arena_block_size)
	}

	r.size = renderer_window_size(r)

	if config.create_depth && r.size[0] > 0 && r.size[1] > 0 {
		r.depth = create_depth_texture(r)
		r.depth_valid = true
	}

	r.initialized = true
}

renderer_destroy :: proc(r: ^Renderer) {
	if !r.initialized do return

	gpu.wait_idle()

	if r.depth_valid {
		gpu.texture_free_and_destroy(&r.depth)
		r.depth_valid = false
	}

	gpu.semaphore_destroy(r.frame_sem)

	for i in 0 ..< MAX_FRAMES {
		gpu.arena_destroy(&r.frame_arenas[i])
	}

	r^ = {}
}

renderer_frame :: proc(r: ^Renderer, passes: []Pass) {
	assert(r.initialized)

	renderer_check_resize(r)

	if r.size[0] == 0 || r.size[1] == 0 do return

	frame := begin_frame(r)

	for i in 0 ..< len(passes) {
		p := &passes[i]

		if i > 0 {
			prev := &passes[i - 1]
			gpu.cmd_barrier(frame.cmd, prev.produces, p.consumes, p.hazards)
		}

		if p.run != nil {
			p.run(&frame, p.user)
		}
	}

	end_frame(r, frame)
}

renderer_window_size :: proc(r: ^Renderer) -> [2]u32 {
	w: c.int
	h: c.int

	sdl.GetWindowSize(r.window, &w, &h)

	if w < 0 do w = 0
	if h < 0 do h = 0

	return {u32(w), u32(h)}
}

renderer_check_resize :: proc(r: ^Renderer) {
	size := renderer_window_size(r)

	if size[0] == 0 || size[1] == 0 do return
	if size == r.size do return

	gpu.wait_idle()

	gpu.swapchain_resize(size)

	if r.depth_valid {
		gpu.texture_free_and_destroy(&r.depth)
		r.depth_valid = false
	}

	if r.config.create_depth {
		r.depth = create_depth_texture(r)
		r.depth_valid = true
	}

	r.size = size
}

create_depth_texture :: proc(r: ^Renderer) -> gpu.Owned_Texture {
	desc := gpu.Texture_Desc {
		type       = .D2,
		dimensions = {r.size[0], r.size[1], 1},
		format     = r.config.depth_format,
		usage      = {.Depth_Stencil_Attachment},
	}

	return gpu.texture_alloc_and_create(desc, .Main, {}, 0, "levi.depth")
}

begin_frame :: proc(r: ^Renderer) -> Frame {
	idx := r.frame_index
	frames := u64(r.config.frames_in_flight)

	if idx >= frames {
		gpu.semaphore_wait(r.frame_sem, idx - frames)
	}

	swapchain := gpu.swapchain_acquire_next()

	arena := &r.frame_arenas[int(idx % frames)]
	gpu.arena_free_all(arena)

	cmd := gpu.commands_begin(.Main)

	depth: gpu.Texture
	if r.depth_valid {
		depth = r.depth.tex
	}

	return Frame {
		renderer = r,
		cmd = cmd,
		arena = arena,
		swapchain = swapchain,
		depth = depth,
		frame_index = idx,
		size = r.size,
	}
}

end_frame :: proc(r: ^Renderer, frame: Frame) {
	gpu.cmd_add_signal_semaphore(frame.cmd, r.frame_sem, frame.frame_index)
	gpu.queue_submit(.Main, {frame.cmd})
	gpu.swapchain_present(.Main, r.frame_sem, frame.frame_index)

	r.frame_index += 1
}
