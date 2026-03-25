module X
  module Assembler
    enum TokenType
      # Directives
      DIRECTIVE_MODULE
      DIRECTIVE_DYNAMIC
      DIRECTIVE_STATIC
      DIRECTIVE_REQUIRE
      DIRECTIVE_IMPORT
      DIRECTIVE_EXPORT
      DIRECTIVE_PROCESS
      DIRECTIVE_SUPERVISOR
      DIRECTIVE_CHILD
      DIRECTIVE_SUBROUTINE
      DIRECTIVE_LOCAL
      DIRECTIVE_GLOBAL
      DIRECTIVE_END

      # Literals
      LITERAL_INTEGER
      LITERAL_UNSIGNED_INTEGER
      LITERAL_FLOAT
      LITERAL_STRING
      LITERAL_SYMBOL
      LITERAL_TRUE
      LITERAL_FALSE
      LITERAL_NULL

      # Keywords — Push
      KEYWORD_PUSH

      # Keywords — Stack
      KEYWORD_POP
      KEYWORD_DUP
      KEYWORD_OVER
      KEYWORD_SWAP
      KEYWORD_ROT
      KEYWORD_ROT_DOWN    # -rot
      KEYWORD_NIP
      KEYWORD_TUCK
      KEYWORD_DEPTH
      KEYWORD_PICK
      KEYWORD_ROLL

      # Keywords — Arithmetic
      KEYWORD_ADD
      KEYWORD_SUB
      KEYWORD_MUL
      KEYWORD_DIV
      KEYWORD_MOD
      KEYWORD_NEG
      KEYWORD_ABS
      KEYWORD_INC
      KEYWORD_DEC
      KEYWORD_POW
      KEYWORD_FLOOR
      KEYWORD_CEIL
      KEYWORD_ROUND
      KEYWORD_MIN
      KEYWORD_MAX

      # Keywords — Bitwise
      KEYWORD_BAND
      KEYWORD_BOR
      KEYWORD_BXOR
      KEYWORD_BNOT
      KEYWORD_SHL
      KEYWORD_SHR
      KEYWORD_USHR

      # Keywords — Comparison
      KEYWORD_EQ
      KEYWORD_NEQ
      KEYWORD_IDEQ
      KEYWORD_NIDEQ
      KEYWORD_LT
      KEYWORD_LTE
      KEYWORD_GT
      KEYWORD_GTE
      KEYWORD_IS_NULL
      KEYWORD_IS_NOT_NULL

      # Keywords — Logic
      KEYWORD_AND
      KEYWORD_OR
      KEYWORD_NOT
      KEYWORD_XOR

      # Keywords — Variables
      KEYWORD_LOAD
      KEYWORD_STORE
      KEYWORD_GLOAD
      KEYWORD_GSTORE
      KEYWORD_UPLOAD
      KEYWORD_UPSTORE

      # Keywords — Control Flow
      KEYWORD_IF
      KEYWORD_ELSE
      KEYWORD_LOOP
      KEYWORD_BREAK
      KEYWORD_BREAK_IF
      KEYWORD_BREAK_UNLESS
      KEYWORD_CONTINUE
      KEYWORD_JUMP
      KEYWORD_JT
      KEYWORD_JF
      KEYWORD_JT_KEEP
      KEYWORD_JF_KEEP
      KEYWORD_CALL
      KEYWORD_CALL_DYNAMIC
      KEYWORD_CALL_INDIRECT
      KEYWORD_RETURN
      KEYWORD_HALT
      KEYWORD_NOP

      # Keywords — Lambdas
      KEYWORD_LAMBDA
      KEYWORD_INVOKE
      KEYWORD_BIND

      # Keywords — Processes
      KEYWORD_SELF
      KEYWORD_REGISTER
      KEYWORD_UNREGISTER
      KEYWORD_WHEREIS
      KEYWORD_SPAWN
      KEYWORD_SPAWN_LINK
      KEYWORD_SPAWN_MONITOR
      KEYWORD_EXIT
      KEYWORD_EXIT_REMOTE
      KEYWORD_KILL
      KEYWORD_SLEEP
      KEYWORD_YIELD
      KEYWORD_LINK
      KEYWORD_UNLINK
      KEYWORD_MONITOR
      KEYWORD_DEMONITOR
      KEYWORD_TRAP_ON
      KEYWORD_TRAP_OFF
      KEYWORD_ALIVE
      KEYWORD_INFO
      KEYWORD_SET_FLAG
      KEYWORD_GET_FLAG
      KEYWORD_RELOAD
      KEYWORD_AWAIT

      # Keywords — Messages
      KEYWORD_SEND
      KEYWORD_SEND_AFTER
      KEYWORD_RECEIVE
      KEYWORD_RECEIVE_TIMEOUT
      KEYWORD_RECEIVE_MATCH
      KEYWORD_RECEIVE_MATCH_TIMEOUT
      KEYWORD_PEEK
      KEYWORD_MAILBOX_SIZE
      KEYWORD_CANCEL_TIMER

      # Keywords — Exceptions
      KEYWORD_TRY
      KEYWORD_CATCH
      KEYWORD_THROW
      KEYWORD_RETHROW
      KEYWORD_STACKTRACE

      # Structural
      LABEL          # :name
      IDENTIFIER     # bare name (for variables, labels, module paths)
      LEFT_BRACKET   # [
      RIGHT_BRACKET  # ]
      EQUALS         # =
      SLASH          # /
      DOT            # .
      KEYWORD_AS     # as (for require aliases)
      KEYWORD_END    # end (block terminator)

      # Meta
      NEWLINE
      EOF
    end

    class Token
      getter type : TokenType
      getter value : String
      getter line : Int32
      getter column : Int32

      def initialize(@type : TokenType, @value : String, @line : Int32, @column : Int32)
      end

      def to_s : String
        "Token(#{@type}, #{@value.inspect}, line=#{@line}, col=#{@column})"
      end
    end
  end
end
