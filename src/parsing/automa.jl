# Parsers Generated from Automa Machines
# ---------------------------------------

"""
    RecordIO.generate_execute_code(machine::Automa.Machine, actions::Dict{Symbol}; iterator = :iterator, skip = false) -> Expr

Generate the code of `machine` with `actions`, which takes each byte from the iterator of bytes in the variable named `iterator`, and whose end is the end of the input; this needs Automa to be loaded.

The machine knows nothing of where the bytes come from: a `Vector{UInt8}`, a view, or a [`RecordIO.Stream`](@ref), which reads more of the source as it goes, whose `iterate(iterator, p)` gives the byte at position `p`.
The code is built from the pieces of Automa's goto generator, and has its variables:

- `p`, the position of the byte, from 1, during its actions, and the position after the last byte at the end of the input;
- `byte`, the byte, and `cs`, the state, which is 0 after the input was accepted at its end, negative when the machine failed, at state `-cs`, and positive after `@escape`.

Actions may use `@escape`, which stops the machine after the byte, with `p` at the next byte.
At the end of the input, a machine in a final state runs its actions at the end, and any other rejects the input.

With `skip = true`, a state that loops to itself on a set of bytes, with no actions, skips the bytes of the set with [`RecordIO.skip_while`](@ref), when the byte after the state's first is in the set too.
It pays for fields with long runs of such bytes, such as the sequences of SAM records, and costs for fields of a few bytes each, such as the attributes of GFF3 records, so a package measures its records both ways.
"""
function generate_execute_code end

"""
    RecordIO.generate_read_record(T, machine::Automa.Machine, actions::Dict{Symbol}; record, kwargs...) -> Expr

Generate the definitions of [`RecordIO.read_record(::Type{T}, stream)`](@ref RecordIO.read_record), a parser of records of type `T` with an Automa `machine`, and of its [`RecordIO.malformation`](@ref).
Define them with `@eval`; this needs Automa to be loaded.

The machine takes each byte from the stream, which reads more of the source as it goes, so each byte is read once, the machine knows nothing of where one read from the source ends and the next begins, and only the end of the source is the end of its input; its code is [`RecordIO.generate_execute_code`](@ref)'s.
It returns `(x, n)`: the value of the expression `record` and the bytes the record took, when it is complete, or `(nothing, -1)` if the machine fails.
`malformation` runs the machine again with `checking = true` to throw the error of a malformed record, so that parsing a well-formed record enters no `try`.

`machine` matches one record, or what isn't a record, such as a comment, and what ends it, which must be optional so that the last record of a source may lack it.
The action named `endaction` marks the end of a record: attach it to the final byte of what ends it, as in `opt(onfinal!(re"\\n", :end_of_record))` for records that end with a newline.
The generated code defines the action, so `actions` must not, and stops the machine there.
A record also ends at the end of the source when the machine accepts all of its bytes.

Code in `actions` and `setup` sees the position `p` of the machine, its state `cs`, the `byte`, and `checking`, which is `true` only when `malformation` parses a malformed record again.
`record` and `error` see `data` too, the bytes that the machine read, which `actions` don't, since they come from the stream as the machine reads.
When the record is complete, `p - 1` is its number of bytes, so `record` finds it in `data[1:(p - 1)]`, whose view a record of type `R{Borrowed}` may borrow.
To reject a record that the machine accepts, `record` returns `(nothing, -1)`, and with `checking` throws the reason.

Keyword arguments:

- `record`: the expression of the record of type `T`, or of what isn't one, such as `nothing` for a comment.
- `setup`: code run before the machine, such as defining the variables that actions assign.
- `endaction = :end_of_record`: the name of the action that marks the end of a record.
- `skip = false`: whether states that loop to themselves skip runs of bytes at once, as [`RecordIO.generate_execute_code`](@ref) does with `skip = true`.
- `error`: code run if the machine fails when `malformation` parses the record again, which should throw; by default [`RecordIO.malformed_record(data, p)`](@ref RecordIO.malformed_record), which quotes the record and gives the position `p` of the failing byte.
  An `ArgumentError` that `record` throws while checking gains the quoted record too.

```julia
using Automa, RecordIO, MemoryViews
using RecordIO: Owned, Borrowed

# A record of one name, which borrows its bytes, or owns them.
struct Name{O <: RecordIO.Ownership}
    bytes::ImmutableMemoryView{UInt8}
end

const machine = let
    name = onexit!(onenter!(re"[^#\\n][^\\n]*", :mark), :name)
    comment = re"#[^\\n]*"
    compile((name | comment) * opt(onfinal!(re"\\n", :end_of_record)))
end

const actions = Dict(:mark => :(mark = p), :name => :(range = mark:(p - 1)))

# A comment is `nothing`, which the reader skips.
@eval \$(RecordIO.generate_read_record(Name{Borrowed}, machine, actions;
    setup = :(mark = 0; range = 1:0),
    record = :(isempty(range) ? nothing : Name{Borrowed}(data[range])),
))
```
"""
function generate_read_record end


"""
    RecordIO.malformed_record(data::AbstractVector{UInt8}, p::Int) -> ArgumentError

The error of a record at the start of `data` that a parser fails at byte `p` of: the record from its start to 20 bytes past `p`, cut after 100 bytes, and `p`, as `the record "chr1\\tx\\t5" does not match the format at byte 6`.
It is the default `error` of [`RecordIO.generate_read_record`](@ref).
"""
malformed_record(data::AbstractVector{UInt8}, p::Int) = ArgumentError(string("the record ", quoted(data, p + 20), " does not match the format at byte ", p))

# An error that a parser's `finish` throws while checking a record, with the record it is about, up to `stop`.
in_record(exception::ArgumentError, data::AbstractVector{UInt8}, stop::Int) = ArgumentError(string(exception.msg, " in the record ", quoted(data, stop)))
in_record(exception, data::AbstractVector{UInt8}, stop::Int) = exception
