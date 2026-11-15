# Writing: What a Record Type Says
# --------------------------------
#
# A record type says how one record is written to a sink, with `write_record`, and a writer does the rest.
# A sink is an `IO` or a BufferIO writer, which both take `unsafe_write` and the write of a byte.

"""
    RecordIO.write_record(sink, record) -> Int

Write `record` to `sink`, with what ends or frames it in its format, such as the newline of a line, and return the number of bytes written.

A record package defines it for its record type, as it defines [`RecordIO.read_record`](@ref) to read one, and for anything else that its files hold, such as the lines of a header.
[`RecordIO.write_bytes`](@ref), [`RecordIO.write_line`](@ref), [`RecordIO.write_le`](@ref) and [`RecordIO.write_length_prefixed`](@ref) write to any sink, and allocate nothing.
"""
function write_record end

"""
    RecordIO.write_bytes(sink, bytes) -> Int
    RecordIO.write_bytes(sink, bytes, range::UnitRange{Int}) -> Int

Write `bytes`, a vector or a memory view of bytes, or those of `range` of it, to `sink`, and return their number.
"""
@inline function write_bytes(sink, bytes::Union{DenseVector{UInt8}, ImmutableMemoryView{UInt8}, MutableMemoryView{UInt8}})
    isempty(bytes) && return 0
    return Int(GC.@preserve bytes unsafe_write(sink, pointer(bytes), UInt(length(bytes))))
end

@inline function write_bytes(sink, bytes::Union{DenseVector{UInt8}, ImmutableMemoryView{UInt8}, MutableMemoryView{UInt8}}, range::UnitRange{Int})
    isempty(range) && return 0
    checkbounds(bytes, range)
    return Int(GC.@preserve bytes unsafe_write(sink, pointer(bytes, first(range)), UInt(length(range))))
end

write_bytes(sink, bytes::Base.CodeUnits{UInt8, String}) = Int(write(sink, bytes))

"""
    RecordIO.write_line(sink, bytes) -> Int
    RecordIO.write_line(sink, bytes, range::UnitRange{Int}) -> Int

Write `bytes`, as [`RecordIO.write_bytes`](@ref) does, and a newline, and return the number of bytes written.
"""
@inline write_line(sink, bytes...) = write_bytes(sink, bytes...) + Int(write(sink, UInt8('\n')))

"""
    RecordIO.write_le(sink, x::Integer) -> Int

Write the bytes of `x`, an integer of a fixed size, in little-endian order, and return their number.
"""
@inline write_le(sink, x::Union{UInt8, Int8}) = Int(write(sink, x % UInt8))

@inline function write_le(sink, x::T) where {T <: Union{Int16, UInt16, Int32, UInt32, Int64, UInt64}}
    ref = Ref(htol(x))
    return Int(GC.@preserve ref unsafe_write(sink, Ptr{UInt8}(Base.unsafe_convert(Ptr{T}, ref)), UInt(sizeof(T))))
end

"""
    RecordIO.write_length_prefixed(sink, parts...) -> Int

Write the record that `parts`, vectors or memory views of bytes, make together, after its length in bytes as a little-endian `Int32`, as [`RecordIO.LengthPrefixed`](@ref) reads it, and return the number of bytes written, the 4 of the length included.
"""
@inline function write_length_prefixed(sink, parts...)
    n = write_le(sink, Int32(sum(length, parts; init = 0)))
    return n + sum(part -> write_bytes(sink, part), parts; init = 0)
end
