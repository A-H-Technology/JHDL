using Test
using JHDL
import JHDL: Column, convert_generics, input_columns, read_field, read_test_data!, write_field, write_test_data

const u8 = VHDL.Unsigned(VHDL.Range(7, 0))
const s8 = VHDL.Signed(VHDL.Range(7, 0))
const v4 = VHDL.std_logic_vector(VHDL.Range(3, 0))

# compare is per design; the adder's output is registered, so it lags its inputs by a cycle
struct Adder <: Design end
JHDL.compare(::Simulation{Adder}, expected, actual; tol=nothing) = actual.Y[2:length(expected.Y)+1] == expected.Y

# Full round trip: generate a testbench for a real DUT, build and run it with
# GHDL, and read the captured outputs back into Julia.
@testset "e2e: registered adder through GHDL" begin
    Sys.which("ghdl") === nothing && error("ghdl not found on PATH; the e2e test needs it")

    mktempdir() do build
        dut = DUT(joinpath(@__DIR__, "vhdl", "adder.vhd"); init=(A=0, B=0))
        tb = Testbench(
            name="adder_tb",
            generics=Generic[],
            constants=Constant[],
            signals=Port[],
            dut=dut,
        )
        sim = Simulation(
            design=Adder(),
            testbench=tb,
            sources=[joinpath(@__DIR__, "vhdl", "adder.vhd")],
            build_directory=build,
            generics=Generic[],
        )

        a = [1, 2, 3, 100, 200, 255]
        b = [1, 5, 7, 27, 55, 0]
        out = simulate(sim; A=a, B=b)

        @test isfile(joinpath(build, "adder_tb.vhd"))
        @test keys(out) == (:Y,)
        # The first sample is captured on the same edge the first inputs are applied
        @test out.Y[2:length(a)+1] == a .+ b
        @test out.Y[1:length(a)] != a .+ b

        @test verify(sim, (Y=a .+ b,); A=a, B=b)
        @test !verify(sim, (Y=a .+ b .+ 1,); A=a, B=b)
    end
end

@testset "e2e: mixed port types, generic override, shuffled and short stims" begin
    mktempdir() do build
        dut = DUT(joinpath(@__DIR__, "vhdl", "mixed.vhd"))
        tb = Testbench(name="mixed_tb", generics=Generic[], constants=Constant[], signals=Port[], dut=dut)
        sim = Simulation(
            testbench=tb,
            sources=[joinpath(@__DIR__, "vhdl", "mixed.vhd")],
            build_directory=build,
            generics=[Generic("OFFSET", VHDL.Integer(), 3)],
        )

        s = [-5, 100, -128, 0]
        v = [0b0000, 0b1010, 0b1111, 0b0110]
        en = [true, false, true, false]
        n = [1, -7]

        out = simulate(sim; N=n, EN=en, V=v, S=s)
        # No design given, so there's no compare to dispatch to
        @test_throws ArgumentError verify(sim, out; N=n, EN=en, V=v, S=s)
        @test keys(out) == (:SO, :VO, :BO, :NO)
        @test out.SO[2:5] == s .+ 3
        @test out.VO[2:5] == 0b1111 .⊻ v
        @test out.BO[2:5] == .!en
        @test out.NO[2:5] == [2 .* n; 0; 0]
    end
end


const sl = VHDL.std_logic()

function counter_sim(build; limit, finish_on=nothing, drain=20)
    dut = DUT(
        name="counter",
        generics=[Generic("LIMIT", VHDL.Natural(), 255)],
        ports=(EN=In(sl; init=0), COUNT=Out(u8), DONE=Out(sl)),
    )
    tb = Testbench(name="counter_tb", generics=Generic[], constants=Constant[], signals=Port[], dut=dut,
        drain_cycles=Constant("DRAIN_CYCLES", VHDL.Integer(), drain), finish_on=finish_on)
    return Simulation(
        testbench=tb,
        sources=[joinpath(@__DIR__, "vhdl", "counter.vhd")],
        build_directory=build,
        generics=[Generic("LIMIT", VHDL.Natural(), limit)],
    )
end

