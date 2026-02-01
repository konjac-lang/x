require "log"
require "json"
require "socket"

require "./extensions/*"
require "./x/**"

module X
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}

  alias Engine = Engine::Context
  alias Value = Value::Context
  alias Operation = Instruction::Operation
  alias Code = Instruction::Code
end
