# Writers
# -------
#
# A writer is the mirror of a reader: it writes records of one type to a sink, as its type's `write_record` says, and counts them.

"""
    RecordWriter{T}(sink)
    RecordWriter{T}(f::Function, sink)

A writer of records of type `T` to `sink`, an `IO` or a BufferIO writer, the mirror of [`RecordReader{T}`](@ref RecordReader).

`write(writer, record)` writes a record as [`RecordIO.write_record`](@ref) of its type does, and returns the number of bytes written; it takes several records too, and a vector or a reader of them.
Anything else that `write_record` writes, such as the lines of a header, is written the same, and is counted in the bytes of the writer but not in its records.
The writer trusts its records: what a format's specification says of them is checked when it is asked for, with [`RecordIO.validate`](@ref).

Closing the writer closes its sink, and given a function `f`, the writer is passed to `f` and closed afterwards.
"""
mutable struct RecordWriter{T, S} <: AbstractWriter{T}
    const sink::S
    number::Int
    offset::Int

    RecordWriter{T}(sink::S) where {T, S} = new{T, S}(sink, 0, 0)
end

records(writer::RecordWriter) = writer

# Write one thing, which is a record of the writer if it is of its type.
@inline function write_counted!(writer::RecordWriter{T}, x) where {T}
    n = Int(write_record(writer.sink, x))
    writer.number += x isa T
    writer.offset += n
    return n
end

Base.close(writer::RecordWriter) = (close(writer.sink); nothing)
Base.flush(writer::RecordWriter) = (flush(writer.sink); nothing)
Base.isopen(writer::RecordWriter) = isopen(writer.sink)

Base.show(io::IO, writer::RecordWriter{T}) where {T} = print(io, "RecordWriter{", T, "}(", typeof(writer.sink), ", ", writer.number, " records)")
