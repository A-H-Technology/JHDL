include("testbench.jl")
using .VHDL

abstract type Frame end

Base.@kwdef struct Simulation
    testbench::Testbench
    sources::Vector{String}
    wave_path::String="waveform.fst"

    stop_time_ms::Int=5
end

function compare(expected::AbstractVector{PortStim}, actual::AbstractVector{PortStim}; tol::Union{Real,Nothing}=nothing)
    throw(ArgumentError("compare is not implemented for this simulation"))
end

function simulate(sim::Simulation)::AbstractVector{PortStim}
    directory = abspath(sim.directory)
    input_path = joinpath(directory, sim.testbench.input_path)
    output_path = joinpath(directory, sim.testbench.output_path)
    stims = vcat(sim.testbench.signals, sim.testbench.dut.ports)

    inputs = filter(x -> ((x.dir == In) || (x.dir == InOut)), stims)
    outputs = filter(x -> ((x.dir == Out) || (x.dir == InOut)), stims)

    mkpath(directory)

    isfile(output_path) && rm(output_path)

    write_test_data(inputs, input_path)

    println("Building project...")

    GHDL_build(sim)

    println("Running testbench $(sim.testbench.name)...")

    GHDL_run(sim)

    isfile(output_path) || throw(ErrorException("The testbench did not produce \"$(sim.testbench.output_path)\""))

    return read_test_data(outputs, output_path)
end


function verify(sim::Simulation, expected::AbstractVector{PortStim}, tol::Union{Real,Nothing}=nothing)::Bool

    actual = simulate(sim)

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


function write_test_data(data::AbstractVector{PortStim}, filename::AbstractString="samples.txt")::Nothing
    N = maximum(map(x -> length(x.value), data))
    open(filename, "w") do io
        for i in 1:N
            for port in data
                if (i > length(port.x.value))
                    print(io, write_field(port.type, nothing) * " ")
                else
                    print(io, write_field(port.type, port.x.value[i]) * " ")
                end
            end
            println()
        end
    end
    return nothing
end

function read_test_data!(output::AbstractVector{PortStim}, filename::AbstractString="results.txt",)
    open(filename, "r") do io
        for (line_number, line) in enumerate(eachline(io))
            stripped_line = strip(line)

            isempty(stripped_line) && continue

            fields = strip.(split(stripped_line, " "))

            for i in eachindex(fields)
                try
                    push!(output[i].value, read_field(output[i].type, fields[i]))
                catch err
                    throw(ArgumentError("Failed to parse field $i of line $line_number of \"$filename\"."*sprint(showerror, err)))
                end
            end
        end
    end
    return data
end


function convert_generics(generics::AbstractVector{Generic})::Vector{String}
    generics_strings = String[]
    for generic in generics
        push!(generics_strings, "-g$(generic)=$(write_field(generic.type,generic.value))")
    end
    return generics_strings
end


function GHDL_build(sim::Simulation)::Nothing

    directory = abspath(sim.testbench.directory)

    sources = abspath.(sim.sources)

    mkpath(directory)

    run(Cmd(
        `ghdl -i --std=08
            $sources`;
        dir=directory
    ))

    run(Cmd(
        `ghdl -m --std=08
            $(sim.name)`;
        dir=directory
    ))
    return nothing
end

function GHDL_run(sim::Simulation)::Nothing

    directory = abspath(sim.testbench.directory)


    mkpath(directory)

    generics = convert_generics(sim.testbench.dut.generics)

    wave_args = isempty(sim.wave_path) ? String[] : ["--fst=$(sim.wave_path)"]
    stop_time = sim.stop_time_ms < 0 ? String[] : ["$(sim.sim_time_ms)ms"]

    run(Cmd(
        `ghdl -r --std=08
            $(sim.name)
            $generics
            $wave_args
            --stop-time=$(stop_time)`;
        dir=directory
    ))
    return nothing
end

