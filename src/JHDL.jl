module JHDL

export Constant, DUT, Direction, Generic, In, InOut, Out, Port, PortStim, Simulation,
    Testbench, VHDL, Variable, compare, construct_testbench, simulate, to_Q_format,
    verify

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

    inputs = order_stims(sim.testbench.dut, sim.stims)
    outputs = [PortStim(p.name, p.type, Any[], p.dir) for p in sim.testbench.dut.ports if p.dir == Out || p.dir == InOut]

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


port_index(dut::DUT, name::AbstractString) = findfirst(p -> p.name == name, dut.ports)

# The testbench reads input columns in DUT port order, so stims have to be written in that order too
function order_stims(dut::DUT, stims::AbstractVector{PortStim})::Vector{PortStim}
    by_name = foldl(stims; init=Dict{String,PortStim}()) do d::Dict{String,PortStim}, stim::PortStim
        i = port_index(dut, stim.name)
        isnothing(i) && throw(ArgumentError("Stim \"$(stim.name)\" doesn't match any port of $(dut.name)"))
        port = dut.ports[i]
        port.dir == Out && throw(ArgumentError("Stim \"$(stim.name)\" is an output; outputs are captured, not stimulated"))
        stim.dir == port.dir || throw(ArgumentError("Stim \"$(stim.name)\" is $(stim.dir) but the port is $(port.dir)"))
        stim.type == port.type || throw(ArgumentError("Stim \"$(stim.name)\" is $(stim.type) but the port is $(port.type)"))
        haskey(d, stim.name) && throw(ArgumentError("Stim \"$(stim.name)\" is given twice"))
        d[stim.name] = stim
        d
    end
    inputs = PortStim[]
    for port in dut.ports
        port.dir == Out && continue
        haskey(by_name, port.name) || throw(ArgumentError("No stim for input \"$(port.name)\" of $(dut.name)"))
        push!(inputs, by_name[port.name])
    end
    return inputs
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
    N = maximum(x -> length(x.value), data; init=0)
    open(filename, "w") do io
        for i in 1:N
            for port in data
                if (i > length(port.value))
                    print(io, pad_field(port.type) * " ")
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
            tokens = split(line)

            isempty(tokens) && continue

            expected = sum(x -> field_tokens(x.type), output; init=0)
            length(tokens) == expected || throw(ArgumentError("Line $line_number of \"$filename\" has $(length(tokens)) fields, expected $expected"))

            k = 1
            for port in output
                n = field_tokens(port.type)
                try
                    push!(port.value, read_field(port.type, join(tokens[k:k+n-1], " ")))
                catch err
                    throw(ArgumentError("Failed to parse $(port.name) on line $line_number of \"$filename\". "*sprint(showerror, err)))
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
