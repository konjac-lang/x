require "../src/x"

# Log.setup(:debug)

engine = X::EngineContext.new

engine.register_built_in_function("IO", "printLine", 1) do |engine, process, arguments|
  puts arguments.first.to_s
  X::ValueContext.null
end

engine.register_built_in_function("String", "concatenate", 2) do |engine, process, arguments|
  X::ValueContext.new(arguments.last.to_s + arguments.first.to_s)
end

# Process 1: Receiver - waits for messages and prints them
receiver = engine.create_process(
  instructions: [
    # Register this process as "receiver"
    X::Operation.new(X::Code::PROCESS_SELF),
    X::Operation.new(X::Code::PROCESS_REGISTER, X::ValueContext.new("receiver")),

    # Wait for and print first message
    X::Operation.new(X::Code::MESSAGE_RECEIVE),
    X::Operation.new(X::Code::PUSH_STRING, X::ValueContext.new("First message: ")),
    X::Operation.new(X::Code::CONTROL_CALL_BUILT_IN_FUNCTION, X::ValueContext.new([X::ValueContext.new("String"), X::ValueContext.new("concatenate"), X::ValueContext.new(2_i64)])),
    X::Operation.new(X::Code::CONTROL_CALL_BUILT_IN_FUNCTION, X::ValueContext.new([X::ValueContext.new("IO"), X::ValueContext.new("printLine"), X::ValueContext.new(1_i64)])),

    # Wait for and print second message
    X::Operation.new(X::Code::MESSAGE_RECEIVE),
    X::Operation.new(X::Code::PUSH_STRING, X::ValueContext.new("Second message: ")),
    X::Operation.new(X::Code::CONTROL_CALL_BUILT_IN_FUNCTION, X::ValueContext.new([X::ValueContext.new("String"), X::ValueContext.new("concatenate"), X::ValueContext.new(2_i64)])),
    X::Operation.new(X::Code::CONTROL_CALL_BUILT_IN_FUNCTION, X::ValueContext.new([X::ValueContext.new("IO"), X::ValueContext.new("printLine"), X::ValueContext.new(1_i64)])),

    # Exit normally
    X::Operation.new(X::Code::PUSH_STRING, X::ValueContext.new("normal")),
    X::Operation.new(X::Code::PROCESS_EXIT),
  ]
)

# Process 2: Sender - sends messages to the receiver
sender = engine.create_process(
  instructions: [
    # Yield to let receiver register first
    X::Operation.new(X::Code::PROCESS_YIELD),
    X::Operation.new(X::Code::PROCESS_YIELD),

    # Send first message to "receiver"
    X::Operation.new(X::Code::PUSH_STRING, X::ValueContext.new("receiver")),
    X::Operation.new(X::Code::PUSH_CUSTOM, X::ValueContext.new("Hello, World!")),
    X::Operation.new(X::Code::MESSAGE_SEND),

    # Send second message
    X::Operation.new(X::Code::PUSH_STRING, X::ValueContext.new("receiver")),
    X::Operation.new(X::Code::PUSH_STRING, X::ValueContext.new("Bye, World!")),
    X::Operation.new(X::Code::MESSAGE_SEND),

    # Print confirmation
    X::Operation.new(X::Code::PUSH_STRING, X::ValueContext.new("Sender: Messages sent!")),
    X::Operation.new(X::Code::CONTROL_CALL_BUILT_IN_FUNCTION, X::ValueContext.new([X::ValueContext.new("IO"), X::ValueContext.new("printLine"), X::ValueContext.new(1_i64)])),

    # Exit normally
    X::Operation.new(X::Code::PUSH_STRING, X::ValueContext.new("normal")),
    X::Operation.new(X::Code::PROCESS_EXIT),
  ]
)

engine.processes.push(receiver)
engine.processes.push(sender)

engine.scheduler.enqueue(receiver)
engine.scheduler.enqueue(sender)

engine.run

# sleep 1.seconds
