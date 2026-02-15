module X
  module InstructionExecutor
    module LambdaClosureOperations
      extend self

      # LAMBDA_CREATE
      # Create a lambda from instruction array and captures
      # Operand: Tuple(Array(Instruction), Array(String)) - (body, capture_names)
      # Stack Before: [...]
      # Stack After: [... lambda]
      private def execute_lambda_create(process : Process::Context, instruction : Instruction::Operation) : Value::Context
        process.counter += 1

        # Extract body instructions and capture names from operand
        unless instruction.value.lambda_definition?
          raise Exceptions::TypeMismatch.new("LAMBDA_CREATE requires a tuple operand")
        end

        tuple = instruction.value.to_lambda_definition
        body_instructions = tuple[0]
        capture_indices = tuple[1]

        # Capture values from parent frame by index into upvalues array
        upvalues = capture_indices.map do |specification|
          parts = specification.split(":")
          if parts.size == 2
            index = parts[1].to_i32
            local_index = process.frame_pointer + index
            if local_index >= 0 && local_index < process.locals.size
              process.locals[local_index].clone
            else
              Value::Context.null
            end
          else
            # Fallback: try as raw index
            begin
              index = specification.to_i32
              local_index = process.frame_pointer + index
              if local_index >= 0 && local_index < process.locals.size
                process.locals[local_index].clone
              else
                Value::Context.null
              end
            rescue
              Value::Context.null
            end
          end
        end

        # Create lambda with upvalues
        lambda = Lambda::Context.new(
          instructions: body_instructions,
          variables: [] of String,
          captured_environment: Hash(String, Value::Context).new,
          upvalues: upvalues
        )

        result = Value::Context.new(lambda)
        process.stack.push(result)
        result
      end

      # LAMBDA_INVOKE
      # Invoke a lambda with arguments from stack
      # Operand: UInt8 (argument count)
      # Stack Before: [... lambda, arg1, arg2, ..., argN]
      # Stack After: [... result]
      private def execute_lambda_invoke(process : Process::Context, instruction : Instruction::Operation) : Value::Context
        process.counter += 1

        unless instruction.value.integer? || instruction.value.unsigned_integer?
          raise Exceptions::TypeMismatch.new("LAMBDA_INVOKE requires an integer argument count")
        end

        arg_count = instruction.value.to_i64.to_i32

        # Need lambda + arg_count values on stack
        check_stack_size(process, arg_count + 1, "LAMBDA_INVOKE")

        # Pop arguments in reverse order
        arguments = Array(Value::Context).new(arg_count)
        arg_count.times do
          arguments.unshift(process.stack.pop)
        end

        # Pop the lambda
        lambda_value = process.stack.pop

        unless lambda_value.lambda?
          raise Exceptions::TypeMismatch.new("LAMBDA_INVOKE requires a lambda value")
        end

        lambda = lambda_value.to_lambda

        # Execute the lambda
        result = execute_lambda(process, lambda, arguments)

        process.stack.push(result)
        result
      end

      # LAMBDA_BIND
      # Partially apply arguments to a lambda
      # Operand: UInt8 (number of arguments to bind)
      # Stack Before: [... lambda, arg1, arg2, ..., argN]
      # Stack After: [... partially_applied_lambda]
      private def execute_lambda_bind(process : Process::Context, instruction : Instruction::Operation) : Value::Context
        process.counter += 1

        unless instruction.value.integer? || instruction.value.unsigned_integer?
          raise Exceptions::TypeMismatch.new("LAMBDA_BIND requires an integer argument count")
        end

        bind_count = instruction.value.to_i64.to_i32

        # Need lambda + bind_count values on stack
        check_stack_size(process, bind_count + 1, "LAMBDA_BIND")

        # Pop arguments to bind in reverse order
        bound_args = Array(Value::Context).new(bind_count)
        bind_count.times do
          bound_args.unshift(process.stack.pop)
        end

        # Pop the lambda
        lambda_value = process.stack.pop

        unless lambda_value.lambda?
          raise Exceptions::TypeMismatch.new("LAMBDA_BIND requires a lambda value")
        end

        original_lambda = lambda_value.to_lambda

        # Create a new lambda with bound arguments
        # The new lambda will prepend bound_args to any call arguments
        partial_lambda = Lambda::Partial.new(
          original: original_lambda,
          bound_arguments: bound_args
        )

        result = Value::Context.new(partial_lambda)
        process.stack.push(result)

        result
      end

      # Execute a lambda with given arguments
      private def execute_lambda(
        process : Process::Context,
        lambda : Lambda::Context,
        arguments : Array(Value::Context),
      ) : Value::Context
        # Handle partial application
        actual_lambda = lambda
        actual_arguments = arguments

        if lambda.is_a?(Lambda::Partial)
          partial = lambda.as(Lambda::Partial)
          actual_arguments = partial.bound_arguments + arguments
          actual_lambda = partial.original
        end

        # Save current execution state
        saved_counter = process.counter
        saved_instructions = process.instructions
        saved_locals = process.locals.dup
        saved_frame_pointer = process.frame_pointer
        saved_closure = process.current_closure

        # Set up lambda execution environment
        process.current_closure = actual_lambda
        process.instructions = actual_lambda.instructions
        process.counter = 0_u64
        process.frame_pointer = process.locals.size

        # The compiler allocates locals as: parameters first, then free variables.
        # The lambda body uses VARIABLE_STORE_LOCAL to pop arguments into parameter slots,
        # then references free variables by their local index.
        # So we push: arguments first (parameters), then upvalues (captured free variables).
        actual_arguments.each do |arg|
          process.locals << arg
        end

        actual_lambda.upvalues.each do |upvalue|
          process.locals << upvalue
        end

        # Execute lambda instructions
        result = Value::Context.null

        while process.counter < process.instructions.size
          instruction = process.instructions[process.counter]

          # Check for return
          if instruction.code == Instruction::Code::CONTROL_RETURN ||
             instruction.code == Instruction::Code::CONTROL_RETURN_VALUE
            if !process.stack.empty?
              result = process.stack.pop
            end
            break
          end

          result = execute(process, instruction)
        end

        # Get result from stack if available
        if result.null? && !process.stack.empty?
          result = process.stack.pop
        end

        # Restore execution state (no need to restore globals anymore!)
        process.instructions = saved_instructions
        process.counter = saved_counter
        process.locals = saved_locals
        process.frame_pointer = saved_frame_pointer
        process.current_closure = saved_closure

        result
      end
    end
  end
end
