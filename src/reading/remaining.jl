# Remaining Bytes
# ---------------

"""
    RecordIO.remaining(reader::RecordReader) -> AbstractBufReader

The BufferIO reader of the bytes of `reader` that it has not read as records, from where it is, to the end of its source.

Formats that start with a header in another form read it from here before their records, as BAM files do, and formats whose records another format follows read that part from here, as GFF3 files hand a trailing FASTA section to a FASTA reader.
It reads the buffer that `reader` parses from, after the last record read, so reading from it is a read of the source, after which a record that borrows the buffer isn't valid.
`read`, `readline`, `peek`, `eof` and the other functions of BufferIO readers read it, and `BufferIO.IOReader` wraps it as an `IO`.
Reading records may alternate with reading from it, and the offsets in later errors count the bytes read from it too, so that they are offsets in the source, past a header read from here.
"""
remaining(reader::RecordReader) = Remaining(reader)

# The buffer of a reader, after the last record it read, which it consumes first.
struct Remaining{D <: RecordReader} <: AbstractBufReader
    reader::D
end

buffer(remaining::Remaining) = settle!(remaining.reader).buffer

BufferIO.get_buffer(remaining::Remaining) = remaining_bytes(buffer(remaining))
BufferIO.fill_buffer(remaining::Remaining) = remaining_fill(buffer(remaining))
BufferIO.consume(remaining::Remaining, n::Int) = (consume!(settle!(remaining.reader), n); nothing)
BufferIO.get_nonempty_buffer(remaining::Remaining, n::Int) = remaining_nonempty(buffer(remaining), n)
BufferIO.is_expandable(::Type{<:Remaining{<:RecordReader{T, S, B}}}) where {T, S, B} = remaining_expandable(B)
Base.close(remaining::Remaining) = close(remaining.reader)
Base.isopen(remaining::Remaining) = isopen_buffer(remaining.reader.buffer)

# A view has all its bytes, which never grow; a growing buffer reads its BufferIO reader.
remaining_bytes(buffer::ViewBuffer) = buffer.data
remaining_bytes(buffer::GrowingBuffer) = get_buffer(buffer.reader)
remaining_fill(::ViewBuffer) = 0
remaining_fill(buffer::GrowingBuffer) = fill_buffer(buffer.reader)
remaining_nonempty(buffer::ViewBuffer, n::Int) = length(buffer.data) >= max(n, 1) ? buffer.data : nothing
remaining_nonempty(buffer::GrowingBuffer, n::Int) = get_nonempty_buffer(buffer.reader, n)
remaining_expandable(::Type{ViewBuffer}) = true
remaining_expandable(::Type{GrowingBuffer{R}}) where {R} = BufferIO.is_expandable(R)
