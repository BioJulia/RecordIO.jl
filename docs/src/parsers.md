# Record types

A record type is a package's own: an immutable value of the bytes of a record and where its fields are in them.

```julia
struct Record{O <: RecordIO.Ownership}
    bytes::ImmutableMemoryView{UInt8}
    fields::Fields
end
```

- **Ownership:** [`RecordIO.Ownership`](@ref) is a parameter of the type: a `Record{Owned}` owns its bytes, and a `Record{Borrowed}`, a view, borrows those of the reader's buffer, so it allocates nothing, and is valid until the next record is read.
- **Fields:** where the fields are, such as ranges of the bytes, which the parser finds as it reads the record, so that an accessor reads a field without finding it again.
- **Copies:** `copy` of a view is an owned record, with a copy of the bytes, and since a record is immutable, `copy` of an owned record is the record itself.

## What a record type says

A reader takes only the source: everything else follows from the record type, by its methods.

| Method | What it says | Default |
|:--|:--|:--|
| [`RecordIO.read_record(T, stream)`](@ref RecordIO.read_record) | the parser of a record | that of its views, copied, for an owned type |
| [`RecordIO.owned_type(T)`](@ref RecordIO.owned_type) | the records that own their bytes of the views `T`, which `collect` gives | `T` |
| [`RecordIO.borrowed_type(T)`](@ref RecordIO.borrowed_type) | the views of the owned records `T`, which a reader that drops some records reads | `T` |
| [`RecordIO.malformation(T, stream)`](@ref RecordIO.malformation) | why a record is malformed | that of its views, or `ArgumentError("the record is malformed")` |
| [`RecordIO.exception(T)`](@ref RecordIO.exception) | the errors of its records | [`RecordIO.RecordError`](@ref) |

## The parser

A record parser reads one record at a time from a [`RecordIO.Stream`](@ref), the bytes of the reader's buffer from the first byte of the record:

```julia
RecordIO.read_record(::Type{T}, stream::RecordIO.Stream) -> (x, n::Int)
```

- `x` is the record, of type `T`, or what the parser found that isn't one, such as `nothing` for a comment, which the reader skips.
- `n > 0` is the number of bytes that the record took, its end, such as a newline, included.
- `n < 0` says that the record is malformed, and [`RecordIO.malformation`](@ref) says why, so that reading a record enters no `try`.
- The stream is iterated as a vector is: `iterate(stream, p)` gives the byte at position `p`, from 1, and reads more of the source when `p` passes the bytes in the buffer, so the parser never sees where one read from the source ends and the next begins.
- [`RecordIO.bytes(stream)`](@ref RecordIO.bytes) is a view of the bytes read so far, of which a view of the record borrows its own.

A line of text, which the other pages of the manual read, is a record without fields.
Its parser finds the newline with [`RecordIO.skip_while`](@ref), which tests 32 bytes of a stream at a time:

```@example parsers
using RecordIO
using RecordIO: Ownership, Owned, Borrowed
using MemoryViews: ImmutableMemoryView
using StringViews: StringView

struct Line{O <: Ownership}
    bytes::ImmutableMemoryView{UInt8}
end

const LineView = Line{Borrowed}

text(line::Line) = StringView(line.bytes)

Base.copy(line::LineView) = Line{Owned}(ImmutableMemoryView(collect(line.bytes)))
Base.copy(line::Line{Owned}) = line
RecordIO.owned_type(::Type{LineView}) = Line{Owned}
RecordIO.borrowed_type(::Type{Line{Owned}}) = LineView

@inline function RecordIO.read_record(::Type{LineView}, stream::RecordIO.Stream)
    p = RecordIO.skip_while(!=(UInt8('\n')), stream, 1)
    data = RecordIO.bytes(stream)
    # At the end of the source, `p` is after the last byte.
    taken = min(p, length(data))
    n = data[taken] == UInt8('\n') ? taken - 1 : taken
    is_line = n > 0 && data[1] != UInt8('#')
    return (is_line ? LineView(data[1:n]) : nothing), taken
end

[String(text(line)) for line in RecordReader{LineView}(IOBuffer("# a header\nfirst\nsecond"))]
```

