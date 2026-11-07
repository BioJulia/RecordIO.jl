# Reading: What a Record Type Says
# ---------------------------------

"""
    RecordIO.read_record(::Type{T}, stream::RecordIO.Stream) -> (x, n::Int)

Parse one record of type `T` from the start of [`RecordIO.bytes(stream)`](@ref RecordIO.bytes), and return it, `x`, with the number of bytes it took, `n`, its end, such as a newline, included.
A record package defines it for its record types, and a [`RecordReader{T}`](@ref RecordReader) calls it for each record.

- `x` is the record, of type `T`, or what the parser found that isn't one, such as `nothing` for a comment or a blank line, or a record of another kind, which the reader skips: it yields only an `x isa T`.
- `n > 0` is the bytes of the record, which the reader consumes before it reads the next one, so that a record of type `T` may borrow them till then.
- `n < 0` says the record is malformed, and [`RecordIO.malformation(T, stream)`](@ref RecordIO.malformation) says why, so that reading a record enters no `try`, which would cost more than a short record takes to parse.
- The parser iterates over the bytes of the stream as they come, as the machines of [`RecordIO.generate_read_record`](@ref) do, to the end of the source, and never sees where one read from the source ends and the next begins.

A record of type `R{Borrowed}` borrows the bytes of `stream`; one of type `R{Owned}` copies them.
A package defines the parser of its views, and that of its owned records follows: where [`RecordIO.borrowed_type(T)`](@ref RecordIO.borrowed_type) is another type, the parser of `T` is that of the views, with each record copied.
A parser that returns a record or something else, such as `nothing`, is `@inline`, so that the reader splits the union where it calls it, rather than allocating the tuple for each record, as the parsers of [`RecordIO.generate_read_record`](@ref) are.
[`RecordIO.generate_read_record`](@ref) generates a parser from an Automa state machine, and [`RecordIO.LengthPrefixed`](@ref) one from a decoder of length-prefixed binary records.
"""
function read_record end

"""
    RecordIO.malformation(::Type{T}, stream::RecordIO.Stream) -> Exception

Why the record of type `T` at the start of `stream` is malformed, after [`RecordIO.read_record(T, stream)`](@ref RecordIO.read_record) returned a negative count: the cause that the reader's exception turns into its error.

It is called only for a malformed record, so it may parse the record again to say why, and may throw the cause rather than return it.
By default, it is that of the views of `T`, [`RecordIO.borrowed_type(T)`](@ref RecordIO.borrowed_type), where `T` has them, and otherwise `ArgumentError("the record is malformed")`.
Parsers made by [`RecordIO.generate_read_record`](@ref) define it, with the messages of their errors.
"""
malformation(::Type{T}, stream::Stream) where {T} = borrowed_type(T) === T ? ArgumentError("the record is malformed") : malformation(borrowed_type(T), stream)

# The parser of the owned records of a type whose views have one: the view, copied.
# A type without views of another type has no parser until its package defines one.
@inline function read_record(::Type{T}, stream::Stream) where {T}
    V = borrowed_type(T)
    V === T && throw(MethodError(read_record, (T, stream)))
    x, n = read_record(V, stream)
    return (x isa V ? copy(x) : x), n
end

"""
    RecordIO.exception(T)

The errors of the records of type `T`: a function of `(offset, number, cause)` that returns the exception to throw for a malformed record, such as a [`RecordIO.MalformedRecord`](@ref).
By default, it is [`RecordIO.RecordError`](@ref).
"""
exception(::Type) = RecordError

# It is inlined, as `read_record` is, so that the record, which the parser's `Union` with what isn't one boxes, is unboxed where it is used.
"""
    RecordIO.parse_record(::Type{T}, data::AbstractVector{UInt8}) -> T

Parse all of `data` as one record of type `T`, with [`RecordIO.read_record(T, stream)`](@ref RecordIO.read_record), as the end of a source, and return it; a record of type `R{Borrowed}` borrows `data`.
It throws the record's `malformation` if it is malformed, and an `ArgumentError` if it is truncated, if it isn't a `T`, such as a comment, or if bytes are left after it.
It is how a package makes a record of given bytes, as a constructor `Record(data)` does.
"""
@inline function parse_record(::Type{T}, data::AbstractVector{UInt8}) where {T}
    view = ImmutableMemoryView(data)
    # A parser is never given no bytes, which aren't a record, as a reader never parses past the end of its source.
    isempty(view) && unparsed(T, view, 0)
    x, n = read_record(T, Stream(ViewBuffer(view)))
    # The record is taken as soon as it is known to be one, so that it is never boxed with what isn't one, and the error is found out of line, so that the buffer never escapes.
    x isa T && n == length(view) && return x
    return unparsed(T, view, n)
end

# Why `data` isn't one record of type `T`, which the parser read `n` bytes of.
@noinline function unparsed(::Type{T}, data::ImmutableMemoryView{UInt8}, n::Int) where {T}
    isempty(data) && throw(ArgumentError("\"\" is not a record"))
    n < 0 && throw(malformation(T, Stream(ViewBuffer(data))))
    iszero(n) && throw(ArgumentError("the record is truncated"))
    n == length(data) || throw(ArgumentError(string("bytes are left after the record, from byte ", n + 1)))
    throw(ArgumentError(string(quoted(data, length(data)), " is not a record")))
end
