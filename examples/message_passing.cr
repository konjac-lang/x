require "../src/x"

Log.setup(:debug)

engine = X::Engine::Context.new

engine.register_built_in_function("IO", "printLine", 1) do |engine, process, arguments|
  puts arguments[0].to_s
  X::Value::Context.null
end

# Process 1: Receiver - waits for messages and prints them
receiver = engine.create_process(
  instructions: [
    # Register this process as "receiver"
    X::Instruction::Operation.new(X::Instruction::Code::PROCESS_SELF),
    X::Instruction::Operation.new(X::Instruction::Code::PROCESS_REGISTER, X::Value::Context.new("receiver")),

    # Wait for and print first message
    X::Instruction::Operation.new(X::Instruction::Code::MESSAGE_RECEIVE),
    X::Instruction::Operation.new(
      X::Instruction::Code::CONTROL_CALL_BUILT_IN_FUNCTION,
      X::Value::Context.new(
        [
          X::Value::Context.new("IO"),
          X::Value::Context.new("printLine"),
          X::Value::Context.new(1_i64),
        ]
      )
    ),

    # Wait for and print second message
    X::Instruction::Operation.new(X::Instruction::Code::MESSAGE_RECEIVE),
    X::Instruction::Operation.new(
      X::Instruction::Code::CONTROL_CALL_BUILT_IN_FUNCTION,
      X::Value::Context.new(
        [
          X::Value::Context.new("IO"),
          X::Value::Context.new("printLine"),
          X::Value::Context.new(1_i64),
        ]
      )
    ),

    # Exit normally
    X::Instruction::Operation.new(X::Instruction::Code::PUSH_STRING, X::Value::Context.new("normal")),
    X::Instruction::Operation.new(X::Instruction::Code::PROCESS_EXIT),
  ]
)

# Process 2: Sender - sends messages to the receiver
sender = engine.create_process(
  instructions: [
    # Yield to let receiver register first
    X::Instruction::Operation.new(X::Instruction::Code::PROCESS_YIELD),

    # Send first message to "receiver"
    X::Instruction::Operation.new(X::Instruction::Code::PUSH_STRING, X::Value::Context.new("receiver")),
    X::Instruction::Operation.new(X::Instruction::Code::PUSH_CUSTOM, X::Value::Context.new({"hello" => "world"})),
    X::Instruction::Operation.new(X::Instruction::Code::MESSAGE_SEND),

    # Send second message
    X::Instruction::Operation.new(X::Instruction::Code::PUSH_STRING, X::Value::Context.new("receiver")),
    X::Instruction::Operation.new(X::Instruction::Code::PUSH_STRING, X::Value::Context.new("Hello, World!")),
    X::Instruction::Operation.new(X::Instruction::Code::MESSAGE_SEND),

    # Print confirmation
    X::Instruction::Operation.new(X::Instruction::Code::PUSH_STRING, X::Value::Context.new("Sender: Messages sent!")),
    X::Instruction::Operation.new(
      X::Instruction::Code::CONTROL_CALL_BUILT_IN_FUNCTION,
      X::Value::Context.new(
        [
          X::Value::Context.new("IO"),
          X::Value::Context.new("printLine"),
          X::Value::Context.new(1_i64),
        ]
      )
    ),

    # Exit normally
    X::Instruction::Operation.new(X::Instruction::Code::PUSH_STRING, X::Value::Context.new("normal")),
    X::Instruction::Operation.new(X::Instruction::Code::PROCESS_EXIT),
  ]
)

engine.processes.push(receiver)
engine.processes.push(sender)

engine.scheduler.enqueue(receiver)
engine.scheduler.enqueue(sender)

engine.run

sleep 1.seconds
