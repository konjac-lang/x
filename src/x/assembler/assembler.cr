module X
  module Assembler
    VERSION = "0.1.0"

    def self.compile(source : String) : CodeGenerator::CompiledModule
      lexer = Lexer.new(source)
      tokens = lexer.tokenize
      parser = Parser.new(tokens)
      ast = parser.parse
      generator = CodeGenerator.new
      generator.generate(ast)
    end

    def self.run(source : String, &setup : Engine::Context ->)
      engine = Engine::Context.new
      yield engine

      loader = Loader.new(engine)
      loader.load_source(source)
      loader.wire_and_run
    end

    def self.run_with_defaults(source : String)
      run(source) do |engine|
        register_default_built_ins(engine)
      end
    end

    def self.register_default_built_ins(engine : Engine::Context)
      register_io(engine)
      register_string(engine)
      register_integer(engine)
      register_float(engine)
      register_array(engine)
      register_map(engine)
      register_type(engine)
    end

    private def self.register_io(engine : Engine::Context)
      engine.register_built_in_function("IO", "puts", 1) do |_engine, _process, arguments|
        STDERR.puts arguments.first.to_s
        Value::Context.new(:ok)
      end

      engine.register_built_in_function("IO", "print", 1) do |_engine, _process, arguments|
        STDERR.print arguments.first.to_s
        Value::Context.new(:ok)
      end

      engine.register_built_in_function("IO", "inspect", 1) do |_engine, _process, arguments|
        STDERR.puts arguments.first.inspect
        arguments.first
      end

      engine.register_built_in_function("IO", "gets", 0) do |_engine, _process, _arguments|
        line = gets || ""
        Value::Context.new(line.chomp)
      end

      engine.register_built_in_function("IO", "printLine", 1) do |_engine, _process, arguments|
        STDERR.puts arguments.first.to_s
        Value::Context.new(:ok)
      end
    end

    private def self.register_string(engine : Engine::Context)
      engine.register_built_in_function("String", "concatenate", 2) do |_engine, _process, arguments|
        Value::Context.new(arguments.last.to_s + arguments.first.to_s)
      end

      engine.register_built_in_function("String", "length", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.size.to_i64)
      end

      engine.register_built_in_function("String", "reverse", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.reverse)
      end

      engine.register_built_in_function("String", "upcase", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.upcase)
      end

      engine.register_built_in_function("String", "downcase", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.downcase)
      end

      engine.register_built_in_function("String", "trim", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.strip)
      end

      engine.register_built_in_function("String", "trimLeading", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.lstrip)
      end

      engine.register_built_in_function("String", "trimTrailing", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.rstrip)
      end

      engine.register_built_in_function("String", "split", 2) do |_engine, _process, arguments|
        str = arguments.last.to_s
        delimiter = arguments.first.to_s
        parts = str.split(delimiter)
        Value::Context.new(parts.map { |p| Value::Context.new(p).as(Value::Context) })
      end

      engine.register_built_in_function("String", "join", 2) do |_engine, _process, arguments|
        list = arguments.last.to_a
        separator = arguments.first.to_s
        Value::Context.new(list.map(&.to_s).join(separator))
      end

      engine.register_built_in_function("String", "contains", 2) do |_engine, _process, arguments|
        str = arguments.last.to_s
        needle = arguments.first.to_s
        Value::Context.new(str.includes?(needle))
      end

      engine.register_built_in_function("String", "startsWith", 2) do |_engine, _process, arguments|
        str = arguments.last.to_s
        prefix = arguments.first.to_s
        Value::Context.new(str.starts_with?(prefix))
      end

      engine.register_built_in_function("String", "endsWith", 2) do |_engine, _process, arguments|
        str = arguments.last.to_s
        suffix = arguments.first.to_s
        Value::Context.new(str.ends_with?(suffix))
      end

      engine.register_built_in_function("String", "replace", 3) do |_engine, _process, arguments|
        str = arguments[2].to_s
        pattern = arguments[1].to_s
        replacement = arguments[0].to_s
        Value::Context.new(str.gsub(pattern, replacement))
      end

      engine.register_built_in_function("String", "slice", 3) do |_engine, _process, arguments|
        str = arguments[2].to_s
        start = arguments[1].to_i64.to_i32
        length = arguments[0].to_i64.to_i32
        Value::Context.new(str[start, length]? || "")
      end

      engine.register_built_in_function("String", "at", 2) do |_engine, _process, arguments|
        str = arguments.last.to_s
        index = arguments.first.to_i64.to_i32
        if index >= 0 && index < str.size
          Value::Context.new(str[index].to_s)
        else
          Value::Context.null
        end
      end

      engine.register_built_in_function("String", "toInteger", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.to_i64)
      end

      engine.register_built_in_function("String", "toFloat", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.to_f64)
      end

      engine.register_built_in_function("String", "toAtom", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s.to_symbol)
      end

      engine.register_built_in_function("String", "duplicate", 2) do |_engine, _process, arguments|
        str = arguments.last.to_s
        times = arguments.first.to_i64.to_i32
        Value::Context.new(str * times)
      end

      engine.register_built_in_function("String", "padLeading", 3) do |_engine, _process, arguments|
        str = arguments[2].to_s
        count = arguments[1].to_i64.to_i32
        padding = arguments[0].to_s
        Value::Context.new(str.rjust(count, padding[0]? || ' '))
      end

      engine.register_built_in_function("String", "padTrailing", 3) do |_engine, _process, arguments|
        str = arguments[2].to_s
        count = arguments[1].to_i64.to_i32
        padding = arguments[0].to_s
        Value::Context.new(str.ljust(count, padding[0]? || ' '))
      end

      engine.register_built_in_function("String", "toString", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s)
      end
    end

    private def self.register_integer(engine : Engine::Context)
      engine.register_built_in_function("Integer", "toString", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_i64.to_s)
      end

      engine.register_built_in_function("Integer", "toFloat", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_i64.to_f64)
      end

      engine.register_built_in_function("Integer", "parse", 1) do |_engine, _process, arguments|
        begin
          Value::Context.new(arguments.first.to_s.to_i64)
        rescue
          Value::Context.new(:error)
        end
      end

      engine.register_built_in_function("Integer", "isEven", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_i64 % 2 == 0)
      end

      engine.register_built_in_function("Integer", "isOdd", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_i64 % 2 != 0)
      end

      engine.register_built_in_function("Integer", "digits", 1) do |_engine, _process, arguments|
        digits = arguments.first.to_i64.abs.to_s.chars.map { |c| Value::Context.new(c.to_i.to_i64).as(Value::Context) }
        Value::Context.new(digits)
      end

      engine.register_built_in_function("Integer", "gcd", 2) do |_engine, _process, arguments|
        a = arguments.last.to_i64.abs
        b = arguments.first.to_i64.abs
        while b != 0
          a, b = b, a % b
        end
        Value::Context.new(a)
      end
    end

    private def self.register_float(engine : Engine::Context)
      engine.register_built_in_function("Float", "toString", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_f64.to_s)
      end

      engine.register_built_in_function("Float", "toInteger", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_f64.to_i64)
      end

      engine.register_built_in_function("Float", "parse", 1) do |_engine, _process, arguments|
        begin
          Value::Context.new(arguments.first.to_s.to_f64)
        rescue
          Value::Context.new(:error)
        end
      end

      engine.register_built_in_function("Float", "round", 2) do |_engine, _process, arguments|
        value = arguments.last.to_f64
        precision = arguments.first.to_i64.to_i32
        multiplier = 10.0 ** precision
        Value::Context.new((value * multiplier).round / multiplier)
      end

      engine.register_built_in_function("Float", "ceil", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_f64.ceil.to_i64)
      end

      engine.register_built_in_function("Float", "floor", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_f64.floor.to_i64)
      end

      engine.register_built_in_function("Float", "isNan", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_f64.nan?)
      end

      engine.register_built_in_function("Float", "isInfinity", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_f64.infinite? != nil)
      end
    end

    private def self.register_array(engine : Engine::Context)
      engine.register_built_in_function("Array", "new", 0) do |_engine, _process, _arguments|
        Value::Context.new([] of Value::Context)
      end

      engine.register_built_in_function("Array", "length", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_a.size.to_i64)
      end

      engine.register_built_in_function("Array", "size", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_a.size.to_i64)
      end

      engine.register_built_in_function("Array", "first", 1) do |_engine, _process, arguments|
        arr = arguments.first.to_a
        arr.empty? ? Value::Context.null : arr.first
      end

      engine.register_built_in_function("Array", "last", 1) do |_engine, _process, arguments|
        arr = arguments.first.to_a
        arr.empty? ? Value::Context.null : arr.last
      end

      engine.register_built_in_function("Array", "at", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a
        index = arguments.first.to_i64.to_i32
        if index >= 0 && index < arr.size
          arr[index]
        else
          Value::Context.null
        end
      end

      engine.register_built_in_function("Array", "get", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a
        index = arguments.first.to_i64.to_i32
        if index >= 0 && index < arr.size
          arr[index]
        else
          Value::Context.null
        end
      end

      engine.register_built_in_function("Array", "set", 3) do |_engine, _process, arguments|
        arr = arguments[2].to_a.dup
        index = arguments[1].to_i64.to_i32
        value = arguments[0]
        if index >= 0 && index < arr.size
          arr[index] = value
        end
        Value::Context.new(arr)
      end

      engine.register_built_in_function("Array", "append", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a.dup
        arr << arguments.first
        Value::Context.new(arr)
      end

      engine.register_built_in_function("Array", "prepend", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a.dup
        arr.unshift(arguments.first)
        Value::Context.new(arr)
      end

      engine.register_built_in_function("Array", "push", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a.dup
        arr << arguments.first
        Value::Context.new(arr)
      end

      engine.register_built_in_function("Array", "pop", 1) do |_engine, _process, arguments|
        arr = arguments.first.to_a.dup
        popped = arr.pop?
        pair = [Value::Context.new(arr), popped || Value::Context.null]
        Value::Context.new(pair)
      end

      engine.register_built_in_function("Array", "concat", 2) do |_engine, _process, arguments|
        a = arguments.last.to_a
        b = arguments.first.to_a
        Value::Context.new(a + b)
      end

      engine.register_built_in_function("Array", "reverse", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_a.reverse)
      end

      engine.register_built_in_function("Array", "sort", 1) do |_engine, _process, arguments|
        sorted = arguments.first.to_a.sort { |a, b| a <=> b }
        Value::Context.new(sorted)
      end

      engine.register_built_in_function("Array", "uniq", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_a.uniq)
      end

      engine.register_built_in_function("Array", "flatten", 1) do |_engine, _process, arguments|
        result = [] of Value::Context
        arguments.first.to_a.each do |item|
          if item.array?
            item.to_a.each { |sub| result << sub }
          else
            result << item
          end
        end
        Value::Context.new(result)
      end

      engine.register_built_in_function("Array", "contains", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a
        item = arguments.first
        Value::Context.new(arr.any? { |el| el == item })
      end

      engine.register_built_in_function("Array", "indexOf", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a
        item = arguments.first
        index = arr.index { |el| el == item }
        index ? Value::Context.new(index.to_i64) : Value::Context.new(-1_i64)
      end

      engine.register_built_in_function("Array", "slice", 3) do |_engine, _process, arguments|
        arr = arguments[2].to_a
        start = arguments[1].to_i64.to_i32
        length = arguments[0].to_i64.to_i32
        Value::Context.new(arr[start, length]? || [] of Value::Context)
      end

      engine.register_built_in_function("Array", "take", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a
        count = arguments.first.to_i64.to_i32
        Value::Context.new(arr.first(count))
      end

      engine.register_built_in_function("Array", "drop", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a
        count = arguments.first.to_i64.to_i32
        Value::Context.new(count < arr.size ? arr[count..] : [] of Value::Context)
      end

      engine.register_built_in_function("Array", "zip", 2) do |_engine, _process, arguments|
        a = arguments.last.to_a
        b = arguments.first.to_a
        min_size = {a.size, b.size}.min
        result = (0...min_size).map do |i|
          Value::Context.new([a[i], b[i]]).as(Value::Context)
        end
        Value::Context.new(result)
      end

      engine.register_built_in_function("Array", "isEmpty", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_a.empty?)
      end

      engine.register_built_in_function("Array", "sum", 1) do |_engine, _process, arguments|
        arr = arguments.first.to_a
        sum = arr.reduce(0_i64) { |acc, el| acc + el.to_i64 }
        Value::Context.new(sum)
      end

      engine.register_built_in_function("Array", "product", 1) do |_engine, _process, arguments|
        arr = arguments.first.to_a
        product = arr.reduce(1_i64) { |acc, el| acc * el.to_i64 }
        Value::Context.new(product)
      end

      engine.register_built_in_function("Array", "min", 1) do |_engine, _process, arguments|
        arr = arguments.first.to_a
        arr.empty? ? Value::Context.null : arr.min_by { |el| el }
      end

      engine.register_built_in_function("Array", "max", 1) do |_engine, _process, arguments|
        arr = arguments.first.to_a
        arr.empty? ? Value::Context.null : arr.max_by { |el| el }
      end

      engine.register_built_in_function("Array", "join", 2) do |_engine, _process, arguments|
        arr = arguments.last.to_a
        separator = arguments.first.to_s
        Value::Context.new(arr.map(&.to_s).join(separator))
      end
    end

    private def self.register_map(engine : Engine::Context)
      engine.register_built_in_function("Map", "new", 0) do |_engine, _process, _arguments|
        Value::Context.new(Hash(String, Value::Context).new)
      end

      engine.register_built_in_function("Map", "put", 3) do |_engine, _process, arguments|
        map = arguments[2].to_h.dup
        key = arguments[1].to_s
        value = arguments[0]
        map[key] = value
        Value::Context.new(map)
      end

      engine.register_built_in_function("Map", "get", 2) do |_engine, _process, arguments|
        map = arguments.last.to_h
        key = arguments.first.to_s
        map[key]? || Value::Context.null
      end

      engine.register_built_in_function("Map", "getWithDefault", 3) do |_engine, _process, arguments|
        map = arguments[2].to_h
        key = arguments[1].to_s
        default = arguments[0]
        map[key]? || default
      end

      engine.register_built_in_function("Map", "delete", 2) do |_engine, _process, arguments|
        map = arguments.last.to_h.dup
        key = arguments.first.to_s
        map.delete(key)
        Value::Context.new(map)
      end

      engine.register_built_in_function("Map", "hasKey", 2) do |_engine, _process, arguments|
        map = arguments.last.to_h
        key = arguments.first.to_s
        Value::Context.new(map.has_key?(key))
      end

      engine.register_built_in_function("Map", "keys", 1) do |_engine, _process, arguments|
        keys = arguments.first.to_h.keys.map { |k| Value::Context.new(k).as(Value::Context) }
        Value::Context.new(keys)
      end

      engine.register_built_in_function("Map", "values", 1) do |_engine, _process, arguments|
        values = arguments.first.to_h.values
        Value::Context.new(values)
      end

      engine.register_built_in_function("Map", "size", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_h.size.to_i64)
      end

      engine.register_built_in_function("Map", "merge", 2) do |_engine, _process, arguments|
        a = arguments.last.to_h
        b = arguments.first.to_h
        Value::Context.new(a.merge(b))
      end

      engine.register_built_in_function("Map", "toArray", 1) do |_engine, _process, arguments|
        pairs = arguments.first.to_h.map do |k, v|
          Value::Context.new([Value::Context.new(k), v]).as(Value::Context)
        end
        Value::Context.new(pairs)
      end

      engine.register_built_in_function("Map", "isEmpty", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_h.empty?)
      end
    end

    private def self.register_type(engine : Engine::Context)
      engine.register_built_in_function("Type", "inspect", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.inspect)
      end

      engine.register_built_in_function("Type", "of", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.type)
      end

      engine.register_built_in_function("Type", "toString", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.to_s)
      end

      engine.register_built_in_function("Type", "isNull", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.null?)
      end

      engine.register_built_in_function("Type", "isInteger", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.integer?)
      end

      engine.register_built_in_function("Type", "isFloat", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.float?)
      end

      engine.register_built_in_function("Type", "isString", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.string?)
      end

      engine.register_built_in_function("Type", "isBoolean", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.boolean?)
      end

      engine.register_built_in_function("Type", "isArray", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.array?)
      end

      engine.register_built_in_function("Type", "isMap", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.map?)
      end

      engine.register_built_in_function("Type", "isSymbol", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.symbol?)
      end

      engine.register_built_in_function("Type", "isLambda", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.lambda?)
      end

      engine.register_built_in_function("Type", "isNumeric", 1) do |_engine, _process, arguments|
        Value::Context.new(arguments.first.numeric?)
      end
    end
  end
end
