package render

import "core:math/linalg"

Perspective :: struct {
	fov: f32,
}

Orthographic :: struct {
	y_mag: f32,
}

Projection :: union {
	Perspective,
	Orthographic,
}

Camera :: struct {
	pos:    [3]f32,
	rot:    linalg.Quaternionf32,
	proj:   Projection,
	near:   f32,
	far:    f32,
	aspect: f32,
}

camera_view :: #force_inline proc "contextless" (c: Camera) -> matrix[4, 4]f32 {
	return linalg.matrix4_from_quaternion_f32(conj(c.rot)) * linalg.matrix4_translate_f32(-c.pos)
}

camera_proj :: #force_inline proc "contextless" (c: Camera) -> matrix[4, 4]f32 {
	switch p in c.proj {
	case Perspective:
		return linalg.matrix4_perspective_f32(p.fov, c.aspect, c.near, c.far, true)
	case Orthographic:
		x_mag := p.y_mag * c.aspect
		return linalg.matrix_ortho3d_f32(-x_mag, x_mag, -p.y_mag, p.y_mag, c.near, c.far, true)
	}
	return linalg.MATRIX4F32_IDENTITY
}

camera_view_proj :: proc "contextless" (c: Camera) -> matrix[4, 4]f32 {
	z_flip: matrix[4, 4]f32 = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, -1, 0, 0, 0, 0, 1}
	return camera_proj(c) * z_flip * camera_view(c)
}
