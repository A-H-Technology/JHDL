include("VHDL.jl")
using .VHDL
import .VHDL: declare
@enum Direction In Out InOut




struct Port
    name::String
    type::VHDL.VHDLType
    value::Any
    dir::Direction
end

struct PortStim
    name::String
    type::VHDL.VHDLType
    value::Vector
    dir::Direction
end

struct Constant
    name::String
    type::VHDL.VHDLType
    value::Any
end

struct Generic
    name::String
    type::VHDL.VHDLType
    value::Any
end

struct Variable
    name::String
    type::VHDL.VHDLType
    value::Any
end

Base.@kwdef struct DUT
    name::String
    generics::Vector{Generic}
    ports::Vector{Port}
    clk::Port = Port("CLK", VHDL.std_logic(), 0, In)
    rst::Port = Port("RST", VHDL.std_logic(), 1, In)
end

Base.@kwdef struct Testbench
    name::String
    generics::Vector{Generic}
    constants::Vector{Constant}
    signals::Vector{Port}
    dut::DUT
    clk_period_ns::Constant = Constant("CLK_PERIOD", VHDL.Time(), 20)
    drain_cycles::Constant = Constant("DRAIN_CYCLES", VHDL.Integer(), 20)
end

std_vals::Set = Set(['0', '1', 'Z', 'H', 'L', 'W', 'X', 'U', '-'])

declare(p::Port) = "signal $(p.name) : $(p.type)" * (isnothing(p.value) ? "" : " := " * literal(p.type, p.value))
declare(g::Generic) = "$(g.name) : $(g.type)" * (isnothing(g.value) ? "" : " := " * literal(g.type, g.value))
declare(v::Variable) = "variable $(v.name) : $(v.type)" * (isnothing(v.value) ? "" : " := " * literal(v.type, v.value))
declare(c::Constant) = "constant $(c.name) : $(c.type)" * (isnothing(c.value) ? "" : " := " * literal(c.type, c.value))

literal(::Union{VHDL.std_logic_vector,VHDL.Signed,VHDL.Unsigned}, x::AbstractVector) = "\""*join(Int.(x))*"\""
function literal(t::VHDL.Unsigned, x::Integer)
    w = abs(t.range.first-t.range.last)+1
    return (x < 0 || x > (2^w)-1) ? throw(ArgumentError("Cannot convert $x to unsigned with $w bits")) : "\""*string(x, base=2, pad=w)*"\""
end
function literal(t::VHDL.std_logic_vector, x::Integer)
    w = abs(t.range.first-t.range.last)+1
    x < 0 ? (-2^(w-1) <= x || throw(ArgumentError("$x doesn't fit in $w bits"))) : (2^w-1 >= x || throw(ArgumentError("$x doesn't fit in $w bits")))
    return "\""*string(big(x) & ((big(1) << w) - 1), base=2, pad=w)*"\""
end
function literal(t::VHDL.Signed, x::Integer)
    w = abs(t.range.first-t.range.last)+1
    x < 0 ? (-2^(w-1) <= x || throw(ArgumentError("$x doesn't fit in $w bits"))) : (2^(w-1)-1 >= x || throw(ArgumentError("$x doesn't fit in $w bits")))

    return "\""*string(big(x) & ((big(1) << w) - 1), base=2, pad=w)*"\""
end
literal(::VHDL.std_logic, x) = "\'"*string(Int(x))*"\'"
literal(::VHDL.Character, x) = "\'"*string(x)*"\'"
literal(::VHDL.String, x) = "\""*string(x)*"\""
literal(::Union{VHDL.Integer,VHDL.Boolean,VHDL.Positive,VHDL.Natural}, x) = string(x)
literal(::VHDL.Time, x) = string(x)*" ns"


write_field(::Union{VHDL.std_logic_vector,VHDL.Signed,VHDL.Unsigned}, x::AbstractVector) = join(Int.(x))
write_field(::Any, x::AbstractString) = string(x)
function write_field(t::VHDL.Unsigned, x::Integer)
    w = abs(t.range.first-t.range.last)+1
    return (x < 0 || x > (2^w)-1) ? throw(ArgumentError("Cannot convert $x to unsigned with $w bits")) : string(x, base=2, pad=w)
end
function write_field(t::VHDL.std_logic_vector, x::Integer)
    w = abs(t.range.first-t.range.last)+1
    x < 0 ? (-2^(w-1) <= x || throw(ArgumentError("$x doesn't fit in $w bits"))) : (2^w-1 >= x || throw(ArgumentError("$x doesn't fit in $w bits")))
    return string(big(x) & ((big(1) << w) - 1), base=2, pad=w)
