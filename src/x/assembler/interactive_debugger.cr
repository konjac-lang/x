module X
  module Assembler
    class InteractiveDebugger
      property engine : Engine::Context
      property breakpoints : Hash(String, UInt64) = {} of String => UInt64
      property process_filter : UInt64? = nil
      property auto_continue : Bool = false
      property show_context_lines : Int32 = 3
      property last_command : String = "step"
      property instruction_names : Hash(UInt64, Hash(UInt64, String)) = {} of UInt64 => Hash(UInt64, String)

      def initialize(@engine : Engine::Context)
      end

      def attach
        debugger = self

        @engine.attach_debugger do |process, instruction|
          if filter = debugger.process_filter
            if process.address != filter
              next Engine::Debugger::Action::Continue
            end
          end

          if debugger.auto_continue
            next Engine::Debugger::Action::Continue
          end

          debugger.display_state(process, instruction)
          debugger.prompt(process, instruction)
        end

        @engine.attached_debugger.not_nil!.enable_step_mode
      end

      def display_state(process : Process::Context, instruction : Instruction::Operation?)
        name = process.registered_name || "untitled"
        STDERR.puts ""
        STDERR.puts "\e[1;36m── Process <#{process.address}> (#{name}) @ instruction #{process.counter} ──\e[0m"

        if inst = instruction
          value_str = inst.value.null? ? "" : " \e[33m#{inst.value.inspect}\e[0m"
          STDERR.puts "\e[1;32m  → #{inst.code}\e[0m#{value_str}"
        end

        display_stack_summary(process)
        STDERR.flush
      end

      def prompt(process : Process::Context, instruction : Instruction::Operation?) : Engine::Debugger::Action
        loop do
          STDERR.print "\e[1;35mxdb>\e[0m "
          STDERR.flush
          input = gets
          unless input
            STDERR.puts ""
            return Engine::Debugger::Action::Continue
          end

          input = input.strip
          input = @last_command if input.empty?

          parts = input.split(/\s+/, 2)
          command = parts[0]
          args = parts[1]?

          action = handle_command(command, args, process, instruction)
          if action
            @last_command = command unless command == ""
            return action
          end
        end
      end

      private def display_stack_summary(process : Process::Context)
        if process.stack.empty?
          STDERR.puts "  Stack: \e[2m(empty)\e[0m"
        else
          top = process.stack.last(5).reverse
          STDERR.puts "  Stack (top #{top.size} of #{process.stack.size}):"
          top.each_with_index do |val, i|
            marker = i == 0 ? "→" : " "
            STDERR.puts "    #{marker} #{val.inspect}"
          end
        end
      end

      private def handle_command(command : String, args : String?, process : Process::Context, instruction : Instruction::Operation?) : Engine::Debugger::Action?
        case command
        when "s", "step"
          Engine::Debugger::Action::Step
        when "n", "next"
          Engine::Debugger::Action::StepOver
        when "c", "continue"
          Engine::Debugger::Action::Continue
        when "r", "run"
          @auto_continue = true
          Engine::Debugger::Action::Continue
        when "k", "kill"
          STDERR.puts "  Killing process <#{process.address}>"
          Engine::Debugger::Action::Abort
        when "stack", "st"
          display_full_stack(process)
          nil
        when "locals", "l"
          display_locals(process)
          nil
        when "mailbox", "mb"
          display_mailbox(process)
          nil
        when "processes", "ps"
          display_processes
          nil
        when "registry", "reg"
          display_registry
          nil
        when "instruction", "i"
          display_current_instruction(process, instruction)
          nil
        when "instructions", "is"
          display_instructions(process, args)
          nil
        when "callstack", "cs"
          display_call_stack(process)
          nil
        when "watch"
          if a = args
            display_watch(process, a)
          else
            STDERR.puts "  Usage: watch <local_index>"
          end
          nil
        when "filter", "f"
          if a = args
            if a == "off" || a == "clear"
              @process_filter = nil
              STDERR.puts "  Process filter cleared"
            else
              @process_filter = a.to_u64
              STDERR.puts "  Filtering to process <#{@process_filter}>"
            end
          else
            if filter = @process_filter
              STDERR.puts "  Filtering: process <#{filter}>"
            else
              STDERR.puts "  No filter active"
            end
          end
          nil
        when "break", "b"
          if a = args
            set_breakpoint(a, process)
          else
            list_breakpoints
          end
          nil
        when "delete", "del"
          if a = args
            delete_breakpoint(a)
          else
            STDERR.puts "  Usage: delete <breakpoint_id>"
          end
          nil
        when "eval", "e"
          if a = args
            eval_expression(process, a)
          else
            STDERR.puts "  Usage: eval <expression>"
          end
          nil
        when "help", "h", "?"
          display_help
          nil
        when "quit", "q"
          STDERR.puts "  Exiting debugger"
          exit 0
        else
          STDERR.puts "  Unknown command: '#{command}'. Type 'help' for commands."
          nil
        end
      end

      private def display_full_stack(process : Process::Context)
        if process.stack.empty?
          STDERR.puts "  Stack: (empty)"
          return
        end

        STDERR.puts "  Stack (#{process.stack.size} values, top first):"
        process.stack.reverse_each.with_index do |val, i|
          depth = process.stack.size - 1 - i
          marker = i == 0 ? "→" : " "
          STDERR.puts "    #{marker} [#{depth}] #{val.inspect}"
        end
      end

      private def display_locals(process : Process::Context)
        if process.locals.empty?
          STDERR.puts "  Locals: (none)"
          return
        end

        STDERR.puts "  Locals (#{process.locals.size}):"
        process.locals.each_with_index do |val, i|
          STDERR.puts "    [#{i}] #{val.inspect}"
        end
      end

      private def display_mailbox(process : Process::Context)
        STDERR.puts "  Mailbox (#{process.mailbox.size} messages):"
        if process.mailbox.size == 0
          STDERR.puts "    (empty)"
          return
        end

        if msg = process.mailbox.peek
          STDERR.puts "    [next] from <#{msg.sender}>: #{msg.value.inspect}"
        end
        if process.mailbox.size > 1
          STDERR.puts "    ... and #{process.mailbox.size - 1} more"
        end
      end

      private def display_processes
        STDERR.puts "  Processes (#{@engine.processes.size}):"
        @engine.processes.each do |p|
          name = p.registered_name || "unnamed"
          marker = @process_filter == p.address ? "→" : " "
          STDERR.puts "  #{marker} <#{p.address}> #{name} [#{p.state}] @ #{p.counter} (stack: #{p.stack.size}, mailbox: #{p.mailbox.size})"
        end
      end

      private def display_registry
        names = @engine.process_registry.registered_names
        if names.empty?
          STDERR.puts "  Registry: (empty)"
          return
        end

        STDERR.puts "  Registry (#{names.size}):"
        names.each do |name|
          if addr = @engine.process_registry.lookup(name)
            STDERR.puts "    #{name} → <#{addr}>"
          end
        end
      end

      private def display_current_instruction(process : Process::Context, instruction : Instruction::Operation?)
        if inst = instruction
          STDERR.puts "  Counter: #{process.counter}"
          STDERR.puts "  Code:    #{inst.code}"
          STDERR.puts "  Value:   #{inst.value.inspect}" unless inst.value.null?
        else
          STDERR.puts "  No current instruction"
        end
      end

      private def display_instructions(process : Process::Context, args : String?)
        range_size = 10
        center = process.counter.to_i32

        if a = args
          range_size = a.to_i32 rescue 10
        end

        start = {center - range_size // 2, 0}.max
        finish = {start + range_size, process.instructions.size}.min

        STDERR.puts "  Instructions (#{start}..#{finish - 1}) of #{process.instructions.size}:"
        (start...finish).each do |idx|
          inst = process.instructions[idx]
          marker = idx == center ? "→" : " "
          value_str = inst.value.null? ? "" : " #{inst.value.inspect}"
          STDERR.puts "  #{marker} %4d  %-35s%s" % [idx, inst.code, value_str]
        end
      end

      private def display_call_stack(process : Process::Context)
        if process.call_stack.empty?
          STDERR.puts "  Call stack: (empty)"
          return
        end

        STDERR.puts "  Call stack (#{process.call_stack.size} frames):"
        process.call_stack.reverse_each.with_index do |addr, i|
          STDERR.puts "    [#{i}] return to #{addr}"
        end
        STDERR.puts "  Frame pointer: #{process.frame_pointer}"
      end

      private def display_watch(process : Process::Context, expr : String)
        if idx = expr.to_i32?
          if idx >= 0 && idx < process.locals.size
            STDERR.puts "  locals[#{idx}] = #{process.locals[idx].inspect}"
          else
            STDERR.puts "  Local index #{idx} out of range (0..#{process.locals.size - 1})"
          end
        elsif expr == "top" || expr == "tos"
          if process.stack.empty?
            STDERR.puts "  Stack is empty"
          else
            STDERR.puts "  Stack top = #{process.stack.last.inspect}"
          end
        elsif expr == "counter" || expr == "pc"
          STDERR.puts "  Counter = #{process.counter}"
        elsif expr == "state"
          STDERR.puts "  State = #{process.state}"
        else
          STDERR.puts "  Unknown watch expression: #{expr}"
          STDERR.puts "  Try: <index>, top, counter, state"
        end
      end

      private def set_breakpoint(args : String, process : Process::Context)
        dbg = @engine.attached_debugger.not_nil!

        if addr = args.to_u64?
          bp = dbg.add_breakpoint_at(addr)
          STDERR.puts "  Breakpoint ##{bp.id} set at instruction #{addr}"
        elsif args.includes?(":")
          parts = args.split(":", 2)
          name = parts[0]
          addr = parts[1].to_u64?
          if addr
            bp = dbg.add_breakpoint { |p| p.registered_name == name && p.counter == addr }
            STDERR.puts "  Breakpoint ##{bp.id} set for process '#{name}' at instruction #{addr}"
          else
            STDERR.puts "  Invalid format. Use: break name:address"
          end
        else
          bp = dbg.add_breakpoint { |p| p.registered_name == args }
          STDERR.puts "  Breakpoint ##{bp.id} set for process '#{args}'"
        end
      end

      private def list_breakpoints
        dbg = @engine.attached_debugger
        unless dbg
          STDERR.puts "  No debugger attached"
          return
        end

        bps = dbg.breakpoints
        if bps.empty?
          STDERR.puts "  No breakpoints set"
          return
        end

        STDERR.puts "  Breakpoints (#{bps.size}):"
        bps.each do |bp|
          status = bp.enabled? ? "enabled" : "disabled"
          STDERR.puts "    ##{bp.id} [#{status}] hits: #{bp.hit_count}"
        end
      end

      private def delete_breakpoint(args : String)
        dbg = @engine.attached_debugger
        unless dbg
          STDERR.puts "  No debugger attached"
          return
        end

        if args == "all"
          dbg.clear_breakpoints
          STDERR.puts "  All breakpoints cleared"
        elsif id = args.to_u64?
          if dbg.remove_breakpoint(id)
            STDERR.puts "  Breakpoint ##{id} removed"
          else
            STDERR.puts "  Breakpoint ##{id} not found"
          end
        else
          STDERR.puts "  Usage: delete <id> or delete all"
        end
      end

      private def eval_expression(process : Process::Context, expr : String)
        case expr
        when "stack.size"
          STDERR.puts "  #{process.stack.size}"
        when "mailbox.size"
          STDERR.puts "  #{process.mailbox.size}"
        when "locals.size"
          STDERR.puts "  #{process.locals.size}"
        when "address"
          STDERR.puts "  #{process.address}"
        when "name"
          STDERR.puts "  #{process.registered_name || "(untitled)"}"
        when "reductions"
          STDERR.puts "  #{process.reductions}"
        when .starts_with?("stack[")
          idx_str = expr.gsub(/stack\[(\d+)\]/, "\\1")
          if idx = idx_str.to_i32?
            if idx >= 0 && idx < process.stack.size
              STDERR.puts "  #{process.stack[idx].inspect}"
            else
              STDERR.puts "  Index out of range"
            end
          end
        when .starts_with?("locals[")
          idx_str = expr.gsub(/locals\[(\d+)\]/, "\\1")
          if idx = idx_str.to_i32?
            if idx >= 0 && idx < process.locals.size
              STDERR.puts "  #{process.locals[idx].inspect}"
            else
              STDERR.puts "  Index out of range"
            end
          end
        else
          STDERR.puts "  Available: stack.size, mailbox.size, locals.size, address, name, reductions, stack[n], locals[n]"
        end
      end

      private def display_help
        STDERR.puts ""
        STDERR.puts "\e[1mExecution:\e[0m"
        STDERR.puts "  s, step          Step one instruction"
        STDERR.puts "  n, next          Step over (skip subroutine internals)"
        STDERR.puts "  c, continue      Continue until next breakpoint"
        STDERR.puts "  r, run           Continue without stopping"
        STDERR.puts "  k, kill          Kill current process"
        STDERR.puts "  q, quit          Exit the VM"
        STDERR.puts ""
        STDERR.puts "\e[1mInspection:\e[0m"
        STDERR.puts "  st, stack        Show full stack"
        STDERR.puts "  l, locals        Show local variables"
        STDERR.puts "  mb, mailbox      Show process mailbox"
        STDERR.puts "  i, instruction   Show current instruction details"
        STDERR.puts "  is, instructions Show nearby instructions (is <count>)"
        STDERR.puts "  cs, callstack    Show call stack"
        STDERR.puts "  watch <expr>     Watch a value (index, top, counter, state)"
        STDERR.puts "  e, eval <expr>   Evaluate expression"
        STDERR.puts ""
        STDERR.puts "\e[1mProcesses:\e[0m"
        STDERR.puts "  ps, processes    List all processes"
        STDERR.puts "  reg, registry    Show process registry"
        STDERR.puts "  f, filter <pid>  Only break on process <pid>"
        STDERR.puts "  f off            Clear process filter"
        STDERR.puts ""
        STDERR.puts "\e[1mBreakpoints:\e[0m"
        STDERR.puts "  b <addr>           Breakpoint at instruction address"
        STDERR.puts "  b <name>           Breakpoint on named process (e.g. b room)"
        STDERR.puts "  b <name>:<addr>    Breakpoint on process at instruction (e.g. b alice:5)"
        STDERR.puts "  b                  List breakpoints"
        STDERR.puts "  del <id>           Delete breakpoint"
        STDERR.puts "  del all            Delete all breakpoints"
        STDERR.puts ""
        STDERR.puts "\e[1mTips:\e[0m"
        STDERR.puts "  Press Enter to repeat last command"
        STDERR.puts ""
      end
    end
  end
end
