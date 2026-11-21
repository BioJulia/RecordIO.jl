"""
    RecordIO

Read the records of a source one after another, with a record parser that finds where each record ends while it finds its fields, so that each byte is read once.

A [`RecordReader{T}`](@ref RecordReader) yields records of type `T`, which a record package defines, with [`RecordIO.read_record(T, stream)`](@ref RecordIO.read_record), its parser, which makes each record.
The reader manages the stream of bytes: it parses straight from where they are, one view of them where they are in memory, or can be mapped into it, and otherwise the buffer of a BufferIO reader, which grows when the parser asks for more bytes, so the parser never sees where one read from the source ends and the next begins.
Sources are vectors of bytes, `IO`s, which it maps into memory where they are regular files and otherwise buffers with a `BufReader`, and BufferIO readers.
"""
module RecordIO

using BufferIO: BufferIO, AbstractBufReader, BufReader, CursorReader, consume, expandable, fill_buffer, get_buffer, get_nonempty_buffer
using Mmap: Mmap
using MemoryViews: ImmutableMemoryView, MutableMemoryView
using StringViews: StringView

export RecordReader, RecordWriter

# Records that own or borrow their bytes.
public Ownership, Owned, Borrowed, owned_type, borrowed_type, copy_bytes

# The errors of malformed records.
public RecordError, MalformedRecord

# Reading: what a record type says, the stream its parser reads, and the readers.
public read_record, malformation, exception, parse_record, Stream, bytes, skip_while
public AbstractReader, records, read_next, remaining, offset, next_offset, number, record_error

# Parsing: what the parsers of record packages share.
public parse_field, try_parse_field, is_missing, separated, field_equals, LengthPrefixed, generate_read_record, generate_execute_code, malformed_record

# The checks of records against the specification of their format.
public problem, is_valid, validate, description, Stop

# Writing: what a record type says, the sinks' helpers, and the writers.
public write_record, write_bytes, write_line, write_le, write_length_prefixed, AbstractWriter

include("errors.jl")
include("ownership.jl")

include("reading/buffers.jl")
include("reading/stream.jl")
include("reading/protocol.jl")
include("reading/abstract_reader.jl")
include("reading/reader.jl")
include("reading/remaining.jl")

include("parsing/fields.jl")
include("parsing/length_prefixed.jl")
include("parsing/automa.jl")

include("validation.jl")

include("writing/protocol.jl")
include("writing/abstract_writer.jl")
include("writing/writer.jl")

end # module RecordIO
