# JHDL

A Julia framework for running configurable testbenches with [GHDL](https://github.com/ghdl/ghdl).

You describe your DUT and its ports in Julia, JHDL generates a VHDL-2008 testbench for it, builds and runs it with GHDL, and gives the outputs back to you as Julia vectors.

## Requirements

- Julia
- GHDL on your `PATH`

On Nix, `nix develop` gives you both.

## Example

```julia
using JHDL   # with `julia --project=path/to/JHDL`, or after `Pkg.develop`

u8 = VHDL.Unsigned(VHDL.Range(7, 0))

dut = DUT(
    name="adder",
    generics=Generic[],
    ports=(A=In(u8; init=0), B=In(u8; init=0), Y=Out(u8; init=0)),
)
tb = Testbench(name="adder_tb", generics=Generic[], constants=Constant[], signals=Port[], dut=dut)

sim = Simulation(testbench=tb, sources=["adder.vhd"], generics=Generic[])

# Generates build/adder_tb.vhd, then builds and runs it with one value per cycle for each input
out = simulate(sim; A=[1, 2, 3], B=[4, 5, 6])

# Y is registered, so its first valid sample comes one cycle in
out.Y[2:4] == [5, 7, 9]
```

The generated testbench drives `CLK` and `RST` for you. It holds reset for 5 cycles, feeds one row of inputs per cycle, and records the outputs on every rising edge. The DUT needs `CLK` and `RST` ports. Ports are declared with `In(type)`, `Out(type)` or `InOut(type)`, in the order you write them. `init=` gives the signal an initial value. After the last row, inputs go back to that value; an input without one keeps its last value.

By default the simulation runs `DRAIN_CYCLES` (20) cycles past the last row. For a DUT that takes an unknown time to finish, pass `finish_on="DONE"` to `Testbench`, naming a `std_logic` or `boolean` output. The simulation then ends on the first rising edge where that output is high, and the drain cycles only bound how long it may take. The edge where it went high is the last captured sample.

Vector outputs come back as integers, or `missing` for samples holding a metavalue (`U`, `X`, `Z`, ...). `simulate` takes one keyword argument per input port, a vector with one value per cycle; their types come from the ports. It returns a NamedTuple with a vector for every `Out`/`InOut` port. A stim shorter than the others is padded with `-` (or 0 for numeric types). `compare` is a stub that throws; `verify` needs a `compare` method for your outputs.

## Tests

The e2e tests build and simulate three small DUTs (`test/vhdl/`) through GHDL. Unit tests cover the field reader/writer, port declarations, stim building and `finish_on` validation:

```sh
julia --project=. test/runtests.jl
```

On Nix, `nix flake check` runs it in a sandbox.

## Status

Work in progress.
