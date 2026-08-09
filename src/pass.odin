package levi

import gpu "gpu/gpu"

Pass :: struct {
	consumes: gpu.Stage,
	produces: gpu.Stage,
	hazards:  gpu.Hazard_Flags,
	run:      proc(frame: ^Frame, user: rawptr),
	user:     rawptr,
}
