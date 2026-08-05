package asset_management

import g "../glTF2"
import "../render"
import "core:math/linalg"

Load_Result :: struct {
	meshes: [dynamic]render.Mesh,
	models: [dynamic]matrix[4, 4]f32,
}

load_scene_data :: proc(path: string, allocator := context.allocator) -> Load_Result {
	data, err := g.load_from_file(path, allocator); ensure(err == nil)
	defer g.unload(data)

	meshes := make([dynamic]render.Mesh, allocator)
	models := make([dynamic]matrix[4, 4]f32, allocator)

	Stack_Entry :: struct {
		node:         g.Integer,
		parent_world: matrix[4, 4]f32,
	}
	stack := make([dynamic]Stack_Entry, allocator)
	defer delete(stack)

	for scene in data.scenes {
		for node in scene.nodes {
			append(&stack, Stack_Entry{node, linalg.MATRIX4F32_IDENTITY})
		}
	}

	for len(stack) > 0 {
		entry := stack[len(stack) - 1]
		resize(&stack, len(stack) - 1)

		node := &data.nodes[entry.node]
		world := entry.parent_world * node_transform(node)

		if node.mesh != nil {
			mesh := &data.meshes[node.mesh.(g.Integer)]
			for &prim in mesh.primitives {
				if prim.mode != .Triangles do continue
				append(&meshes, emit_mesh(data, &prim, allocator))
				append(&models, world)
			}
		}

		for child in node.children {
			append(&stack, Stack_Entry{child, world})
		}
	}

	return Load_Result{meshes, models}
}

@(private)
emit_mesh :: proc(
	data: ^g.Data,
	prim: ^g.Mesh_Primitive,
	allocator := context.allocator,
) -> render.Mesh {
	m: render.Mesh

	for k, v in prim.attributes {
		switch k {
		case "POSITION":
			buf := g.buffer_slice(data, v).([][3]f32)
			m.pos = make([][4]f32, len(buf), allocator)
			for p, i in buf {
				m.pos[i] = {p[0], p[1], p[2], 1} // no world transform baked
			}
		case "COLOR_0":
			buf := g.buffer_slice(data, v).([][3]f32)
			m.col = make([][4]f32, len(buf), allocator)
			for c, i in buf {
				m.col[i] = {c[0], c[1], c[2], 1}
			}
		}
	}

	if m.col == nil {
		m.col = make([][4]f32, len(m.pos), allocator)
		for &c in m.col do c = {1, 1, 1, 1}
	}

	if prim.indices != nil {
		id := prim.indices.(g.Integer)
		acc := data.accessors[id]
		#partial switch acc.component_type {
		case .Unsigned_Short:
			buf := g.buffer_slice(data, id).([]u16)
			m.indices = make([]u32, len(buf), allocator)
			for i, v in buf do m.indices[i] = u32(v)
		case .Unsigned_Int:
			buf := g.buffer_slice(data, id).([]u32)
			m.indices = make([]u32, len(buf), allocator)
			copy(m.indices, buf)
		}
	} else {
		m.indices = make([]u32, len(m.pos), allocator)
		for i in 0 ..< len(m.pos) do m.indices[i] = u32(i)
	}

	return m
}

@(private)
node_transform :: #force_inline proc "contextless" (node: ^g.Node) -> matrix[4, 4]f32 {
	if node.mat != linalg.MATRIX4F32_IDENTITY do return node.mat
	r := node.rotation
	s := node.scale
	if r == linalg.Quaternionf32(0) do r = linalg.QUATERNIONF32_IDENTITY
	if s == {0, 0, 0} do s = {1, 1, 1}
	return linalg.matrix4_from_trs_f32(node.translation, r, s)
}
