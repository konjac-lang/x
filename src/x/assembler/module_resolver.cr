module X
  module Assembler
    class ModuleResolver
      Log = ::Log.for(self)

      getter search_roots : Array(String)

      def initialize(@search_roots : Array(String) = ["src/", "lib/", "./"])
      end

      def add_search_root(path : String)
        @search_roots << path unless @search_roots.includes?(path)
      end

      def resolve(module_name : String) : String?
        Log.debug { "Resolving module '#{module_name}'" }

        # First: try path-based candidates (fast)
        if path = resolve_by_path(module_name)
          return path
        end

        # Second: scan all .xasm files and check their .module declaration
        if path = resolve_by_module_declaration(module_name)
          return path
        end

        Log.warn { "Could not resolve module '#{module_name}'" }
        nil
      end

      private def resolve_by_path(module_name : String) : String?
        parts = module_name.split('.')
        candidates = generate_candidates(parts)

        Log.debug { "Path candidates: #{candidates}" }

        @search_roots.each do |root|
          candidates.each do |candidate|
            full_path = File.join(root, candidate)
            Log.debug { "Trying: #{full_path} — #{File.exists?(full_path) ? "FOUND" : "not found"}" }
            if File.exists?(full_path)
              Log.debug { "Resolved '#{module_name}' → #{full_path}" }
              return full_path
            end
          end
        end

        nil
      end

      private def resolve_by_module_declaration(module_name : String) : String?
        Log.debug { "Scanning for .module #{module_name} in search roots" }

        @search_roots.each do |root|
          next unless Dir.exists?(root)

          result = scan_for_module(root, module_name)
          if result
            Log.debug { "Found '#{module_name}' declared in #{result}" }
            return result
          end
        end

        nil
      end

      private def scan_for_module(dir : String, module_name : String) : String?
        Dir.each_child(dir) do |entry|
          full_path = File.join(dir, entry)

          if File.directory?(full_path)
            if found = scan_for_module(full_path, module_name)
              return found
            end
          elsif entry.ends_with?(".xasm")
            if file_declares_module?(full_path, module_name)
              return full_path
            end
          end
        end

        nil
      rescue ex
        Log.debug { "Could not scan directory '#{dir}': #{ex.message}" }
        nil
      end

      private def scan_directory(dir : String, &block : String ->)
        Dir.each_child(dir) do |entry|
          full_path = File.join(dir, entry)

          if File.directory?(full_path)
            scan_directory(full_path, &block)
          elsif entry.ends_with?(".xasm")
            yield full_path
          end
        end
      rescue ex
        Log.debug { "Could not scan directory '#{dir}': #{ex.message}" }
      end

      private def file_declares_module?(file_path : String, module_name : String) : Bool
        File.each_line(file_path) do |line|
          stripped = line.strip

          # Skip empty lines and comments
          next if stripped.empty?
          next if stripped.starts_with?('#') || stripped.starts_with?(';')

          # Check for .module declaration
          if stripped.starts_with?(".module ")
            declared_name = stripped[8..].strip
            return declared_name == module_name
          end

          # .module should be the first non-comment line — stop looking
          return false
        end

        false
      rescue
        false
      end

      private def generate_candidates(parts : Array(String)) : Array(String)
        candidates = [] of String

        # 1. Exact case: MyApp/Math/Vector.xasm
        candidates << File.join(parts[0..-2] + ["#{parts.last}.xasm"])

        # 2. All lowercase: my_app/math/vector.xasm
        snake_parts = parts.map { |p| to_snake_case(p) }
        candidates << File.join(snake_parts[0..-2] + ["#{snake_parts.last}.xasm"])

        # 3. Lowercase with dots as separators: my_app.math.vector.xasm
        candidates << "#{snake_parts.join('.')}.xasm"

        # 4. Mixed case — capitalize top, lowercase rest
        if parts.size > 1
          mixed = [parts[0]] + parts[1..].map { |p| to_snake_case(p) }
          candidates << File.join(mixed[0..-2] + ["#{mixed.last}.xasm"])
        end

        # 5. Just the last component: Vector.xasm
        candidates << "#{parts.last}.xasm"

        # 6. Just the last component lowercase: vector.xasm
        candidates << "#{to_snake_case(parts.last)}.xasm"

        # 7. Full dot-separated capitalized: MyApp.Math.Vector.xasm
        candidates << "#{parts.join('.')}.xasm"

        candidates.uniq
      end

      private def to_snake_case(name : String) : String
        result = String.build do |builder|
          name.each_char_with_index do |char, index|
            if char.uppercase?
              builder << '_' if index > 0 && name[index - 1]?.try(&.lowercase?)
              builder << char.downcase
            else
              builder << char
            end
          end
        end
        result.lstrip('_')
      end
    end
  end
end
