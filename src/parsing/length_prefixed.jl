# Length-Prefixed Records
# -----------------------

"""
    RecordIO.LengthPrefixed(decode)

A parser of length-prefixed binary records, such as BAM records, of a decoder of one record, for a package's [`RecordIO.read_record`](@ref):

```julia
RecordIO.read_record(::Type{Record{Borrowed}}, stream) = RecordIO.LengthPrefixed(decode)(Record{Borrowed}, stream)
RecordIO.malformation(::Type{Record{Borrowed}}, stream) = RecordIO.malformation(RecordIO.LengthPrefixed(decode), Record{Borrowed}, stream)
```

Each record starts with its length in bytes as a little-endian `Int32`, not counting the 4 bytes of the length itself (`block_size` in BAM).
`decode(T, bytes)` decodes the record of type `T` from `bytes`, a view of its bytes, length included, which a record of type `R{Borrowed}` may borrow.
For a malformed record, it returns the exception that says why, rather than throwing it, so that reading a record enters no `try`; anything else it returns is the record.
A negative length is malformed too, and a record that the source ends inside is truncated.
"""
struct LengthPrefixed{F}
    decode::F
end

# The little-endian `Int32` in the first 4 bytes of `data`.
read_length(data::AbstractVector{UInt8}) = reinterpret(Int32, foldl((value, k) -> value | UInt32(@inbounds data[1 + k]) << (8k), 0:3; init = UInt32(0)))

# The bytes of the record, its length included, asking for more until they are all there, or `nothing` for a negative length or a record that the source ends inside.
@inline function framed(stream::Stream)
    while length(bytes(stream)) < 4
        next_bytes!(stream) || return nothing
    end
    size = read_length(bytes(stream))
    size >= 0 || return nothing
    n = 4 + Int(size)
    while length(bytes(stream)) < n
        next_bytes!(stream) || return nothing
    end
    return bytes(stream)[1:n]
end

# It is inlined, as is the decoder, so that its unions of views are split where it is called, rather than allocated for each record.
@inline function (framing::LengthPrefixed)(::Type{T}, stream::Stream) where {T}
    data = framed(stream)
    data === nothing && return nothing, -1
    x = framing.decode(T, data)
    return x isa Exception ? (nothing, -1) : (x, length(data))
end

function malformation(framing::LengthPrefixed, ::Type{T}, stream::Stream) where {T}
    data = framed(stream)
    data === nothing || return something(cause_of(framing.decode(T, data)), ArgumentError("the record is malformed"))
    available = bytes(stream)
    length(available) >= 4 && read_length(available) < 0 && return ArgumentError("negative record length $(read_length(available))")
    return ErrorException("the record is truncated")
end

cause_of(cause::Exception) = cause
cause_of(_) = nothing
