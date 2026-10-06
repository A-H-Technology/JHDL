using Test

using JHDL

const u8 = VHDL.Unsigned(VHDL.Range(7, 0))

# Full round trip: generate a testbench for a real DUT, build and run it with
# GHDL, and read the captured outputs back into Julia.
@testset "e2e: registered adder through GHDL" begin
    Sys.which("ghdl") === nothing && error("ghdl not found on PATH; the e2e test needs it")

    mktempdir() do build
        dut = DUT(
            name="adder",
            generics=Generic[],
            ports=[
                Port("A", u8, 0, In),
                Port("B", u8, 0, In),
                Port("Y", u8, 0, Out),
            ],
        )
        tb = Testbench(
            name="adder_tb",
            generics=Generic[],
            constants=Constant[],
            signals=Port[],
            dut=dut,
        )

        construct_testbench(tb; directory=relpath(build))
        tb_file = joinpath(build, "adder_tb.vhd")
        @test isfile(tb_file)

        a = [1, 2, 3, 100, 200, 255]
        b = [1, 5, 7, 27, 55, 0]

        sim = Simulation(
            testbench=tb,
            sources=[joinpath(@__DIR__, "vhdl", "adder.vhd"), tb_file],
            build_directory=build,
            generics=Generic[],
            stims=[
                PortStim("A", u8, a, In),
                PortStim("B", u8, b, In),
                PortStim("Y", u8, Int[], Out),
            ],
        )

        outputs = simulate(sim)

        # The first sample is captured on the same edge the first inputs are applied
        @test compare([PortStim("Y", u8, a .+ b, Out)], outputs; latency=1)
        @test !compare([PortStim("Y", u8, a .+ b, Out)], outputs; latency=0)
    end
end
