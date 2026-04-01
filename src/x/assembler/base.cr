module X
  module Assembler
    module Base
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
        register_tcp(engine)
        register_udp(engine)
        register_unix(engine)
        register_socket(engine)
      end

      private def self.register_io(engine : Engine::Context)
        engine.register_built_in_function("IO", "puts", 1) do |_engine, _process, arguments|
          STDERR.puts arguments.first.to_s
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("IO", "print", 1) do |_engine, _process, arguments|
          STDERR.print arguments.first.to_s
          Value::Context.new(:okay)
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
          Value::Context.new(:okay)
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

      private def self.register_tcp(engine : Engine::Context)
        engine.register_built_in_function("TCP", "listen", 1) do |_engine, _process, arguments|
          port = arguments.first.to_i64.to_i32
          server = TCPServer.new("0.0.0.0", port)
          server.sync = false
          Value::Context.new(server)
        end

        engine.register_built_in_function("TCP", "listenOn", 2) do |_engine, _process, arguments|
          address = arguments.last.to_s
          port = arguments.first.to_i64.to_i32
          server = TCPServer.new(address, port)
          server.sync = false
          Value::Context.new(server)
        end

        engine.register_built_in_function("TCP", "listenWithBacklog", 3) do |_engine, _process, arguments|
          address = arguments[2].to_s
          port = arguments[1].to_i64.to_i32
          backlog = arguments[0].to_i64.to_i32
          server = TCPServer.new(address, port, backlog: backlog)
          server.sync = false
          Value::Context.new(server)
        end

        engine.register_built_in_function("TCP", "accept", 1) do |engine, process, arguments|
          server = Box(TCPServer).unbox(arguments.first.pointer)

          process.state = Process::State::WAITING
          process.waiting_for = Value::Context.new(:io)
          process.waiting_since = Time.utc

          spawn do
            begin
              client = server.accept
              client.sync = false
              client.tcp_nodelay = true
              process.stack.push(Value::Context.new(client))
            rescue ex
              process.stack.push(Value::Context.new([
                Value::Context.new(:error),
                Value::Context.new(ex.message || "Accept failed"),
              ] of Value::Context))
            end
            engine.queue_process_for_reactivation(process)
          end

          Value::Context.null
        end

        engine.register_built_in_function("TCP", "acceptTimeout", 2) do |_engine, _process, arguments|
          server = Box(TCPServer).unbox(arguments.last.pointer)
          timeout_ms = arguments.first.to_i64.to_i32
          server.read_timeout = timeout_ms.milliseconds
          begin
            client = server.accept
            client.sync = false
            client.tcp_nodelay = true
            Value::Context.new(client)
          rescue IO::TimeoutError
            Value::Context.new(:timeout)
          ensure
            server.read_timeout = nil
          end
        end

        engine.register_built_in_function("TCP", "connect", 2) do |_engine, _process, arguments|
          host = arguments.last.to_s
          port = arguments.first.to_i64.to_i32
          socket = TCPSocket.new(host, port)
          socket.sync = false
          socket.tcp_nodelay = true
          Value::Context.new(socket)
        end

        engine.register_built_in_function("TCP", "connectTimeout", 3) do |_engine, _process, arguments|
          host = arguments[2].to_s
          port = arguments[1].to_i64.to_i32
          timeout_ms = arguments[0].to_i64.to_i32
          begin
            socket = TCPSocket.new(host, port, connect_timeout: timeout_ms.milliseconds)
            socket.sync = false
            socket.tcp_nodelay = true
            Value::Context.new(socket)
          rescue IO::TimeoutError
            Value::Context.new(:timeout)
          end
        end

        engine.register_built_in_function("TCP", "send", 2) do |engine, process, arguments|
          socket = Box(TCPSocket).unbox(arguments.first.pointer)
          data = arguments.last.to_s

          process.state = Process::State::WAITING
          process.waiting_for = Value::Context.new(:io)
          process.waiting_since = Time.utc

          spawn do
            begin
              socket.write(data.to_slice)
              process.stack.push(Value::Context.new(:okay))
            rescue ex
              process.stack.push(Value::Context.new([
                Value::Context.new(:error),
                Value::Context.new(ex.message || "write failed"),
              ] of Value::Context))
            end
            engine.queue_process_for_reactivation(process)
          end

          Value::Context.null
        end

        engine.register_built_in_function("TCP", "sendBinary", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          data = arguments.first.to_binary
          begin
            socket.write(data)
            Value::Context.new(:okay)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "write failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("TCP", "receive", 2) do |engine, process, arguments|
          socket = Box(TCPSocket).unbox(arguments.first.pointer)
          max = arguments.last.to_i64.to_i32

          process.state = Process::State::WAITING
          process.waiting_for = Value::Context.new(:io)
          process.waiting_since = Time.utc

          spawn do
            begin
              buffer = Bytes.new(max)
              bytes_read = socket.read(buffer)
              if bytes_read == 0
                process.stack.push(Value::Context.new(:closed))
              else
                process.stack.push(Value::Context.new(String.new(buffer[0, bytes_read])))
              end
            rescue ex
              process.stack.push(Value::Context.new([
                Value::Context.new(:error),
                Value::Context.new(ex.message || "read failed"),
              ] of Value::Context))
            end
            engine.queue_process_for_reactivation(process)
          end

          Value::Context.null
        end

        engine.register_built_in_function("TCP", "receiveBinary", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          max = arguments.first.to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            bytes_read = socket.read(buffer)
            if bytes_read == 0
              Value::Context.new(:closed)
            else
              Value::Context.new(buffer[0, bytes_read])
            end
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "read failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("TCP", "receiveTimeout", 3) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments[2].pointer)
          max = arguments[1].to_i64.to_i32
          timeout_ms = arguments[0].to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            socket.read_timeout = timeout_ms.milliseconds
            bytes_read = socket.read(buffer)
            if bytes_read == 0
              Value::Context.new(:closed)
            else
              Value::Context.new(String.new(buffer[0, bytes_read]))
            end
          rescue IO::TimeoutError
            Value::Context.new(:timeout)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "read failed"),
            ] of Value::Context)
          ensure
            socket.read_timeout = nil
          end
        end

        engine.register_built_in_function("TCP", "receiveLine", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          max = arguments.first.to_i64.to_i32
          begin
            line = socket.gets(max)
            if line.nil?
              Value::Context.new(:closed)
            else
              Value::Context.new(line)
            end
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "read failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("TCP", "receiveExact", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          exact = arguments.first.to_i64.to_i32
          buffer = Bytes.new(exact)
          begin
            total_read = 0
            while total_read < exact
              bytes_read = socket.read(buffer[total_read..])

              if bytes_read == 0
                next Value::Context.new(:closed)
              end

              total_read += bytes_read
            end

            Value::Context.new(String.new(buffer))
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "read failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("TCP", "close", 1) do |_engine, _process, arguments|
          begin
            io = Box(IO).unbox(arguments.first.pointer)
            io.close unless io.closed?
          rescue
          end
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "shutdown", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          direction = arguments.first.to_s
          begin
            case direction
            when "read"  then socket.close_read
            when "write" then socket.close_write
            when "both"
              socket.close_read
              socket.close_write
            else
              next Value::Context.new([
                Value::Context.new(:error),
                Value::Context.new("invalid direction: #{direction}, expected read|write|both"),
              ] of Value::Context)
            end
            Value::Context.new(:okay)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "shutdown failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("TCP", "isClosed", 1) do |_engine, _process, arguments|
          begin
            io = Box(IO).unbox(arguments.first.pointer)
            Value::Context.new(io.closed?)
          rescue
            Value::Context.new(true)
          end
        end

        engine.register_built_in_function("TCP", "setNodelay", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          socket.tcp_nodelay = arguments.first.to_bool
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "setKeepalive", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          socket.keepalive = arguments.first.to_bool
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "setReceiveBufferSize", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          socket.recv_buffer_size = arguments.first.to_i64.to_i32
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "setSendBufferSize", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          socket.send_buffer_size = arguments.first.to_i64.to_i32
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "setReadTimeout", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          socket.read_timeout = arguments.first.to_i64.to_i32.milliseconds
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "setWriteTimeout", 2) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.last.pointer)
          socket.write_timeout = arguments.first.to_i64.to_i32.milliseconds
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "clearReadTimeout", 1) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.first.pointer)
          socket.read_timeout = nil
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "clearWriteTimeout", 1) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.first.pointer)
          socket.write_timeout = nil
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "setReuseAddress", 2) do |_engine, _process, arguments|
          server = Box(TCPServer).unbox(arguments.last.pointer)
          server.reuse_address = arguments.first.to_bool
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "setReusePort", 2) do |_engine, _process, arguments|
          server = Box(TCPServer).unbox(arguments.last.pointer)
          server.reuse_port = arguments.first.to_bool
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "setLingerOption", 3) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments[2].pointer)
          enabled = arguments[1].to_bool
          timeout = arguments[0].to_i64.to_i32
          socket.linger = enabled ? timeout : nil
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("TCP", "localAddress", 1) do |_engine, _process, arguments|
          raw = arguments.first.pointer
          addr = begin
            Box(TCPSocket).unbox(raw).local_address.as(Socket::IPAddress)
          rescue
            Box(TCPServer).unbox(raw).local_address.as(Socket::IPAddress)
          end
          Value::Context.new([
            Value::Context.new(addr.address),
            Value::Context.new(addr.port.to_i64),
          ] of Value::Context)
        end

        engine.register_built_in_function("TCP", "remoteAddress", 1) do |_engine, _process, arguments|
          socket = Box(TCPSocket).unbox(arguments.first.pointer)
          addr = socket.remote_address.as(Socket::IPAddress)
          Value::Context.new([
            Value::Context.new(addr.address),
            Value::Context.new(addr.port.to_i64),
          ] of Value::Context)
        end
      end

      private def self.register_udp(engine : Engine::Context)
        engine.register_built_in_function("UDP", "open", 1) do |_engine, _process, arguments|
          port = arguments.first.to_i64.to_i32
          socket = UDPSocket.new
          socket.bind("0.0.0.0", port)
          socket.sync = false
          Value::Context.new(socket)
        end

        engine.register_built_in_function("UDP", "openOn", 2) do |_engine, _process, arguments|
          address = arguments.last.to_s
          port = arguments.first.to_i64.to_i32
          socket = UDPSocket.new
          socket.bind(address, port)
          socket.sync = false
          Value::Context.new(socket)
        end

        engine.register_built_in_function("UDP", "openUnbound", 0) do |_engine, _process, _arguments|
          socket = UDPSocket.new
          socket.sync = false
          Value::Context.new(socket)
        end

        engine.register_built_in_function("UDP", "sendTo", 4) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments[3].pointer)
          host = arguments[2].to_s
          port = arguments[1].to_i64.to_i32
          data = arguments[0].to_s
          begin
            socket.send(data, Socket::IPAddress.new(host, port))
            Value::Context.new(:okay)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "send failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("UDP", "sendToBinary", 4) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments[3].pointer)
          host = arguments[2].to_s
          port = arguments[1].to_i64.to_i32
          data = arguments[0].to_binary
          begin
            socket.send(data, Socket::IPAddress.new(host, port))
            Value::Context.new(:okay)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "send failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("UDP", "receiveFrom", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          max = arguments.first.to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            bytes_read, addr = socket.receive(buffer)
            ip_addr = addr.as(Socket::IPAddress)
            Value::Context.new([
              Value::Context.new(String.new(buffer[0, bytes_read])),
              Value::Context.new(ip_addr.address),
              Value::Context.new(ip_addr.port.to_i64),
            ] of Value::Context)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "receive failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("UDP", "receiveFromBinary", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          max = arguments.first.to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            bytes_read, addr = socket.receive(buffer)
            ip_addr = addr.as(Socket::IPAddress)
            Value::Context.new([
              Value::Context.new(buffer[0, bytes_read]),
              Value::Context.new(ip_addr.address),
              Value::Context.new(ip_addr.port.to_i64),
            ] of Value::Context)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "receive failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("UDP", "receiveFromTimeout", 3) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments[2].pointer)
          max = arguments[1].to_i64.to_i32
          timeout_ms = arguments[0].to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            socket.read_timeout = timeout_ms.milliseconds
            bytes_read, addr = socket.receive(buffer)
            ip_addr = addr.as(Socket::IPAddress)
            Value::Context.new([
              Value::Context.new(String.new(buffer[0, bytes_read])),
              Value::Context.new(ip_addr.address),
              Value::Context.new(ip_addr.port.to_i64),
            ] of Value::Context)
          rescue IO::TimeoutError
            Value::Context.new(:timeout)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "receive failed"),
            ] of Value::Context)
          ensure
            socket.read_timeout = nil
          end
        end

        engine.register_built_in_function("UDP", "connect", 3) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments[2].pointer)
          host = arguments[1].to_s
          port = arguments[0].to_i64.to_i32
          socket.connect(host, port)
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "send", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          data = arguments.first.to_s
          begin
            socket.write(data.to_slice)
            Value::Context.new(:okay)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "send failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("UDP", "receive", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          max = arguments.first.to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            bytes_read = socket.read(buffer)
            Value::Context.new(String.new(buffer[0, bytes_read]))
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "receive failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("UDP", "setBroadcast", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          socket.broadcast = arguments.first.to_bool
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "setReceiveBufferSize", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          socket.recv_buffer_size = arguments.first.to_i64.to_i32
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "setSendBufferSize", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          socket.send_buffer_size = arguments.first.to_i64.to_i32
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "joinMulticastGroup", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          group = arguments.first.to_s
          socket.join_group(Socket::IPAddress.new(group, 0))
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "leaveMulticastGroup", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          group = arguments.first.to_s
          socket.leave_group(Socket::IPAddress.new(group, 0))
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "setMulticastLoopback", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          socket.multicast_loopback = arguments.first.to_bool
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "setMulticastHops", 2) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.last.pointer)
          socket.multicast_hops = arguments.first.to_i64.to_i32
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "localAddress", 1) do |_engine, _process, arguments|
          socket = Box(UDPSocket).unbox(arguments.first.pointer)
          addr = socket.local_address.as(Socket::IPAddress)
          Value::Context.new([
            Value::Context.new(addr.address),
            Value::Context.new(addr.port.to_i64),
          ] of Value::Context)
        end

        engine.register_built_in_function("UDP", "close", 1) do |_engine, _process, arguments|
          begin
            socket = Box(UDPSocket).unbox(arguments.first.pointer)
            socket.close unless socket.closed?
          rescue
          end
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("UDP", "isClosed", 1) do |_engine, _process, arguments|
          begin
            socket = Box(UDPSocket).unbox(arguments.first.pointer)
            Value::Context.new(socket.closed?)
          rescue
            Value::Context.new(true)
          end
        end
      end

      private def self.register_unix(engine : Engine::Context)
        engine.register_built_in_function("Unix", "listen", 1) do |_engine, _process, arguments|
          path = arguments.first.to_s
          server = UNIXServer.new(path)
          Value::Context.new(server)
        end

        engine.register_built_in_function("Unix", "listenWithBacklog", 2) do |_engine, _process, arguments|
          path = arguments.last.to_s
          backlog = arguments.first.to_i64.to_i32
          server = UNIXServer.new(path, backlog: backlog)
          Value::Context.new(server)
        end

        engine.register_built_in_function("Unix", "accept", 1) do |_engine, _process, arguments|
          server = Box(UNIXServer).unbox(arguments.first.pointer)
          client = server.accept
          client.sync = false
          Value::Context.new(client)
        end

        engine.register_built_in_function("Unix", "acceptTimeout", 2) do |_engine, _process, arguments|
          server = Box(UNIXServer).unbox(arguments.last.pointer)
          timeout_ms = arguments.first.to_i64.to_i32
          server.read_timeout = timeout_ms.milliseconds
          begin
            client = server.accept
            client.sync = false
            Value::Context.new(client)
          rescue IO::TimeoutError
            Value::Context.new(:timeout)
          ensure
            server.read_timeout = nil
          end
        end

        engine.register_built_in_function("Unix", "connect", 1) do |_engine, _process, arguments|
          path = arguments.first.to_s
          socket = UNIXSocket.new(path)
          socket.sync = false
          Value::Context.new(socket)
        end

        engine.register_built_in_function("Unix", "send", 2) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.last.pointer)
          data = arguments.first.to_s
          begin
            socket.write(data.to_slice)
            Value::Context.new(:okay)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "write failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Unix", "sendBinary", 2) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.last.pointer)
          data = arguments.first.to_binary
          begin
            socket.write(data)
            Value::Context.new(:okay)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "write failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Unix", "receive", 2) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.last.pointer)
          max = arguments.first.to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            bytes_read = socket.read(buffer)
            if bytes_read == 0
              Value::Context.new(:closed)
            else
              Value::Context.new(String.new(buffer[0, bytes_read]))
            end
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "read failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Unix", "receiveBinary", 2) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.last.pointer)
          max = arguments.first.to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            bytes_read = socket.read(buffer)
            if bytes_read == 0
              Value::Context.new(:closed)
            else
              Value::Context.new(buffer[0, bytes_read])
            end
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "read failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Unix", "receiveTimeout", 3) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments[2].pointer)
          max = arguments[1].to_i64.to_i32
          timeout_ms = arguments[0].to_i64.to_i32
          buffer = Bytes.new(max)
          begin
            socket.read_timeout = timeout_ms.milliseconds
            bytes_read = socket.read(buffer)
            if bytes_read == 0
              Value::Context.new(:closed)
            else
              Value::Context.new(String.new(buffer[0, bytes_read]))
            end
          rescue IO::TimeoutError
            Value::Context.new(:timeout)
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "read failed"),
            ] of Value::Context)
          ensure
            socket.read_timeout = nil
          end
        end

        engine.register_built_in_function("Unix", "receiveLine", 2) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.last.pointer)
          max = arguments.first.to_i64.to_i32
          begin
            line = socket.gets(max)
            if line.nil?
              Value::Context.new(:closed)
            else
              Value::Context.new(line)
            end
          rescue ex : IO::Error
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "read failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Unix", "sendFileDescriptor", 2) do |_engine, _process, _arguments|
          Value::Context.new([
            Value::Context.new(:error),
            Value::Context.new("sendFileDescriptor not supported"),
          ] of Value::Context)
        end

        engine.register_built_in_function("Unix", "receiveFileDescriptor", 1) do |_engine, _process, _arguments|
          Value::Context.new([
            Value::Context.new(:error),
            Value::Context.new("recvFileDescriptor not supported"),
          ] of Value::Context)
        end

        engine.register_built_in_function("Unix", "close", 1) do |_engine, _process, arguments|
          begin
            io = Box(IO).unbox(arguments.first.pointer)
            io.close unless io.closed?
          rescue
          end
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("Unix", "isClosed", 1) do |_engine, _process, arguments|
          begin
            io = Box(IO).unbox(arguments.first.pointer)
            Value::Context.new(io.closed?)
          rescue
            Value::Context.new(true)
          end
        end

        engine.register_built_in_function("Unix", "unlink", 1) do |_engine, _process, arguments|
          path = arguments.first.to_s
          begin
            File.delete(path)
            Value::Context.new(:okay)
          rescue ex
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "unlink failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Unix", "setReadTimeout", 2) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.last.pointer)
          socket.read_timeout = arguments.first.to_i64.to_i32.milliseconds
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("Unix", "setWriteTimeout", 2) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.last.pointer)
          socket.write_timeout = arguments.first.to_i64.to_i32.milliseconds
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("Unix", "clearReadTimeout", 1) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.first.pointer)
          socket.read_timeout = nil
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("Unix", "clearWriteTimeout", 1) do |_engine, _process, arguments|
          socket = Box(UNIXSocket).unbox(arguments.first.pointer)
          socket.write_timeout = nil
          Value::Context.new(:okay)
        end

        engine.register_built_in_function("Unix", "path", 1) do |_engine, _process, arguments|
          raw = arguments.first.pointer
          begin
            server = Box(UNIXServer).unbox(raw)
            addr = server.local_address.as(Socket::UNIXAddress)
            Value::Context.new(addr.path)
          rescue
            begin
              socket = Box(UNIXSocket).unbox(raw)
              addr = socket.local_address.as(Socket::UNIXAddress)
              Value::Context.new(addr.path)
            rescue
              Value::Context.new(:error)
            end
          end
        end
      end

      private def self.register_socket(engine : Engine::Context)
        engine.register_built_in_function("Socket", "resolve", 1) do |_engine, _process, arguments|
          hostname = arguments.first.to_s
          begin
            addrs = Socket::Addrinfo.resolve(hostname, "http", type: Socket::Type::STREAM)
            results = addrs.map do |addr|
              Value::Context.new(addr.ip_address.address).as(Value::Context)
            end
            Value::Context.new(results)
          rescue ex
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "resolve failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Socket", "resolveAll", 3) do |_engine, _process, arguments|
          hostname = arguments[2].to_s
          service = arguments[1].to_s
          family_str = arguments[0].to_s
          family = case family_str
                   when "ipv4" then Socket::Family::INET
                   when "ipv6" then Socket::Family::INET6
                   else             Socket::Family::UNSPEC
                   end
          begin
            addrs = Socket::Addrinfo.resolve(hostname, service, family: family, type: Socket::Type::STREAM)
            results = addrs.map do |addr|
              ip = addr.ip_address
              Value::Context.new([
                Value::Context.new(ip.address),
                Value::Context.new(ip.port.to_i64),
                Value::Context.new(ip.family == Socket::Family::INET6 ? "ipv6" : "ipv4"),
              ] of Value::Context).as(Value::Context)
            end
            Value::Context.new(results)
          rescue ex
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "resolve failed"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Socket", "parseIpAddress", 2) do |_engine, _process, arguments|
          address = arguments.last.to_s
          port = arguments.first.to_i64.to_i32
          begin
            ip = Socket::IPAddress.new(address, port)
            Value::Context.new([
              Value::Context.new(ip.address),
              Value::Context.new(ip.port.to_i64),
              Value::Context.new(ip.family == Socket::Family::INET6 ? "ipv6" : "ipv4"),
            ] of Value::Context)
          rescue ex
            Value::Context.new([
              Value::Context.new(:error),
              Value::Context.new(ex.message || "invalid address"),
            ] of Value::Context)
          end
        end

        engine.register_built_in_function("Socket", "isValidIp", 1) do |_engine, _process, arguments|
          address = arguments.first.to_s
          begin
            Socket::IPAddress.new(address, 0)
            Value::Context.new(true)
          rescue
            Value::Context.new(false)
          end
        end
      end
    end
  end
end
