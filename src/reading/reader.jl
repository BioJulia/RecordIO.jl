# Readers
# -------

"""
    RecordReader{T}(source)
    RecordReader{T}(reader::RecordReader)

Read the records of type `T` of `source` one after another, each made by [`RecordIO.read_record(T, stream)`](@ref RecordIO.read_record), a parser that the package of `T` defines, with its errors, [`RecordIO.exception(T)`](@ref RecordIO.exception).

`source` is a vector of bytes that are contiguous in memory, such as a `Vector{UInt8}` or a contiguous view of one, an `IO`, or a BufferIO reader.
Where its bytes are in memory, as a vector's and a `CursorReader`'s are, or can be mapped into memory, as a regular file's can, the reader parses them as one view; otherwise it parses from a BufferIO buffer that grows: a `BufReader` of an `IO`, or the buffer of a BufferIO reader, wrapped with `expandable` if it can't grow.
To choose the size of the buffer, pass a `BufReader(io, size)`.
The reader takes over its source: read from it only through the reader, or through [`RecordIO.remaining`](@ref).

A reader is an iterator of records of type `T`, as a `Vector{T}` is of its elements:

- it yields what the parser makes that is a `T`, and skips the rest, such as comments;
- a record that borrows the buffer of the source, such as an `R{Borrowed}`, is valid until the next record is read;
- `collect` gives records of [`RecordIO.owned_type(T)`](@ref RecordIO.owned_type), copies of those that borrow;
- iteration ends at the end of the source, with `nothing`, as an iterator does;
- `close(reader)` closes the source.

It is itself a [`RecordIO.AbstractReader{T}`](@ref RecordIO.AbstractReader), whose [`RecordIO.records`](@ref) is itself.

Made from another reader, it carries on from where that reader is, through its source and its buffer, with its count of records and of bytes, and reads records of type `T` in place of that reader's, which is not to be read from again.
So a package reads the rest of a source as another type, such as one that keeps the lines that its records skip, to check a file.
"""
mutable struct RecordReader{T, S, B <: Buffer, E} <: AbstractReader{T}
    # The source, as the caller gave it, and the buffer of its bytes, which the parser reads through a stream.
    const source::S
    const buffer::B
    const exception::E
    # The bytes of the last record read, which stay in the buffer for the records that borrow them until the next read consumes them.
    unconsumed::Int
    # What the reader has read: each record is consumed from the buffer before the next, so the buffer starts at the next unread byte.
    number::Int # The parses read.
    consumed::Int # The bytes consumed from the buffer.

    function RecordReader{T}(source) where {T}
        buffer = buffer_of(source)
        error = callable(exception(T))
        return new{T, typeof(source), typeof(buffer), typeof(error)}(source, buffer, error, 0, 0, 0)
    end

    function RecordReader{T}(reader::RecordReader{<:Any, S, B}) where {T, S, B <: Buffer}
        settle!(reader)
        error = callable(exception(T))
        return new{T, S, B, typeof(error)}(reader.source, reader.buffer, error, 0, reader.number, reader.consumed)
    end
end

# A `RecordReader` is the reader of records that it wraps.
records(reader::RecordReader) = reader

# A type given as a function, such as the default exception, `RecordError`, is called through a function of its own type, which a reader's type then names exactly.
struct Constructs{E} end
(::Constructs{E})(arguments...) where {E} = E(arguments...)
callable(f::Type) = Constructs{f}()
callable(f) = f

# The Buffer
# ----------

# Consume the `n` bytes of a record, so that the buffer starts at the next unread byte.
function consume!(reader::RecordReader, n::Int)
    consume_bytes!(reader.buffer, n)
    reader.consumed += n
    return reader
end

# Consume the bytes of the last record read, which the records that borrow them have until the next read, so that the buffer starts at the next unread byte.
@inline function settle!(reader::RecordReader)
    n = reader.unconsumed
    iszero(n) || (consume!(reader, n); reader.unconsumed = 0)
    return reader
end


# Parsing
# -------

