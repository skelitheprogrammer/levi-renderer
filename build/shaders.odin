package build

import "core:fmt"
import "core:log"
import "core:os"
import "core:strings"


STAGES :: []struct {
	token, stage, suffix: string,
} {
	{`[shader("vertex")]`, "vertex", "vert"},
	{`[shader("fragment")]`, "fragment", "frag"},
	{`[shader("compute")]`, "compute", "comp"},
}

compile_shaders :: proc() {
	err: os.Error
	dir, shaders_dir, shaders_out: string
	dir, err = os.get_working_directory(context.temp_allocator); ensure(err == os.ERROR_NONE)
	log.info(dir)

	shaders_dir, err = os.join_path(
		{dir, SHADER_ASSETS},
		context.temp_allocator,
	); ensure(err == os.ERROR_NONE)
	shaders_out, err = os.join_path(
		{dir, SHADERS_OUT},
		context.temp_allocator,
	); ensure(err == os.ERROR_NONE)

	os.remove_all(shaders_out)
	os.make_directory(shaders_out)

	fi: []os.File_Info
	fi, err = os.read_all_directory_by_path(
		shaders_dir,
		context.temp_allocator,
	); ensure(err == os.ERROR_NONE)

	for f in fi {
		if f.type != .Regular do continue
		if os.ext(f.name) != ".slang" do continue

		content_bytes, read_err := os.read_entire_file(
			f.fullpath,
			allocator = context.temp_allocator,
		)
		ensure(read_err == os.ERROR_NONE)
		content := string(content_bytes)

		compiled_any := false

		for stage_info in STAGES {
			search_from := 0
			for {
				idx := strings.index(content[search_from:], stage_info.token)
				if idx < 0 do break
				idx += search_from

				entry_name, ok := extract_entry_name(content, idx + len(stage_info.token))
				if !ok {
					log.warn(
						"found %s but couldn't parse entry name in %s",
						stage_info.token,
						f.name,
					)
					search_from = idx + len(stage_info.token)
					continue
				}

				// Entry points keep the `_<stage>` suffix in Slang so a vertex
				// and fragment stage can share one file with unique names. The
				// artifact is named after the logical shader, so both stages land
				// under one registry key. Falls through unchanged if an entry
				// doesn't follow the `name_<stage>` convention.
				shader_name := entry_name
				stage_tag := fmt.tprintf("_%s", stage_info.suffix)
				if strings.has_suffix(shader_name, stage_tag) {
					shader_name = strings.trim_suffix(shader_name, stage_tag)
				}

				out_name, _ := os.join_filename(
					shader_name,
					fmt.tprintf("%s.spv", stage_info.suffix),
					context.temp_allocator,
				)
				out_path, _ := os.join_path({shaders_out, out_name}, context.temp_allocator)

				cmd := []string {
					"slangc",
					"-target",
					"spirv",
					"-fvk-use-c-layout",
					"-fvk-use-scalar-layout",
					"-force-glsl-scalar-layout",
					"-validate-ir",
					"-no-mangle",
					"-entry",
					entry_name,
					"-stage",
					stage_info.stage,
					f.fullpath,
					"-o",
					out_path,
				}

				log.infof("\nparsing: %s\nfrom %s\ninto %s", entry_name, f.fullpath, out_path)
				os.flush(os.stdout)
				stderr: []byte
				_, _, stderr, err = os.process_exec({command = cmd}, context.temp_allocator)
				ensure(err == os.ERROR_NONE)
				if len(stderr) > 0 {
					log.error("%s", transmute(string)stderr)
					os.exit(1)
				}
				compiled_any = true
				search_from = idx + len(stage_info.token)
			}
		}

		if !compiled_any {
			log.debug("skipped %s (no entry points)", f.name)
		}
	}
}

extract_entry_name :: proc "contextless" (content: string, start: int) -> (string, bool) {
	paren := strings.index(content[start:], "(")
	if paren < 0 do return "", false
	paren += start

	end := paren
	for end > start &&
	    (content[end - 1] == ' ' ||
			    content[end - 1] == '\t' ||
			    content[end - 1] == '\n' ||
			    content[end - 1] == '\r') {
		end -= 1
	}

	begin := end
	for begin > start {
		c := content[begin - 1]
		is_ident :=
			(c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '_'
		if !is_ident do break
		begin -= 1
	}

	if begin == end do return "", false
	return content[begin:end], true
}
