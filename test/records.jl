# The Record Types of the Tests
# =============================
#
# Record types of the tests' own, which make their records with `RecordIO.read_record`, from every kind of source:
# - `Item`, a name and a number on a line, whose parser, generated from an Automa machine, makes `nothing` of a comment, which readers skip;
# - `Entry`, a record of two lines, a name and a value, written by hand, so that nothing assumes a record is a line;
# - `Blob`, a binary record of a little-endian length and that many bytes;
# - `Marked` and `Note`, the lines and comments of one parser, which a reader of either type yields only the records of.

# How a view becomes an owned record, which each record package defines for its own records.
function copied(bytes::ImmutableMemoryView{UInt8})
    memory = Memory{UInt8}(undef, length(bytes))
    copyto!(MutableMemoryView(memory), bytes)
    return ImmutableMemoryView(memory)
end

# Items
# -----

Base.@kwdef struct ItemFields
    name::UnitRange{Int} = 1:0
    number::UnitRange{Int} = 1:0
end

struct Item{O <: RecordIO.Ownership}
    bytes::ImmutableMemoryView{UInt8}
    fields::ItemFields
end

const ItemView = Item{Borrowed}

name(item::Item) = RecordIO.parse_field(StringView, item.bytes, item.fields.name)
number(item::Item) = RecordIO.parse_field(Int, item.bytes, item.fields.number)
fields(item::Item) = (String(name(item)), number(item))

const ITEM_MACHINE = let
    name = onexit!(onenter!(RE("[a-z][a-z0-9]*"), :mark), :name)
    number = onexit!(onenter!(RE("[0-9]+"), :mark), :number)
    item = onexit!(name * RE("\t") * number, :item)
    comment = RE("#[^\n]*")
    compile((item | comment) * opt(onfinal!(RE("\n"), :end_of_record)))
end

const ITEM_ACTIONS = Dict(
    :mark => :(mark = p),
    :name => :(name = mark:(p - 1)),
    :number => :(number = mark:(p - 1)),
    :item => :(filled = p - 1),
)

# Each run of the machine counts itself, so that a test can tell that a record is parsed in one run, however many refills it spans.
const ITEM_RUNS = Ref(0)
const ITEM_SETUP = :($(GlobalRef(@__MODULE__, :ITEM_RUNS))[] += 1; mark = 0; filled = 0; name = number = 1:0)

# The actions find where the fields are, and the record borrows its bytes from the stream; a comment is `nothing`.
# Its states skip runs of bytes, so that the long records below skip across refills.
@eval $(
    generate_read_record(
        ItemView, ITEM_MACHINE, ITEM_ACTIONS;
        setup = ITEM_SETUP,
        skip = true,
        record = :(iszero(filled) ? nothing : ItemView(data[1:filled], ItemFields(; name, number))),
    )
)

RecordIO.exception(::Type{<:Item}) = RecordIO.MalformedRecord{ArgumentError}("Malformed item")

const LINES = vcat(["# header"], ["item$(k)\t$(k)" for k in 1:5_000], ["# between"], ["other$(k)\t$(2k)" for k in 1:5_000])
const TEXT = join(LINES, '\n') * '\n'
const ITEMS = [(String(name), parse(Int, number)) for (name, number) in (split(line, '\t') for line in LINES if !startswith(line, '#'))]

# Entries of two lines
# --------------------

# A record of a name line, `>name`, and a value line, which no machine is needed for.
Base.@kwdef struct EntryFields
    name::UnitRange{Int} = 1:0
    value::UnitRange{Int} = 1:0
end

struct Entry{O <: RecordIO.Ownership}
    bytes::ImmutableMemoryView{UInt8}
    fields::EntryFields
end

entry(record::Entry) = (String(RecordIO.parse_field(StringView, record.bytes, record.fields.name)), String(RecordIO.parse_field(StringView, record.bytes, record.fields.value)))

# The bytes of the stream are iterated over as they come, which knows nothing of where one read from the source ends and the next begins.
# The record is `>name`, a newline, and the value, up to the next newline or the end of the source.
function RecordIO.read_record(::Type{Entry{Borrowed}}, stream::RecordIO.Stream)
    first_newline = 0
    stop = 0
    for (i, byte) in enumerate(stream)
        i == 1 && byte != UInt8('>') && return nothing, -1
        stop = i
        byte == UInt8('\n') || continue
        iszero(first_newline) || break
        first_newline = i
    end
    iszero(first_newline) && return nothing, -1
    data = bytes(stream)
    last_byte = data[stop] == UInt8('\n') && stop > first_newline ? stop - 1 : stop
    return Entry{Borrowed}(data[1:last_byte], EntryFields(; name = 2:(first_newline - 1), value = (first_newline + 1):last_byte)), stop
end

# Binary blobs
# ------------

Base.@kwdef struct BlobFields
    payload::UnitRange{Int} = 1:0
end

struct Blob{O <: RecordIO.Ownership}
    bytes::ImmutableMemoryView{UInt8}
    fields::BlobFields
