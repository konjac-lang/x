require "log"
require "json"
require "socket"

require "./extensions/*"
require "./x/**"

module X
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  alias EngineContext = Engine::Context
  alias ValueContext = Value::Context
  alias Operation = Instruction::Operation
  alias Code = Instruction::Code
end
