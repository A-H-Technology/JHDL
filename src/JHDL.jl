module JHDL

export Constant, DUT, Direction, Generic, In, InOut, Out, Port, Simulation,
    Testbench, VHDL, Variable, compare, construct_testbench, simulate, to_Q_format,
    verify

include("testbench.jl")
include("entity.jl")

abstract type Frame end

Base.@kwdef struct Simulation
    testbench::Testbench
    sources::Vector{String}
    build_directory::String="build/"
    generics::Vector{Generic}

    wave_path::String="waveform.fst"
    input_path::String="samples.txt"
    output_path::String="output.txt"

    stop_time_ms::Int=5
end

function compare(expected::NamedTuple, actual::NamedTuple; tol::Union{Real,Nothing}=nothing)
    throw(ArgumentError("compare is not implemented for this simulation"))
end

# Generates the testbench, runs it with one input value per cycle for each input port,
# given as keyword arguments (`simulate(sim; A=[1, 2], B=[3, 4])`), and returns the
# captured outputs as a NamedTuple of vectors, one value per cycle (`out.Y`).
function simulate(sim::Simulation; stims...)::NamedTuple
    build_directory = abspath(sim.build_directory)

    input_path = joinpath(build_directory, sim.input_path)
    output_path = joinpath(build_directory, sim.output_path)

    dut = sim.testbench.dut
    inputs = input_columns(dut, values(stims))
    outputs = [Column(p.name, p.type, Any[]) for p in dut.ports if p.dir != In]

    mkpath(build_directory)

    isfile(output_path) && rm(output_path)

    tb_file = construct_testbench(sim.testbench; directory=build_directory)

    write_test_data(inputs, input_path)

    println("Building project...")

    GHDL_build(sim, tb_file)

    println("Running testbench $(sim.testbench.name)...")

    GHDL_run(sim)

    isfile(output_path) || throw(ErrorException("The testbench did not produce \"$(sim.output_path)\""))

    read_test_data!(outputs, output_path)
    return NamedTuple(Symbol(c.name) => c.values for c in outputs)
end


# Built by walking dut.ports, the same list construct_testbench takes its read order
# and types from, so the columns of the input file can't come out in a different order
function input_columns(dut::DUT, stims::NamedTuple)::Vector{Column}
    inputs = filter(p -> p.dir != Out, dut.ports)
    for name in keys(stims)
        any(p -> p.name == String(name), inputs) || throw(ArgumentError("Stim \"$name\" isn't an input of $(dut.name)"))
    end
    return map(inputs) do port
        name = Symbol(port.name)
        haskey(stims, name) || throw(ArgumentError("No stim for input \"$name\" of $(dut.name)"))
        stim = stims[name]
        stim isa AbstractVector || throw(ArgumentError("Stim \"$name\" has to be a vector, one value per cycle"))
        Column(port.name, port.type, collect(stim))
    end
end


function verify(sim::Simulation, expected::NamedTuple, tol::Union{Real,Nothing}=nothing; stims...)::Bool

    actual = simulate(sim; stims...)

    println("Comparing results...")

    passed = compare(expected, actual; tol=tol)

    println(passed ? "PASS" : "FAIL")

    return passed
end


function to_Q_format(x::Real, N::Integer, M::Integer)::BigInt

    N >= 1 || throw(ArgumentError("N must include at least one sign bit"))

    M >= 0 || throw(ArgumentError("M must be nonnegative"))

    scale::BigInt = big(1) << M

    limit::BigInt = big(1) << (M+N-1)

    y::BigInt = round(BigInt, x * scale)

    # Check if the number will fit
    if (y >= limit || y < -limit)
        throw(OverflowError("$x does not fit in signed Q$N.$M"))
    end
    return y
end


function write_test_data(data::AbstractVector{Column}, filename::AbstractString="samples.txt")::Nothing
    N = maximum(x -> length(x.values), data; init=0)
    open(filename, "w") do io
        for i in 1:N
            for column in data
                if (i > length(column.values))
                    print(io, pad_field(column.type) * " ")
                else
                    print(io, write_field(column.type, column.values[i]) * " ")
                end
            end
            println(io)
        end
    end
    return nothing
end

function read_test_data!(output::AbstractVector{Column}, filename::AbstractString="results.txt",)
    open(filename, "r") do io
        for (line_number, line) in enumerate(eachline(io))
            tokens = split(line)

            isempty(tokens) && continue

            expected = sum(x -> field_tokens(x.type), output; init=0)
            length(tokens) == expected || throw(ArgumentError("Line $line_number of \"$filename\" has $(length(tokens)) fields, expected $expected"))

            k = 1
            for column in output
                n = field_tokens(column.type)
                try
                    push!(column.values, read_field(column.type, join(tokens[k:k+n-1], " ")))
                catch err
                    throw(ArgumentError("Failed to parse $(column.name) on line $line_number of \"$filename\". "*sprint(showerror, err)))
                end
                k += n
            end
        end
    end
    return output
end


function convert_generics(generics::AbstractVector{Generic})::Vector{String}
    generics_strings = String[]
    for generic in generics
        push!(generics_strings, "-g$(generic.name)=$(write_field(generic.type,generic.value))")
    end
    return generics_strings
end


function GHDL_build(sim::Simulation, tb_file::AbstractString)::Nothing

    build_directory = abspath(sim.build_directory)

    sources = [abspath.(sim.sources); tb_file]

    mkpath(build_directory)

    run(Cmd(
        `ghdl -i --std=08
            $sources`;
        dir=build_directory
    ))

    run(Cmd(
        `ghdl -m --std=08
            $(sim.testbench.name)`;
        dir=build_directory
    ))
    return nothing
end

function GHDL_run(sim::Simulation)::Nothing

    build_directory = abspath(sim.build_directory)


    mkpath(build_directory)

    generics = convert_generics(sim.generics)
    push!(generics, "-gINPUT_FILE="*sim.input_path)
    push!(generics, "-gOUTPUT_FILE="*sim.output_path)

    wave_args = isempty(sim.wave_path) ? String[] : ["--fst=$(sim.wave_path)"]

    run(Cmd(
        `ghdl -r --std=08
            $(sim.testbench.name)
            $generics
            $wave_args
            --stop-time=$(sim.stop_time_ms)ms`;
        dir=build_directory
    ))
    return nothing
end


end
