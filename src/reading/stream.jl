# Streams
# -------
#
# The stream is the iterator over a buffer's bytes that a parser reads.

"""
    RecordIO.Stream

The bytes that a record parser reads: an iterator over the bytes of the reader's buffer, from the first byte of a record, as `UInt8`s.

- As for a vector, `iterate(stream, p)` gives the byte at position `p`, from 1, so a parser's position is the state it iterates with, and `enumerate(stream)` gives positions and bytes.
- When `p` passes the bytes in the buffer, the stream reads more of the source, and it ends at the end of the source, so a parser never sees where one read from the source ends and the next begins.
- [`RecordIO.bytes(stream)`](@ref RecordIO.bytes) is an `ImmutableMemoryView{UInt8}` of the bytes read so far, of which a record takes its own.

The bytes start at the record's first byte, which stays at index 1 when they grow, so a parser's positions stay valid.
A record may borrow them, which are valid until the reader reads the next record.
"""
struct Stream{B <: Buffer}
    buffer::B
end

"""
    RecordIO.bytes(stream::RecordIO.Stream) -> ImmutableMemoryView{UInt8}

The bytes of `stream` read so far, from the first byte of the record that the parser reads.
"""
@inline bytes(stream::Stream) = bytes(stream.buffer)
next_bytes!(stream::Stream) = next_bytes!(stream.buffer)

Base.eltype(::Type{<:Stream}) = UInt8
Base.IteratorSize(::Type{<:Stream}) = Base.SizeUnknown()

# The state is the position of the byte, and the bytes are those of the buffer, which change only when more of the source is read.
@inline function Base.iterate(stream::Stream, p::Int = 1)
    data = bytes(stream)
    if p > length(data)
        next_bytes!(stream.buffer) || return nothing
        data = bytes(stream)
    end
    return (@inbounds data[p]), p + 1
end

"""
    RecordIO.skip_while(f, iterator, p::Int) -> Int

The position of the first byte of `iterator` from position `p` for which `f` is false, or the position after its last byte, where `iterate(iterator, p)` gives the byte at position `p`.

The machines of [`RecordIO.generate_execute_code`](@ref) with `skip = true` call it in a state that loops to itself on a set of bytes, such as a long sequence of a SAM record, with `f` the test of the set, which has no branches.
A [`RecordIO.Stream`](@ref) tests 32 bytes at a time, which compiles to vector instructions, and reads more of the source when it reaches the end of the bytes in its buffer; any other iterator, one byte at a time.
"""
@inline function skip_while(f::F, iterator, p::Int) where {F}
    while true
        next = iterate(iterator, p)
        (next === nothing || !f(first(next))) && return p
        p += 1
    end
    return
end

@inline function skip_while(f::F, stream::Stream, p::Int) where {F}
    while true
        data = bytes(stream)
        n = length(data)
        # 32 bytes at a time, without branches, while all are in the set.
        while p + 31 <= n
            all_in = true
            for k in 0:31
                all_in &= f(@inbounds data[p + k])
            end
            all_in || break
            p += 32
        end
        while p <= n
            f(@inbounds data[p]) || return p
            p += 1
        end
        next_bytes!(stream.buffer) || return p
    end
    return
end
