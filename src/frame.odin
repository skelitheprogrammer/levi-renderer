package levi

import gpu "gpu/gpu"

Frame :: struct {
	renderer:    ^Renderer,
	cmd:         gpu.Command_Buffer,
	arena:       ^gpu.Arena,
	swapchain:   gpu.Texture,
	depth:       gpu.Texture,
	frame_index: u64,
	size:        [2]u32,
}
