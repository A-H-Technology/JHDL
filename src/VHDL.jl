module VHDL
export declare

abstract type VHDLType end

struct std_logic <: VHDLType end
struct Boolean <: VHDLType end
struct Integer <: VHDLType end
struct Natural <: VHDLType end
struct Positive <: VHDLType end
struct String <: VHDLType end
struct Character <: VHDLType end
struct Time <: VHDLType end
struct Range
    first::Int
    last::Int
end
struct std_logic_vector <: VHDLType
    range::Range
end
struct Signed <: VHDLType
    range::Range
end
struct Unsigned <: VHDLType
    range::Range
end

declare(r::Range) = string(r.first) * (r.first >= r.last ? " downto " : " to ") * string(r.last)
declare(::std_logic) = "std_logic"
declare(::Boolean) = "boolean"
declare(::Integer) = "integer"
declare(::Natural) = "natural"
declare(::Positive) = "positive"
declare(::Character) = "character"
declare(::Time) = "time"
declare(::String) = "string"
declare(t::std_logic_vector) = "std_logic_vector(" * declare(t.range) * ")"
declare(t::Signed) = "signed(" * declare(t.range) * ")"
declare(t::Unsigned) = "unsigned(" * declare(t.range) * ")"

Base.show(io::IO, t::VHDLType) = print(io, declare(t));

Base.show(io::IO, ::MIME"text/plain", t::VHDLType) = print(io, declare(t));
end