@testset "e2e: inputs return to their initial value after the stim" begin
    mktempdir() do build
        out = simulate(counter_sim(build; limit=255); EN=[1, 1, 1])
        count = out.COUNT
        # EN held at '1' would keep counting through the 20 drain cycles
        @test count[end] == 3
    end
end

@testset "e2e: finish_on ends the simulation on the first edge it's high" begin
    mktempdir() do build
        out = simulate(counter_sim(build; limit=4, finish_on="DONE", drain=1000); EN=fill(1, 10))
        count, done = out.COUNT, out.DONE
        @test done[end] == '1' && count[end] == 4
        @test all(==('0'), done[1:end-1])
        @test length(done) == 5
    end
end

@testset "finish_on validation" begin
    dut = DUT(name="d", generics=Generic[], ports=(A=In(u8; init=0), Y=Out(u8; init=0), D=Out(sl; init=0)))
    tb(f) = Testbench(name="d_tb", generics=Generic[], constants=Constant[], signals=Port[], dut=dut, finish_on=f)
    mktempdir() do build
        @test_throws ArgumentError construct_testbench(tb("NOPE"); directory=build)
        @test_throws ArgumentError construct_testbench(tb("A"); directory=build)
        @test_throws ArgumentError construct_testbench(tb("Y"); directory=build)
        construct_testbench(tb("D"); directory=build)
        @test occursin("if D = '1' then", read(joinpath(build, "d_tb.vhd"), String))
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
        write_test_data(Column[], path)
        @test read(path, String) == ""

        write_test_data([Column("A", u8, [1, 2]), Column("N", VHDL.Integer(), [7])], path)
        @test readlines(path) == ["00000001 7 ", "00000010 0 "]

        write(path, "20 ns 00000011\n")
        out = read_test_data!([Column("T", VHDL.Time(), Any[]), Column("Y", u8, Any[])], path)
        @test out[1].values == [20.0] && out[2].values == [3]

        write(path, "00000011 1\n")
        @test_throws ArgumentError read_test_data!([Column("Y", u8, Any[])], path)
    end
end

@testset "DUT read from VHDL" begin
    widths = joinpath(@__DIR__, "vhdl", "widths.vhd")
    dut = DUT(widths; init=(A=1,))
    @test dut.name == "Widths"
    @test [(g.name, g.type, g.value) for g in dut.generics] ==
          [("WIDTH", VHDL.Natural(), 4), ("FLAG", VHDL.Boolean(), true)]
    u4 = VHDL.Unsigned(VHDL.Range(3, 0))
    @test [(p.name, p.type, p.value, p.dir) for p in dut.ports] == [
        ("A", u4, 1, In),
        ("Bb", u4, nothing, In),
        ("Wide", VHDL.std_logic_vector(VHDL.Range(10, 0)), nothing, Out),
        ("Up", VHDL.Signed(VHDL.Range(0, 4)), nothing, InOut),
    ]
    @test (dut.clk.name, dut.rst.name) == ("Clk", "Rst")
    @test_throws ArgumentError DUT(widths; init=(Nope=1,))
    @test_throws ArgumentError DUT(widths; clk="CK")
    @test_throws ArgumentError DUT(widths; entity="other")
end

@testset "DUT ports" begin
    dut = DUT(name="d", generics=Generic[], ports=(A=In(u8), Y=Out(u8; init=3), B=InOut(s8)))
    @test [(p.name, p.type, p.value, p.dir) for p in dut.ports] ==
          [("A", u8, nothing, In), ("Y", u8, 3, Out), ("B", s8, nothing, InOut)]
end

@testset "input_columns" begin
    dut = DUT(name="d", generics=Generic[], ports=(A=In(u8), Y=Out(u8), B=In(s8)))
    inputs = input_columns(dut, (B=[2], A=1:1))
    @test [(c.name, c.type, c.values) for c in inputs] == [("A", u8, [1]), ("B", s8, [2])]
    @test_throws ArgumentError input_columns(dut, (A=[1],))
    @test_throws ArgumentError input_columns(dut, (A=[1], B=[2], Y=[3]))
    @test_throws ArgumentError input_columns(dut, (A=[1], B=[2], C=[3]))
    @test_throws ArgumentError input_columns(dut, (A=[1], B=2))
end
