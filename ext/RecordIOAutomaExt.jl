module RecordIOAutomaExt

using RecordIO
using Automa: Automa, CodeGenContext, Machine, Node

# Machines on Byte Iterators
# --------------------------
#
# The code of a machine that takes each byte from an iterator, whose `iterate(iterator, p)` gives the byte at position `p`, as a vector's does, and whose end is the end of the input, so that it knows nothing of where the bytes come from.
# Its only state is `p`, an `Int`, which the compiler keeps in a register.
# It is built from the pieces of Automa's goto generator: its states, the conditions of its edges, its actions and `@escape`, and its actions at the end of the input.
# `p` is the position of the byte, from 1, during its actions, and the position after the last byte at the end of the input, as in Automa's code.

const CONTEXT = CodeGenContext(generator = :goto)

# A function of a byte that tells whether it is in `set`, without branches, as Automa's SIMD loop tests it, so that a skip over many bytes compiles to vector instructions.
function membership(set)
    byte = gensym("byte")
    test = foldr(Automa.range_encode(set); init = :(false)) do range, otherwise
        within = length(range) == 1 ? :($byte == $(first(range))) : :(($byte >= $(first(range))) & ($byte <= $(last(range))))
        Expr(:call, :|, within, otherwise)
    end
    return :($byte -> $test)
end

state_label(node::Node) = Symbol("state_", node.state)
case_label(node::Node) = Symbol("state_case_", node.state)

function RecordIO.generate_execute_code(machine::Machine, actions::AbstractDict{Symbol}; iterator = :iterator, skip::Bool = false)
    actions = Dict{Symbol, Expr}(name => Expr(:block, code) for (name, code) in actions)
    # Names that the actions cannot use by accident.
    next = gensym("next")
    nodes = collect(Automa.traverse(machine.start))
    # The sets of actions on the edges into each node, each of which has a label of its own, which runs them and goes to the node.
    action_labels = Dict{Node, Dict{Vector{Symbol}, Symbol}}(node => Dict{Vector{Symbol}, Symbol}() for node in nodes)
    for node in nodes, (edge, target) in node.edges
        names = Automa.action_names(edge.actions)
        isempty(names) || get!(action_labels[target], names, Symbol("state_", target.state, "_action_", length(action_labels[target]) + 1))
    end
    blocks = map(nodes) do node
        action_blocks = map(collect(action_labels[node])) do (names, label)
            quote
                @label $label
                $(Automa.rewrite_special_macros(; ctx = CONTEXT, ex = Automa.generate_action_code(names, actions), at_eof = false, cs = node.state))
                @goto $(state_label(node))
            end
        end
        # A byte that no edge takes fails the machine in this state.
        dispatch = foldr(Automa.optimize_edge_order(node.edges); init = :(cs = $(-node.state); @goto exit)) do (edge, target), otherwise
            names = Automa.action_names(edge.actions)
            go = isempty(names) ? :(@goto $(state_label(target))) : :(@goto $(action_labels[target][names]))
            Expr(:if, Automa.generate_condition_code(CONTEXT, edge, actions), go, otherwise)
        end
        # With `skip`, a state that loops to itself on a set of bytes, with no actions or preconditions, skips the bytes of the set at once.
        # It reads the next byte first, and skips only if that byte is in the set too, so that a run too short to skip costs no call.
        simd, _ = skip ? Automa.peel_simd_edge(node) : (nothing, nothing)
        skipping = if simd === nothing
            :()
        else
            in_set = membership(simd.labels)
            quote
                if $in_set(byte)
                    p = $(GlobalRef(RecordIO, :skip_while))($in_set, $iterator, p + 1)
                    $next = iterate($iterator, p)
                    $next === nothing && (cs = $(node.state); @goto end_of_input)
                    byte = first($next)
                end
            end
        end
        quote
            $(action_blocks...)
            @label $(state_label(node))
            p += 1
            $next = iterate($iterator, p)
            $next === nothing && (cs = $(node.state); @goto end_of_input)
            byte = first($next)
            $skipping
            @label $(case_label(node))
            $dispatch
        end
    end
    # At the end of the input, a machine in a final state runs its actions at the end and accepts, and in any other state rejects.
    end_actions = Automa.rewrite_special_macros(; ctx = CONTEXT, ex = Automa.generate_eof_action_code(CONTEXT, machine, actions), at_eof = true, cs = nothing)
    return quote
        p = 1
        cs = $(machine.start.state)
        $next = iterate($iterator, p)
        $next === nothing && @goto end_of_input
        byte = first($next)
        @goto $(case_label(machine.start))
        $(blocks...)
        @label end_of_input
        if $(Automa.generate_final_state_mem_code(CONTEXT, machine))
            $end_actions
            cs = 0
        else
            cs = -cs
        end
        @label exit
    end
end

# Parsers of Records
# ------------------

function RecordIO.generate_read_record(
        T, machine::Machine, actions::AbstractDict{Symbol};
        record,
        setup = :(),
        endaction::Symbol = :end_of_record,
        error = :(throw($(GlobalRef(RecordIO, :malformed_record))(data, p))),
        skip::Bool = false,
    )
    haskey(actions, endaction) && throw(ArgumentError("the actions define $(repr(endaction)), which marks the end of a record and is defined by the generated code"))
    # A name that the code of the caller cannot use by accident.
    complete = gensym("complete")
    actions = Dict{Symbol, Any}(actions)
    actions[endaction] = quote
        $complete = true
        @escape
    end
    machine_code = RecordIO.generate_execute_code(machine, actions; iterator = :bytes_of_stream, skip)
    bytes = GlobalRef(RecordIO, :bytes)
    # The parser, and the same parser for `malformation`, which throws the error of a malformed record.
    body(checking::Bool) = quote
        checking = $checking
        $complete = false
        $setup
        bytes_of_stream = stream
        $machine_code
        # The bytes read, from which the record takes its own, and the error quotes it.
        data = $bytes(stream)
        cs < 0 && $(checking ? error : :(return nothing, -1))
        # The end action leaves `p` after the newline, and an accepted end of input leaves `p` after the last byte with `cs == 0`.
        ($complete || cs == 0) || $(checking ? error : :(return nothing, -1))
        x = $(
            checking ? :(
                    try
                        $record
                catch exception
                        throw($(GlobalRef(RecordIO, :in_record))(exception, data, p - 1))
                end
                ) : record
        )
        return x, p - 1
    end
    checker = gensym("checking")
    return quote
        # It is inlined, so that its tuple of a record, or of what isn't one, is split at the reader's call site rather than allocated for each record.
        @inline function $(GlobalRef(RecordIO, :read_record))(::Type{$T}, stream::$(GlobalRef(RecordIO, :Stream)))
            $(body(false))
        end
        function $checker(::Type{$T}, stream::$(GlobalRef(RecordIO, :Stream)))
            $(body(true))
        end
        function $(GlobalRef(RecordIO, :malformation))(::Type{$T}, stream::$(GlobalRef(RecordIO, :Stream)))
            $checker($T, stream)
            return ArgumentError("the record is malformed")
        end
    end
end

end # module RecordIOAutomaExt
