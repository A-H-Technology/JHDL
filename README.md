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
    ports=[Port("A", u8, 0, In), Port("B", u8, 0, In), Port("Y", u8, 0, Out)],
)
tb = Testbench(name="adder_tb", generics=Generic[], constants=Constant[], signals=Port[], dut=dut)

construct_testbench(tb; directory="build")   # writes build/adder_tb.vhd

sim = Simulation(
    testbench=tb,
    sources=["adder.vhd", "build/adder_tb.vhd"],
    generics=Generic[],
    stims=[
        PortStim("A", u8, [1, 2, 3], In),
        PortStim("B", u8, [4, 5, 6], In),
    ],
)

outputs = simulate(sim)   # Y's captured values, one per clock cycle

# Y is registered, so its first valid sample comes one cycle in
verify(sim, [PortStim("Y", u8, [5, 7, 9], Out)]; latency=1)
```

The generated testbench drives `CLK` and `RST` for you. It holds reset for 5 cycles, feeds one row of inputs per cycle, and records the outputs on every rising edge. The DUT needs `CLK` and `RST` ports. After the last row, inputs go back to the initial values their `Port`s declare (a port declared with `nothing` keeps its last value).

By default the simulation runs `DRAIN_CYCLES` (20) cycles past the last row. For a DUT that takes an unknown time to finish, pass `finish_on="DONE"` to `Testbench`, naming a `std_logic` or `boolean` output. The simulation then ends on the first rising edge where that output is high, and the drain cycles only bound how long it may take. The edge where it went high is the last captured sample.

Vector outputs come back as integers, or `missing` for samples holding a metavalue (`U`, `X`, `Z`, ...). Stims are matched to input ports by name, in any order. Outputs are captured from every `Out`/`InOut` port, so don't pass stims for them. A stim shorter than the others is padded with `-` (or 0 for numeric types). `compare`/`verify` match outputs by name and skip the first `latency` samples.

## Tests

The e2e tests build and simulate three small DUTs (`test/vhdl/`) through GHDL. Unit tests cover the field reader/writer, stim matching, `finish_on` validation and `compare`:

```sh
julia --project=. test/runtests.jl
```

On Nix, `nix flake check` runs it in a sandbox.

## Status

Work in progress.