end

payload(blob::Blob) = String(blob.bytes[blob.fields.payload])

# A blob of the payload "bad" is malformed, which the decoder returns rather than throws.
function decode_blob(::Type{Blob{Borrowed}}, bytes::ImmutableMemoryView{UInt8})
    length(bytes) == 7 && String(bytes[5:7]) == "bad" && return ArgumentError("a bad blob")
    return Blob{Borrowed}(bytes, BlobFields(; payload = 5:length(bytes)))
end

RecordIO.read_record(::Type{Blob{Borrowed}}, stream::RecordIO.Stream) = LengthPrefixed(decode_blob)(Blob{Borrowed}, stream)
RecordIO.malformation(::Type{Blob{Borrowed}}, stream::RecordIO.Stream) = RecordIO.malformation(LengthPrefixed(decode_blob), Blob{Borrowed}, stream)

blobs(payloads) = reduce(vcat, [[reinterpret(UInt8, [htol(Int32(sizeof(payload)))]); Vector{UInt8}(payload)] for payload in payloads]; init = UInt8[])

# Lines and notes of one parser
# -----------------------------

struct Marked{O <: RecordIO.Ownership}
    bytes::ImmutableMemoryView{UInt8}
    fields::Nothing
end

# A comment of the same files, a record of its own type, which owns its text.
struct Note
    text::String
end

# Every line is a `Marked` view, or a `Note` if it starts with `#`, so that a reader of either type yields its records, and skips the others.
function read_line_or_note(stream::RecordIO.Stream)
    n = 0
    for (i, byte) in enumerate(stream)
        n = i
        byte == UInt8('\n') && break
    end
    data = bytes(stream)
    stop = data[n] == UInt8('\n') ? n - 1 : n
    return (data[1] == UInt8('#') ? Note(String(data[2:stop])) : Marked{Borrowed}(data[1:stop], nothing)), n
end

RecordIO.read_record(::Type{Marked{Borrowed}}, stream::RecordIO.Stream) = read_line_or_note(stream)
RecordIO.read_record(::Type{Note}, stream::RecordIO.Stream) = read_line_or_note(stream)

# The record types of two fields, `bytes` and `fields`, whose owned records are copies of the views, read by the parser of the views, which is RecordIO.jl's parser of an owned type that has views.
for R in (:Item, :Entry, :Blob, :Marked)
    @eval begin
        Base.copy(record::$R{Borrowed}) = $R{Owned}(copied(record.bytes), record.fields)
        Base.copy(record::$R{Owned}) = record
        Base.:(==)(a::$R, b::$R) = a.bytes == b.bytes
        Base.hash(record::$R, h::UInt) = hash(record.bytes, h)
        RecordIO.owned_type(::Type{$R{Borrowed}}) = $R{Owned}
        RecordIO.borrowed_type(::Type{$R{Owned}}) = $R{Borrowed}
    end
end

# A reader of a package
# ---------------------

# A reader parameterised on the records it yields, whose methods are those of `RecordIO.AbstractReader`.
struct ItemReader{T <: Item, R} <: RecordIO.AbstractReader{T}
    records::R
end

ItemReader{T}(io) where {T} = (records = RecordReader{T}(io); ItemReader{T, typeof(records)}(records))
ItemReader(io) = ItemReader{Item{Owned}}(io)
Base.close(reader::ItemReader) = close(reader.records)

# Sources
# -------

# A source that gives at most 1,000 bytes a fill, from a buffer of at most 1,000 bytes that can't grow, so that the reader wraps it to grow it.
# Each fill and consume moves its buffer to new memory, and overwrites the old, so a view of it kept too long shows other bytes.
trickle(text) = BoundedReader(text, 1_000; max_fill = 1_000)

# A BufferIO reader of a type of its own, which says where it is in errors, through `RecordIO.offset`, and can't grow its buffer, so that the reader wraps it.
struct Located <: AbstractBufReader
    inner::CursorReader
end

BufferIO.get_buffer(reader::Located) = get_buffer(reader.inner)
BufferIO.fill_buffer(reader::Located) = fill_buffer(reader.inner)
BufferIO.consume(reader::Located, n::Int) = consume(reader.inner, n)
Base.close(reader::Located) = close(reader.inner)
RecordIO.offset(reader::Located, bytes::Int) = (position(reader.inner), bytes)

# The exception that `f` throws.
thrown(f) = try
    f()
catch exception
    exception
end

# The sources that the tests read each kind of record from.
const directory = mktempdir()
const plain = joinpath(directory, "items.txt")
write(plain, TEXT)

const sources = [
    "Vector{UInt8}" => () -> Vector{UInt8}(TEXT),
    "IOBuffer" => () -> IOBuffer(TEXT),
    "IOStream" => () -> open(plain),
    "CursorReader" => () -> CursorReader(TEXT),
    # A buffer smaller than a line makes lines span refills.
    "BufReader" => () -> BufReader(IOBuffer(TEXT), 7),
    "trickle" => () -> trickle(TEXT),
]
