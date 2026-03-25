module X
  module Assembler
    class CodeGenerator
      Log = ::Log.for(self)

      # Compiled module output
      class CompiledModule
        getter name : String
        getter is_dynamic : Bool
        getter requires : Array(AST::RequireNode)
        getter imports : Array(AST::ImportNode)
        getter exports : Array(AST::ExportNode)
        getter processes : Array(CompiledProcess)
        getter supervisors : Array(AST::SupervisorNode)
        getter exported_subroutines : Hash(String, Array(Instruction::Operation))
        getter globals : Hash(String, Value::Context)

        def initialize(
          @name : String,
          @is_dynamic : Bool = false,
          @requires : Array(AST::RequireNode) = [] of AST::RequireNode,
          @imports : Array(AST::ImportNode) = [] of AST::ImportNode,
          @exports : Array(AST::ExportNode) = [] of AST::ExportNode,
          @processes : Array(CompiledProcess) = [] of CompiledProcess,
          @supervisors : Array(AST::SupervisorNode) = [] of AST::SupervisorNode,
          @exported_subroutines : Hash(String, Array(Instruction::Operation)) = {} of String => Array(Instruction::Operation),
          @globals : Hash(String, Value::Context) = {} of String => Value::Context,
        )
        end
      end

      class CompiledProcess
        getter name : String
        getter instructions : Array(Instruction::Operation)
        getter subroutines : Hash(String, Instruction::Subroutine)

        def initialize(
          @name : String,
          @instructions : Array(Instruction::Operation) = [] of Instruction::Operation,
          @subroutines : Hash(String, Instruction::Subroutine) = {} of String => Instruction::Subroutine,
        )
        end
      end

      # Context for tracking state during compilation of a single body
      class CompilationContext
        property instructions : Array(Instruction::Operation) = [] of Instruction::Operation
        property labels : Hash(String, Int32) = {} of String => Int32
        property label_references : Array(Tuple(Int32, String, String)) = [] of Tuple(Int32, String, String)
        property locals : Hash(String, Int32) = {} of String => Int32
        property next_local_slot : Int32 = 0
        property loop_stack : Array(Tuple(Int32, Array(Int32))) = [] of Tuple(Int32, Array(Int32))
        # loop_stack entries: {loop_start_address, [break_patch_addresses]}
        property subroutines : Hash(String, Instruction::Subroutine) = {} of String => Instruction::Subroutine

        def emit(code : Instruction::Code, value : Value::Context = Value::Context.null) : Int32
          addr = @instructions.size
          @instructions << Instruction::Operation.new(code, value)
          addr
        end

        def current_address : Int32
          @instructions.size
        end

        def patch_jump(address : Int32, target : Int32)
          instruction = @instructions[address]
          code = instruction.code

          offset = target - (address + 1) # +1 because jumps are relative to next instruction

          @instructions[address] = Instruction::Operation.new(code, Value::Context.new(offset.to_i64))
        end

        def resolve_local(name : String) : Int32
          if slot = @locals[name]?
            return slot
          end
          raise Exceptions::Emulation.new("Undefined local variable: '#{name}'")
        end

        def declare_local(name : String) : Int32
          slot = @next_local_slot
          @locals[name] = slot
          @next_local_slot += 1
          slot
        end
      end

      @module_registry : Hash(String, CompiledModule) = {} of String => CompiledModule

      def initialize
      end

      def generate(ast : AST::ModuleNode) : CompiledModule
        processes = ast.processes.map { |p| compile_process(p) }

        # Compile module-level subroutines (for export)
        exported_subs = {} of String => Array(Instruction::Operation)
        ast.subroutines.each do |sub_node|
          context = CompilationContext.new
          compile_body(context, sub_node.body)
          resolve_labels(context)
          exported_subs[sub_node.name] = context.instructions
        end

        # Compile globals
        globals = {} of String => Value::Context
        ast.globals.each do |global_node|
          globals[global_node.name] = literal_to_value(global_node.value.operand || "null")
        end

        compiled = CompiledModule.new(
          name: ast.name,
          is_dynamic: ast.is_dynamic,
          requires: ast.requires,
          imports: ast.imports,
          exports: ast.exports,
          processes: processes,
          supervisors: ast.supervisors,
          exported_subroutines: exported_subs,
          globals: globals,
        )

        @module_registry[ast.name] = compiled
        compiled
      end

      private def compile_process(node : AST::ProcessNode) : CompiledProcess
        context = CompilationContext.new

        # First pass: compile body
        compile_body(context, node.body)

        # Resolve labels
        resolve_labels(context)

        CompiledProcess.new(
          name: node.name,
          instructions: context.instructions,
          subroutines: context.subroutines,
        )
      end

      private def compile_body(context : CompilationContext, statements : Array(AST::StatementNode))
        statements.each do |stmt|
          compile_statement(context, stmt)
        end
      end

      private def compile_statement(context : CompilationContext, stmt : AST::StatementNode)
        case stmt
        when AST::InstructionNode
          compile_instruction(context, stmt)
        when AST::LabelNode
          context.labels[stmt.name] = context.current_address
        when AST::LocalNode
          context.declare_local(stmt.name)
        when AST::SubroutineNode
          compile_subroutine(context, stmt)
        when AST::IfBlock
          compile_if_block(context, stmt)
        when AST::LoopBlock
          compile_loop_block(context, stmt)
        when AST::TryBlock
          compile_try_block(context, stmt)
        when AST::SpawnBlock
          compile_spawn_block(context, stmt)
        when AST::LambdaBlock
          compile_lambda_block(context, stmt)
        when AST::ReceiveMatchBlock
          compile_receive_match_block(context, stmt)
        end
      end

      # Instruction compilation

      private def compile_instruction(context : CompilationContext, node : AST::InstructionNode)
        case node.mnemonic
        # Push
        when "push"
          compile_push(context, node)
          # Stack operations
        when "pop"   then context.emit(Instruction::Code::STACK_POP)
        when "dup"   then context.emit(Instruction::Code::STACK_DUPLICATE)
        when "over"  then context.emit(Instruction::Code::STACK_DUPLICATE_SECOND)
        when "swap"  then context.emit(Instruction::Code::STACK_SWAP)
        when "rot"   then context.emit(Instruction::Code::STACK_ROTATE_UP)
        when "-rot"  then context.emit(Instruction::Code::STACK_ROTATE_DOWN)
        when "nip"   then context.emit(Instruction::Code::STACK_REMOVE_SECOND)
        when "tuck"  then context.emit(Instruction::Code::STACK_TUCK)
        when "depth" then context.emit(Instruction::Code::STACK_DEPTH)
        when "pick"  then context.emit(Instruction::Code::STACK_PICK)
        when "roll"  then context.emit(Instruction::Code::STACK_ROLL)
          # Arithmetic
        when "add"   then context.emit(Instruction::Code::ARITHMETIC_ADD)
        when "sub"   then context.emit(Instruction::Code::ARITHMETIC_SUBTRACT)
        when "mul"   then context.emit(Instruction::Code::ARITHMETIC_MULTIPLY)
        when "div"   then context.emit(Instruction::Code::ARITHMETIC_DIVIDE)
        when "mod"   then context.emit(Instruction::Code::ARITHMETIC_MODULO)
        when "neg"   then context.emit(Instruction::Code::ARITHMETIC_NEGATE)
        when "abs"   then context.emit(Instruction::Code::ARITHMETIC_ABSOLUTE)
        when "inc"   then context.emit(Instruction::Code::ARITHMETIC_INCREMENT)
        when "dec"   then context.emit(Instruction::Code::ARITHMETIC_DECREMENT)
        when "pow"   then context.emit(Instruction::Code::ARITHMETIC_POWER)
        when "floor" then context.emit(Instruction::Code::ARITHMETIC_FLOOR)
        when "ceil"  then context.emit(Instruction::Code::ARITHMETIC_CEILING)
        when "round" then context.emit(Instruction::Code::ARITHMETIC_ROUND)
        when "min"   then context.emit(Instruction::Code::ARITHMETIC_MINIMUM)
        when "max"   then context.emit(Instruction::Code::ARITHMETIC_MAXIMUM)
          # Bitwise
        when "band" then context.emit(Instruction::Code::BITWISE_AND)
        when "bor"  then context.emit(Instruction::Code::BITWISE_OR)
        when "bxor" then context.emit(Instruction::Code::BITWISE_XOR)
        when "bnot" then context.emit(Instruction::Code::BITWISE_NOT)
        when "shl"  then context.emit(Instruction::Code::BITWISE_SHIFT_LEFT)
        when "shr"  then context.emit(Instruction::Code::BITWISE_SHIFT_RIGHT)
        when "ushr" then context.emit(Instruction::Code::BITWISE_SHIFT_RIGHT_UNSIGNED)
          # Comparison
        when "eq"          then context.emit(Instruction::Code::COMPARISON_EQUAL)
        when "neq"         then context.emit(Instruction::Code::COMPARISON_NOT_EQUAL)
        when "ideq"        then context.emit(Instruction::Code::COMPARISON_IDENTICAL)
        when "nideq"       then context.emit(Instruction::Code::COMPARISON_NOT_IDENTICAL)
        when "lt"          then context.emit(Instruction::Code::COMPARISON_LESS_THAN)
        when "lte"         then context.emit(Instruction::Code::COMPARISON_LESS_THAN_OR_EQUAL)
        when "gt"          then context.emit(Instruction::Code::COMPARISON_GREATER_THAN)
        when "gte"         then context.emit(Instruction::Code::COMPARISON_GREATER_THAN_OR_EQUAL)
        when "is_null"     then context.emit(Instruction::Code::COMPARISON_IS_NULL)
        when "is_not_null" then context.emit(Instruction::Code::COMPARISON_IS_NOT_NULL)
          # Logic
        when "and" then context.emit(Instruction::Code::LOGICAL_AND)
        when "or"  then context.emit(Instruction::Code::LOGICAL_OR)
        when "not" then context.emit(Instruction::Code::LOGICAL_NOT)
        when "xor" then context.emit(Instruction::Code::LOGICAL_XOR)
          # Variables
        when "load"
          operand = node.operand.not_nil!
          slot = resolve_variable_slot(context, operand)
          context.emit(Instruction::Code::VARIABLE_LOAD_LOCAL, Value::Context.new(slot.to_i64))
        when "store"
          operand = node.operand.not_nil!
          slot = resolve_or_declare_variable_slot(context, operand)
          context.emit(Instruction::Code::VARIABLE_STORE_LOCAL, Value::Context.new(slot.to_i64))
        when "gload"
          context.emit(Instruction::Code::VARIABLE_LOAD_GLOBAL, Value::Context.new(node.operand.not_nil!))
        when "gstore"
          context.emit(Instruction::Code::VARIABLE_STORE_GLOBAL, Value::Context.new(node.operand.not_nil!))
        when "upload"
          context.emit(Instruction::Code::VARIABLE_LOAD_UPVALUE, Value::Context.new(node.operand.not_nil!.to_i64))
        when "upstore"
          context.emit(Instruction::Code::VARIABLE_STORE_UPVALUE, Value::Context.new(node.operand.not_nil!.to_i64))
          # Control flow — jumps with label resolution
        when "jump"
          label = node.operand.not_nil!.lstrip(':')
          addr = context.emit(Instruction::Code::CONTROL_JUMP, Value::Context.new(0_i64))
          context.label_references << {addr, label, "absolute"}
        when "jt"
          label = node.operand.not_nil!.lstrip(':')
          addr = context.emit(Instruction::Code::CONTROL_JUMP_IF_TRUE, Value::Context.new(0_i64))
          context.label_references << {addr, label, "relative"}
        when "jf"
          label = node.operand.not_nil!.lstrip(':')
          addr = context.emit(Instruction::Code::CONTROL_JUMP_IF_FALSE, Value::Context.new(0_i64))
          context.label_references << {addr, label, "relative"}
        when "jt?"
          label = node.operand.not_nil!.lstrip(':')
          addr = context.emit(Instruction::Code::CONTROL_JUMP_IF_TRUE_KEEP, Value::Context.new(0_i64))
          context.label_references << {addr, label, "relative"}
        when "jf?"
          label = node.operand.not_nil!.lstrip(':')
          addr = context.emit(Instruction::Code::CONTROL_JUMP_IF_FALSE_KEEP, Value::Context.new(0_i64))
          context.label_references << {addr, label, "relative"}

          # Call
        when "call"
          compile_call(context, node)
        when "call_dynamic"
          context.emit(Instruction::Code::CONTROL_CALL_DYNAMIC)
        when "call_indirect"
          context.emit(Instruction::Code::CONTROL_CALL_INDIRECT)
          # Return
        when "return"
          context.emit(Instruction::Code::CONTROL_RETURN_VALUE)
        when "halt"
          context.emit(Instruction::Code::CONTROL_HALT)
        when "nop"
          context.emit(Instruction::Code::CONTROL_NO_OPERATION)
          # Lambdas
        when "invoke"
          arity = node.operand.not_nil!.to_i64
          context.emit(Instruction::Code::LAMBDA_INVOKE, Value::Context.new(arity))
        when "bind"
          count = node.operand.not_nil!.to_i64
          context.emit(Instruction::Code::LAMBDA_BIND, Value::Context.new(count))

          # Process operations
        when "self"
          context.emit(Instruction::Code::PROCESS_SELF)
        when "register"
          context.emit(Instruction::Code::PROCESS_REGISTER, Value::Context.new(node.operand.not_nil!))
        when "unregister"
          context.emit(Instruction::Code::PROCESS_UNREGISTER, Value::Context.new(node.operand.not_nil!))
        when "whereis"
          context.emit(Instruction::Code::PROCESS_WHEREIS, Value::Context.new(node.operand.not_nil!))
        when "exit"
          context.emit(Instruction::Code::PROCESS_EXIT)
        when "exit_remote"
          context.emit(Instruction::Code::PROCESS_EXIT_REMOTE)
        when "kill"
          context.emit(Instruction::Code::PROCESS_KILL)
        when "sleep"
          context.emit(Instruction::Code::PROCESS_SLEEP)
        when "yield"
          context.emit(Instruction::Code::PROCESS_YIELD)
        when "link"
          context.emit(Instruction::Code::PROCESS_LINK)
        when "unlink"
          context.emit(Instruction::Code::PROCESS_UNLINK)
        when "monitor"
          context.emit(Instruction::Code::PROCESS_MONITOR)
        when "demonitor"
          context.emit(Instruction::Code::PROCESS_DEMONITOR)
        when "trap_on"
          context.emit(Instruction::Code::PROCESS_TRAP_EXIT_ENABLE)
        when "trap_off"
          context.emit(Instruction::Code::PROCESS_TRAP_EXIT_DISABLE)
        when "alive?"
          context.emit(Instruction::Code::PROCESS_IS_ALIVE)
        when "info"
          context.emit(Instruction::Code::PROCESS_GET_INFO)
        when "set_flag"
          context.emit(Instruction::Code::PROCESS_SET_FLAG)
        when "get_flag"
          context.emit(Instruction::Code::PROCESS_GET_FLAG)
        when "await"
          context.emit(Instruction::Code::PROCESS_AWAIT, Value::Context.new(node.operand.not_nil!))
          # Message operations
        when "send"
          context.emit(Instruction::Code::MESSAGE_SEND)
        when "send_after"
          context.emit(Instruction::Code::MESSAGE_SEND_AFTER)
        when "receive"
          context.emit(Instruction::Code::MESSAGE_RECEIVE)
        when "receive_timeout"
          context.emit(Instruction::Code::MESSAGE_RECEIVE_WITH_TIMEOUT)
        when "peek"
          context.emit(Instruction::Code::MESSAGE_PEEK)
        when "mailbox_size"
          context.emit(Instruction::Code::MESSAGE_MAILBOX_SIZE)
        when "cancel_timer"
          context.emit(Instruction::Code::MESSAGE_CANCEL_TIMER)
          # Exception operations
        when "throw"
          context.emit(Instruction::Code::EXCEPTION_THROW)
        when "rethrow"
          context.emit(Instruction::Code::EXCEPTION_RETHROW)
        when "stacktrace"
          context.emit(Instruction::Code::EXCEPTION_GET_STACKTRACE)
          # Supervisor operations (from within process code)
          # These are stack-based, no special compilation needed

          # Break/continue — handled in loop context
        when "break"
          compile_break(context)
        when "break_if"
          compile_break_if(context)
        when "break_unless"
          compile_break_unless(context)
        when "continue"
          compile_continue(context)
        when "reload"
          context.emit(Instruction::Code::CONTROL_CALL_BUILT_IN_FUNCTION,
            Value::Context.new([
              Value::Context.new("Code"),
              Value::Context.new("reload"),
              Value::Context.new(2_i64),
            ]))
        else
          raise Exceptions::Emulation.new("Unknown mnemonic: '#{node.mnemonic}' at line #{node.line}")
        end
      end

      # Push compilation

      private def compile_push(context : CompilationContext, node : AST::InstructionNode)
        operand = node.operand.not_nil!

        case operand
        when "null"
          context.emit(Instruction::Code::PUSH_NULL)
        when "true"
          context.emit(Instruction::Code::PUSH_BOOLEAN_TRUE)
        when "false"
          context.emit(Instruction::Code::PUSH_BOOLEAN_FALSE)
        when "self"
          context.emit(Instruction::Code::PROCESS_SELF)
        when "depth"
          context.emit(Instruction::Code::STACK_DEPTH)
        when .starts_with?(':')
          symbol_name = operand[1..]
          if symbol_name.matches?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/)
            runtime_symbol = symbol_name.to_symbol
            context.emit(Instruction::Code::PUSH_SYMBOL, Value::Context.new(runtime_symbol))
          else
            context.emit(Instruction::Code::PUSH_STRING, Value::Context.new(operand))
          end
        when .ends_with?('u'), .ends_with?('U')
          context.emit(Instruction::Code::PUSH_UNSIGNED_INTEGER, Value::Context.new(operand.rstrip("uU").to_u64))
        else
          # Try integer first
          if int_val = operand.to_i64?
            context.emit(Instruction::Code::PUSH_INTEGER, Value::Context.new(int_val))
          elsif float_val = operand.to_f64?
            context.emit(Instruction::Code::PUSH_FLOAT, Value::Context.new(float_val))
          else
            # Everything else is a string
            context.emit(Instruction::Code::PUSH_STRING, Value::Context.new(operand))
          end
        end
      end

      # Call compilation

      private def compile_call(context : CompilationContext, node : AST::InstructionNode)
        target = node.operand.not_nil!

        if target.starts_with?(':')
          # call :subroutine — local subroutine call
          sub_name = target[1..]
          context.emit(Instruction::Code::CONTROL_CALL, Value::Context.new(sub_name))
        elsif node.operand2
          # call Module.function/arity — built-in or module function
          module_name = target
          function_name = node.operand2.not_nil!
          arity = node.operand3.not_nil!.to_i64

          call_info = [
            Value::Context.new(module_name),
            Value::Context.new(function_name),
            Value::Context.new(arity),
          ]
          context.emit(Instruction::Code::CONTROL_CALL_BUILT_IN_FUNCTION, Value::Context.new(call_info))
        else
          # Bare name — treat as subroutine call
          context.emit(Instruction::Code::CONTROL_CALL, Value::Context.new(target))
        end
      end

      # Block compilation

      private def compile_if_block(context : CompilationContext, node : AST::IfBlock)
        # Emit: JUMP_IF_FALSE to else/end
        jf_addr = context.emit(Instruction::Code::CONTROL_JUMP_IF_FALSE, Value::Context.new(0_i64))

        # Compile then body
        compile_body(context, node.then_body)

        if else_body = node.else_body
          # Emit: JUMP over else body
          jump_end_addr = context.emit(Instruction::Code::CONTROL_JUMP_FORWARD, Value::Context.new(0_i64))

          # Patch JF to point here (else start)
          context.patch_jump(jf_addr, context.current_address)

          # Compile else body
          compile_body(context, else_body)

          # Patch JUMP to point here (end)
          context.patch_jump(jump_end_addr, context.current_address)
        else
          # No else — patch JF to point here
          context.patch_jump(jf_addr, context.current_address)
        end
      end

      private def compile_loop_block(context : CompilationContext, node : AST::LoopBlock)
        loop_start = context.current_address
        break_patches = [] of Int32

        # Push loop context
        context.loop_stack.push({loop_start, break_patches})

        # Compile loop body
        compile_body(context, node.body)

        # Jump back to start
        offset = loop_start - (context.current_address + 1)
        context.emit(Instruction::Code::CONTROL_JUMP_BACKWARD, Value::Context.new((-offset).to_i64))

        # Patch all break addresses to point here
        loop_start_addr, breaks = context.loop_stack.pop
        breaks.each do |break_addr|
          context.patch_jump(break_addr, context.current_address)
        end
      end

      private def compile_break(context : CompilationContext)
        if context.loop_stack.empty?
          raise Exceptions::Emulation.new("'break' used outside of loop")
        end

        _, breaks = context.loop_stack.last
        addr = context.emit(Instruction::Code::CONTROL_JUMP_FORWARD, Value::Context.new(0_i64))
        breaks << addr
      end

      private def compile_break_if(context : CompilationContext)
        if context.loop_stack.empty?
          raise Exceptions::Emulation.new("'break_if' used outside of loop")
        end

        _, breaks = context.loop_stack.last
        addr = context.emit(Instruction::Code::CONTROL_JUMP_IF_TRUE, Value::Context.new(0_i64))
        breaks << addr
      end

      private def compile_break_unless(context : CompilationContext)
        if context.loop_stack.empty?
          raise Exceptions::Emulation.new("'break_unless' used outside of loop")
        end

        _, breaks = context.loop_stack.last
        addr = context.emit(Instruction::Code::CONTROL_JUMP_IF_FALSE, Value::Context.new(0_i64))
        breaks << addr
      end

      private def compile_continue(context : CompilationContext)
        if context.loop_stack.empty?
          raise Exceptions::Emulation.new("'continue' used outside of loop")
        end

        loop_start, _ = context.loop_stack.last
        offset = loop_start - (context.current_address + 1)
        context.emit(Instruction::Code::CONTROL_JUMP_BACKWARD, Value::Context.new((-offset).to_i64))
      end

      private def compile_try_block(context : CompilationContext, node : AST::TryBlock)
        # Emit TRY_BEGIN with placeholder offset
        try_begin_addr = context.emit(Instruction::Code::EXCEPTION_TRY_BEGIN, Value::Context.new(0_i64))

        # Compile try body
        compile_body(context, node.try_body)

        # Emit TRY_END (normal exit from try)
        context.emit(Instruction::Code::EXCEPTION_TRY_END)

        # Emit JUMP_FORWARD past catch block
        jump_past_catch = context.emit(Instruction::Code::CONTROL_JUMP_FORWARD, Value::Context.new(0_i64))

        # Patch TRY_BEGIN to point to catch
        catch_start = context.current_address
        offset = catch_start - (try_begin_addr + 1)
        context.instructions[try_begin_addr] = Instruction::Operation.new(
          Instruction::Code::EXCEPTION_TRY_BEGIN,
          Value::Context.new(offset.to_i64)
        )

        # Emit CATCH entry
        context.emit(Instruction::Code::EXCEPTION_CATCH)

        # Compile catch body
        compile_body(context, node.catch_body)

        # Emit TRY_END (end of catch)
        context.emit(Instruction::Code::EXCEPTION_TRY_END)

        # Patch JUMP past catch
        context.patch_jump(jump_past_catch, context.current_address)
      end

      private def compile_spawn_block(context : CompilationContext, node : AST::SpawnBlock)
        # Compile the spawn body into a separate instruction array
        spawn_context = CompilationContext.new
        compile_body(spawn_context, node.body)
        resolve_labels(spawn_context)

        # Push the instructions onto the stack
        context.emit(Instruction::Code::PUSH_INSTRUCTIONS, Value::Context.new(spawn_context.instructions))

        # Emit the appropriate spawn instruction
        case node.spawn_type
        when "spawn"         then context.emit(Instruction::Code::PROCESS_SPAWN)
        when "spawn_link"    then context.emit(Instruction::Code::PROCESS_SPAWN_LINKED)
        when "spawn_monitor" then context.emit(Instruction::Code::PROCESS_SPAWN_MONITORED)
        end
      end

      private def compile_lambda_block(context : CompilationContext, node : AST::LambdaBlock)
        # Compile the lambda body into a separate instruction array
        lambda_context = CompilationContext.new
        compile_body(lambda_context, node.body)
        resolve_labels(lambda_context)

        # Build capture specifications
        capture_specs = node.captures.map_with_index do |name, index|
          if slot = context.locals[name]?
            "local:#{slot}"
          else
            "local:#{index}"
          end
        end

        # Emit LAMBDA_CREATE with body and captures
        lambda_def = {lambda_context.instructions, capture_specs}
        context.emit(Instruction::Code::LAMBDA_CREATE, Value::Context.new(lambda_def))
      end

      private def compile_receive_match_block(context : CompilationContext, node : AST::ReceiveMatchBlock)
        # Compile the matcher body into a separate instruction array
        matcher_context = CompilationContext.new
        compile_body(matcher_context, node.body)
        resolve_labels(matcher_context)

        matcher_instructions = matcher_context.instructions

        if node.with_timeout
          context.emit(Instruction::Code::MESSAGE_RECEIVE_SELECTIVE_WITH_TIMEOUT,
            Value::Context.new(matcher_instructions))
        else
          context.emit(Instruction::Code::MESSAGE_RECEIVE_SELECTIVE,
            Value::Context.new(matcher_instructions))
        end
      end

      private def compile_subroutine(context : CompilationContext, node : AST::SubroutineNode)
        # Compile subroutine as a separate chunk appended after main code
        sub_start = context.current_address

        # We'll compile the subroutine body inline but track its start address
        sub_context = CompilationContext.new
        sub_context.locals = context.locals.dup # inherit locals namespace for now
        sub_context.next_local_slot = context.next_local_slot

        compile_body(sub_context, node.body)
        resolve_labels(sub_context)

        # Register the subroutine
        context.subroutines[node.name] = Instruction::Subroutine.new(
          name: node.name,
          instructions: sub_context.instructions,
          start_address: 0_u64 # will be remapped when loaded into process
        )
      end

      # Label resolution

      private def resolve_labels(context : CompilationContext)
        context.label_references.each do |address, label, mode|
          target = context.labels[label]?
          unless target
            raise Exceptions::Emulation.new("Undefined label: ':#{label}'")
          end

          instruction = context.instructions[address]

          case mode
          when "absolute"
            context.instructions[address] = Instruction::Operation.new(
              instruction.code,
              Value::Context.new(target.to_i64)
            )
          when "relative"
            offset = target - (address + 1)
            context.instructions[address] = Instruction::Operation.new(
              instruction.code,
              Value::Context.new(offset.to_i64)
            )
          end
        end
      end

      # Helpers

      private def resolve_variable_slot(context : CompilationContext, name : String) : Int32
        # Try as named local first
        if slot = context.locals[name]?
          return slot
        end

        # Try as integer slot number
        begin
          return name.to_i32
        rescue
        end

        raise Exceptions::Emulation.new("Undefined local variable: '#{name}'")
      end

      private def resolve_or_declare_variable_slot(context : CompilationContext, name : String) : Int32
        # Try as named local first
        if slot = context.locals[name]?
          return slot
        end

        # Try as integer slot number
        begin
          return name.to_i32
        rescue
        end

        # Auto-declare if storing to an undeclared name
        context.declare_local(name)
      end

      private def literal_to_value(operand : String) : Value::Context
        case operand
        when "null"             then Value::Context.null
        when "true"             then Value::Context.new(true)
        when "false"            then Value::Context.new(false)
        when .starts_with?(':') then Value::Context.new(operand[1..])
        when .includes?('.')    then Value::Context.new(operand.to_f64)
        else
          begin
            Value::Context.new(operand.to_i64)
          rescue
            Value::Context.new(operand)
          end
        end
      end
    end
  end
end
