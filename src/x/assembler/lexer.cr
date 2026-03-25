module X
  module Assembler
    class Lexer
      Log = ::Log.for(self)

      @source : String
      @tokens : Array(Token) = [] of Token
      @start : Int32 = 0
      @current : Int32 = 0
      @line : Int32 = 1
      @column : Int32 = 1
      @line_start : Int32 = 0

      # Keyword lookup table
      KEYWORDS = {
        # Push
        "push" => TokenType::KEYWORD_PUSH,

        # Stack
        "pop"   => TokenType::KEYWORD_POP,
        "dup"   => TokenType::KEYWORD_DUP,
        "over"  => TokenType::KEYWORD_OVER,
        "swap"  => TokenType::KEYWORD_SWAP,
        "rot"   => TokenType::KEYWORD_ROT,
        "-rot"  => TokenType::KEYWORD_ROT_DOWN,
        "nip"   => TokenType::KEYWORD_NIP,
        "tuck"  => TokenType::KEYWORD_TUCK,
        "depth" => TokenType::KEYWORD_DEPTH,
        "pick"  => TokenType::KEYWORD_PICK,
        "roll"  => TokenType::KEYWORD_ROLL,

        # Arithmetic
        "add"   => TokenType::KEYWORD_ADD,
        "sub"   => TokenType::KEYWORD_SUB,
        "mul"   => TokenType::KEYWORD_MUL,
        "div"   => TokenType::KEYWORD_DIV,
        "mod"   => TokenType::KEYWORD_MOD,
        "neg"   => TokenType::KEYWORD_NEG,
        "abs"   => TokenType::KEYWORD_ABS,
        "inc"   => TokenType::KEYWORD_INC,
        "dec"   => TokenType::KEYWORD_DEC,
        "pow"   => TokenType::KEYWORD_POW,
        "floor" => TokenType::KEYWORD_FLOOR,
        "ceil"  => TokenType::KEYWORD_CEIL,
        "round" => TokenType::KEYWORD_ROUND,
        "min"   => TokenType::KEYWORD_MIN,
        "max"   => TokenType::KEYWORD_MAX,

        # Bitwise
        "band" => TokenType::KEYWORD_BAND,
        "bor"  => TokenType::KEYWORD_BOR,
        "bxor" => TokenType::KEYWORD_BXOR,
        "bnot" => TokenType::KEYWORD_BNOT,
        "shl"  => TokenType::KEYWORD_SHL,
        "shr"  => TokenType::KEYWORD_SHR,
        "ushr" => TokenType::KEYWORD_USHR,

        # Comparison
        "eq"          => TokenType::KEYWORD_EQ,
        "neq"         => TokenType::KEYWORD_NEQ,
        "ideq"        => TokenType::KEYWORD_IDEQ,
        "nideq"       => TokenType::KEYWORD_NIDEQ,
        "lt"          => TokenType::KEYWORD_LT,
        "lte"         => TokenType::KEYWORD_LTE,
        "gt"          => TokenType::KEYWORD_GT,
        "gte"         => TokenType::KEYWORD_GTE,
        "is_null"     => TokenType::KEYWORD_IS_NULL,
        "is_not_null" => TokenType::KEYWORD_IS_NOT_NULL,

        # Logic
        "and" => TokenType::KEYWORD_AND,
        "or"  => TokenType::KEYWORD_OR,
        "not" => TokenType::KEYWORD_NOT,
        "xor" => TokenType::KEYWORD_XOR,

        # Variables
        "load"    => TokenType::KEYWORD_LOAD,
        "store"   => TokenType::KEYWORD_STORE,
        "gload"   => TokenType::KEYWORD_GLOAD,
        "gstore"  => TokenType::KEYWORD_GSTORE,
        "upload"  => TokenType::KEYWORD_UPLOAD,
        "upstore" => TokenType::KEYWORD_UPSTORE,

        # Control flow
        "if"             => TokenType::KEYWORD_IF,
        "else"           => TokenType::KEYWORD_ELSE,
        "loop"           => TokenType::KEYWORD_LOOP,
        "break"          => TokenType::KEYWORD_BREAK,
        "break_if"       => TokenType::KEYWORD_BREAK_IF,
        "break_unless"   => TokenType::KEYWORD_BREAK_UNLESS,
        "continue"       => TokenType::KEYWORD_CONTINUE,
        "jump"           => TokenType::KEYWORD_JUMP,
        "jt"             => TokenType::KEYWORD_JT,
        "jf"             => TokenType::KEYWORD_JF,
        "jt?"            => TokenType::KEYWORD_JT_KEEP,
        "jf?"            => TokenType::KEYWORD_JF_KEEP,
        "call"           => TokenType::KEYWORD_CALL,
        "call_dynamic"   => TokenType::KEYWORD_CALL_DYNAMIC,
        "call_indirectt" => TokenType::KEYWORD_CALL_INDIRECT,
        "return"         => TokenType::KEYWORD_RETURN,
        "halt"           => TokenType::KEYWORD_HALT,
        "nop"            => TokenType::KEYWORD_NOP,

        # Lambdas
        "lambda" => TokenType::KEYWORD_LAMBDA,
        "invoke" => TokenType::KEYWORD_INVOKE,
        "bind"   => TokenType::KEYWORD_BIND,

        # Processes
        "self"          => TokenType::KEYWORD_SELF,
        "register"      => TokenType::KEYWORD_REGISTER,
        "unregister"    => TokenType::KEYWORD_UNREGISTER,
        "whereis"       => TokenType::KEYWORD_WHEREIS,
        "spawn"         => TokenType::KEYWORD_SPAWN,
        "spawn_link"    => TokenType::KEYWORD_SPAWN_LINK,
        "spawn_monitor" => TokenType::KEYWORD_SPAWN_MONITOR,
        "exit"          => TokenType::KEYWORD_EXIT,
        "exit_remote"   => TokenType::KEYWORD_EXIT_REMOTE,
        "kill"          => TokenType::KEYWORD_KILL,
        "sleep"         => TokenType::KEYWORD_SLEEP,
        "yield"         => TokenType::KEYWORD_YIELD,
        "link"          => TokenType::KEYWORD_LINK,
        "unlink"        => TokenType::KEYWORD_UNLINK,
        "monitor"       => TokenType::KEYWORD_MONITOR,
        "demonitor"     => TokenType::KEYWORD_DEMONITOR,
        "trap_on"       => TokenType::KEYWORD_TRAP_ON,
        "trap_off"      => TokenType::KEYWORD_TRAP_OFF,
        "alive?"        => TokenType::KEYWORD_ALIVE,
        "info"          => TokenType::KEYWORD_INFO,
        "set_flag"      => TokenType::KEYWORD_SET_FLAG,
        "get_flag"      => TokenType::KEYWORD_GET_FLAG,
        "reload"        => TokenType::KEYWORD_RELOAD,
        "await"         => TokenType::KEYWORD_AWAIT,

        # Messages
        "send"                  => TokenType::KEYWORD_SEND,
        "send_after"            => TokenType::KEYWORD_SEND_AFTER,
        "receive"               => TokenType::KEYWORD_RECEIVE,
        "receive_timeout"       => TokenType::KEYWORD_RECEIVE_TIMEOUT,
        "receive_match"         => TokenType::KEYWORD_RECEIVE_MATCH,
        "receive_match_timeout" => TokenType::KEYWORD_RECEIVE_MATCH_TIMEOUT,
        "peek"                  => TokenType::KEYWORD_PEEK,
        "mailbox_size"          => TokenType::KEYWORD_MAILBOX_SIZE,
        "cancel_timer"          => TokenType::KEYWORD_CANCEL_TIMER,

        # Exceptions
        "try"        => TokenType::KEYWORD_TRY,
        "catch"      => TokenType::KEYWORD_CATCH,
        "throw"      => TokenType::KEYWORD_THROW,
        "rethrow"    => TokenType::KEYWORD_RETHROW,
        "stacktrace" => TokenType::KEYWORD_STACKTRACE,

        # Block terminators
        "end" => TokenType::KEYWORD_END,
        "as"  => TokenType::KEYWORD_AS,

        # Literals
        "true"  => TokenType::LITERAL_TRUE,
        "false" => TokenType::LITERAL_FALSE,
        "null"  => TokenType::LITERAL_NULL,
      }

      # Directive lookup table
      DIRECTIVES = {
        "module"     => TokenType::DIRECTIVE_MODULE,
        "dynamic"    => TokenType::DIRECTIVE_DYNAMIC,
        "static"     => TokenType::DIRECTIVE_STATIC,
        "require"    => TokenType::DIRECTIVE_REQUIRE,
        "import"     => TokenType::DIRECTIVE_IMPORT,
        "export"     => TokenType::DIRECTIVE_EXPORT,
        "process"    => TokenType::DIRECTIVE_PROCESS,
        "supervisor" => TokenType::DIRECTIVE_SUPERVISOR,
        "child"      => TokenType::DIRECTIVE_CHILD,
        "subroutine" => TokenType::DIRECTIVE_SUBROUTINE,
        "local"      => TokenType::DIRECTIVE_LOCAL,
        "global"     => TokenType::DIRECTIVE_GLOBAL,
        "end"        => TokenType::DIRECTIVE_END,
      }

      def initialize(@source : String)
      end

      def tokenize : Array(Token)
        while !at_end?
          @start = @current
          scan_token
        end

        add_token(TokenType::EOF, "")
        @tokens
      end

      private def scan_token
        char = advance

        case char
        when ' ', '\t', '\r'
          # Skip whitespace
        when '\n'
          add_token(TokenType::NEWLINE, "\\n")
          @line += 1
          @line_start = @current
          @column = 1
        when '#', ';'
          # Comment — skip to end of line
          while !at_end? && peek != '\n'
            advance
          end
        when '.'
          scan_directive
        when ':'
          scan_symbol_or_label
        when '"'
          scan_string
        when '['
          add_token(TokenType::LEFT_BRACKET, "[")
        when ']'
          add_token(TokenType::RIGHT_BRACKET, "]")
        when '='
          add_token(TokenType::EQUALS, "=")
        when '/'
          add_token(TokenType::SLASH, "/")
        when '-'
          if peek == 'r' && peek_next == 'o'
            # Check for -rot
            pos = @current
            if pos + 2 < @source.size && @source[pos] == 'r' && @source[pos + 1] == 'o' && @source[pos + 2] == 't'
              # Make sure it's not part of a longer word
              after_t = pos + 3
              if after_t >= @source.size || !@source[after_t].ascii_letter?
                advance # r
                advance # o
                advance # t
                add_token(TokenType::KEYWORD_ROT_DOWN, "-rot")
              else
                add_token(TokenType::IDENTIFIER, "-")
              end
            else
              add_token(TokenType::IDENTIFIER, "-")
            end
          elsif peek.ascii_number?
            scan_number(negative: true)
          else
            add_token(TokenType::IDENTIFIER, "-")
          end
        else
          if char.ascii_number?
            scan_number(negative: false)
          elsif char.ascii_letter? || char == '_'
            scan_identifier_or_keyword
          else
            raise parse_error("Unexpected character: '#{char}'")
          end
        end
      end

      private def scan_directive
        # Already consumed the '.'
        start_pos = @current
        while !at_end? && (peek.ascii_letter? || peek == '_')
          advance
        end

        name = @source[start_pos...@current]

        if directive_type = DIRECTIVES[name]?
          add_token(directive_type, ".#{name}")
        else
          raise parse_error("Unknown directive: .#{name}")
        end
      end

      private def scan_symbol_or_label
        # Already consumed the ':'
        start_pos = @current
        while !at_end? && (peek.ascii_letter? || peek.ascii_number? || peek == '_')
          advance
        end

        name = @source[start_pos...@current]

        if name.empty?
          raise parse_error("Expected symbol or label name after ':'")
        end

        # Determine if this is a label (at start of line, or standalone)
        # or a symbol (used as a value after push or in other contexts)
        # We'll let the parser decide based on context — just emit as LABEL/SYMBOL
        # Heuristic: if we're right after 'push', it's a symbol; otherwise it's a label
        # But actually, let's just use LITERAL_SYMBOL for all :name tokens
        # and let the parser figure out the context
        add_token(TokenType::LITERAL_SYMBOL, ":#{name}")
      end

      private def scan_string
        # Already consumed the opening '"'
        # Check for triple-quoted strings
        if peek == '"' && peek_next == '"'
          advance # second "
          advance # third "
          scan_triple_quoted_string
          return
        end

        value = String.build do |builder|
          while !at_end? && peek != '"'
            if peek == '\n'
              @line += 1
              @line_start = @current + 1
            end

            if peek == '\\'
              advance # consume backslash
              case peek
              when 'n'  then builder << '\n'
              when 't'  then builder << '\t'
              when 'r'  then builder << '\r'
              when '\\' then builder << '\\'
              when '"'  then builder << '"'
              else           builder << '\\' << peek
              end
              advance
            else
              builder << advance
            end
          end

          if at_end?
            raise parse_error("Unterminated string")
          end

          advance # closing "
        end

        add_token(TokenType::LITERAL_STRING, value)
      end

      private def scan_triple_quoted_string
        value = String.build do |builder|
          while !at_end?
            if peek == '"' && peek_next == '"' && peek_at(2) == '"'
              advance # first "
              advance # second "
              advance # third "
              break
            end

            if peek == '\n'
              @line += 1
              @line_start = @current + 1
            end

            builder << advance
          end
        end

        # Strip leading/trailing whitespace from triple-quoted strings
        add_token(TokenType::LITERAL_STRING, value.strip)
      end

      private def scan_number(negative : Bool)
        # When we get here, the first digit (or '-') has already been consumed by advance
        # For negative: we consumed '-', and the digits start at @current
        # For positive: we consumed the first digit, more digits start at @current
        # Either way, @current - 1 is the last consumed char
        # But for negative, the '-' is at @current - 1 and we need to also scan digits
        start_pos = negative ? @current - 1 : @current - 1
        is_float = false
        is_unsigned = false

        # For negative numbers, we consumed '-' but not the first digit yet
        # The first digit is at peek position
        while !at_end? && (peek.ascii_number? || peek == '_')
          advance
        end

        # Check for float
        if !at_end? && peek == '.' && peek_next.ascii_number?
          is_float = true
          advance # consume '.'
          while !at_end? && (peek.ascii_number? || peek == '_')
            advance
          end
        end

        # Check for unsigned suffix
        if !at_end? && (peek == 'u' || peek == 'U') && !is_float
          is_unsigned = true
          advance # consume 'u'
        end

        text = @source[start_pos...@current].gsub('_', "")

        if is_float
          add_token(TokenType::LITERAL_FLOAT, text)
        elsif is_unsigned
          add_token(TokenType::LITERAL_UNSIGNED_INTEGER, text.rstrip('u').rstrip('U'))
        else
          add_token(TokenType::LITERAL_INTEGER, text)
        end
      end

      private def scan_identifier_or_keyword
        start_pos = @current - 1 # we already consumed the first char

        while !at_end? && (peek.ascii_letter? || peek.ascii_number? || peek == '_' || peek == '?' || peek == '.')
          # Allow dots in identifiers for module paths like MyApp.Math.Vector
          # But stop if the dot is followed by a directive keyword
          if peek == '.'
            # Look ahead: if next char is a letter, it's part of a module path
            if peek_next.ascii_letter?
              advance # consume the dot
            else
              break
            end
          else
            advance
          end
        end

        text = @source[start_pos...@current]

        # Check keywords first
        if token_type = KEYWORDS[text]?
          add_token(token_type, text)
        else
          add_token(TokenType::IDENTIFIER, text)
        end
      end

      # Character access helpers

      private def advance : Char
        char = @source[@current]
        @current += 1
        @column += 1
        char
      end

      private def peek : Char
        return '\0' if at_end?
        @source[@current]
      end

      private def peek_next : Char
        return '\0' if @current + 1 >= @source.size
        @source[@current + 1]
      end

      private def peek_at(offset : Int32) : Char
        pos = @current + offset - 1
        return '\0' if pos >= @source.size
        @source[pos]
      end

      private def at_end? : Bool
        @current >= @source.size
      end

      private def add_token(type : TokenType, value : String)
        col = @current - @line_start - value.size + 1
        col = 1 if col < 1
        @tokens << Token.new(type, value, @line, col)
      end

      private def parse_error(message : String) : Exception
        Exceptions::Emulation.new("Lexer error at line #{@line}, column #{@column}: #{message}")
      end
    end
  end
end
