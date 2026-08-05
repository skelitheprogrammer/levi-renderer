package render

import "core:math/linalg"

prim_triangle :: proc(allocator := context.allocator) -> (vertex: Mesh) {
	vertex.pos = make([][4]f32, 3, allocator)
	vertex.pos[0] = {-0.5, -0.5, 0, 1}
	vertex.pos[1] = {0.5, -0.5, 0, 1}
	vertex.pos[2] = {0.0, 0.5, 0, 1}

	vertex.indices = make([]u32, 3, allocator)
	vertex.indices[0] = 0
	vertex.indices[2] = 2
	vertex.indices[1] = 1

	vertex.col = make([][4]f32, 3, allocator)
	vertex.col[0] = {1, 0, 0, 1}
	vertex.col[1] = {0, 1, 0, 1}
	vertex.col[2] = {0, 0, 1, 1}

	return
}


prim_quad :: proc(allocator := context.allocator) -> (vertex: Mesh) {
	vertex.pos = make([][4]f32, 4, allocator)
	vertex.pos[0] = {-0.5, -0.5, 0, 1}
	vertex.pos[1] = {0.5, -0.5, 0, 1}
	vertex.pos[2] = {0.5, 0.5, 0, 1}
	vertex.pos[3] = {-0.5, 0.5, 0, 1}

	vertex.indices = make([]u32, 6, allocator)
	vertex.indices[0] = 0
	vertex.indices[1] = 1
	vertex.indices[2] = 2
	vertex.indices[3] = 0
	vertex.indices[4] = 2
	vertex.indices[5] = 3

	vertex.col = make([][4]f32, 4, allocator)
	vertex.col[0] = {1, 0, 0, 1}
	vertex.col[1] = {0, 1, 0, 1}
	vertex.col[2] = {0, 0, 1, 1}
	vertex.col[3] = {1, 1, 0, 1}

	return
}

compute_face_normal :: #force_inline proc "contextless" (p: [][3]f32) -> [3]f32 {
	e1 := p[1] - p[0]
	e2 := p[2] - p[0]
	return linalg.normalize(linalg.cross(e1, e2))
}
