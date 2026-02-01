require "./emulation"

module X
  module Exceptions
    # Raised when the VM detects a deadlock situation
    class Deadlock < Emulation
    end
  end
end