A parser that returns a record or something else, such as `nothing`, is `@inline`, so that the reader splits the two where it calls it, rather than allocating for each record.
The parser of the owned records follows from that of the views: since `borrowed_type(Line{Owned})` is `LineView`, a reader of `Line{Owned}` reads views and copies each.

[`RecordIO.parse_record(T, data)`](@ref RecordIO.parse_record) parses all of `data` as one record, as a package makes a record of given bytes:

```@example parsers
String(text(RecordIO.parse_record(Line{Owned}, Vector{UInt8}("given\n"))))
```

## Fields

The fields of a record are ranges of its bytes, which these read by the type wanted, allocating only for a `String`:

- [`RecordIO.parse_field(T, data, range)`](@ref RecordIO.parse_field): an integer, a float, a `String`, a `StringView` or a `Char`;
- [`RecordIO.is_missing(data, range, placeholder)`](@ref RecordIO.is_missing): whether a field is the placeholder of a missing value;
- [`RecordIO.separated(data, range, delimiter)`](@ref RecordIO.separated): the ranges of the values of a field;
- [`RecordIO.field_equals(data, range, text)`](@ref RecordIO.field_equals): whether a field is a text.

```@example parsers
data = Vector{UInt8}("chr1\t-12\t3.5e2\ta,b")
RecordIO.parse_field(Int, data, 6:8), RecordIO.parse_field(Float64, data, 10:14), [String(data[value]) for value in RecordIO.separated(data, 16:18, UInt8(','))]
```

## Parsers from Automa machines

With Automa loaded, [`RecordIO.generate_read_record`](@ref) generates the parser of a record type from a state machine, and its `malformation`, which parses a malformed record again to say where it fails.
The machine matches one record, or what isn't a record, and what ends it; its actions find the fields in local variables, and the expression `record` makes the record of them once it is complete.

```@example parsers
using Automa

Base.@kwdef struct ItemFields
    name::UnitRange{Int} = 1:0
    number::UnitRange{Int} = 1:0
end

struct Item{O <: Ownership}
    bytes::ImmutableMemoryView{UInt8}
    fields::ItemFields
end

name(item::Item) = RecordIO.parse_field(StringView, item.bytes, item.fields.name)
number(item::Item) = RecordIO.parse_field(Int, item.bytes, item.fields.number)

# A name and a number, or a comment, to a newline or the end of the source.
const item_machine = let
    name = onexit!(onenter!(re"[a-z][a-z0-9]*", :mark), :name)
    number = onexit!(onenter!(re"[0-9]+", :mark), :number)
    item = onexit!(name * re"\t" * number, :item)
    comment = re"#[^\n]*"
    compile((item | comment) * opt(onfinal!(re"\n", :end_of_record)))
end

const item_actions = Dict(
    :mark => :(mark = p),
    :name => :(name = mark:(p - 1)),
    :number => :(number = mark:(p - 1)),
    :item => :(filled = p - 1),
)

@eval $(
    RecordIO.generate_read_record(
        Item{Borrowed}, item_machine, item_actions;
        setup = :(mark = 0; filled = 0; name = number = 1:0),
        record = :(iszero(filled) ? nothing : Item{Borrowed}(data[1:filled], ItemFields(; name, number))),
    )
)

[(String(name(item)), number(item)) for item in RecordReader{Item{Borrowed}}(IOBuffer("# items\nfirst\t1\nsecond\t22\n"))]
```

The machine takes each byte from the stream, so each byte is read once, and only the end of the source is the end of its input.
With `skip = true`, a state that loops to itself on a set of bytes skips them at once, which pays for fields with long runs of such bytes.

## Length-prefixed records

[`RecordIO.LengthPrefixed`](@ref) frames binary records that start with their length, as BAM records do, with a decoder of one record, which returns the exception of a malformed record rather than throwing it:

