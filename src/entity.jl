using EzXML: EzXML, parsexml

# Reads the DUT from the entity declaration in a VHDL file, so the ports and generics
# can't drift from the VHDL. GHDL parses the file and dumps its AST as XML.
#
# - `entity`: which entity to read, when the file declares more than one
# - `clk`, `rst`: the clock and reset port names; they're kept out of `ports`
# - `init`: initial values for the testbench signals, by port name (`init=(EN=0,)`)
#
# Ranges may use the entity's generics (`WIDTH-1 downto 0`); they're evaluated with
# the generics' default values.
function DUT(
    file::AbstractString;
    entity::Union{AbstractString,Nothing}=nothing,
    clk::AbstractString="CLK",
    rst::AbstractString="RST",
    init::NamedTuple=(;),
)
    path = abspath(file)
    xml = mktempdir() do dir
        read(Cmd(`ghdl --file-to-xml --std=08 $path`; dir=dir), String)
    end
    source = readlines(path)

    unit = find_entity(parsexml(xml), path, entity)
    name = original_case(source, unit)

    generics = Generic[]
    generic_values = Dict{String,Any}()
    for el in children_of(unit, "generic_chain")
        g = Generic(original_case(source, el), read_type(only_child(el, "subtype_indication"), generic_values), read_default(el))
        generic_values[lowercase(g.name)] = g.value
        push!(generics, g)
    end

    decls = Pair{Symbol,PortDecl}[]
    clk_port = rst_port = nothing
    type = nothing
    for el in children_of(unit, "port_chain")
        port_name = original_case(source, el)
        # In `A, B : in t`, only A carries the type; B refers back to it
        el["is_ref"] == "true" || (type = read_type(only_child(el, "subtype_indication"), generic_values))
        dir = read_mode(port_name, el["mode"])
        if lowercase(port_name) in (lowercase(clk), lowercase(rst))
            (type isa VHDL.std_logic && dir == In) || throw(ArgumentError("$port_name has to be an std_logic input"))
            p = Port(port_name, type, lowercase(port_name) == lowercase(clk) ? 0 : 1, In)
            lowercase(port_name) == lowercase(clk) ? (clk_port = p) : (rst_port = p)
        else
            push!(decls, Symbol(port_name) => PortDecl(type, get(init, Symbol(port_name), nothing), dir))
        end
    end
    isnothing(clk_port) && throw(ArgumentError("$name has no clock port \"$clk\""))
    isnothing(rst_port) && throw(ArgumentError("$name has no reset port \"$rst\""))
    for k in keys(init)
        any(d -> first(d) == k, decls) || throw(ArgumentError("init has \"$k\", which isn't a port of $name"))
    end

    return DUT(name=name, generics=generics, ports=NamedTuple(decls), clk=clk_port, rst=rst_port)
end

function find_entity(doc::EzXML.Document, path::AbstractString, entity)::EzXML.Node
    units = filter(u -> u["file"] == path, findall("//library_unit[@kind='entity_declaration']", doc))
    isempty(units) && throw(ArgumentError("No entity declared in $path"))
    if isnothing(entity)
        length(units) == 1 || throw(ArgumentError("$path declares $(length(units)) entities, pick one with entity="))
        return only(units)
    end
    i = findfirst(u -> u["identifier"] == lowercase(entity), units)
    isnothing(i) && throw(ArgumentError("No entity $entity in $path"))
    return units[i]
end

children_of(node::EzXML.Node, chain::AbstractString) = findall("$chain/el", node)

function only_child(node::EzXML.Node, name::AbstractString)::EzXML.Node
    child = findfirst(name, node)
    isnothing(child) && throw(ArgumentError("GHDL's AST has no $name under line $(node["line"])"))
    return child
end

