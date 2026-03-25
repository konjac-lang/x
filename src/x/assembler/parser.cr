module X
  module Assembler
    class Parser
      Log = ::Log.for(self)

      @tokens : Array(Token)
      @current : Int32 = 0

      def initialize(@tokens : Array(Token))
      end

      def parse : AST::ModuleNode
        skip_newlines

        # Parse module declaration
        expect_directive(TokenType::DIRECTIVE_MODULE)
        module_name = parse_module_path
        skip_newlines

        is_dynamic = false
        requires = [] of AST::RequireNode
        imports = [] of AST::ImportNode
        exports = [] of AST::ExportNode
        processes = [] of AST::ProcessNode
        supervisors = [] of AST::SupervisorNode
        subroutines = [] of AST::SubroutineNode
        globals = [] of AST::GlobalNode

        while !at_end?
          skip_newlines
          break if at_end?

          token = current_token

          case token.type
          when TokenType::DIRECTIVE_DYNAMIC
            is_dynamic = true
            advance
            skip_newlines
          when TokenType::DIRECTIVE_STATIC
            advance
            skip_newlines
          when TokenType::DIRECTIVE_REQUIRE
            requires << parse_require
          when TokenType::DIRECTIVE_IMPORT
            imports.concat(parse_import)
          when TokenType::DIRECTIVE_EXPORT
            exports << parse_export
          when TokenType::DIRECTIVE_PROCESS
            processes << parse_process
          when TokenType::DIRECTIVE_SUPERVISOR
            supervisors << parse_supervisor
          when TokenType::DIRECTIVE_SUBROUTINE
            subroutines << parse_subroutine
          when TokenType::DIRECTIVE_GLOBAL
            globals << parse_global
          when TokenType::EOF
            break
          else
            raise parse_error("Unexpected token at module level: #{token}")
          end
        end

        AST::ModuleNode.new(
          name: module_name,
          is_dynamic: is_dynamic,
          requires: requires,
          imports: imports,
          exports: exports,
          processes: processes,
          supervisors: supervisors,
          subroutines: subroutines,
          globals: globals,
        )
      end

      # Directive parsers

      private def parse_require : AST::RequireNode
        line = current_token.line
        advance # consume .require

        # Expect a quoted string or identifier
        module_name = consume_string_or_identifier("module name")
        skip_newlines_in_line

        alias_name : String? = nil
        if !at_end? && current_token.type == TokenType::KEYWORD_AS
          advance # consume 'as'
          alias_name = consume_identifier("alias name")
        end

        skip_newlines
        AST::RequireNode.new(module_name, alias_name, line)
      end

      private def parse_import : Array(AST::ImportNode)
        line = current_token.line
        advance # consume .import

        imports = [] of AST::ImportNode

        # Parse module.function/arity or module block
        path = parse_module_path

        if !at_end? && !is_newline?(current_token) && current_token.type == TokenType::EOF
          skip_newlines
          return imports
        end

        # Check if this is Module.function/arity (single import)
        if path.includes?('/') || (!at_end? && current_token.type == TokenType::SLASH)
          # Single import: Module.function/arity
          if current_token.type == TokenType::SLASH
            advance # consume /
            arity_str = consume_integer("arity")
            mod_func = path
          elsif path =~ /(.+)\/(\d+)$/
            mod_func = $1
            arity_str = $2
          else
            raise parse_error("Expected function/arity in import, got: #{path}")
          end

          parts = mod_func.rpartition('.')
          if parts[1].empty?
            raise parse_error("Import must include module name: #{mod_func}")
          end

          module_name = parts[0]
          function_name = parts[2]
          arity = arity_str.to_i32

          imports << AST::ImportNode.new(module_name, function_name, arity, line)
          skip_newlines
          return imports
        end

        # Check for block import:
        # .import Module
        #   function/arity
        #   function/arity
        # .end
        module_name = path
        skip_newlines

        while !at_end?
          skip_newlines
          break if at_end?

          token = current_token
          break if token.type == TokenType::DIRECTIVE_END

          # Parse function_name/arity
          func_name = consume_identifier("function name")

          if current_token.type == TokenType::SLASH
            advance # consume /
          else
            raise parse_error("Expected '/' after function name in import block")
          end

          arity_str = consume_integer("arity")
          arity = arity_str.to_i32

          imports << AST::ImportNode.new(module_name, func_name, arity, line)
          skip_newlines
        end

        if !at_end? && current_token.type == TokenType::DIRECTIVE_END
          advance # consume .end
        else
          raise parse_error("Expected .end to close import block")
        end

        skip_newlines
        imports
      end

      private def parse_export : AST::ExportNode
        line = current_token.line
        advance # consume .export

        func_name = consume_identifier("function name")

        if current_token.type == TokenType::SLASH
          advance # consume /
        else
          raise parse_error("Expected '/' after function name in export")
        end

        arity_str = consume_integer("arity")
        arity = arity_str.to_i32

        skip_newlines
        AST::ExportNode.new(func_name, arity, line)
      end

      private def parse_global : AST::GlobalNode
        line = current_token.line
        advance # consume .global

        name = consume_identifier("global name")
        value = parse_instruction # the initial value (a push instruction basically)

        skip_newlines
        AST::GlobalNode.new(name, value, line)
      end

      private def parse_process : AST::ProcessNode
        line = current_token.line
        advance # consume .process

        name = consume_identifier("process name")
        skip_newlines

        body = parse_body(terminators: [TokenType::DIRECTIVE_END])
        expect_directive(TokenType::DIRECTIVE_END)
        skip_newlines

        AST::ProcessNode.new(name, body, line)
      end

      private def parse_supervisor : AST::SupervisorNode
        line = current_token.line
        advance # consume .supervisor

        name = consume_identifier("supervisor name")

        # Parse strategy (e.g., :one_for_one)
        strategy = consume_symbol("supervisor strategy")

        # Parse optional key=value options
        options = parse_options

        skip_newlines

        children = [] of AST::ChildNode
        while !at_end?
          skip_newlines
          break if at_end?

          token = current_token
          break if token.type == TokenType::DIRECTIVE_END

          if token.type == TokenType::DIRECTIVE_CHILD
            children << parse_child
          else
            raise parse_error("Expected .child or .end in supervisor block, got: #{token}")
          end
        end

        expect_directive(TokenType::DIRECTIVE_END)
        skip_newlines

        AST::SupervisorNode.new(name, strategy, options, children, line)
      end

      private def parse_child : AST::ChildNode
        line = current_token.line
        advance # consume .child

        # Child id (string)
        id = consume_string_or_identifier("child id")

        # Restart type (symbol like :permanent)
        restart_type = consume_symbol("restart type")

        # Optional key=value options
        options = parse_options

        skip_newlines

        body = [] of AST::StatementNode
        subroutines = [] of AST::SubroutineNode

        while !at_end?
          skip_newlines
          break if at_end?

          token = current_token
          break if token.type == TokenType::DIRECTIVE_END

          if token.type == TokenType::DIRECTIVE_SUBROUTINE
            subroutines << parse_subroutine
          else
            stmt = parse_statement
            body << stmt if stmt
          end
        end

        expect_directive(TokenType::DIRECTIVE_END)
        skip_newlines

        AST::ChildNode.new(id, restart_type, options, body, subroutines, line)
      end

      private def parse_subroutine : AST::SubroutineNode
        line = current_token.line
        advance # consume .subroutine

        name = consume_identifier("subroutine name")
        skip_newlines

        body = parse_body(terminators: [TokenType::DIRECTIVE_END])
        expect_directive(TokenType::DIRECTIVE_END)
        skip_newlines

        AST::SubroutineNode.new(name, body, line)
      end

      # Body and statement parsing

      private def parse_body(terminators : Array(TokenType)) : Array(AST::StatementNode)
        statements = [] of AST::StatementNode

        while !at_end?
          skip_newlines
          break if at_end?
          break if terminators.includes?(current_token.type)

          stmt = parse_statement
          statements << stmt if stmt
        end

        statements
      end

      private def parse_statement : AST::StatementNode?
        skip_newlines
        return nil if at_end?

        token = current_token

        case token.type
        when TokenType::DIRECTIVE_LOCAL
          parse_local_declaration
        when TokenType::DIRECTIVE_SUBROUTINE
          parse_subroutine
        when TokenType::LITERAL_SYMBOL
          # Could be a label if it's at the start of a line (standalone :name)
          # Labels are :name on their own line with nothing after (before newline)
          parse_label_or_symbol_instruction
        when TokenType::KEYWORD_IF
          parse_if_block
        when TokenType::KEYWORD_LOOP
          parse_loop_block
        when TokenType::KEYWORD_TRY
          parse_try_block
        when TokenType::KEYWORD_SPAWN, TokenType::KEYWORD_SPAWN_LINK, TokenType::KEYWORD_SPAWN_MONITOR
          parse_spawn_block
        when TokenType::KEYWORD_LAMBDA
          parse_lambda_block
        when TokenType::KEYWORD_RECEIVE_MATCH, TokenType::KEYWORD_RECEIVE_MATCH_TIMEOUT
          parse_receive_match_block
        else
          parse_instruction
        end
      end

      private def parse_local_declaration : AST::LocalNode
        line = current_token.line
        advance # consume .local
        name = consume_identifier("local variable name")
        skip_newlines
        AST::LocalNode.new(name, line)
      end

      private def parse_label_or_symbol_instruction : AST::StatementNode
        # We have a :name token. If the next non-whitespace token is a newline or EOF,
        # this is a label. Otherwise it's part of an instruction.
        token = current_token
        line = token.line
        name = token.value[1..] # strip leading ':'

        advance # consume the :name token

        # Check if this is a standalone label
        if at_end? || is_newline?(current_token)
          return AST::LabelNode.new(name, line)
        end

        # Not a label — this shouldn't happen in normal flow since symbols
        # appear after 'push'. But handle it gracefully.
        AST::LabelNode.new(name, line)
      end

      # Block parsers

      private def parse_if_block : AST::IfBlock
        line = current_token.line
        advance # consume 'if'
        skip_newlines

        then_body = parse_body(terminators: [TokenType::KEYWORD_ELSE, TokenType::KEYWORD_END])

        else_body : Array(AST::StatementNode)? = nil

        if !at_end? && current_token.type == TokenType::KEYWORD_ELSE
          advance # consume 'else'
          skip_newlines
          else_body = parse_body(terminators: [TokenType::KEYWORD_END])
        end

        expect_keyword(TokenType::KEYWORD_END, "end")
        skip_newlines

        AST::IfBlock.new(then_body, else_body, line)
      end

      private def parse_loop_block : AST::LoopBlock
        line = current_token.line
        advance # consume 'loop'
        skip_newlines

        body = parse_body(terminators: [TokenType::KEYWORD_END])

        expect_keyword(TokenType::KEYWORD_END, "end")
        skip_newlines

        AST::LoopBlock.new(body, line)
      end

      private def parse_try_block : AST::TryBlock
        line = current_token.line
        advance # consume 'try'
        skip_newlines

        try_body = parse_body(terminators: [TokenType::KEYWORD_CATCH])

        expect_keyword(TokenType::KEYWORD_CATCH, "catch")
        skip_newlines

        catch_body = parse_body(terminators: [TokenType::KEYWORD_END])

        expect_keyword(TokenType::KEYWORD_END, "end")
        skip_newlines

        AST::TryBlock.new(try_body, catch_body, line)
      end

      private def parse_spawn_block : AST::SpawnBlock
        line = current_token.line
        spawn_type = case current_token.type
                     when TokenType::KEYWORD_SPAWN         then "spawn"
                     when TokenType::KEYWORD_SPAWN_LINK    then "spawn_link"
                     when TokenType::KEYWORD_SPAWN_MONITOR then "spawn_monitor"
                     else                                       "spawn"
                     end
        advance # consume spawn keyword
        skip_newlines

        body = parse_body(terminators: [TokenType::KEYWORD_END])

        expect_keyword(TokenType::KEYWORD_END, "end")
        skip_newlines

        AST::SpawnBlock.new(spawn_type, body, line)
      end

      private def parse_lambda_block : AST::LambdaBlock
        line = current_token.line
        advance # consume 'lambda'

        captures = [] of String

        # Parse optional captures [name1, name2]
        if !at_end? && current_token.type == TokenType::LEFT_BRACKET
          advance # consume [
          while !at_end? && current_token.type != TokenType::RIGHT_BRACKET
            skip_newlines
            capture_name = consume_identifier("capture name")
            captures << capture_name

            # Skip optional comma (we're lenient)
            if !at_end? && current_token.value == ","
              advance
            end
          end
          expect_token(TokenType::RIGHT_BRACKET, "]")
        end

        skip_newlines

        body = parse_body(terminators: [TokenType::KEYWORD_END])

        expect_keyword(TokenType::KEYWORD_END, "end")
        skip_newlines

        AST::LambdaBlock.new(captures, body, line)
      end

      private def parse_receive_match_block : AST::ReceiveMatchBlock
        line = current_token.line
        with_timeout = current_token.type == TokenType::KEYWORD_RECEIVE_MATCH_TIMEOUT
        advance # consume receive_match or receive_match_timeout
        skip_newlines

        body = parse_body(terminators: [TokenType::KEYWORD_END])

        expect_keyword(TokenType::KEYWORD_END, "end")
        skip_newlines

        AST::ReceiveMatchBlock.new(with_timeout, body, line)
      end

      # Instruction parsing

      private def parse_instruction : AST::InstructionNode
        token = current_token
        line = token.line
        advance # consume the instruction token

        mnemonic = token.value
        operand : String? = nil
        operand2 : String? = nil
        operand3 : String? = nil

        case token.type
        # Push — expects a literal or keyword after it
        when TokenType::KEYWORD_PUSH
          operand = parse_push_operand
          # Variable operations — expect name or slot number
        when TokenType::KEYWORD_LOAD, TokenType::KEYWORD_STORE
          operand = consume_identifier_or_integer("variable name or slot")
        when TokenType::KEYWORD_GLOAD, TokenType::KEYWORD_GSTORE
          operand = consume_string_or_identifier("global variable name")
        when TokenType::KEYWORD_UPLOAD, TokenType::KEYWORD_UPSTORE
          operand = consume_integer("upvalue index")
          # Jump operations — expect label reference
        when TokenType::KEYWORD_JUMP, TokenType::KEYWORD_JT, TokenType::KEYWORD_JF,
             TokenType::KEYWORD_JT_KEEP, TokenType::KEYWORD_JF_KEEP
          operand = consume_label_reference("jump target")
          # Call — expects either :subroutine or Module.function/arity
        when TokenType::KEYWORD_CALL
          operand, operand2, operand3 = parse_call_target
          # Register/unregister/whereis — expect name
        when TokenType::KEYWORD_REGISTER, TokenType::KEYWORD_UNREGISTER, TokenType::KEYWORD_WHEREIS
          operand = consume_string_or_identifier("name")
          # Invoke/bind — expect arity
        when TokenType::KEYWORD_INVOKE, TokenType::KEYWORD_BIND
          operand = consume_integer("arity/count")
          # Await — expect registered process name to wait for
        when TokenType::KEYWORD_AWAIT
          operand = consume_string_or_identifier("registered name")
          # Reload — expects module name from stack, no operand
        when TokenType::KEYWORD_RELOAD
          # no operand needed — module name is on the stack

          # Everything else — no operand
        else
          # No operand needed
        end

        skip_newlines

        AST::InstructionNode.new(mnemonic, operand, operand2, operand3, line)
      end

      private def parse_push_operand : String
        token = current_token

        case token.type
        when TokenType::LITERAL_INTEGER, TokenType::LITERAL_UNSIGNED_INTEGER,
             TokenType::LITERAL_FLOAT, TokenType::LITERAL_STRING
          advance
          token.value
        when TokenType::LITERAL_SYMBOL
          advance
          token.value
        when TokenType::LITERAL_TRUE
          advance
          "true"
        when TokenType::LITERAL_FALSE
          advance
          "false"
        when TokenType::LITERAL_NULL
          advance
          "null"
        when TokenType::KEYWORD_SELF
          advance
          "self"
        when TokenType::KEYWORD_DEPTH
          advance
          "depth"
        else
          raise parse_error("Expected literal value after 'push', got: #{token}")
        end
      end

      private def parse_call_target : Tuple(String, String?, String?)
        token = current_token

        if token.type == TokenType::LITERAL_SYMBOL
          # call :subroutine_name
          advance
          label = token.value # includes the ':'
          return {label, nil, nil}
        end

        # call Module.function/arity
        path = parse_module_path

        if !at_end? && current_token.type == TokenType::SLASH
          advance # consume /
          arity = consume_integer("arity")

          # Split path into module and function
          parts = path.rpartition('.')
          if parts[1].empty?
            raise parse_error("Call target must include module: #{path}")
          end

          module_name = parts[0]
          function_name = parts[2]

          return {module_name, function_name, arity}
        end

        # Might be just a name reference
        {path, nil, nil}
      end

      # Helper methods

      private def parse_module_path : String
        path = String.build do |builder|
          builder << consume_identifier("module/path component")

          while !at_end? && current_token.type == TokenType::DOT
            advance # consume .
            builder << '.'
            builder << consume_identifier("path component")
          end
        end

        # The identifier scanner may have already consumed dots in module paths
        # so we might already have the full path
        path
      end

      private def parse_options : Hash(String, String)
        options = {} of String => String

        while !at_end? && !is_newline?(current_token) && current_token.type == TokenType::IDENTIFIER
          key = current_token.value
          advance # consume key

          if !at_end? && current_token.type == TokenType::EQUALS
            advance # consume =
            value = current_token.value
            advance # consume value
            options[key] = value
          else
            options[key] = "true"
          end
        end

        options
      end

      private def consume_identifier(context : String) : String
        token = current_token

        if token.type == TokenType::IDENTIFIER
          advance
          return token.value
        end

        # Some keywords can appear in identifier positions (e.g., "info" as a variable name)
        # But primarily we want actual identifiers
        # Also allow module path identifiers that contain dots
        raise parse_error("Expected #{context}, got: #{token}")
      end

      private def consume_identifier_or_integer(context : String) : String
        token = current_token

        if token.type == TokenType::LITERAL_INTEGER ||
           token.type == TokenType::LITERAL_UNSIGNED_INTEGER ||
           token.type == TokenType::IDENTIFIER
          advance
          return token.value
        end

        raise parse_error("Expected #{context}, got: #{token}")
      end

      private def consume_integer(context : String) : String
        token = current_token

        unless token.type == TokenType::LITERAL_INTEGER ||
               token.type == TokenType::LITERAL_UNSIGNED_INTEGER
          raise parse_error("Expected integer for #{context}, got: #{token}")
        end

        advance
        token.value
      end

      private def consume_string_or_identifier(context : String) : String
        token = current_token

        if token.type == TokenType::LITERAL_STRING
          advance
          return token.value
        end

        if token.type == TokenType::IDENTIFIER
          advance
          return token.value
        end

        raise parse_error("Expected string or identifier for #{context}, got: #{token}")
      end

      private def consume_symbol(context : String) : String
        token = current_token

        unless token.type == TokenType::LITERAL_SYMBOL
          raise parse_error("Expected symbol for #{context}, got: #{token}")
        end

        advance
        name = token.value[1..] # strip leading ':'
        name
      end

      private def consume_label_reference(context : String) : String
        token = current_token

        unless token.type == TokenType::LITERAL_SYMBOL
          raise parse_error("Expected label reference (like :name) for #{context}, got: #{token}")
        end

        advance
        token.value # keep the ':' prefix
      end

      private def expect_directive(type : TokenType)
        unless current_token.type == type
          raise parse_error("Expected directive #{type}, got: #{current_token}")
        end
        advance
      end

      private def expect_keyword(type : TokenType, name : String)
        unless current_token.type == type
          raise parse_error("Expected '#{name}', got: #{current_token}")
        end
        advance
      end

      private def expect_token(type : TokenType, name : String)
        unless current_token.type == type
          raise parse_error("Expected '#{name}', got: #{current_token}")
        end
        advance
      end

      # Token navigation

      private def current_token : Token
        if @current >= @tokens.size
          Token.new(TokenType::EOF, "", @tokens.last?.try(&.line) || 0, 0)
        else
          @tokens[@current]
        end
      end

      private def advance : Token
        token = current_token
        @current += 1
        token
      end

      private def at_end? : Bool
        @current >= @tokens.size || current_token.type == TokenType::EOF
      end

      private def is_newline?(token : Token) : Bool
        token.type == TokenType::NEWLINE
      end

      private def skip_newlines
        while !at_end? && current_token.type == TokenType::NEWLINE
          @current += 1
        end
      end

      private def skip_newlines_in_line
        # Don't skip — just peek ahead past whitespace on same line
      end

      private def parse_error(message : String) : Exception
        token = current_token
        Exceptions::Emulation.new("Parse error at line #{token.line}: #{message}")
      end
    end
  end
end