# The reader's exception for the record at the start of the buffer.
failure(reader::RecordReader, cause) = reader.exception(offset(reader.source, reader.consumed), reader.number + 1, cause)

"""
    RecordIO.offset(source, bytes::Int)

Where a record starts in `source`, for the error of a malformed record: by default `bytes`, the number of bytes of the source before it, counted from where reading started.

`source` is the source that the [`RecordReader`](@ref) was made with, so a package adds a method for its type of source to give its own kind of offset instead, such as the virtual offset of a BGZF file.
It is called only when a record fails, so it costs nothing per record.
"""
offset(source, bytes::Int) = bytes

"""
    RecordIO.offset(reader) -> offset

Where the record that `reader` last read starts in its source, as [`RecordIO.offset(source, bytes)`](@ref) gives it: by default the number of bytes of the source before it, counted from where reading started, or the source's own kind of offset, such as the virtual offset of a BGZF file.
Before the first record, and after reading from [`RecordIO.remaining`](@ref), it is where the reader is.
`reader` is a [`RecordReader`](@ref), or a package's [`RecordIO.AbstractReader`](@ref).
"""
offset(reader::RecordReader) = offset(reader.source, reader.consumed)

"""
    RecordIO.next_offset(reader) -> offset

Where the next record of `reader` starts in its source, which is where the reader is: after the record that it last read.
It is an offset as [`RecordIO.offset(reader)`](@ref) is.
"""
next_offset(reader::RecordReader) = offset(reader.source, reader.consumed + reader.unconsumed)

"""
    RecordIO.number(reader) -> Int

The number of parses that `reader` has made, what isn't a record, such as a comment, included: the number of the record that it last read, which is its line number in a text file of one record a line, read from its start.
"""
number(reader::RecordReader) = reader.number

"""
    RecordIO.record_error(reader, cause) -> Exception

The error of the record that `reader` last read, for a `cause` found after it was read, such as a check of its values: what [`RecordIO.exception`](@ref) of its type makes of its [`RecordIO.offset`](@ref), its [`RecordIO.number`](@ref) and `cause`, as the reader throws for a malformed record.
"""
record_error(reader::RecordReader, cause) = reader.exception(offset(reader), number(reader), cause)

# The parser's cause of a malformed record, which it may throw rather than return, as the reader's exception.
@noinline function malformed!(reader::RecordReader{T}) where {T}
    cause = try
        malformation(T, Stream(reader.buffer))
    catch exception
        exception
    end
    throw(failure(reader, cause))
end

@noinline function miscounted(reader::RecordReader, n::Int)
    available = length(bytes(reader.buffer))
    return ArgumentError("the record parser took $n bytes of the $available available")
end

"""
    RecordIO.read_next(reader::RecordReader{T}) -> Union{T, Nothing}

The next record of `reader`, skipping what isn't one, or `nothing` at the end of the source.
It is how a package reads records itself, as a query of an indexed file does, and `iterate` reads through it.
"""
@inline function read_next(reader::RecordReader{T}) where {T}
    while available!(settle!(reader).buffer)
        x, n = read_record(T, Stream(reader.buffer))::Tuple{Any, Int}
        n < 0 && malformed!(reader)
        0 < n <= length(bytes(reader.buffer)) || throw(miscounted(reader, n))
        reader.unconsumed = n
        reader.number += 1
        x isa T && return x
    end
    return nothing
end

# `iterate` is inlined so that the tuple of a record is built at the call site, which would otherwise be allocated for each record.
@inline function Base.iterate(reader::RecordReader, state = nothing)
    x = read_next(reader)
    x === nothing && return nothing
    return x, nothing
end

# Closing a reader closes its buffer's BufferIO reader, which closes the source it wraps, and the source of a buffer that doesn't wrap it, as a mapped file.
Base.close(reader::RecordReader) = (close_buffer(reader.buffer); close_source(reader.source); nothing)
close_source(source::IO) = isopen(source) && close(source)
close_source(source) = nothing
