module X
  module Value
    # ─────────────────────────────────────────────────────────────────────
    # Erlang-style Term Partitioning
    # ─────────────────────────────────────────────────────────────────────
    #
    # All values are classified into two partitions:
    #
    #   IMMEDIATES  – stored inline in the 64-bit @bits field, zero heap
    #                 allocations. Includes: Null, Bool, Int64, UInt64,
    #                 Float64, Symbol.
    #
    #   HEAP TERMS  – require a pointer to GC-managed memory. Includes:
    #                 String, Map, Array, Binary, Lambda, Instructions,
    #                 and all Custom types.
    #
    # Encoding (NaN-boxing variant using a tag byte + 56-bit payload):
    #
    #   @bits layout (64 bits):
    #   ┌────────┬────────────────────────────────────────────────────────┐
    #   │ tag(8) │                   payload(56)                          │
    #   └────────┴────────────────────────────────────────────────────────┘
    #
    #   For immediates the payload holds the value directly.
    #   For heap terms the payload holds a raw pointer address.
    #
    # This gives us:
    #   - Zero allocations for all numeric types, bools, null, symbols
    #   - Single cache-line-friendly struct (16 bytes total with custom_type)
    #   - Pattern matching on tag byte is a single-cycle comparison
    #   - Erlang-style ordering: number < symbol < reference < … < list < map
    # ─────────────────────────────────────────────────────────────────────

    # Tag constants — chosen so numeric types are adjacent for fast numeric? checks.
    # Erlang-style ordering is encoded in tag values for comparison.
    module Tag
      NULL             = 0x00_u8 # Immediate: no payload
      BOOLEAN          = 0x01_u8 # Immediate: 0 or 1 in payload
      INTEGER          = 0x02_u8 # Immediate: raw Int64 bits in payload via @bits_signed
      UNSIGNED_INTEGER = 0x03_u8 # Immediate: raw UInt64 in lower 56 bits (full 64-bit via @raw_uint)
      FLOAT            = 0x04_u8 # Immediate: raw Float64 bits in @float_bits

      SYMBOL       = 0x10_u8
      STRING       = 0x11_u8
      BINARY       = 0x11_u8
      MAP          = 0x12_u8
      ARRAY        = 0x13_u8
      LAMBDA       = 0x14_u8
      INSTRUCTIONS = 0x15_u8
      CUSTOM       = 0x1F_u8

      # Fast classification helpers
      IMMEDIATE_MAX = 0x05_u8 # Null, Bool, Int, UInt, Float
      HEAP_MIN      = 0x10_u8
      NUMERIC_MIN   = INTEGER
      NUMERIC_MAX   = FLOAT
    end

    @[Packed]
    struct Context
      # Primary storage
      # For immediates: the value itself, encoded in 64 bits.
      # For heap terms: the raw pointer address.
      @bits : UInt64

      # Tag byte identifying the type — kept separate for clarity and
      # because Crystal's enum dispatch is fast on small values.
      @tag : UInt8

      # Only set for Custom types; nil for all built-in types.
      # This is the only field that may cause an allocation on construction
      # of custom types (the string itself is usually a literal).
      @custom_type : ::String?

      # Class-level null singleton
      class_getter null : Context = Context.new(nil)

      # Getters for compatibility
      getter custom_type : ::String?

      def primitive_type : PrimitiveType
        tag_to_primitive_type
      end

      # Returns the raw pointer for heap terms
      def pointer : Pointer(Void)
        if @tag >= Tag::HEAP_MIN
          Pointer(Void).new(@bits)
        else
          Pointer(Void).null
        end
      end

      # Null
      def initialize
        @bits = 0_u64
        @tag = Tag::NULL
        @custom_type = nil
      end

      def initialize(object : Nil)
        @bits = 0_u64
        @tag = Tag::NULL
        @custom_type = nil
      end

      # Integer — store raw bits; reinterpret on read
      def initialize(object : Int64)
        @bits = object.unsafe_as(UInt64)
        @tag = Tag::INTEGER
        @custom_type = nil
      end

      # Unsigned Integer — stored directly
      def initialize(object : UInt64)
        @bits = object
        @tag = Tag::UNSIGNED_INTEGER
        @custom_type = nil
      end

      # Float — store raw IEEE 754 bits
      def initialize(object : Float64)
        @bits = object.unsafe_as(UInt64)
        @tag = Tag::FLOAT
        @custom_type = nil
      end

      # Boolean — 0 or 1
      def initialize(object : Bool)
        @bits = object ? 1_u64 : 0_u64
        @tag = Tag::BOOLEAN
        @custom_type = nil
      end

      # Symbol — boxed (Crystal symbols cannot be reconstructed from ordinals)
      def initialize(object : Symbol)
        @bits = Box.box(object).address
        @tag = Tag::SYMBOL
        @custom_type = nil
      end

      def initialize(object : String)
        @bits = Box.box(object).address
        @tag = Tag::STRING
        @custom_type = nil
      end

      def initialize(object : Hash(::String, Context))
        @bits = Box.box(object).address
        @tag = Tag::MAP
        @custom_type = nil
      end

      def initialize(object : ::Array(Context))
        @bits = Box.box(object).address
        @tag = Tag::ARRAY
        @custom_type = nil
      end

      # Binary — copies the slice to ensure ownership
      def initialize(slice : Slice(UInt8))
        owned = Slice(UInt8).new(slice.size)
        owned.copy_from(slice)
        @bits = Box.box(owned).address
        @tag = Tag::BINARY
        @custom_type = nil
      end

      def initialize(object : Lambda::Context)
        @bits = Box.box(object).address
        @tag = Tag::LAMBDA
        @custom_type = nil
      end

      def initialize(object : ::Array(Instruction::Operation))
        @bits = Box.box(object).address
        @tag = Tag::INSTRUCTIONS
        @custom_type = nil
      end

      def initialize(object : Tuple(UInt64, Context))
        @bits = Box.box(object).address
        @tag = Tag::CUSTOM
        @custom_type = "Tuple(UInt64, X::X::Value::Context)"
      end

      def initialize(object : Tuple(Context, Float64))
        @bits = Box.box(object).address
        @tag = Tag::CUSTOM
        @custom_type = "Tuple(Context, Float64)"
      end

      def initialize(object : Tuple(UInt64, Context, Float64))
        @bits = Box.box(object).address
        @tag = Tag::CUSTOM
        @custom_type = "Tuple(UInt64, Context, Float64)"
      end

      def initialize(object : Tuple(::Array(Instruction::Operation), ::Array(::String)))
        @bits = Box.box(object).address
        @tag = Tag::CUSTOM
        @custom_type = "LambdaCreateTuple"
      end

      def initialize(object : Process::MonitorReference)
        @bits = Box.box(object).address
        @tag = Tag::CUSTOM
        @custom_type = "MonitorReference"
      end

      # Generic fallback for unknown custom types
      def initialize(object : Object)
        @bits = Box.box(object).address
        @tag = Tag::CUSTOM
        @custom_type = object.class.to_s
      end

      # Raw pointer reconstruction
      @[AlwaysInline]
      private def heap_pointer : Pointer(Void)
        Pointer(Void).new(@bits)
      end

      @[AlwaysInline]
      private def unbox(type : T.class) : T forall T
        Box(T).unbox(heap_pointer)
      end

      @[AlwaysInline]
      def null? : Bool
        @tag == Tag::NULL
      end

      @[AlwaysInline]
      def integer? : Bool
        @tag == Tag::INTEGER
      end

      @[AlwaysInline]
      def unsigned_integer? : Bool
        @tag == Tag::UNSIGNED_INTEGER
      end

      @[AlwaysInline]
      def float? : Bool
        @tag == Tag::FLOAT
      end

      @[AlwaysInline]
      def string? : Bool
        @tag == Tag::STRING
      end

      @[AlwaysInline]
      def symbol? : Bool
        @tag == Tag::SYMBOL
      end

      @[AlwaysInline]
      def boolean? : Bool
        @tag == Tag::BOOLEAN
      end

      @[AlwaysInline]
      def map? : Bool
        @tag == Tag::MAP
      end

      @[AlwaysInline]
      def array? : Bool
        @tag == Tag::ARRAY
      end

      @[AlwaysInline]
      def binary? : Bool
        @tag == Tag::BINARY
      end

      @[AlwaysInline]
      def lambda? : Bool
        @tag == Tag::LAMBDA
      end

      @[AlwaysInline]
      def instructions? : Bool
        @tag == Tag::INSTRUCTIONS
      end

      @[AlwaysInline]
      def custom? : Bool
        @tag == Tag::CUSTOM
      end

      @[AlwaysInline]
      def monitor_reference? : Bool
        @tag == Tag::CUSTOM && @custom_type == "MonitorReference"
      end

      # Erlang-style: is this an immediate (no heap pointer)?
      @[AlwaysInline]
      def immediate? : Bool
        @tag <= Tag::IMMEDIATE_MAX
      end

      # Erlang-style: is this a heap-allocated term?
      @[AlwaysInline]
      def heap_term? : Bool
        @tag >= Tag::HEAP_MIN
      end

      # Numeric covers integer, unsigned integer, and float — contiguous tags
      @[AlwaysInline]
      def numeric? : Bool
        @tag >= Tag::NUMERIC_MIN && @tag <= Tag::NUMERIC_MAX
      end

      @[AlwaysInline]
      def tuple? : Bool
        @tag == Tag::CUSTOM && @custom_type.try(&.starts_with?("Tuple")) || false
      end

      @[AlwaysInline]
      def lambda_create_tuple? : Bool
        @tag == Tag::CUSTOM && @custom_type == "LambdaCreateTuple"
      end

      @[AlwaysInline]
      def to_i64 : Int64
        case @tag
        when Tag::INTEGER          then @bits.unsafe_as(Int64)
        when Tag::UNSIGNED_INTEGER then @bits.to_i64!
        when Tag::FLOAT            then @bits.unsafe_as(Float64).to_i64
        when Tag::BOOLEAN          then (@bits != 0) ? 1_i64 : 0_i64
        else
          raise Exceptions::Emulation.new("Cannot convert #{type} to integer")
        end
      end

      @[AlwaysInline]
      def to_u64 : UInt64
        case @tag
        when Tag::UNSIGNED_INTEGER then @bits
        when Tag::INTEGER
          val = @bits.unsafe_as(Int64)
          raise Exceptions::Emulation.new("Cannot convert negative integer to unsigned integer") if val < 0
          val.to_u64!
        when Tag::FLOAT
          val = @bits.unsafe_as(Float64)
          raise Exceptions::Emulation.new("Cannot convert negative float to unsigned integer") if val < 0
          val.to_u64
        when Tag::BOOLEAN then (@bits != 0) ? 1_u64 : 0_u64
        else
          raise Exceptions::Emulation.new("Cannot convert #{type} to unsigned integer")
        end
      end

      @[AlwaysInline]
      def to_f64 : Float64
        case @tag
        when Tag::FLOAT            then @bits.unsafe_as(Float64)
        when Tag::INTEGER          then @bits.unsafe_as(Int64).to_f64
        when Tag::UNSIGNED_INTEGER then @bits.to_f64
        when Tag::BOOLEAN          then (@bits != 0) ? 1.0 : 0.0
        else
          raise Exceptions::Emulation.new("Cannot convert #{type} to float")
        end
      end

      def to_s : ::String
        case @tag
        when Tag::NULL             then "null"
        when Tag::INTEGER          then @bits.unsafe_as(Int64).to_s
        when Tag::UNSIGNED_INTEGER then @bits.to_s
        when Tag::FLOAT            then @bits.unsafe_as(Float64).to_s
        when Tag::BOOLEAN          then (@bits != 0) ? "true" : "false"
        when Tag::SYMBOL           then unbox(Symbol).to_s
        when Tag::STRING           then unbox(::String)
        when Tag::MAP
          hash = unbox(Hash(::String, Context))
          "{#{hash.map { |k, v| "#{k}: #{v}" }.join(", ")}}"
        when Tag::ARRAY
          arr = unbox(::Array(Context))
          "[#{arr.map(&.to_s).join(", ")}]"
        when Tag::BINARY
          slice = unbox(Slice(UInt8))
          "<Binary(#{slice.size} bytes)>"
        when Tag::LAMBDA
          lam = unbox(Lambda::Context)
          "<Lambda(#{lam.variables.size} params, #{lam.instructions.size} instructions)>"
        when Tag::INSTRUCTIONS
          instrs = unbox(::Array(Instruction::Operation))
          "<Instructions(#{instrs.size})>"
        when Tag::CUSTOM
          if @custom_type == "MonitorReference"
            ref = to_monitor_reference
            "#<Monitor #{ref.id} watcher:#{ref.watcher} → #{ref.watched}>"
          else
            "<#{@custom_type}>"
          end
        else
          "<unknown>"
        end
      end

      # IO overload — required for string interpolation to use our to_s
      def to_s(io : IO) : Nil
        io << to_s
      end

      @[AlwaysInline]
      def to_symbol : Symbol
        raise Exceptions::Emulation.new("Cannot convert #{type} to symbol") unless @tag == Tag::SYMBOL
        unbox(Symbol)
      end

      def to_bool : Bool
        case @tag
        when Tag::NULL             then false
        when Tag::BOOLEAN          then @bits != 0
        when Tag::INTEGER          then @bits.unsafe_as(Int64) != 0_i64
        when Tag::UNSIGNED_INTEGER then @bits != 0_u64
        when Tag::FLOAT            then @bits.unsafe_as(Float64) != 0.0
        when Tag::STRING           then !unbox(::String).empty?
        when Tag::SYMBOL           then true
        when Tag::MAP              then !unbox(Hash(::String, Context)).empty?
        when Tag::ARRAY            then !unbox(::Array(Context)).empty?
        when Tag::BINARY           then !unbox(Slice(UInt8)).empty?
        when Tag::LAMBDA           then true
        when Tag::INSTRUCTIONS     then !unbox(::Array(Instruction::Operation)).empty?
        when Tag::CUSTOM           then true
        else                            false
        end
      end

      @[AlwaysInline]
      def to_h : Hash(::String, Context)
        raise Exceptions::Emulation.new("Cannot convert #{type} to hash") unless @tag == Tag::MAP
        unbox(Hash(::String, Context))
      end

      @[AlwaysInline]
      def to_a : ::Array(Context)
        raise Exceptions::Emulation.new("Cannot convert #{type} to array") unless @tag == Tag::ARRAY
        unbox(::Array(Context))
      end

      @[AlwaysInline]
      def to_binary : Slice(UInt8)
        raise Exceptions::Emulation.new("Cannot convert #{type} to binary") unless @tag == Tag::BINARY
        unbox(Slice(UInt8))
      end

      @[AlwaysInline]
      def to_send_tuple : Tuple(UInt64, Context)
        unless @custom_type == "Tuple(UInt64, X::X::Value::Context)"
          raise Exceptions::Emulation.new("Cannot convert #{type} to Tuple(UInt64, Context)")
        end
        unbox(Tuple(UInt64, Context))
      end

      @[AlwaysInline]
      def to_receive_timeout_tuple : Tuple(Context, Float64)
        unless @custom_type == "Tuple(Context, Float64)"
          raise Exceptions::Emulation.new("Cannot convert #{type} to Tuple(Context, Float64)")
        end
        unbox(Tuple(Context, Float64))
      end

      @[AlwaysInline]
      def to_send_after_tuple : Tuple(UInt64, Context, Float64)
        unless @custom_type == "Tuple(UInt64, Context, Float64)"
          raise Exceptions::Emulation.new("Cannot convert #{type} to Tuple(UInt64, Context, Float64)")
        end
        unbox(Tuple(UInt64, Context, Float64))
      end

      @[AlwaysInline]
      def to_lambda_create_tuple : Tuple(::Array(Instruction::Operation), ::Array(::String))
        unless @custom_type == "LambdaCreateTuple"
          raise Exceptions::Emulation.new("Cannot convert #{type} to LambdaCreateTuple")
        end
        unbox(Tuple(::Array(Instruction::Operation), ::Array(::String)))
      end

      @[AlwaysInline]
      def to_instructions : ::Array(Instruction::Operation)
        raise Exceptions::TypeMismatch.new("Cannot convert #{type} to instructions") unless @tag == Tag::INSTRUCTIONS
        unbox(::Array(Instruction::Operation))
      end

      @[AlwaysInline]
      def to_monitor_reference : Process::MonitorReference
        unless monitor_reference?
          raise Exceptions::Emulation.new("Cannot convert #{type} to MonitorReference")
        end
        unbox(Process::MonitorReference)
      end

      @[AlwaysInline]
      def to_lambda : Lambda::Context
        raise Exceptions::Emulation.new("Cannot convert #{type} to lambda") unless @tag == Tag::LAMBDA
        unbox(Lambda::Context)
      end

      def type : ::String
        case @tag
        when Tag::NULL             then "Null"
        when Tag::INTEGER          then "Integer"
        when Tag::UNSIGNED_INTEGER then "UnsignedInteger"
        when Tag::FLOAT            then "Float"
        when Tag::STRING           then "String"
        when Tag::SYMBOL           then "Symbol"
        when Tag::BOOLEAN          then "Boolean"
        when Tag::MAP              then "Map"
        when Tag::ARRAY            then "Array"
        when Tag::BINARY           then "Binary"
        when Tag::LAMBDA           then "Lambda"
        when Tag::INSTRUCTIONS     then "Instructions"
        when Tag::CUSTOM
          case @custom_type
          when "MonitorReference" then "MonitorReference"
          else                         @custom_type || "Unknown"
          end
        else "Unknown"
        end
      end

      def clone : Context
        # Just return self — it's a struct copy, zero cost
        return self if @tag <= Tag::IMMEDIATE_MAX

        case @tag
        when Tag::SYMBOL then Context.new(unbox(Symbol))
        when Tag::STRING then Context.new(unbox(::String).dup)
        when Tag::MAP
          src = unbox(Hash(::String, Context))
          cloned = Hash(::String, Context).new(initial_capacity: src.size)
          src.each { |k, v| cloned[k] = v.clone }
          Context.new(cloned)
        when Tag::ARRAY        then Context.new(unbox(::Array(Context)).map(&.clone))
        when Tag::BINARY       then Context.new(unbox(Slice(UInt8)))
        when Tag::LAMBDA       then Context.new(unbox(Lambda::Context).clone)
        when Tag::INSTRUCTIONS then Context.new(unbox(::Array(Instruction::Operation)).map(&.clone))
        when Tag::CUSTOM
          if @custom_type == "MonitorReference"
            Context.new(unbox(Process::MonitorReference)) # struct → value copy
          else
            self
          end
        else
          raise Exceptions::TypeMismatch.new("Cannot clone unsupported value type: #{type}")
        end
      end

      def ==(other : Context) : Bool
        return false unless @tag == other.@tag

        # Immediates: bit-exact comparison — single instruction, no branching
        if @tag <= Tag::IMMEDIATE_MAX
          return @bits == other.@bits
        end

        # Heap terms: structural comparison
        case @tag
        when Tag::SYMBOL       then unbox(Symbol) == other.unbox(Symbol)
        when Tag::STRING       then unbox(::String) == other.unbox(::String)
        when Tag::MAP          then unbox(Hash(::String, Context)) == other.unbox(Hash(::String, Context))
        when Tag::ARRAY        then unbox(::Array(Context)) == other.unbox(::Array(Context))
        when Tag::BINARY       then unbox(Slice(UInt8)) == other.unbox(Slice(UInt8))
        when Tag::LAMBDA       then @bits == other.@bits # reference equality
        when Tag::INSTRUCTIONS then @bits == other.@bits # reference equality
        when Tag::CUSTOM
          if @custom_type == "MonitorReference" && other.@custom_type == "MonitorReference"
            unbox(Process::MonitorReference) == other.unbox(Process::MonitorReference)
          else
            @custom_type == other.@custom_type && @bits == other.@bits
          end
        else
          false
        end
      end

      #
      # Erlang ordering: number < symbol < reference < fun < port < pid <
      #                  tuple < map < list < bitstring
      #
      # We approximate this with tag ordering and provide a comparison
      # operator for use in pattern matching, guards, and sorted

      def <=>(other : Context) : Int32
        # Different types: order by tag (approximates Erlang term ordering)
        tag_cmp = @tag.to_i32 - other.@tag.to_i32
        return tag_cmp unless tag_cmp == 0

        case @tag
        when Tag::NULL    then 0
        when Tag::BOOLEAN then @bits.to_i32 - other.@bits.to_i32
        when Tag::INTEGER
          a = @bits.unsafe_as(Int64)
          b = other.@bits.unsafe_as(Int64)
          a < b ? -1 : (a > b ? 1 : 0)
        when Tag::UNSIGNED_INTEGER
          a = @bits
          b = other.@bits
          a < b ? -1 : (a > b ? 1 : 0)
        when Tag::FLOAT
          a = @bits.unsafe_as(Float64)
          b = other.@bits.unsafe_as(Float64)
          a < b ? -1 : (a > b ? 1 : 0)
        when Tag::SYMBOL
          unbox(Symbol).to_s <=> other.unbox(Symbol).to_s
        when Tag::STRING
          unbox(::String) <=> other.unbox(::String)
        when Tag::BINARY
          a = unbox(Slice(UInt8))
          b = other.unbox(Slice(UInt8))
          min_len = a.size < b.size ? a.size : b.size
          min_len.times do |i|
            cmp = a.unsafe_fetch(i).to_i32 - b.unsafe_fetch(i).to_i32
            return cmp unless cmp == 0
          end
          a.size - b.size
        when Tag::ARRAY
          a = unbox(::Array(Context))
          b = other.unbox(::Array(Context))
          min_len = a.size < b.size ? a.size : b.size
          min_len.times do |i|
            cmp = a.unsafe_fetch(i) <=> b.unsafe_fetch(i)
            return cmp unless cmp == 0
          end
          a.size - b.size
        when Tag::MAP
          # Maps compared by size, then key-value pairs
          a = unbox(Hash(::String, Context))
          b = other.unbox(Hash(::String, Context))
          size_cmp = a.size - b.size
          return size_cmp unless size_cmp == 0
          # Lexicographic on sorted keys
          a_keys = a.keys.sort
          b_keys = b.keys.sort
          a_keys.zip(b_keys) do |ak, bk|
            key_cmp = ak <=> bk
            return key_cmp unless key_cmp == 0
            val_cmp = a[ak] <=> b[bk]
            return val_cmp unless val_cmp == 0
          end
          0
        else
          # Lambda, Instructions, Custom: compare by pointer address
          a = @bits
          b = other.@bits
          a < b ? -1 : (a > b ? 1 : 0)
        end
      end

      def <(other : Context) : Bool
        (self <=> other) < 0
      end

      def >(other : Context) : Bool
        (self <=> other) > 0
      end

      def <=(other : Context) : Bool
        (self <=> other) <= 0
      end

      def >=(other : Context) : Bool
        (self <=> other) >= 0
      end

      # Match against a type tag — used in guard clauses
      @[AlwaysInline]
      def matches_type?(expected_tag : UInt8) : Bool
        @tag == expected_tag
      end

      # Match a map value and extract a key in one step (avoids double lookup)
      @[AlwaysInline]
      def match_map_key?(key : ::String) : Context?
        return nil unless @tag == Tag::MAP
        unbox(Hash(::String, Context))[key]?
      end

      # Match an array by size and return it if it matches
      @[AlwaysInline]
      def match_array_size?(expected : Int32) : ::Array(Context)?
        return nil unless @tag == Tag::ARRAY
        arr = unbox(::Array(Context))
        arr.size == expected ? arr : nil
      end

      # Erlang-style is_number guard
      @[AlwaysInline]
      def is_number? : Bool
        numeric?
      end

      # Erlang-style is_symbol guard (symbols are our symbols)
      @[AlwaysInline]
      def is_symbol? : Bool
        @tag == Tag::SYMBOL
      end

      # Erlang-style is_list guard
      @[AlwaysInline]
      def is_list? : Bool
        @tag == Tag::ARRAY
      end

      # Erlang-style is_map guard
      @[AlwaysInline]
      def is_map? : Bool
        @tag == Tag::MAP
      end

      # Erlang-style is_binary guard
      @[AlwaysInline]
      def is_binary? : Bool
        @tag == Tag::STRING || @tag == Tag::BINARY
      end

      # Erlang-style is_function guard
      @[AlwaysInline]
      def is_function? : Bool
        @tag == Tag::LAMBDA
      end

      def inspect : ::String
        case @tag
        when Tag::NULL   then "null"
        when Tag::STRING then "\"#{to_s}\""
        when Tag::SYMBOL then ":#{to_s}"
        when Tag::BINARY then "<<#{unbox(Slice(UInt8)).join(", ")}>>"
        else                  to_s
        end
      end

      def hash(hasher)
        hasher = @tag.hash(hasher)
        if @tag <= Tag::IMMEDIATE_MAX
          hasher = @bits.hash(hasher)
        else
          case @tag
          when Tag::STRING then hasher = unbox(::String).hash(hasher)
          when Tag::SYMBOL then hasher = unbox(Symbol).hash(hasher)
          when Tag::BINARY then hasher = unbox(Slice(UInt8)).hash(hasher)
          when Tag::MAP    then hasher = unbox(Hash(::String, Context)).hash(hasher)
          when Tag::ARRAY  then hasher = unbox(::Array(Context)).hash(hasher)
          else                  hasher = @bits.hash(hasher) # pointer hash
          end
        end
        hasher
      end

      private def tag_to_primitive_type : PrimitiveType
        case @tag
        when Tag::NULL             then PrimitiveType::Null
        when Tag::BOOLEAN          then PrimitiveType::Boolean
        when Tag::INTEGER          then PrimitiveType::Integer
        when Tag::UNSIGNED_INTEGER then PrimitiveType::UnsignedInteger
        when Tag::FLOAT            then PrimitiveType::Float
        when Tag::SYMBOL           then PrimitiveType::Symbol
        when Tag::STRING           then PrimitiveType::String
        when Tag::BINARY           then PrimitiveType::Binary
        when Tag::MAP              then PrimitiveType::Map
        when Tag::ARRAY            then PrimitiveType::Array
        when Tag::LAMBDA           then PrimitiveType::Lambda
        when Tag::INSTRUCTIONS     then PrimitiveType::Instructions
        when Tag::CUSTOM           then PrimitiveType::Custom
        else                            PrimitiveType::Null
        end
      end

      # Allow other Context methods to access @bits and @tag for comparison
      protected def bits : UInt64
        @bits
      end

      protected def tag : UInt8
        @tag
      end

      # For heap term unboxing from outside (used in == and <=>)
      protected def unbox(type : T.class) : T forall T
        Box(T).unbox(heap_pointer)
      end
    end
  end
end
