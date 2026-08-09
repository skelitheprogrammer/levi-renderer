package levi

import "gpu/gpu"
import vk "vendor:vulkan"

Render_State :: struct {
	frames_in_flight: int,
	frame_arenas:     [dynamic]gpu.Arena,
	frame_sem:        gpu.Semaphore,
	next_frame:       u64,
}

Frame :: struct {
	state:       ^Render_State,
	cmd:         gpu.Command_Buffer,
	arena:       ^gpu.Arena,
	swapchain:   gpu.Texture,
	frame_index: u64,
}

Pass :: struct {
	run:   proc(f: ^Frame),
	stage: gpu.Stage,
}

init :: #force_inline proc(validation: bool = true, loc := #caller_location) -> bool {
	return gpu.init(validation, loc)
}

render_init :: proc(
	state: ^Render_State,
	surface: vk.SurfaceKHR,
	width: u32,
	height: u32,
	frames_in_flight := 3,
	present_mode: gpu.Present_Mode = {},
) -> bool {
	assert(state != nil)
	assert(frames_in_flight > 0)

	gpu.swapchain_create(surface, {width, height}, u32(frames_in_flight), present_mode)

	state.frames_in_flight = frames_in_flight
	state.frame_sem = gpu.semaphore_create()
	state.frame_arenas = make([dynamic]gpu.Arena, frames_in_flight)
	for &a in state.frame_arenas do a = gpu.arena_create()

	state.next_frame = 1
	return true
}

render_destroy :: proc(state: ^Render_State) {
	gpu.wait_idle()

	gpu.semaphore_destroy(state.frame_sem)

	for &a in state.frame_arenas {
		gpu.arena_destroy(&a)
	}
	delete(state.frame_arenas)

	gpu.cleanup()

	state^ = {}
}

render_resize :: proc(state: ^Render_State, width: u32, height: u32) {
	assert(state != nil)
	gpu.swapchain_resize({width, height})
}

render_frame :: proc(state: ^Render_State, passes: []Pass) {
	assert(state != nil)
	assert(passes != nil)

	if state.next_frame > u64(state.frames_in_flight) {
		gpu.semaphore_wait(state.frame_sem, state.next_frame - u64(state.frames_in_flight))
	}

	swapchain := gpu.swapchain_acquire_next()

	arena_index := int(state.next_frame % u64(state.frames_in_flight))
	arena := &state.frame_arenas[arena_index]
	gpu.arena_free_all(arena)

	cmd := gpu.commands_begin(.Main)

	f: Frame
	f.state = state
	f.cmd = cmd
	f.arena = arena
	f.swapchain = swapchain
	f.frame_index = state.next_frame

	for p, i in passes {
		if p.run != nil {
			p.run(&f)
		}

		if i + 1 < len(passes) {
			gpu.cmd_barrier(cmd, p.stage, passes[i + 1].stage, {})
		}
	}

	gpu.cmd_add_signal_semaphore(cmd, state.frame_sem, state.next_frame)
	gpu.queue_submit(.Main, {cmd})
	gpu.swapchain_present(.Main, state.frame_sem, state.next_frame)

	state.next_frame += 1
}
