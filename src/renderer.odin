package render

import "gpu/gpu"
import sdl "vendor:sdl3"

FLIGHT :: 3
GPU :: gpu.Memory.GPU

Render_State :: struct {
	frame_sem:    gpu.Semaphore,
	frame_arenas: [FLIGHT]gpu.Arena,
}

render_init :: proc(state: ^Render_State, window: ^sdl.Window) {
	ok := gpu.init(); ensure(ok)
	gpu.swapchain_create_from_sdl(window, FLIGHT)
	state.frame_sem = gpu.semaphore_create()
	for &f in state.frame_arenas do f = gpu.arena_create()
}

render_destroy :: proc(state: ^Render_State) {
	gpu.semaphore_destroy(state.frame_sem)
	for &f in state.frame_arenas do gpu.arena_destroy(&f)
}

Target :: enum {
	Swapchain,
}

Frame_Ctx :: struct {
	targets:   [Target]gpu.Texture,
	arena:     ^gpu.Arena,
	scene:     ^Scene,
	view_proj: [16]f32,
}

render_frame :: proc(state: ^Render_State, ctx: ^Frame_Ctx, pipeline: []Pass, next_frame: u64) {
	cmd, swapchain_tex, arena := begin_frame(state, next_frame)
	defer end_frame(state, cmd, next_frame)

	ctx.targets[.Swapchain] = swapchain_tex
	ctx.arena = arena

	for &p, i in pipeline {
		if i > 0 {
			gpu.cmd_barrier(cmd, pipeline[i - 1].barrier, .Fragment_Shader, {})
		}
		p->run(cmd, ctx)
	}
}

@(private)
begin_frame :: proc(
	state: ^Render_State,
	frame_idx: u64,
) -> (
	cmd: gpu.Command_Buffer,
	swapchain: gpu.Texture,
	frame_arena: ^gpu.Arena,
) {
	if frame_idx > FLIGHT do gpu.semaphore_wait(state.frame_sem, frame_idx - FLIGHT)
	swapchain = gpu.swapchain_acquire_next()
	frame_arena = &state.frame_arenas[frame_idx % FLIGHT]
	gpu.arena_free_all(frame_arena)
	cmd = gpu.commands_begin(.Main)
	return
}

@(private)
end_frame :: proc(state: ^Render_State, cmd: gpu.Command_Buffer, frame_idx: u64) {
	gpu.cmd_add_signal_semaphore(cmd, state.frame_sem, frame_idx)
	gpu.queue_submit(.Main, {cmd})
	gpu.swapchain_present(.Main, state.frame_sem, frame_idx)
}