end
function write_field(t::VHDL.Signed, x::Integer)
    w = abs(t.range.first-t.range.last)+1
    x < 0 ? (-2^(w-1) <= x || throw(ArgumentError("$x doesn't fit in $w bits"))) : (2^(w-1)-1 >= x || throw(ArgumentError("$x doesn't fit in $w bits")))

    return string(big(x) & ((big(1) << w) - 1), base=2, pad=w)
end
write_field(::Union{VHDL.Integer,VHDL.Boolean,VHDL.Positive,VHDL.Natural,VHDL.std_logic,VHDL.Character,VHDL.String,VHDL.Time}, x) = string(x)
write_field(::VHDL.std_logic, ::Nothing) = "-"
write_field(t::VHDL.std_logic_vector, ::Nothing) = "-"^(abs(t.range.first-t.range.last)+1)
write_field(t, x::Nothing) = write_field(t, 0)

read_field(t::Union{VHDL.Integer,VHDL.Positive,VHDL.Natural,VHDL.Time}, x) = isnothing(tryparse(Int, x)) ? throw(ArgumentError("Cannot convert $x to a boolean")) : parse(Int, x)
read_field(t::VHDL.Boolean, x) = x == 1 ? true : (x == 0 ? false : throw(ArgumentError("Cannot convert $x to a boolean")))
read_field(t::VHDL.std_logic, x::AbstractString) = (length(x) == 1 && x[1] in std_vals) ? x[1] : throw(ArgumentError("Cannot convert $x to an std_logic"))
read_field(t::VHDL.std_logic, x::Char) = (x[1] in std_vals) ? x : throw(ArgumentError("Cannot convert $x to an std_logic"))
read_field(t::VHDL.std_logic, x::Integer) = (x == 1 || x == 0) ? Char(x) : throw(ArgumentError("Cannot convert $x to an std_logic"))
read_field(t::Union{VHDL.std_logic_vector,VHDL.Signed,VHDL.Unsigned}, x::Integer) = x
read_field(t::VHDL.std_logic_vector, x::AbstractString) = isnothing(tryparse(Int, x, base=2)) ? join(read_field.(VHDL.std_logic(), (split(string(x), "")))) : tryparse(Int, x, base=2)
read_field(t::VHDL.std_logic_vector, x::AbstractVector) = isnothing(tryparse(Int, join(Int.(x)), base=2)) ? throw(ArgumentError("Cannot convert $x to an std_logic_vector")) : tryparse(Int, join(Int.(x)), base=2)

read_field(t::Union{VHDL.Signed,VHDL.Unsigned}, x::AbstractString) = isnothing(tryparse(Int, x, base=2)) ? (isnothing(tryparse(Int, x)):throw(ArgumentError("Cannot convert $x to $(typeof(t))"))) : tryparse(Int, x, base=2)
read_field(t::Union{VHDL.Signed,VHDL.Unsigned}, x::AbstractVector) = isnothing(tryparse(Int, join(Int.(x)), base=2)) ? (isnothing(tryparse(Int, join(Int.(x)))) ? throw(ArgumentError("Cannot convert $x to $(typeof(t))")) : tryparse(Int, join(Int.(x)))) : tryparse(Int, join(Int.(x)), base=2)

read_field(t::VHDL.String, x) = string(x)
read_field(t::VHDL.Character, x::AbstractString) = (length(x) == 1) ? x[1] : throw(ArgumentError("Cannot convert $x to a character"))
read_field(t::VHDL.Character, x::Char) = x
read_field(t::VHDL.Character, x::Integer) = 0 <= x < 10 ? string(x)[1] : throw(ArgumentError("Cannot convert $x to a character"))


