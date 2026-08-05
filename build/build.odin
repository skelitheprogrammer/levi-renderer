package build

import "core:log"
import "core:os"

SHADER_ASSETS :: #config(string, "assets/shaders")
SHADERS_OUT :: #config(string, ".out/shaders")
PROJECT_DIR :: #config(string, "./src/client")
OUT_BINARY :: #config(string, ".out/game.bin")
NO_RUN :: #config(bool, false)
DEPLOY_DIR :: #config(string, ".out/deploy")

main :: proc() {
	logger := log.create_console_logger(
		.Debug,
		{.Level, .Terminal_Color},
		"",
		context.temp_allocator,
	)
	context.logger = logger
	defer log.destroy_console_logger(logger, context.temp_allocator)

	log.info("=== compiling shaders ===")
	compile_shaders()
	log.info("=== done ===")

	// log.info("=== compiling project ===")
	// build_project()

	// when !NO_RUN {
	// 	log.info("=== running ===")
	// 	run_project()
	// }
}

build_project :: proc() {
	os.remove_all(OUT_BINARY)
	cmd := []string{"odin", "build", PROJECT_DIR, "-out:" + OUT_BINARY, "-o:speed"}
	log.info(cmd)

	stderr: []byte
	err: os.Error
	_, _, stderr, err = os.process_exec({command = cmd}, context.temp_allocator)
	ensure(err == os.ERROR_NONE)
	if len(stderr) > 0 {
		log.error("%s", transmute(string)stderr)
		os.exit(1)
	}
}

run_project :: proc() {
	cmd := []string{OUT_BINARY}
	log.info(cmd)

	stderr: []byte
	err: os.Error
	_, _, stderr, err = os.process_exec({command = cmd}, context.temp_allocator)
	ensure(err == os.ERROR_NONE)
	if len(stderr) > 0 {
		log.error("%s", transmute(string)stderr)
		os.exit(1)
	}
}
