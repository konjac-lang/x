module X
  module Assembler
    module AST
      # Leaf nodes (no forward references)

      class LabelNode
        getter name : String
        getter line : Int32

        def initialize(@name : String, @line : Int32 = 0)
        end
      end

      class LocalNode
        getter name : String
        getter line : Int32

        def initialize(@name : String, @line : Int32 = 0)
        end
      end

      class InstructionNode
        getter mnemonic : String
        getter operand : String?
        getter operand2 : String?  # for call Module.function/arity
        getter operand3 : String?
        getter line : Int32

        def initialize(
          @mnemonic : String,
          @operand : String? = nil,
          @operand2 : String? = nil,
          @operand3 : String? = nil,
          @line : Int32 = 0,
        )
        end
      end

      # Statement union alias (Crystal resolves forward refs)

      alias StatementNode = InstructionNode | LabelNode | LocalNode | SubroutineNode |
                            IfBlock | LoopBlock | TryBlock | SpawnBlock |
                            LambdaBlock | ReceiveMatchBlock

      # Block structures

      class IfBlock
        getter then_body : Array(StatementNode)
        getter else_body : Array(StatementNode)?
        getter line : Int32

        def initialize(
          @then_body : Array(StatementNode),
          @else_body : Array(StatementNode)? = nil,
          @line : Int32 = 0,
        )
        end
      end

      class LoopBlock
        getter body : Array(StatementNode)
        getter line : Int32

        def initialize(@body : Array(StatementNode), @line : Int32 = 0)
        end
      end

      class TryBlock
        getter try_body : Array(StatementNode)
        getter catch_body : Array(StatementNode)
        getter line : Int32

        def initialize(
          @try_body : Array(StatementNode),
          @catch_body : Array(StatementNode),
          @line : Int32 = 0,
        )
        end
      end

      class SpawnBlock
        getter spawn_type : String  # "spawn", "spawn_link", "spawn_monitor"
        getter body : Array(StatementNode)
        getter line : Int32

        def initialize(@spawn_type : String, @body : Array(StatementNode), @line : Int32 = 0)
        end
      end

      class LambdaBlock
        getter captures : Array(String)
        getter body : Array(StatementNode)
        getter line : Int32

        def initialize(
          @captures : Array(String) = [] of String,
          @body : Array(StatementNode) = [] of StatementNode,
          @line : Int32 = 0,
        )
        end
      end

      class ReceiveMatchBlock
        getter with_timeout : Bool
        getter body : Array(StatementNode)  # the matcher instructions
        getter line : Int32

        def initialize(
          @with_timeout : Bool = false,
          @body : Array(StatementNode) = [] of StatementNode,
          @line : Int32 = 0,
        )
        end
      end

      # Subroutine (recursive: contains StatementNode)

      class SubroutineNode
        getter name : String
        getter body : Array(StatementNode)
        getter line : Int32

        def initialize(@name : String, @body : Array(StatementNode), @line : Int32 = 0)
        end
      end

      # Module-level nodes

      class RequireNode
        getter module_name : String
        getter alias_name : String?
        getter line : Int32

        def initialize(@module_name : String, @alias_name : String? = nil, @line : Int32 = 0)
        end
      end

      class ImportNode
        getter module_name : String
        getter function_name : String
        getter arity : Int32
        getter line : Int32

        def initialize(@module_name : String, @function_name : String, @arity : Int32, @line : Int32 = 0)
        end

        def full_name : String
          "#{@module_name}.#{@function_name}"
        end
      end

      class ExportNode
        getter function_name : String
        getter arity : Int32
        getter line : Int32

        def initialize(@function_name : String, @arity : Int32, @line : Int32 = 0)
        end
      end

      class GlobalNode
        getter name : String
        getter value : InstructionNode
        getter line : Int32

        def initialize(@name : String, @value : InstructionNode, @line : Int32 = 0)
        end
      end

      class ProcessNode
        getter name : String
        getter body : Array(StatementNode)
        getter line : Int32

        def initialize(@name : String, @body : Array(StatementNode), @line : Int32 = 0)
        end
      end

      class SupervisorNode
        getter name : String
        getter strategy : String
        getter options : Hash(String, String)
        getter children : Array(ChildNode)
        getter line : Int32

        def initialize(
          @name : String,
          @strategy : String,
          @options : Hash(String, String) = {} of String => String,
          @children : Array(ChildNode) = [] of ChildNode,
          @line : Int32 = 0,
        )
        end
      end

      class ChildNode
        getter id : String
        getter restart_type : String
        getter options : Hash(String, String)
        getter body : Array(StatementNode)
        getter subroutines : Array(SubroutineNode)
        getter line : Int32

        def initialize(
          @id : String,
          @restart_type : String,
          @options : Hash(String, String) = {} of String => String,
          @body : Array(StatementNode) = [] of StatementNode,
          @subroutines : Array(SubroutineNode) = [] of SubroutineNode,
          @line : Int32 = 0,
        )
        end
      end

      # Top-level module

      class ModuleNode
        getter name : String
        getter is_dynamic : Bool
        getter requires : Array(RequireNode)
        getter imports : Array(ImportNode)
        getter exports : Array(ExportNode)
        getter processes : Array(ProcessNode)
        getter supervisors : Array(SupervisorNode)
        getter subroutines : Array(SubroutineNode)
        getter globals : Array(GlobalNode)

        def initialize(
          @name : String,
          @is_dynamic : Bool = false,
          @requires : Array(RequireNode) = [] of RequireNode,
          @imports : Array(ImportNode) = [] of ImportNode,
          @exports : Array(ExportNode) = [] of ExportNode,
          @processes : Array(ProcessNode) = [] of ProcessNode,
          @supervisors : Array(SupervisorNode) = [] of SupervisorNode,
          @subroutines : Array(SubroutineNode) = [] of SubroutineNode,
          @globals : Array(GlobalNode) = [] of GlobalNode,
        )
        end
      end
    end
  end
end
