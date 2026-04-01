module X
  module Assembler
    class Loader
      Log = ::Log.for(self)

      getter engine : Engine::Context
      getter resolver : ModuleResolver
      getter loaded_modules : Hash(String, CodeGenerator::CompiledModule)
      getter aliases : Hash(String, String) # alias → real module name

      @code_generator : CodeGenerator

      def initialize(@engine : Engine::Context, search_roots : Array(String) = ["src/", "lib/", "./"])
        @resolver = ModuleResolver.new(search_roots)
        @loaded_modules = {} of String => CodeGenerator::CompiledModule
        @aliases = {} of String => String
        @code_generator = CodeGenerator.new
      end

      # Load a single .xasm file from source string
      def load_source(source : String, filename : String = "<input>") : CodeGenerator::CompiledModule
        Log.debug { "Loading source: #{filename}" }

        # Lex
        lexer = Lexer.new(source)
        tokens = lexer.tokenize

        # Parse
        parser = Parser.new(tokens)
        ast = parser.parse

        # Generate code
        compiled = @code_generator.generate(ast)

        # Process requires
        compiled.requires.each do |req|
          load_require(req)
        end

        # Validate imports
        validate_imports(compiled)

        # Register module
        @loaded_modules[compiled.name] = compiled
        Log.debug { "Module '#{compiled.name}' loaded successfully" }

        compiled
      end

      # Load a .xasm file from disk
      def load_file(path : String) : CodeGenerator::CompiledModule
        unless File.exists?(path)
          raise Exceptions::Emulation.new("File not found: #{path}")
        end

        source = File.read(path)
        load_source(source, path)
      end

      # Load a module by name (resolves file path automatically)
      def load_module(module_name : String) : CodeGenerator::CompiledModule
        # Check if already loaded
        if existing = @loaded_modules[module_name]?
          return existing
        end

        # Resolve module name to file path
        path = @resolver.resolve(module_name)
        unless path
          raise Exceptions::Emulation.new("Cannot resolve module '#{module_name}' in search paths: #{@resolver.search_roots}")
        end

        load_file(path)
      end

      # Wire all loaded modules into the engine and run
      def wire_and_run
        register_runtime_builtins

        @loaded_modules.each_value do |compiled|
          wire_module(compiled)
        end

        @engine.run
      end

      # Wire a single module into the engine
      def wire_module(compiled : CodeGenerator::CompiledModule)
        Log.debug { "Wiring module '#{compiled.name}' into engine" }

        compiled.globals.each do |name, value|
        end

        # Wire exports for library modules (no processes)
        if compiled.processes.empty? && !compiled.exported_subroutines.empty?
          compiled.imports.each do |import_node|
            real_module_name = resolve_alias(import_node.module_name)
            if imported_module = @loaded_modules[real_module_name]?
              if instructions = imported_module.exported_subroutines[import_node.function_name]?
                register_module_function(real_module_name, import_node.function_name, instructions)
              end
            end
          end

          compiled.exported_subroutines.each do |func_name, instructions|
            register_module_function(compiled.name, func_name, instructions)
          end
        end

        compiled.processes.each do |compiled_process|
          wire_process(compiled_process, compiled)
        end

        compiled.supervisors.each do |supervisor_node|
          wire_supervisor(supervisor_node, compiled)
        end
      end

      # Reload a dynamic module
      def reload_module(module_name : String, new_source : String) : Bool
        old_module = @loaded_modules[module_name]?

        unless old_module
          Log.warn { "Cannot reload '#{module_name}': not loaded" }
          return false
        end

        unless old_module.is_dynamic
          Log.warn { "Cannot reload '#{module_name}': module is not .dynamic" }
          return false
        end

        Log.debug { "Hot-reloading module '#{module_name}'" }

        begin
          new_module = load_source(new_source, "#{module_name} (reload)")

          # Update exported subroutines in the built-in function registry
          # so that new calls resolve to the new code
          new_module.exported_subroutines.each do |func_name, instructions|
            full_name = "#{module_name}.#{func_name}"
            register_module_function(module_name, func_name, instructions)
          end

          @loaded_modules[module_name] = new_module
          Log.debug { "Hot-reload of '#{module_name}' succeeded" }
          true
        rescue ex
          Log.error { "Hot-reload of '#{module_name}' failed: #{ex.message}" }
          false
        end
      end

      # Private: Wiring

      private def register_runtime_builtins
        captured_loader = self
        captured_resolver = @resolver

        @engine.register_built_in_function("Code", "reload", 2) do |_engine, _process, arguments|
          module_name = arguments.first.to_s
          file_hint = arguments.last.to_s

          # Try direct resolution first, then fall back to file path
          path = captured_resolver.resolve(file_hint)

          unless path
            Log.warn { "reload: Cannot resolve '#{file_hint}'" }
            next Value::Context.new(:error)
          end

          Log.debug { "reload: Reading #{path}" }
          source = File.read(path)

          if captured_loader.reload_module(module_name, source)
            Value::Context.new(:okay)
          else
            Value::Context.new(:error)
          end
        end
      end

      private def wire_process(
        compiled_process : CodeGenerator::CompiledProcess,
        compiled_module : CodeGenerator::CompiledModule,
      )
        process = @engine.create_process(instructions: compiled_process.instructions)

        # Copy subroutines into process
        compiled_process.subroutines.each do |name, subroutine|
          # Remap start address: append instructions to process
          new_start = process.instructions.size.to_u64
          subroutine.instructions.each { |inst| process.instructions << inst }

          process.subroutines[name] = Instruction::Subroutine.new(
            name: subroutine.name,
            instructions: subroutine.instructions,
            start_address: new_start,
          )
        end

        # Also add subroutines from imported modules
        compiled_module.imports.each do |import_node|
          real_module_name = resolve_alias(import_node.module_name)
          Log.debug { "Wiring import: #{import_node.full_name}/#{import_node.arity} from '#{real_module_name}'" }
          if imported_module = @loaded_modules[real_module_name]?
            Log.debug { "  Found module, exports: #{imported_module.exported_subroutines.keys}" }
            if instructions = imported_module.exported_subroutines[import_node.function_name]?
              Log.debug { "  Registering #{real_module_name}.#{import_node.function_name} (#{instructions.size} instructions)" }
              register_module_function(real_module_name, import_node.function_name, instructions)
            else
              Log.debug { "  Function '#{import_node.function_name}' not found in exports" }
            end
          else
            Log.debug { "  Module '#{real_module_name}' not found in loaded modules" }
          end
        end

        # Set globals
        compiled_module.globals.each do |name, value|
          process.globals[name] = value.clone
        end

        # Register and schedule
        @engine.processes << process
        @engine.scheduler.enqueue(process)

        Log.debug { "Process '#{compiled_process.name}' created as <#{process.address}>" }
      end

      private def wire_supervisor(
        supervisor_node : AST::SupervisorNode,
        compiled_module : CodeGenerator::CompiledModule,
      )
        strategy = case supervisor_node.strategy
                   when "one_for_one"        then Supervisor::RestartStrategy::OneForOne
                   when "one_for_all"        then Supervisor::RestartStrategy::OneForAll
                   when "rest_for_one"       then Supervisor::RestartStrategy::RestForOne
                   when "simple_one_for_one" then Supervisor::RestartStrategy::SimpleOneForOne
                   else                           Supervisor::RestartStrategy::OneForOne
                   end

        max_restarts = supervisor_node.options["max_restarts"]?.try(&.to_i32) || 3
        window = supervisor_node.options["window"]?.try(&.to_i32.seconds) || 5.seconds

        supervisor = @engine.create_supervisor(
          strategy: strategy,
          max_restarts: max_restarts,
          restart_window: window,
        )

        supervisor_node.children.each do |child_node|
          wire_supervisor_child(supervisor, child_node, compiled_module)
        end

        Log.debug { "Supervisor '#{supervisor_node.name}' created as <#{supervisor.address}>" }
      end

      private def wire_supervisor_child(
        supervisor : Supervisor::Context,
        child_node : AST::ChildNode,
        compiled_module : CodeGenerator::CompiledModule,
      )
        # Use a temporary code generator to compile the child body
        child_gen = CodeGenerator.new
        child_process_node = AST::ProcessNode.new(
          name: child_node.id,
          body: child_node.body,
          line: child_node.line,
        )

        # Generate a temporary module to compile the child process
        child_module_ast = AST::ModuleNode.new(
          name: "#{compiled_module.name}.__child_#{child_node.id}",
          processes: [child_process_node],
        )

        child_compiled = child_gen.generate(child_module_ast)
        child_process = child_compiled.processes.first

        restart = case child_node.restart_type
                  when "permanent" then Supervisor::Child::RestartType::Permanent
                  when "transient" then Supervisor::Child::RestartType::Transient
                  when "temporary" then Supervisor::Child::RestartType::Temporary
                  else                  Supervisor::Child::RestartType::Permanent
                  end

        shutdown = case child_node.options["shutdown"]?
                   when "brutal"   then Supervisor::Child::ShutdownType::Brutal
                   when "infinity" then Supervisor::Child::ShutdownType::Infinity
                   else                 Supervisor::Child::ShutdownType::Timeout
                   end

        spec = Supervisor::Child::Specification.new(
          id: child_node.id,
          instructions: child_process.instructions,
          restart: restart,
          shutdown: shutdown,
        )

        supervisor.add_child(spec)
      end

      # Private: Import validation

      private def validate_imports(compiled : CodeGenerator::CompiledModule)
        compiled.imports.each do |import_node|
          real_module_name = resolve_alias(import_node.module_name)

          # Check if it's a loaded module
          if loaded = @loaded_modules[real_module_name]?
            # Check if the function is exported
            exported = loaded.exports.find { |e| e.function_name == import_node.function_name && e.arity == import_node.arity }
            unless exported || loaded.exported_subroutines.has_key?(import_node.function_name)
              Log.warn { "Import '#{import_node.full_name}/#{import_node.arity}' not exported from '#{real_module_name}'" }
            end
            next
          end

          # Check if it's a built-in function
          if @engine.built_in_function_registry.exists?(real_module_name, import_node.function_name, import_node.arity)
            next
          end

          Log.warn { "Import '#{import_node.full_name}/#{import_node.arity}' could not be validated (module '#{real_module_name}' not loaded and not a built-in)" }
        end
      end

      # Private: Module function registration

      private def register_module_function(
        module_name : String,
        function_name : String,
        instructions : Array(Instruction::Operation),
      )
        # Register the exported function as a built-in that executes the instructions
        captured_instructions = instructions
        captured_engine = @engine

        @engine.register_built_in_function(module_name, function_name, -1) do |engine, process, arguments|
          # Execute the instructions inline
          engine.executor.execute_inline_function(process, captured_instructions, arguments)
        end
      end

      # Private: Require handling

      private def load_require(req : AST::RequireNode)
        module_name = req.module_name

        # Check if already loaded
        if @loaded_modules.has_key?(module_name)
          Log.debug { "Module '#{module_name}' already loaded, skipping require" }
          return
        end

        # Register alias if present
        if alias_name = req.alias_name
          @aliases[alias_name] = module_name
          Log.debug { "Registered alias '#{alias_name}' → '#{module_name}'" }
        end

        # Try to load from disk
        Log.debug { "Attempting to auto-load required module '#{module_name}'" }
        Log.debug { "Search roots: #{@resolver.search_roots}" }

        begin
          load_module(module_name)
          Log.debug { "Successfully auto-loaded '#{module_name}'" }
        rescue ex
          Log.warn { "Could not auto-load required module '#{module_name}': #{ex.message}" }
        end
      end

      private def resolve_alias(name : String) : String
        @aliases[name]? || name
      end
    end
  end
end
