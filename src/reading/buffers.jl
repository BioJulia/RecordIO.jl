# Buffers
# -------
#
# A reader's buffer holds the bytes of its source from the next record's first byte, as one view of all of them where they are in memory, or in a BufferIO buffer that grows where they aren't.
# Either keeps its current view in a field, so that a parser reads one field for each byte, whatever the buffer is.

abstract type Buffer end

const NO_BYTES = Memory{UInt8}(undef, 0)

# All the bytes of a source, as one view, which only moves on as records are consumed: it never grows, so a parser never refills it.
mutable struct ViewBuffer <: Buffer
    data::ImmutableMemoryView{UInt8}
end

@inline bytes(buffer::ViewBuffer) = buffer.data
next_bytes!(::ViewBuffer) = false
consume_bytes!(buffer::ViewBuffer, n::Int) = (buffer.data = buffer.data[(n + 1):end]; nothing)
available!(buffer::ViewBuffer) = !isempty(buffer.data)
close_buffer(::ViewBuffer) = nothing
isopen_buffer(::ViewBuffer) = true

# A BufferIO reader that grows, with its view, which is taken again after each consume and refill.
# The view starts empty, and is taken before each record, since taking it may take a shared source over, as a query of an indexed file does.
mutable struct GrowingBuffer{B <: AbstractBufReader} <: Buffer
    const reader::B
    data::ImmutableMemoryView{UInt8}
end

GrowingBuffer(reader::AbstractBufReader) = GrowingBuffer(reader, ImmutableMemoryView(NO_BYTES))

@inline bytes(buffer::GrowingBuffer) = buffer.data
@inline renewed!(buffer::GrowingBuffer) = (buffer.data = get_buffer(buffer.reader); buffer)

# BufferIO grows the buffer to at least the bytes asked for, or to every byte left if the source ends first.
# It is rare, and kept out of line, so that the code of each state of a machine, which iterates over the bytes, stays small.
@noinline function next_bytes!(buffer::GrowingBuffer)
    available = length(buffer.data)
    get_nonempty_buffer(buffer.reader, max(2 * available, available + 1))
    renewed!(buffer)
    return length(buffer.data) > available
end

consume_bytes!(buffer::GrowingBuffer, n::Int) = (consume(buffer.reader, n); renewed!(buffer); nothing)

# Whether the source has bytes left, refilling an empty buffer, which fills nothing only at its end.
@inline available!(buffer::GrowingBuffer) = !isempty(bytes(renewed!(buffer))) || (!iszero(fill_buffer(buffer.reader)) && (renewed!(buffer); true))

close_buffer(buffer::GrowingBuffer) = close(buffer.reader)
isopen_buffer(buffer::GrowingBuffer) = isopen(buffer.reader)

# The Buffer of a Source
# ----------------------

# The buffer of a source, by its type: one view of all its bytes where they are in memory, as a vector's and a `CursorReader`'s are, or where they can be mapped into memory, as a regular file's can; otherwise a BufferIO buffer that grows.
# An `IOBuffer` has no public view of its bytes, so it is read through a buffer that grows, rather than copied.
buffer_of(source::AbstractVector{UInt8}) = ViewBuffer(ImmutableMemoryView(source))
buffer_of(source::CursorReader) = ViewBuffer(get_buffer(source))
buffer_of(source::IOStream) = isfile(stat(source)) ? ViewBuffer(mapped(source)) : GrowingBuffer(buffered(source))
buffer_of(source) = GrowingBuffer(buffered(source))

# A regular file from its position, mapped into memory, which the OS reads as its pages are read.
function mapped(io::IOStream)
    start = position(io)
    length = filesize(io) - start
    length > 0 || return ImmutableMemoryView(NO_BYTES)
    return ImmutableMemoryView(Mmap.mmap(io, Vector{UInt8}, length, start; grow = false, shared = false))
end

# The BufferIO reader of a source whose bytes aren't in memory: a buffer that can grow to hold a record of any length.
buffered(io::IO) = BufReader(io)
buffered(reader::AbstractBufReader) = expandable(reader)
buffered(source) = throw(ArgumentError("a RecordReader reads an IO, a BufferIO reader, or a vector of bytes, but not a $(typeof(source))"))