function construct_testbench(testbench::Testbench; directory::AbstractString="build")
    input_file::Generic = Generic("INPUT_FILE", VHDL.String(), "samples.txt")
    output_file::Generic = Generic("OUTPUT_FILE", VHDL.String(), "output.txt")
    root_dir = abspath(".")
    tb_dir = root_dir*"/"*directory*"/"
    mkpath(tb_dir)

    lines = String[]

    # Library and Package Declaration 
    push!(lines, "library IEEE;")
    push!(lines, "use IEEE.std_logic_1164.all;")
    push!(lines, "use IEEE.numeric_std.all;")
    push!(lines, "use std.textio.all;")
    push!(lines, "use std.env.all;")

    # Entity Declaration
    push!(lines, "entity $(testbench.name)  is")
    generics = vcat(testbench.generics, testbench.dut.generics, input_file, output_file)
    if !(isempty(generics))
        N = length(generics)
        push!(lines, "generic (")
        for i in 1:N
            push!(lines, declare(generics[i])*(i < N ? ";" : ""))
        end
        push!(lines, ");")
    end
    push!(lines, "end entity;")

    # Architecture
    push!(lines, "architecture SIM of $(testbench.name)  is")

    # Declarations
    constants = vcat(testbench.constants, testbench.clk_period_ns, testbench.drain_cycles)
    for constant in constants
        push!(lines, declare(constant) * ";")
    end
    signals = vcat(testbench.signals, testbench.dut.ports, testbench.dut.clk, testbench.dut.rst)
    for signal in signals
        push!(lines, declare(signal) * ";")
    end

    push!(lines, "file in_file : text open read_mode is $(input_file.name);")
    push!(lines, "file out_file : text open write_mode is $(output_file.name);")
    # Begin
    push!(lines, "begin")

    # Dut Declaration
    push!(lines, "DUT : entity work.$(testbench.dut.name)")

    ports = vcat(testbench.dut.ports, testbench.dut.clk, testbench.dut.rst)
    # Generic Map
    if !(isempty(testbench.dut.generics))
        N = length(testbench.dut.generics)
        push!(lines, "generic map( ")
        for i in 1:N
            push!(lines, "$(testbench.dut.generics[i].name) => $(testbench.dut.generics[i].name)" * (i < N ? "," : ""))
        end
        push!(lines, ")" * (isempty(ports) ? ";" : ""))
    end

    # Port Map
    if !(isempty(ports))
        N = length(ports)
        push!(lines, "port map( ")
        for i in 1:N
            push!(lines, "$(ports[i].name) => $(ports[i].name)" * (i < N ? "," : ""))
        end
        push!(lines, ");")
    end

    # CLK
    push!(lines, "$(testbench.dut.clk.name) <= not $(testbench.dut.clk.name) after $(testbench.clk_period_ns.name)/2;")

    # Reset Process
    # Should perhaps be conditional?
    push!(lines, "reset : process")
    push!(lines, "begin")
    push!(lines, "$(testbench.dut.rst.name) <= '1';")
    push!(lines, "wait for 5*$(testbench.clk_period_ns.name);")
    push!(lines, "$(testbench.dut.rst.name) <= '0';")
    push!(lines, "wait;")
    push!(lines, "end process;")

    # Stim Process


    push!(lines, "stim : process")

    # Stim Variables
    inputs = filter(x -> x.dir == In || x.dir == InOut, testbench.dut.ports)

    for input in inputs
        push!(lines, "variable v_$(input.name) : $(input.type);")
    end

    push!(lines, "variable L : line;")

    push!(lines, "begin")


    # Read Input Data and Apply Stim
    push!(lines, "wait until $(testbench.dut.rst.name) = '0';")

    push!(lines, "while not endfile(in_file) loop")

    push!(lines, "readline(in_file,L);")

    push!(lines, "next when L = null or L.all'length = 0;")

    for input in inputs
        push!(lines, "read(L,v_$(input.name));")
    end

    for input in inputs
        push!(lines, "$(input.name) <= v_$(input.name);")
    end

    push!(lines, "wait until rising_edge($(testbench.dut.clk.name));")
    push!(lines, "end loop;")

    push!(lines, "wait for $(testbench.drain_cycles.name) * $(testbench.clk_period_ns.name);")
    push!(lines, "finish;")

    push!(lines, "end process;")


    # Capture Process

    outputs = filter(x -> x.dir == Out || x.dir == InOut, testbench.dut.ports)

    if !(isempty(outputs))
        push!(lines, "capture : process")
        # Capture Variables

        push!(lines, "variable L : line;")


        push!(lines, "begin")

        push!(lines, "wait until $(testbench.dut.rst.name) = '0';")

        # Capture Output

        push!(lines, "loop")

        push!(lines, "wait until rising_edge($(testbench.dut.clk.name));")

        for output in outputs
            push!(lines, "write(L,$(output.name));")
            push!(lines, "write(L, \' \');")
        end
        push!(lines, "writeline(out_file, L);")

        push!(lines, "end loop;")
        push!(lines, "end process;")
    end

    push!(lines, "end architecture;")

    filename = joinpath(tb_dir, testbench.name * ".vhd")

    isfile(filename) && rm(filename)

    open(filename, "w") do io
        for line in lines
            println(io, line)
        end
    end
end

