require "log"
require "json"
require "socket"

require "./extensions/*"
require "./x/**"

module X
  VERSION = {{ `shards version "#{__DIR__}"`.chomp.stringify }}
end
