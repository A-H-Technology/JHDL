# JHDL

A Julia framework for running configurable testbenches with [GHDL](https://github.com/ghdl/ghdl).

You point JHDL at your DUT's VHDL (or describe its ports in Julia), JHDL generates a VHDL-2008 testbench for it, builds and runs it with GHDL, and gives the outputs back to you as Julia vectors.

## Requirements

- Julia
- GHDL on your `PATH`

On Nix, `nix develop` gives you both.

## Example

```julia
using JHDL   # with `julia --project=path/to/JHDL`, or after `Pkg.develop`

u8 = VHDL.Unsigned(VHDL.Range(7, 0))

# Ports and generics are read from the entity in adder.vhd, through GHDL
dut = DUT("adder.vhd"; init=(A=0, B=0))
tb = Testbench(name="adder_tb", generics=Generic[], constants=Constant[], signals=Port[], dut=dut)

sim = Simulation(testbench=tb, sources=["adder.vhd"], generics=Generic[])

# Generates build/adder_tb.vhd, then builds and runs it with one value per cycle for each input
out = simulate(sim; A=[1, 2, 3], B=[4, 5, 6])

# Y is registered, so its first valid sample comes one cycle in
out.Y[2:4] == [5, 7, 9]
```

The generated testbench drives `CLK` and `RST` for you. It holds reset for 5 cycles, feeds one row of inputs per cycle, and records the outputs on every rising edge. The DUT needs `CLK` and `RST` ports (`DUT(file; clk=..., rst=...)` if they're named differently).

`DUT(file)` reads the entity with `ghdl --file-to-xml`. Port names keep their spelling from the source. Vector ranges may use generics (`WIDTH-1 downto 0`) and are evaluated with the generics' defaults. If the file declares several entities, pick one with `entity=`. Supported port types are the ones in `VHDL`: `std_logic`, `std_logic_vector`, `signed`, `unsigned`, `boolean`, `integer`, `natural`, `positive`, `character`, `string` and `time`.

You can also declare the ports by hand with `DUT(name=..., generics=..., ports=(A=In(u8), Y=Out(u8)))`. Ports are declared with `In(type)`, `Out(type)` or `InOut(type)`, in the order you write them. `init=` gives the signal an initial value. After the last row, inputs go back to that value; an input without one keeps its last value.

By default the simulation runs `DRAIN_CYCLES` (20) cycles past the last row. For a DUT that takes an unknown time to finish, pass `finish_on="DONE"` to `Testbench`, naming a `std_logic` or `boolean` output. The simulation then ends on the first rising edge where that output is high, and the drain cycles only bound how long it may take. The edge where it went high is the last captured sample.

Vector outputs come back as integers, or `missing` for samples holding a metavalue (`U`, `X`, `Z`, ...). `simulate` takes one keyword argument per input port, a vector with one value per cycle; their types come from the ports. It returns a NamedTuple with a vector for every `Out`/`InOut` port. A stim shorter than the others is padded with `-` (or 0 for numeric types).

### Test cases

A `TestCase` holds one test's data. `verify(sim, case)` drives the DUT with `stims(case)` and passes the outputs to the `compare` method for the case's type:

```julia
struct AdderCase <: TestCase
    A::Vector{Int}
    B::Vector{Int}
end

# Y is registered, so it lags the inputs by a cycle
JHDL.compare(c::AdderCase, actual) = actual.Y[2:length(c.A)+1] == c.A .+ c.B

verify(sim, AdderCase([1, 2, 3], [4, 5, 6]))                  # true
verify(sim, AdderCase(rand(0:127, 100), rand(0:127, 100)))    # same sim, another case
```

By default `stims(case)` takes every field of the case, by name, so the fields above are the adder's inputs. A case that carries anything else, like expected values or a tolerance, defines `stims` itself:

```julia
struct Scaled <: TestCase
    x::Vector{Float64}
    tol::Float64
end
JHDL.stims(c::Scaled) = (X=to_Q_format.(c.x, 1, 7),)
```

`compare` has no general implementation, because what counts as a match (latency, tolerance, cycles to skip) depends on the design. A case without a `compare` method throws.

## Tests

The e2e tests build and simulate three small DUTs (`test/vhdl/`) through GHDL. Unit tests cover the field reader/writer, reading entities from VHDL, port declarations, stim building, test cases and `finish_on` validation:

```sh
julia --project=. test/runtests.jl
```

On Nix, `nix develop` symlinks `Manifest.toml` to the environment nix built EzXML into, and `nix flake check` runs the tests in a sandbox. Elsewhere, run `Pkg.instantiate()` first.

## Status

Work in progress.
