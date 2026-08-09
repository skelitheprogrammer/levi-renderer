package levi

import gpu "gpu/gpu"

Pass :: struct {
	name:     string,
	consumes: gpu.Stage,
	produces: gpu.Stage,
	hazards:  gpu.Hazard_Flags,
	run:      proc(frame: ^Frame, user: rawptr),
	user:     rawptr,
}
