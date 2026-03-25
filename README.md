# X

**A lightweight, Erlang-inspired virtual machine for concurrent, fault-tolerant applications in Crystal.**

[![Crystal](https://img.shields.io/badge/crystal-1.15+-blue?logo=crystal)](https://crystal-lang.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Build Status](https://github.com/konjac-lang/x/actions/workflows/ci.yml/badge.svg)](https://github.com/konjac-lang/x/actions)

This project combines a clean **stack-based bytecode interpreter** with **actor-model concurrency**, lightweight processes, message passing, supervision trees, and built-in fault tolerance - all implemented in pure Crystal.

Inspired by Erlang's BEAM, but designed to be simple, hackable, and embeddable.

## Features

- **Stack-based VM** - 120+ instructions across stack, arithmetic, logic, control flow, process, and message operations
- **Actor-model concurrency** - Lightweight processes with isolated stacks, mailboxes, and preemptive scheduling via reductions
- **Fault tolerance** - Process linking, monitoring, exit trapping, and supervision trees (one-for-one, one-for-all, rest-for-one)
- **XASM assembler** - Human-readable assembly language with modules, imports, exports, subroutines, and block-based control flow
- **Multi-module system** - `.require` with automatic file resolution, `.import`/`.export` for cross-module calls
- **Hot code reloading** - `.dynamic` modules can be reloaded at runtime without restarting processes
- **Elixir-style standard library** - IO, String, Integer, Float, Array, Map, Type modules with 80+ built-in functions
- **Interactive debugger** - Step, continue, breakpoints, stack/locals inspection, process filtering
- **Lambdas and closures** - First-class functions with captured variables
- **Exception handling** - try/catch/throw with stack unwinding
- **Pure Crystal** - No external dependencies beyond standard library

## Quick Start

### Installation

```bash
git clone https://github.com/konjac-lang/x.git
cd x
shards install
```

### Hello World

Create `hello.xasm`:

```xasm
.module Hello

.import IO.printLine/1

.process main
  push "Hello, World!"
  call IO.printLine/1

  push :normal
  exit
.end
```

Run it:

```bash
shards run -- hello.xasm
```

### Build the binary

```bash
shards build --release
./bin/x hello.xasm
```

## The XASM Language

XASM is a human-readable assembly language for the X VM. Every line is a verb - there are no implicit operations.

### Modules and Directives

Every `.xasm` file starts with a module declaration:

```xasm
.module MyApp.Main

; Import functions from other modules or standard library
.import IO.printLine/1
.import String.concatenate/2

; Require other modules (auto-resolved from disk)
.require "MyApp.Utils"

; Export functions for other modules to use
.export myFunction/1
```

### Processes

Processes are the unit of concurrency. Each process has its own stack, locals, and mailbox:

```xasm
.process main
  push "I am a process"
  call IO.printLine/1

  push :normal
  exit
.end
```

### Variables

Local variables are declared with `.local` and accessed with `load`/`store`:

```xasm
.process main
  .local name
  .local counter

  push "alice"
  store name

  push 0
  store counter

  load name
  call IO.printLine/1

  push :normal
  exit
.end
```

### Control Flow

Block-based control flow - no manual jump offsets:

```xasm
; If/else
load x
push 10
gt
if
  push "x is greater than 10"
  call IO.printLine/1
else
  push "x is 10 or less"
  call IO.printLine/1
end

; Loops
push 0
store i
loop
  load i
  push 10
  gte
  break_if

  load i
  inc
  store i
end

; Try/catch
try
  push "something dangerous"
  throw
catch
  push "caught it"
  call IO.printLine/1
end
```

### Subroutines

Reusable code blocks within a module:

```xasm
.subroutine greet
  .local name
  store name
  push "Hello, "
  load name
  call String.concatenate/2
  return
.end
```

### Message Passing

Processes communicate through messages:

```xasm
; Send a message to a named process
push "worker"
push "do something"
send

; Receive a message (blocks until one arrives)
receive

; Wait for a process to register
await "worker"
```

### Spawning Processes

```xasm
; Spawn a new process
spawn
  self
  register "worker"
  loop
    receive
    call IO.printLine/1
  end
end

; Spawn with a link (crash propagation)
spawn_link
  push "linked child"
  call IO.printLine/1
  push :normal
  exit
end
```

### Lambdas

```xasm
; Create a lambda capturing a variable
lambda [multiplier]
  load multiplier
  mul
  return
end

; Invoke with arity
push 5
invoke 1
```

### Hot Code Reloading

Mark a module as dynamic to enable live reloading:

```xasm
.module MyApp.Config
.dynamic

.export version/1

.subroutine version
  push "1.0.0"
  return
.end
```

Reload at runtime from another process:

```xasm
push "MyApp.Config"           ; module name to reload
push "MyApp.Config.v2"        ; file hint (resolved by module resolver)
reload
```

The new code is picked up by all processes on their next function call - no restart required.

### Supervision Trees

Declarative supervisor configuration:

```xasm
.supervisor pool :one_for_one max_restarts=3 window=5

  .child "logger" :permanent
    self
    register "logger"
    loop
      receive
      call IO.printLine/1
    end
  .end

  .child "worker" :transient
    push "working..."
    call IO.printLine/1
    push :normal
    exit
  .end

.end
```

## CLI

```
Usage: x [options] <file.xasm> [file2.xasm ...]

Options:
    -v, --version                    Show version
    -h, --help                       Show this help
    -d, --debug                      Enable debug logging
    -q, --quiet                      Suppress info logging
    -I PATH, --include PATH          Add search path for module resolution
    --ast                            Print the AST and exit
    --instructions                   Print compiled instructions and exit
    --debugger                       Launch interactive debugger
```

### Interactive Debugger

Launch with `--debugger` to step through execution:

```
-- Process <1> (room) @ instruction 0 --
  -> PROCESS_SELF
  Stack: (empty)
xdb>
```

Commands:

| Command | Short | Description |
|---------|-------|-------------|
| `step` | `s` | Execute one instruction |
| `next` | `n` | Step over subroutines |
| `continue` | `c` | Continue until next breakpoint |
| `run` | `r` | Run without stopping |
| `kill` | `k` | Kill current process |
| `stack` | `st` | Show full stack |
| `locals` | `l` | Show local variables |
| `mailbox` | `mb` | Show process mailbox |
| `processes` | `ps` | List all processes |
| `registry` | `reg` | Show named processes |
| `instructions` | `is` | Show nearby instructions |
| `callstack` | `cs` | Show call frames |
| `break <addr>` | `b` | Breakpoint at instruction |
| `break <name>` | `b` | Breakpoint on named process |
| `break <name>:<addr>` | `b` | Breakpoint on process at instruction |
| `filter <pid>` | `f` | Only break on one process |
| `eval <expr>` | `e` | Inspect values |
| `help` | `h` | Show all commands |
| `quit` | `q` | Exit |

Press Enter to repeat the last command.

## Standard Library

### IO

| Function | Description |
|----------|-------------|
| `IO.puts/1` | Print string with newline, returns `:ok` |
| `IO.print/1` | Print string without newline, returns `:ok` |
| `IO.printLine/1` | Alias for `IO.puts/1` |
| `IO.inspect/1` | Print inspect representation, returns the value |
| `IO.gets/0` | Read a line from stdin |

### String

| Function | Description |
|----------|-------------|
| `String.concatenate/2` | Concatenate two strings |
| `String.length/1` | String length |
| `String.reverse/1` | Reverse a string |
| `String.upcase/1` | Convert to uppercase |
| `String.downcase/1` | Convert to lowercase |
| `String.trim/1` | Strip whitespace from both ends |
| `String.trimLeading/1` | Strip leading whitespace |
| `String.trimTrailing/1` | Strip trailing whitespace |
| `String.split/2` | Split string by delimiter |
| `String.join/2` | Join array with separator |
| `String.contains/2` | Check if string contains substring |
| `String.startsWith/2` | Check prefix |
| `String.endsWith/2` | Check suffix |
| `String.replace/3` | Replace all occurrences |
| `String.slice/3` | Extract substring (string, start, length) |
| `String.at/2` | Character at index |
| `String.toInteger/1` | Parse to integer |
| `String.toFloat/1` | Parse to float |
| `String.toAtom/1` | Convert to atom/symbol |
| `String.duplicate/2` | Repeat string N times |
| `String.padLeading/3` | Pad start to width |
| `String.padTrailing/3` | Pad end to width |
| `String.toString/1` | Convert any value to string |

### Integer

| Function | Description |
|----------|-------------|
| `Integer.toString/1` | Convert to string |
| `Integer.toFloat/1` | Convert to float |
| `Integer.parse/1` | Parse string to integer |
| `Integer.isEven/1` | Check if even |
| `Integer.isOdd/1` | Check if odd |
| `Integer.digits/1` | Get array of digits |
| `Integer.gcd/2` | Greatest common divisor |

### Float

| Function | Description |
|----------|-------------|
| `Float.toString/1` | Convert to string |
| `Float.toInteger/1` | Truncate to integer |
| `Float.parse/1` | Parse string to float |
| `Float.round/2` | Round to N decimal places |
| `Float.ceil/1` | Ceiling |
| `Float.floor/1` | Floor |
| `Float.isNan/1` | Check for NaN |
| `Float.isInfinity/1` | Check for infinity |

### Array

| Function | Description |
|----------|-------------|
| `Array.new/0` | Create empty array |
| `Array.length/1` | Array length |
| `Array.size/1` | Alias for length |
| `Array.first/1` | First element |
| `Array.last/1` | Last element |
| `Array.at/2` | Element at index |
| `Array.get/2` | Alias for at |
| `Array.set/3` | Set element at index |
| `Array.append/2` | Add to end |
| `Array.prepend/2` | Add to start |
| `Array.push/2` | Alias for append |
| `Array.pop/1` | Remove last, returns [array, element] |
| `Array.concat/2` | Concatenate two arrays |
| `Array.reverse/1` | Reverse array |
| `Array.sort/1` | Sort array |
| `Array.uniq/1` | Remove duplicates |
| `Array.flatten/1` | Flatten one level |
| `Array.contains/2` | Check membership |
| `Array.indexOf/2` | Find index of element |
| `Array.slice/3` | Extract sub-array |
| `Array.take/2` | Take first N elements |
| `Array.drop/2` | Drop first N elements |
| `Array.zip/2` | Zip two arrays into pairs |
| `Array.isEmpty/1` | Check if empty |
| `Array.sum/1` | Sum of elements |
| `Array.product/1` | Product of elements |
| `Array.min/1` | Minimum element |
| `Array.max/1` | Maximum element |
| `Array.join/2` | Join elements with separator |

### Map

| Function | Description |
|----------|-------------|
| `Map.new/0` | Create empty map |
| `Map.put/3` | Set key-value pair |
| `Map.get/2` | Get value by key |
| `Map.getWithDefault/3` | Get with fallback |
| `Map.delete/2` | Remove key |
| `Map.hasKey/2` | Check if key exists |
| `Map.keys/1` | Get all keys |
| `Map.values/1` | Get all values |
| `Map.size/1` | Number of entries |
| `Map.merge/2` | Merge two maps |
| `Map.toArray/1` | Convert to array of [key, value] pairs |
| `Map.isEmpty/1` | Check if empty |

### Type

| Function | Description |
|----------|-------------|
| `Type.of/1` | Get type name as string |
| `Type.inspect/1` | Get inspect representation |
| `Type.toString/1` | Convert any value to string |
| `Type.isNull/1` | Check if null |
| `Type.isInteger/1` | Check if integer |
| `Type.isFloat/1` | Check if float |
| `Type.isString/1` | Check if string |
| `Type.isBoolean/1` | Check if boolean |
| `Type.isArray/1` | Check if array |
| `Type.isMap/1` | Check if map |
| `Type.isSymbol/1` | Check if symbol |
| `Type.isLambda/1` | Check if lambda |
| `Type.isNumeric/1` | Check if integer or float |

## Instruction Set Reference

### Stack Operations

| XASM | Description |
|------|-------------|
| `push <value>` | Push literal (string, integer, float, symbol, true, false, null) |
| `pop` | Discard top of stack |
| `dup` | Duplicate top |
| `over` | Copy second element to top |
| `swap` | Swap top two |
| `rot` | Rotate top three up |
| `-rot` | Rotate top three down |
| `nip` | Remove second element |
| `tuck` | Copy top below second |
| `depth` | Push stack depth |
| `pick` | Copy Nth element to top |
| `roll` | Move Nth element to top |

### Arithmetic

| XASM | Description |
|------|-------------|
| `add` | a + b |
| `sub` | a - b |
| `mul` | a * b |
| `div` | a / b |
| `mod` | a % b |
| `neg` | Negate |
| `abs` | Absolute value |
| `inc` | Increment by 1 |
| `dec` | Decrement by 1 |
| `pow` | Power |
| `floor` | Floor |
| `ceil` | Ceiling |
| `round` | Round |
| `min` | Minimum of two |
| `max` | Maximum of two |

### Bitwise

| XASM | Description |
|------|-------------|
| `band` | Bitwise AND |
| `bor` | Bitwise OR |
| `bxor` | Bitwise XOR |
| `bnot` | Bitwise NOT |
| `shl` | Shift left |
| `shr` | Shift right |
| `ushr` | Unsigned shift right |

### Comparison

| XASM | Description |
|------|-------------|
| `eq` | Equal |
| `neq` | Not equal |
| `ideq` | Identical (strict) |
| `nideq` | Not identical |
| `lt` | Less than |
| `lte` | Less than or equal |
| `gt` | Greater than |
| `gte` | Greater than or equal |
| `is_null` | Check null |
| `is_not_null` | Check not null |

### Logic

| XASM | Description |
|------|-------------|
| `and` | Logical AND |
| `or` | Logical OR |
| `not` | Logical NOT |
| `xor` | Logical XOR |

### Variables

| XASM | Description |
|------|-------------|
| `load <name>` | Push local variable onto stack |
| `store <name>` | Pop stack into local variable |
| `gload <name>` | Load global variable |
| `gstore <name>` | Store global variable |

### Control Flow

| XASM | Description |
|------|-------------|
| `if...else...end` | Conditional block |
| `loop...end` | Loop block |
| `break` | Exit loop |
| `break_if` | Exit loop if top is true |
| `break_unless` | Exit loop if top is false |
| `continue` | Jump to loop start |
| `call Module.func/arity` | Call built-in or module function |
| `return` | Return from subroutine |
| `nop` | No operation |
| `halt` | Halt execution |

### Process Operations

| XASM | Description |
|------|-------------|
| `self` | Push current process ID |
| `register <name>` | Register process with a name |
| `unregister <name>` | Remove name registration |
| `whereis <name>` | Look up process by name |
| `spawn...end` | Spawn a new process |
| `spawn_link...end` | Spawn with bidirectional link |
| `spawn_monitor...end` | Spawn with monitor |
| `exit` | Exit current process (reason on stack) |
| `kill` | Kill a process |
| `sleep` | Sleep for duration |
| `yield` | Yield to scheduler |
| `link` | Link to another process |
| `unlink` | Unlink from a process |
| `monitor` | Monitor a process |
| `demonitor` | Stop monitoring |
| `trap_on` | Enable exit signal trapping |
| `trap_off` | Disable exit signal trapping |
| `alive?` | Check if process is alive |
| `await <name>` | Wait for a process to register |

### Messages

| XASM | Description |
|------|-------------|
| `send` | Send message (name and value on stack) |
| `send_after` | Send message with delay |
| `receive` | Receive next message (blocks) |
| `receive_timeout` | Receive with timeout |
| `peek` | Peek at next message without consuming |
| `mailbox_size` | Push mailbox size |

### Exceptions

| XASM | Description |
|------|-------------|
| `try...catch...end` | Exception handling block |
| `throw` | Throw an exception |
| `rethrow` | Re-throw current exception |

### Hot Reload

| XASM | Description |
|------|-------------|
| `reload` | Reload a dynamic module (file hint and module name on stack) |

## Module Resolution

When you `.require "MyApp.Utils"`, the resolver searches for matching files in this order:

1. `MyApp/Utils.xasm`
2. `my_app/utils.xasm`
3. `my_app.utils.xasm`
4. `MyApp/utils.xasm`
5. `Utils.xasm`
6. `utils.xasm`
7. `MyApp.Utils.xasm`

Search roots include the directory of the entry file and any paths added with `-I`.

If no file matches by name, the resolver scans `.xasm` files for a matching `.module` declaration.

## Examples

The `examples/` directory contains working demos:

Run any example:

```bash
shards run -- examples/single_module/Stick.Messaging.xasm
shards run -- examples/chat/Chat.Main.xasm
shards run -- examples/dynamic/Dynamic.Main.xasm
```

## Architecture

```
                    XASM Source
                   (.xasm files)
                        |
                   +----v----+
                   |  Lexer  |  Tokenization
                   +----+----+
                   +----v----+
                   |  Parser |  AST generation
                   +----+----+
                   +----v---------+
                   | Code Generator|  Bytecode compilation
                   +----+---------+
                   +----v----+
                   |  Loader |  Module resolution, wiring
                   +----+----+
                        |
    +-------------------v---------------------+
    |            X VM Engine                   |
    |                                          |
    | +--------+  +--------+  +--------+      |
    | |Proc <1>|  |Proc <2>|  |Proc <N>|      |
    | | Stack  |  | Stack  |  | Stack  |      |
    | | Locals |  | Locals |  | Locals |      |
    | |Mailbox |  |Mailbox |  |Mailbox |      |
    | +--------+  +--------+  +--------+      |
    |                                          |
    | +--------------------------------------+ |
    | |           Scheduler                  | |
    | | Reduction-based preemptive scheduling| |
    | +--------------------------------------+ |
    |                                          |
    | +-------------+  +-------------------+   |
    | |Fault Handler|  |Supervisor Registry|   |
    | |Links/Monitors| |Restart strategies |   |
    | +-------------+  +-------------------+   |
    |                                          |
    | +--------------------------------------+ |
    | |    Built-in Function Registry        | |
    | | IO String Array Map Type Integer ... | |
    | +--------------------------------------+ |
    +------------------------------------------+
```

## Why X?

- **Learning** - Understand how actor-model VMs work from the inside
- **Embedding** - Drop a concurrent runtime into your Crystal application
- **Experimentation** - Build DSLs, game scripting engines, or workflow systems
- **Compiler target** - XASM is a clean compilation target for higher-level languages

## Contributing

1. Fork it (<https://github.com/konjac-lang/x/fork>)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## Contributors

- [Giorgi Kavrelishvili](https://github.com/grkek) - creator and maintainer
