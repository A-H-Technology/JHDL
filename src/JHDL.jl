module JHDL

export VHDL, Direction, In, Out, InOut, Port, PortStim, Constant, Generic, Variable, DUT, Testbench,
    Simulation, construct_testbench, simulate, verify, compare, to_Q_format

include("testbench.jl")

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

    stims::Vector{PortStim}
end

function compare(expected::AbstractVector{PortStim}, actual::AbstractVector{PortStim}; tol::Union{Real,Nothing}=nothing, latency::Integer=0)::Bool
    latency >= 0 || throw(ArgumentError("latency must be nonnegative"))
    passed = true
    for e in expected
        i = findfirst(a -> a.name == e.name, actual)
        isnothing(i) && throw(ArgumentError("No captured output named \"$(e.name)\""))
        got = actual[i].value[latency+1:end]
        if length(got) < length(e.value)
            println("$(e.name): expected $(length(e.value)) samples, only $(length(got)) captured after latency $latency")
            passed = false
            continue
        end
        for (k, (want, have)) in enumerate(zip(e.value, got))
            if !sample_matches(want, have, tol)
                println("$(e.name)[$k]: expected $(repr(want)), got $(repr(have))")
                passed = false
                break
            end
        end
    end
    return passed
end

sample_matches(want::Real, have::Real, tol::Real) = abs(want - have) <= tol
sample_matches(want, have, _) = isequal(want, have)

function simulate(sim::Simulation)::AbstractVector{PortStim}
    build_directory = abspath(sim.build_directory)

    input_path = joinpath(build_directory, sim.input_path)
    output_path = joinpath(build_directory, sim.output_path)

    inputs = filter(x -> ((x.dir == In) || (x.dir == InOut)), sim.stims)
    # Fresh vectors so reading results never mutates the caller's stims
    outputs = [PortStim(x.name, x.type, Any[], x.dir) for x in sim.stims if x.dir == Out || x.dir == InOut]

    mkpath(build_directory)

    isfile(output_path) && rm(output_path)

    write_test_data(inputs, input_path)

    println("Building project...")

    GHDL_build(sim)

    println("Running testbench $(sim.testbench.name)...")

    GHDL_run(sim)

    isfile(output_path) || throw(ErrorException("The testbench did not produce \"$(sim.output_path)\""))

    return read_test_data!(outputs, output_path)
end


function verify(sim::Simulation, expected::AbstractVector{PortStim}; tol::Union{Real,Nothing}=nothing, latency::Integer=0)::Bool

    actual = simulate(sim)

    println("Comparing results...")

    passed = compare(expected, actual; tol=tol, latency=latency)

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
                if (i > length(port.value))
                    print(io, write_field(port.type, nothing) * " ")
                else
                    print(io, write_field(port.type, port.value[i]) * " ")
                end
            end
            println(io)
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
    return output
end


function convert_generics(generics::AbstractVector{Generic})::Vector{String}
    generics_strings = String[]
    for generic in generics
        push!(generics_strings, "-g$(generic)=$(write_field(generic.type,generic.value))")
    end
    return generics_strings
end


function GHDL_build(sim::Simulation)::Nothing

    build_directory = abspath(sim.build_directory)

    sources = abspath.(sim.sources)

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
