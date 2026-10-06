using Test
using JHDL
import JHDL: write_field, read_field, write_test_data, read_test_data!, convert_generics, order_stims

const u8 = VHDL.Unsigned(VHDL.Range(7, 0))
const s8 = VHDL.Signed(VHDL.Range(7, 0))
const v4 = VHDL.std_logic_vector(VHDL.Range(3, 0))

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

        construct_testbench(tb; directory=build)
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
            ],
        )

        outputs = simulate(sim)

        # The first sample is captured on the same edge the first inputs are applied
        @test compare([PortStim("Y", u8, a .+ b, Out)], outputs; latency=1)
        @test !compare([PortStim("Y", u8, a .+ b, Out)], outputs; latency=0)
    end
end

@testset "e2e: mixed port types, generic override, shuffled and short stims" begin
    mktempdir() do build
        dut = DUT(
            name="mixed",
            generics=[Generic("OFFSET", VHDL.Integer(), 0)],
            ports=[
                Port("S", s8, 0, In),
                Port("V", v4, 0, In),
                Port("EN", VHDL.Boolean(), false, In),
                Port("N", VHDL.Integer(), 0, In),
                Port("SO", s8, 0, Out),
                Port("VO", v4, 0, Out),
                Port("BO", VHDL.Boolean(), false, Out),
                Port("NO", VHDL.Integer(), 0, Out),
            ],
        )
        tb = Testbench(name="mixed_tb", generics=Generic[], constants=Constant[], signals=Port[], dut=dut)
        construct_testbench(tb; directory=build)

        s = [-5, 100, -128, 0]
        v = [0b0000, 0b1010, 0b1111, 0b0110]
        en = [true, false, true, false]
        n = [1, -7]

        sim = Simulation(
            testbench=tb,
            sources=[joinpath(@__DIR__, "vhdl", "mixed.vhd"), joinpath(build, "mixed_tb.vhd")],
            build_directory=build,
            generics=[Generic("OFFSET", VHDL.Integer(), 3)],
            stims=[
                PortStim("N", VHDL.Integer(), n, In),
                PortStim("EN", VHDL.Boolean(), en, In),
                PortStim("V", v4, v, In),
                PortStim("S", s8, s, In),
            ],
        )

        @test verify(sim, [
                PortStim("SO", s8, s .+ 3, Out),
                PortStim("VO", v4, 0b1111 .⊻ v, Out),
                PortStim("BO", VHDL.Boolean(), .!en, Out),
                PortStim("NO", VHDL.Integer(), [2 .* n; 0; 0], Out),
            ]; latency=1)
    end
end

@testset "no method ambiguities" begin
    @test isempty(Test.detect_ambiguities(JHDL; recursive=true))
end

@testset "write_field" begin
    @test write_field(VHDL.Unsigned(VHDL.Range(63, 0)), 5) == "0"^61 * "101"
    @test write_field(VHDL.Unsigned(VHDL.Range(63, 0)), typemax(UInt64)) == "1"^64
    @test write_field(s8, -1) == "11111111"
    @test_throws ArgumentError write_field(s8, 128)
    @test_throws ArgumentError write_field(u8, -1)
    @test write_field(VHDL.Integer(), "5") == "5"
    @test write_field(VHDL.Time(), 20) == "20 ns"
    @test convert_generics([Generic("N", VHDL.Integer(), 8)]) == ["-gN=8"]
end

@testset "read_field" begin
    @test read_field(s8, "11111111") == -1
    @test read_field(s8, "01111111") == 127
    @test read_field(u8, "11111111") == 255
    @test read_field(v4, "1010") == 10
    @test ismissing(read_field(u8, "UUUUUUUU"))
    @test ismissing(read_field(v4, "10X1"))
    @test_throws ArgumentError read_field(u8, "101")
    @test_throws ArgumentError read_field(u8, "1010101q")
    @test read_field(VHDL.Unsigned(VHDL.Range(63, 0)), "1"^64) == big(2)^64 - 1
    @test read_field(VHDL.Boolean(), "TRUE") === true
    @test read_field(VHDL.Boolean(), "false") === false
    @test_throws ArgumentError read_field(VHDL.Boolean(), "1")
    @test read_field(VHDL.Time(), "20 ns") == 20.0
    @test read_field(VHDL.Time(), "5 us") == 5000.0
end

@testset "test data files" begin
    mktempdir() do dir
        path = joinpath(dir, "in.txt")
        write_test_data(PortStim[], path)
        @test read(path, String) == ""

        write_test_data([PortStim("A", u8, [1, 2], In), PortStim("N", VHDL.Integer(), [7], In)], path)
        @test readlines(path) == ["00000001 7 ", "00000010 0 "]

        write(path, "20 ns 00000011\n")
        out = read_test_data!([PortStim("T", VHDL.Time(), Any[], Out), PortStim("Y", u8, Any[], Out)], path)
        @test out[1].value == [20.0] && out[2].value == [3]

        write(path, "00000011 1\n")
        @test_throws ArgumentError read_test_data!([PortStim("Y", u8, Any[], Out)], path)
    end
end

@testset "order_stims" begin
    dut = DUT(name="d", generics=Generic[], ports=[Port("A", u8, 0, In), Port("B", u8, 0, In), Port("Y", u8, 0, Out)])
    a = PortStim("A", u8, [1], In)
    b = PortStim("B", u8, [2], In)
    @test [x.name for x in order_stims(dut, [b, a])] == ["A", "B"]
    @test_throws ArgumentError order_stims(dut, [a])
    @test_throws ArgumentError order_stims(dut, [a, b, PortStim("Y", u8, Int[], Out)])
    @test_throws ArgumentError order_stims(dut, [a, b, PortStim("C", u8, [1], In)])
    @test_throws ArgumentError order_stims(dut, [a, b, a])
    @test_throws ArgumentError order_stims(dut, [a, PortStim("B", s8, [2], In)])
end

@testset "compare" begin
    actual = [PortStim("Y", VHDL.Integer(), Any[0, 10, 21, missing], Out)]
    @test compare([PortStim("Y", VHDL.Integer(), [10, 20], Out)], actual; latency=1, tol=1)
    @test !compare([PortStim("Y", VHDL.Integer(), [10, 20], Out)], actual; latency=1)
    @test !compare([PortStim("Y", VHDL.Integer(), [21, 0], Out)], actual; latency=2)
    @test !compare([PortStim("Y", VHDL.Integer(), [1, 2, 3, 4], Out)], actual; latency=1)
    @test_throws ArgumentError compare([PortStim("Z", VHDL.Integer(), [1], Out)], actual)
end
