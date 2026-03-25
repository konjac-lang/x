require "./**"

module X
  module Engine
    class Context
      Log = ::Log.for(self)

      # Properties

      # Configuration & Customization
      property configuration : Configuration = Configuration.new
      property custom_handlers : Hash(Instruction::Code, Handler) = {} of Instruction::Code => Handler

      # Debugging
      property attached_debugger : Debugger::Context? = nil

      # Process Management
      property processes : Array(Process::Context) = [] of Process::Context
      property process_registry : ProcessRegistry = ProcessRegistry.new
      property reactivation_queue : Array(Process::Context) = [] of Process::Context
      property delayed_messages : Array(Tuple(Time, UInt64, UInt64, Value::Context)) = [] of Tuple(Time, UInt64, UInt64, Value::Context)
      property last_cleanup_time : Time = Time.utc
      getter next_process_address : UInt64 = 1_u64

      # Function Registry
      property built_in_function_registry : BuiltInFunctionRegistry = BuiltInFunctionRegistry.new

      # Fault Tolerance
      property link_registry : LinkRegistry = LinkRegistry.new
      property supervisor_registry : SupervisorRegistry = SupervisorRegistry.new
      property timer_manager : TimerManager = TimerManager.new
      property storage : FaultHandler::Storage = FaultHandler::Storage.new

      # Lazy-initialized components
      @executor : InstructionExecutor::Context?
      @fault_handler : FaultHandler::Context?
      @scheduler : Scheduler?

      # Initialization & Component Accessors

      def initialize
        Log.debug { "Initializing the Engine" }
      end

      def executor : InstructionExecutor::Context
        @executor ||= InstructionExecutor::Context.new(self)
      end

      def fault_handler : FaultHandler::Context
        @fault_handler ||= FaultHandler::Context.new(self)
      end

      def scheduler : Scheduler
        @scheduler ||= Scheduler.new(self)
      end

      # Custom Handler & Debugger Registration

      def on_instruction(code : Code, &block : Process::Context, Instruction::Operation -> Value::Context)
        @custom_handlers[code] = Handler.new(&block)
      end

      def attach_debugger(&handler : (Process::Context, Instruction::Operation?) -> Debugger::Action) : Debugger::Context
        @attached_debugger = Debugger::Context.new(&handler)
        @attached_debugger.not_nil!
      end

      def detach_debugger
        @attached_debugger = nil
      end

      # Instruction Execution

      def execute(process : Process::Context, instruction : Instruction::Operation) : Value::Context
        return Value::Context.null unless process.state.alive?

        if debug_action = check_debugger(process, instruction)
          return Value::Context.null if debug_action.abort?
        end

        increment_reductions(process)
        execute_with_error_handling(process, instruction)
      end

      def call_built_in_function(
        process : Process::Context,
        module_name : String,
        function_name : String,
        arguments : Array(Value::Context),
      ) : Value::Context
        @built_in_function_registry.call(self, process, module_name, function_name, arguments)
      end

      def register_built_in_function(
        module_name : String,
        function_name : String,
        arity : Int32,
        &block : BuiltInFunctionRegistry::Function
      )
        @built_in_function_registry.register(module_name, function_name, arity, &block)
      end

      # Process Lifecycle

      def create_process(
        instructions : Array(Instruction::Operation) = [] of Instruction::Operation,
        start_address : UInt64 = 0_u64,
      ) : Process::Context
        process = Process::Context.new(@next_process_address, instructions)
        @next_process_address += 1
        process.counter = start_address
        Log.debug { "Created Process <#{process.address}>" }
        process
      end

      def spawn_process(instructions : Array(Instruction::Operation)) : Process::Context
        process = create_process(instructions: instructions)
        register_and_schedule(process)
        process
      end

      def spawn_link(parent : Process::Context, instructions : Array(Instruction::Operation)) : Process::Context
        child = create_child_process(parent, instructions)
        @link_registry.link(parent.address, child.address)
        register_and_schedule(child)
        child
      end

      def spawn_monitor(
        parent : Process::Context,
        instructions : Array(Instruction::Operation),
      ) : Tuple(Process::Context, Process::MonitorReference)
        child = create_child_process(parent, instructions)
        ref = @link_registry.monitor(parent.address, child.address)
        register_and_schedule(child)
        {child, ref}
      end

      def exit_process(process_id : UInt64, reason : String)
        reason_value = map_reason_string(reason)
        fault_handler.kill_process(process_id, reason_value)
      end

      # Supervisor Management

      def create_supervisor(
        strategy : Supervisor::RestartStrategy = Supervisor::RestartStrategy::OneForOne,
        max_restarts : Int32 = 3,
        restart_window : Time::Span = 5.seconds,
      ) : Supervisor::Context
        sup_process = create_process(instructions: [] of Instruction::Operation)
        @processes << sup_process

        supervisor = Supervisor::Context.new(self, sup_process.address, strategy, max_restarts, restart_window)
        @supervisor_registry.register(supervisor)
        supervisor
      end

      # Message & Queue Management

      def queue_process_for_reactivation(process : Process::Context)
        return if @reactivation_queue.includes?(process)
        @reactivation_queue << process
      end

      def schedule_delayed_message(
        sender : UInt64,
        recipient : UInt64,
        value : Value::Context,
        delay_seconds : Float64,
      )
        delivery_time = Time.utc + delay_seconds.seconds
        @delayed_messages << {delivery_time, sender, recipient, value}
        Log.debug { "Scheduled message from <0.#{sender}> to <0.#{recipient}> for delivery at #{delivery_time}" }
      end

      def check_blocked_sends(process : Process::Context)
        blocked_processes.each do |blocked|
          try_unblock_send(blocked, process)
        end
      end

      def deliver_delayed_messages : Int32
        delivered = deliver_timer_messages + deliver_legacy_messages
        cleanup_delivered_messages
        delivered
      end

      # Exception Handling

      def handle_process_exception(process : Process::Context, exception : Exception)
        Log.error { "Process <#{process.address}>: #{exception.message}" }

        return if executor.handle_execution_exception(process, exception)
        return if FaultHandler::Recovery.try_recover(self, process, exception)

        mark_process_dead(process, exception)
      end

      # Main Run Loop

      def run
        fault_handler.start
        iterations = run_main_loop
        fault_handler.stop
        Log.debug { "VM completed after #{iterations} iterations" }
      end

      # Diagnostics & Inspection

      def fault_tolerance_statistics : NamedTuple(
        links: Int32,
        monitors: Int32,
        trapping: Int32,
        supervisors: Int32,
        crash_dumps: Int32)
        stats = @link_registry.stats
        {
          links:       stats[:links],
          monitors:    stats[:monitors],
          trapping:    stats[:trapping],
          supervisors: @supervisor_registry.all.size,
          crash_dumps: @storage.all.size,
        }
      end

      def inspect_process(address : UInt64) : String?
        process = find_process(address)
        return nil unless process

        build_process_inspection(process).to_json
      end

      # Private: Execution Helpers

      private def check_debugger(process : Process::Context, instruction : Instruction::Operation)
        dbg = @attached_debugger
        return nil unless dbg && dbg.should_break?(process, instruction)
        dbg.handle(process, instruction)
      end

      private def increment_reductions(process : Process::Context)
        process.reductions += 1 if process.responds_to?(:reductions)
      end

      private def execute_with_error_handling(
        process : Process::Context,
        instruction : Instruction::Operation,
      ) : Value::Context
        executor.execute(process, instruction)
      rescue ex : Exceptions::Emulation | Exception
        handle_process_exception(process, ex)
        Value::Context.new(ex)
      end

      # Private: Process Lifecycle Helpers

      private def create_child_process(
        parent : Process::Context,
        instructions : Array(Instruction::Operation),
      ) : Process::Context
        child = create_process(instructions: instructions)
        child.parent = parent.address if child.responds_to?(:parent=)
        child
      end

      private def register_and_schedule(process : Process::Context)
        @processes << process
        scheduler.enqueue(process)
      end

      private def mark_process_dead(process : Process::Context, exception : Exception)
        process.state = Process::State::DEAD
        process.exception_handlers.clear

        exception_value = build_exception_value(exception, process)
        reason = Process::Reason::Context.exception(exception_value)
        process.reason = reason if process.responds_to?(:reason=)

        dump = FaultHandler::Recovery.create_crash_dump(process, reason)
        @storage.store(dump)

        fault_handler.handle_exit(process, reason)

        # Cleanup
        process.stack.clear
        process.locals.clear
        process.mailbox.clear
        @processes.delete(process)
      end

      private def handle_process_result(process : Process::Context)
        if process.state.dead?
          process.stack.clear
          process.locals.clear
          process.mailbox.clear
          @processes.delete(process)
          return
        end

        return unless process.state.alive?
        return unless process.counter >= process.instructions.size

        process.state = Process::State::DEAD
        scheduler.mark_dead(process)
        fault_handler.handle_exit(process, Process::Reason::Context.normal)

        process.stack.clear
        process.locals.clear
        process.mailbox.clear

        @processes.delete(process)
      end

      private def build_exception_value(exception : Exception, process : Process::Context) : Value::Context
        if executor.responds_to?(:build_exception_value_from_crystal)
          return executor.build_exception_value_from_crystal(exception, process)
        end

        Value::Context.new({
          "type"    => Value::Context.new(:exception),
          "message" => Value::Context.new(exception.message || "Unknown error"),
          "error"   => Value::Context.new(exception.class.name),
        })
      end

      private def map_reason_string(reason : String) : Process::Reason::Context
        case reason
        when "normal"   then Process::Reason::Context.normal
        when "kill"     then Process::Reason::Context.kill
        when "shutdown" then Process::Reason::Context.shutdown
        else                 Process::Reason::Context.custom(reason)
        end
      end

      # Private: Message Delivery Helpers

      private def blocked_processes
        @processes.select { |actual_process| actual_process.state == Process::State::BLOCKED }
      end

      private def try_unblock_send(blocked_process : Process::Context, target_process : Process::Context)
        blocked_process.blocked_sends.each_with_index do |(target_address, message), index|
          next unless can_deliver_blocked_message?(target_address, target_process, message)

          complete_blocked_send(blocked_process, target_process, message, index)
          return
        end
      end

      private def can_deliver_blocked_message?(
        target_address : UInt64,
        target_process : Process::Context,
        message,
      ) : Bool
        target_address == target_process.address &&
          target_process.mailbox.size < @configuration.max_mailbox_size
      end

      private def complete_blocked_send(
        blocked_process : Process::Context,
        target_process : Process::Context,
        message,
        index : Int32,
      )
        return unless target_process.mailbox.push(message)

        Log.debug { "Unblocked send from <0.#{blocked_process.address}> to <0.#{target_process.address}>" }

        blocked_process.blocked_sends.delete_at(index)
        blocked_process.remove_dependency(target_process.address)

        if blocked_process.blocked_sends.empty?
          blocked_process.state = Process::State::ALIVE
          queue_process_for_reactivation(blocked_process)
        end
      end

      private def deliver_timer_messages : Int32
        count = 0
        timer_manager.get_due_timers.each do |_, sender, recipient, value|
          count += 1 if deliver_single_message(sender, recipient, value)
        end
        count
      end

      private def deliver_legacy_messages : Int32
        now = Time.utc
        count = 0
        @delayed_messages.each do |time, sender, recipient, value|
          next unless time <= now
          count += 1 if deliver_single_message(sender, recipient, value)
        end
        count
      end

      private def cleanup_delivered_messages
        now = Time.utc
        @delayed_messages.reject! { |time, _, _, _| time <= now }
      end

      private def deliver_single_message(sender : UInt64, recipient : UInt64, value : Value::Context) : Bool
        target = find_live_process(recipient)
        return false unless target
        return false unless can_accept_message?(target)

        message = Message::Context.new(sender, value, @configuration.enable_message_acknowledgments?)
        return false unless target.mailbox.push(message)

        Log.debug { "Delivered delayed message from <0.#{sender}> to <0.#{recipient}>" }
        maybe_reactivate_waiting_process(target, message)
        true
      end

      private def can_accept_message?(process : Process::Context) : Bool
        process.mailbox.size < @configuration.max_mailbox_size
      end

      private def maybe_reactivate_waiting_process(process : Process::Context, message : Message::Context)
        return unless should_reactivate?(process, message)
        queue_process_for_reactivation(process)
      end

      private def should_reactivate?(process : Process::Context, message : Message::Context) : Bool
        return true if process.state == Process::State::WAITING
        return false unless process.state == Process::State::STALE
        return false unless @configuration.auto_reactivate_processes?

        process.waiting_for.nil? ||
          process.mailbox.matches_pattern?(message.value, process.waiting_for.not_nil!)
      end

      # Private: Main Loop Helpers

      private def run_main_loop : Int32
        iterations = 0

        loop do
          iterations += 1

          if @configuration.limit_iteration?
            break if iterations >= @configuration.iteration_limit
          end

          Log.debug { "Scheduler stats: #{scheduler.stats}" }
          perform_scheduler_checks

          process = scheduler.next_runnable
          Log.debug { "Next runnable process: #{process ? "<#{process.address}>" : "nil"}" }

          break unless continue_running?(process)
          next if process.nil?

          Log.debug { "Executing process <#{process.address}>" }
          execute_process_slice(process)
          handle_process_result(process)

          Fiber.yield
        end

        iterations
      end

      private def continue_running?(process : Process::Context?) : Bool
        return true if process

        Log.debug { "No runnable process, checking if scheduler has work..." }

        unless scheduler.has_work?
          Log.debug { "Scheduler has no work, breaking loop" }
          return false
        end

        Log.debug { "Scheduler has work (waiting/blocked processes), sleeping..." }
        sleep 1.millisecond
        true
      end

      private def perform_scheduler_checks
        deliver_delayed_messages
        process_reactivation_queue
        check_await_conditions
        scheduler.check_timeouts
        scheduler.check_blocked
      end

      private def process_reactivation_queue
        while process = @reactivation_queue.shift?
          Log.debug { "Reactivating process <#{process.address}>" }
          scheduler.make_runnable(process)
        end
      end

      private def check_await_conditions
        @processes.each do |process|
          next unless process.state == Process::State::WAITING
          next unless waiting = process.waiting_for
          next unless waiting.string?

          name = waiting.to_s

          if process_registry.lookup(name)
            queue_process_for_reactivation(process)
          end
        end
      end

      private def execute_process_slice(process : Process::Context)
        process.reductions = 0_u64
        max_reductions = @configuration.max_reductions_per_slice

        while process.reductions < max_reductions && process.state.alive?
          break if process.counter >= process.instructions.size

          instruction = process.instructions[process.counter]
          execute(process, instruction)
        end
      end

      # Private: Query Helpers

      private def find_process(address : UInt64) : Process::Context?
        @processes.find { |actual_process| actual_process.address == address }
      end

      private def find_live_process(address : UInt64) : Process::Context?
        @processes.find { |actual_process| actual_process.address == address && actual_process.state != Process::State::DEAD }
      end

      private def build_process_inspection(process : Process::Context)
        {
          address:       process.address,
          state:         process.state,
          counter:       process.counter,
          stack:         process.stack.map(&.to_s),
          mailbox:       process.mailbox.size,
          call_stack:    process.call_stack.to_a,
          frame_pointer: process.frame_pointer,
          links:         @link_registry.get_links(process.address),
          traps_exit:    @link_registry.traps_exit?(process.address),
        }
      end
    end
  end
end