```@example parsers
struct Blob{O <: Ownership}
    bytes::ImmutableMemoryView{UInt8}
end

# The payload follows the 4 bytes of the length.
decode_blob(::Type{Blob{Borrowed}}, bytes) = length(bytes) > 4 ? Blob{Borrowed}(bytes[5:end]) : ArgumentError("a blob without a payload")

RecordIO.read_record(::Type{Blob{Borrowed}}, stream::RecordIO.Stream) = RecordIO.LengthPrefixed(decode_blob)(Blob{Borrowed}, stream)
RecordIO.malformation(::Type{Blob{Borrowed}}, stream::RecordIO.Stream) = RecordIO.malformation(RecordIO.LengthPrefixed(decode_blob), Blob{Borrowed}, stream)

blob(payload) = [reinterpret(UInt8, [htol(Int32(sizeof(payload)))]); codeunits(payload)]
[String(blob.bytes) for blob in RecordReader{Blob{Borrowed}}(IOBuffer([blob("first"); blob("second")]))]
```

## Checking records against a specification

A parser finds the fields of a record by its syntax, and a reader yields what it finds.
What the specification of a format says of the values of the fields, such as their ranges, and how they agree with each other, is checked when it is asked for, when a file is new, rather than as part of reading it every time.

A record package says how a record breaks the specification, with a method of [`RecordIO.problem`](@ref), which reads the fields as their accessors do, and a number with [`RecordIO.try_parse_field`](@ref), which gives `nothing` where the accessor's [`RecordIO.parse_field`](@ref) throws.
[`RecordIO.is_valid`](@ref) and [`RecordIO.validate`](@ref) of a record follow from it, and [`RecordIO.description`](@ref) is what an error quotes of a record.

```@example parsers
# How an item breaks the rule that its number is at most 255, or `nothing`.
RecordIO.problem(item::Item) = RecordIO.try_parse_field(UInt8, item.bytes, item.fields.number) === nothing ? "the number is above 255" : nothing
RecordIO.description(item::Item) = RecordIO.description(item.bytes)

items = collect(RecordReader{Item{Borrowed}}(IOBuffer("first\t1\nsecond\t256\n")))
map(RecordIO.is_valid, items), RecordIO.problem(last(items))
```

The check of a file is a loop over a reader, [`RecordIO.validate(step, reader, state)`](@ref RecordIO.validate), whose `step` checks each record with what those before it left in `state`, for what the specification says of a file as a whole.
Its error is that of the record, with its number and its offset in the source, as the reader throws for a malformed one.

```@example parsers
# Each item honours the specification, and the numbers of a file do not descend.
function step(last_number, item)
    message = RecordIO.problem(item)
    message === nothing || return message
    return number(item) >= last_number ? number(item) : "the numbers descend"
end

try
    RecordIO.validate(step, RecordReader{Item{Borrowed}}(IOBuffer("first\t1\nsecond\t256\n")), 0)
catch error
    error
end
```

A package's reader checks its file with a method of `RecordIO.validate(reader)` that calls the loop, and `RecordIO.validate(Reader, source)` opens a source with a type of reader, checks it, and closes it.

## Where a reader is

[`RecordIO.offset(reader)`](@ref RecordIO.offset) is where the record last read starts in the source, [`RecordIO.next_offset(reader)`](@ref RecordIO.next_offset) where the next one starts, and [`RecordIO.number(reader)`](@ref RecordIO.number) the number of parses so far, which is the line number of a text file of one record a line.
An offset is a number of bytes, or the source's own kind of offset, as a source of a BGZF file gives virtual offsets.

```@example parsers
reader = RecordReader{Item{Borrowed}}(IOBuffer("# items\nfirst\t1\nsecond\t22\n"))
[(String(name(item)), RecordIO.number(reader), RecordIO.offset(reader), RecordIO.next_offset(reader)) for item in reader]
```
