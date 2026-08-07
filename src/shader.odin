package render

import "core:os"
import path "core:path/filepath"
import "core:slice"
import "core:strings"
import "gpu/gpu"

Shader_Pair :: [gpu.Shader_Type_Graphics]gpu.Shader

Shader_Registry :: struct {
	entries: map[string]Shader_Pair,
}

shader_registry_scan :: proc(reg: ^Shader_Registry, dir: string, allocator := context.allocator) {
	if reg.entries == nil do reg.entries = make(map[string]Shader_Pair, allocator)

	infos, err := os.read_all_directory_by_path(dir, allocator)
	ensure(err == nil, "shader dir not found")
	defer delete(infos)

	for info in infos {
		if info.type == .Directory do continue
		if !strings.has_suffix(info.name, ".spv") do continue

		name: string
		shader_type: gpu.Shader_Type_Graphics

		if strings.has_suffix(info.name, ".vert.spv") {
			name = strings.trim_suffix(info.name, ".vert.spv")
			shader_type = .Vertex
		} else if strings.has_suffix(info.name, ".frag.spv") {
			name = strings.trim_suffix(info.name, ".frag.spv")
			shader_type = .Fragment
		} else {
			continue
		}

		full, join_err := path.join({dir, info.name}, allocator)
		ensure(join_err == .None)
		data, read_err := os.read_entire_file(full, allocator)
		delete(full)
		ensure(read_err == nil)

		words := slice.from_ptr(cast(^u32)raw_data(data), len(data) / 4)
		shader := gpu.shader_create(words, shader_type)
		delete(data)
		ensure(shader != nil)

		_, v, _, _ := map_entry(&reg.entries, name)
		v^[shader_type] = shader
	}
}

shader_registry_destroy :: proc(reg: ^Shader_Registry) {
	for _, &pair in reg.entries {
		for &s in pair {
			if s != nil do gpu.shader_destroy(s)
		}
	}
	delete(reg.entries)
}

resolve_shader_pair :: proc(reg: ^Shader_Registry, base: string) -> Shader_Pair {
	pair := reg.entries[base]
	ensure(pair[.Vertex] != nil, "missing vertex shader")
	ensure(pair[.Fragment] != nil, "missing fragment shader")
	return pair
}