# GHDL lowercases identifiers; take the spelling from the source. Its columns count
# tabs to the next multiple of 8.
function original_case(source::AbstractVector{<:AbstractString}, node::EzXML.Node)::String
    id = node["identifier"]
    line = replace_tabs(source[parse(Int, node["line"])])
    col = parse(Int, node["col"])
    spelled = col + length(id) - 1 <= length(line) ? line[col:col+length(id)-1] : ""
    return lowercase(spelled) == id ? spelled : id
end

function replace_tabs(line::AbstractString)::String
    out = IOBuffer()
    col = 0
    for c in line
        n = c == '\t' ? 8 - col % 8 : 1
        print(out, c == '\t' ? " "^n : c)
        col += n
    end
    return String(take!(out))
end

function read_mode(port::AbstractString, mode::AbstractString)::Direction
    mode == "in" && return In
    mode == "out" && return Out
    mode == "inout" && return InOut
    throw(ArgumentError("$port is a $mode port, only in, out and inout are supported"))
end

const scalar_types = Dict(
    "std_logic" => VHDL.std_logic(),
    "boolean" => VHDL.Boolean(),
    "integer" => VHDL.Integer(),
    "natural" => VHDL.Natural(),
    "positive" => VHDL.Positive(),
    "character" => VHDL.Character(),
    "string" => VHDL.String(),
    "time" => VHDL.Time(),
)

const vector_types = Dict(
    "std_logic_vector" => VHDL.std_logic_vector,
    "signed" => VHDL.Signed,
    "unsigned" => VHDL.Unsigned,
)

function read_type(si::EzXML.Node, generic_values::AbstractDict)::VHDL.VHDLType
    kind = si["kind"]
    if kind == "simple_name"
        haskey(scalar_types, si["identifier"]) || throw(ArgumentError("Unsupported type $(si["identifier"]) on line $(si["line"])"))
        return scalar_types[si["identifier"]]
    elseif kind == "array_subtype_definition"
        mark = only_child(si, "subtype_type_mark")["identifier"]
        haskey(vector_types, mark) || throw(ArgumentError("Unsupported type $mark on line $(si["line"])"))
        r = only_child(si, "index_constraint_list/el/range_constraint")
        left = eval_expr(only_child(r, "left_limit_expr"), generic_values)
        right = eval_expr(only_child(r, "right_limit_expr"), generic_values)
        # VHDL.Range has no direction of its own, declare() infers it from first >= last
        (r["direction"] == "downto") == (left >= right) || throw(ArgumentError("Unsupported null or single-bit 'to' range on line $(si["line"])"))
        return vector_types[mark](VHDL.Range(left, right))
    end
    throw(ArgumentError("Unsupported type ($kind) on line $(si["line"])"))
end

const operators = Dict(
    "addition_operator" => +,
    "substraction_operator" => -,
    "multiplication_operator" => *,
    "division_operator" => div,
)

function eval_expr(node::EzXML.Node, generic_values::AbstractDict)::Int
    kind = node["kind"]
    kind == "integer_literal" && return parse(Int, strip(node["value"]))
    kind == "parenthesis_expression" && return eval_expr(only_child(node, "expression"), generic_values)
    if kind == "simple_name"
        v = get(generic_values, node["identifier"], nothing)
        v isa Integer || throw(ArgumentError("Range on line $(node["line"]) uses $(node["identifier"]), which isn't a generic with an integer default"))
        return v
    end
    haskey(operators, kind) || throw(ArgumentError("Unsupported range expression ($kind) on line $(node["line"])"))
    return operators[kind](eval_expr(only_child(node, "left"), generic_values), eval_expr(only_child(node, "right"), generic_values))
end

# Only defaults with a plain Julia equivalent; anything else is left for GHDL's -g
function read_default(el::EzXML.Node)
    d = findfirst("default_value", el)
    isnothing(d) && return nothing
    d["kind"] == "integer_literal" && return parse(Int, strip(d["value"]))
    d["kind"] == "simple_name" && d["identifier"] in ("true", "false") && return d["identifier"] == "true"
    return nothing
end
