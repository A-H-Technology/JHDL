# JHDL

A Julia framework for running configurable testbenches with [GHDL](https://github.com/ghdl/ghdl).

You describe your DUT and its ports in Julia, JHDL generates a VHDL-2008 testbench for it, builds and runs it with GHDL, and gives the outputs back to you as Julia vectors.

## Requirements

- Julia
- GHDL on your `PATH`

## Example

```julia
include("src/JHDL.jl")

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
        PortStim("Y", u8, Int[], Out),
    ],
)

outputs = simulate(sim)   # Y's captured values, one per clock cycle
```

The generated testbench drives `CLK` and `RST` for you. It holds reset for 5 cycles, feeds one row of inputs per cycle, and records the outputs on every rising edge. The DUT needs `CLK` and `RST` ports.

## Tests

The e2e test builds and simulates a small registered adder (`test/vhdl/adder.vhd`) through GHDL:

```sh
julia test/runtests.jl
```

On Nix, run `nix shell nixpkgs#ghdl --command julia test/runtests.jl`.

## Status

Work in progress. `compare`/`verify` aren't implemented yet.
