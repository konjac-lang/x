require "./x"
require "option_parser"

module X
  def self.main
    log_level = Log::Severity::Info
    files = [] of String
    search_roots = [] of String
    show_help = false
    show_version = false
    show_ast = false
    show_instructions = false
    use_debugger = false

    parser = OptionParser.new do |opts|
      opts.banner = "Usage: x [options] <file.xasm> [file2.xasm ...]"
      opts.separator ""
      opts.separator "The X Virtual Machine — BEAM-inspired VM with actor-model concurrency"
      opts.separator ""
      opts.separator "Options:"

      opts.on("-v", "--version", "Show version") do
        show_version = true
      end

      opts.on("-h", "--help", "Show this help") do
        show_help = true
      end

      opts.on("-d", "--debug", "Enable debug logging") do
        log_level = Log::Severity::Debug
      end

      opts.on("-q", "--quiet", "Suppress info logging") do
        log_level = Log::Severity::Warn
      end

      opts.on("-I PATH", "--include PATH", "Add search path for module resolution") do |path|
        search_roots << path
      end

      opts.on("--ast", "Print the AST and exit (don't run)") do
        show_ast = true
      end

      opts.on("--instructions", "Print compiled instructions and exit (don't run)") do
        show_instructions = true
      end

      opts.on("--debugger", "Launch interactive debugger") do
        use_debugger = true
      end

      opts.unknown_args do |args|
        files = args
      end
    end

    parser.parse

    if show_version
      STDERR.puts "X Virtual Machine #{VERSION}"
      STDERR.puts ""
      STDERR.puts "Crystal #{Crystal::VERSION} (#{Crystal::BUILD_DATE})"
      STDERR.puts "LLVM: #{Crystal::LLVM_VERSION}"
      STDERR.puts "Default target: #{Crystal::HOST_TRIPLE}"
      return
    end

    if show_help || files.empty?
      STDERR.puts parser
      return
    end

    Log.setup(log_level)

    # Build search roots from file locations + explicit includes
    files.each do |file|
      dir = File.dirname(File.expand_path(file))
      search_roots << dir unless search_roots.includes?(dir)
    end
    search_roots << Dir.current unless search_roots.includes?(Dir.current)

    # Create engine
    engine = Engine::Context.new
    Assembler.register_default_built_ins(engine)

    # Create loader
    loader = Assembler::Loader.new(engine, search_roots: search_roots)

    # Load all files
    compiled_modules = [] of Assembler::CodeGenerator::CompiledModule

    files.each do |file|
      unless File.exists?(file)
        STDERR.puts "Error: File not found: #{file}"
        exit 1
      end

      begin
        source = File.read(file)
        compiled = loader.load_source(source, file)
        compiled_modules << compiled
      rescue ex
        STDERR.puts "Error loading #{file}: #{ex.message}"
        exit 1
      end
    end

    # AST dump mode
    if show_ast
      compiled_modules.each do |compiled|
        print_module_info(compiled)
      end
      return
    end

    # Instruction dump mode
    if show_instructions
      compiled_modules.each do |compiled|
        print_instructions(compiled)
      end
      return
    end

    # Run
    begin
      if use_debugger
        debugger = Assembler::InteractiveDebugger.new(engine)
        debugger.attach
        STDERR.puts "\e[1;36mX Virtual Machine Debugger (xdb)\e[0m"
        STDERR.puts "Type \e[1mhelp\e[0m for commands, \e[1mEnter\e[0m repeats last command"
      end

      loader.wire_and_run
      sleep 100.milliseconds
    rescue ex
      STDERR.puts "Runtime error: #{ex.message}"
      exit 1
    end
  end

  # Diagnostic outpu

  private def self.print_module_info(compiled : Assembler::CodeGenerator::CompiledModule)
    STDERR.puts "Module: #{compiled.name}"
    STDERR.puts "  Dynamic: #{compiled.is_dynamic}"

    unless compiled.requires.empty?
      STDERR.puts "  Requires:"
      compiled.requires.each do |req|
        alias_str = req.alias_name ? " as #{req.alias_name}" : ""
        STDERR.puts "    #{req.module_name}#{alias_str}"
      end
    end

    unless compiled.imports.empty?
      STDERR.puts "  Imports:"
      compiled.imports.each do |imp|
        STDERR.puts "    #{imp.module_name}.#{imp.function_name}/#{imp.arity}"
      end
    end

    unless compiled.exports.empty?
      STDERR.puts "  Exports:"
      compiled.exports.each do |exp|
        STDERR.puts "    #{exp.function_name}/#{exp.arity}"
      end
    end

    compiled.processes.each do |process|
      STDERR.puts "  Process: #{process.name}"
      STDERR.puts "    Instructions: #{process.instructions.size}"
      STDERR.puts "    Subroutines: #{process.subroutines.size}"
      process.subroutines.each do |name, sub|
        STDERR.puts "      .sub #{name} (#{sub.instructions.size} instructions)"
      end
    end

    compiled.supervisors.each do |sup|
      STDERR.puts "  Supervisor: #{sup.name} (#{sup.strategy})"
      sup.children.each do |child|
        STDERR.puts "    Child: #{child.id} (#{child.restart_type})"
      end
    end

    STDERR.puts ""
  end

  private def self.print_instructions(compiled : Assembler::CodeGenerator::CompiledModule)
    STDERR.puts "Module: #{compiled.name}"
    STDERR.puts ""

    compiled.processes.each do |process|
      STDERR.puts "  Process: #{process.name}"
      STDERR.puts "  ─────────────────────────────"

      process.instructions.each_with_index do |instruction, index|
        value_str = instruction.value.null? ? "" : " #{instruction.value.inspect}"
        STDERR.puts "    %4d  %-40s%s" % [index, instruction.code, value_str]
      end

      process.subroutines.each do |name, sub|
        STDERR.puts ""
        STDERR.puts "  Subroutine: #{name} (start: #{sub.start_address})"
        STDERR.puts "  ─────────────────────────────"

        sub.instructions.each_with_index do |instruction, index|
          value_str = instruction.value.null? ? "" : " #{instruction.value.inspect}"
          STDERR.puts "    %4d  %-40s%s" % [index, instruction.code, value_str]
        end
      end

      STDERR.puts ""
    end
  end
end

# Run

X.main
