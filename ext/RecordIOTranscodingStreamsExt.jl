module RecordIOTranscodingStreamsExt

using RecordIO
using TranscodingStreams: TranscodingStream
# An extension loads only its parent and its triggers, so BufferIO and the view types come through RecordIO.
using RecordIO: BufReader, MutableMemoryView

# BufferIO's `BufReader` reads an `IO` with `readbytes!` into a `MutableMemoryView`, which is ambiguous for a `TranscodingStream`:
# MemoryViews' method for any `IO` and TranscodingStreams' method for any `DenseArray` both apply, and neither is more specific.
# A `TranscodingStream` is read through this adapter instead, whose method of its own reads the bytes that the stream has buffered.
struct Transcoded{S <: TranscodingStream} <: IO
    stream::S
end

function Base.readbytes!(io::Transcoded, destination::MutableMemoryView{UInt8}, count::Integer = length(destination))
    eof(io.stream) && return 0
    # The stream has buffered at least one byte, which it reads without blocking.
    n = min(Int(count), length(destination), max(bytesavailable(io.stream), 1))
    GC.@preserve destination unsafe_read(io.stream, pointer(destination), n)
    return n
end

Base.eof(io::Transcoded) = eof(io.stream)
Base.isopen(io::Transcoded) = isopen(io.stream)
Base.close(io::Transcoded) = close(io.stream)
Base.bytesavailable(io::Transcoded) = bytesavailable(io.stream)

RecordIO.buffered(stream::TranscodingStream) = BufReader(Transcoded(stream))

end # module RecordIOTranscodingStreamsExt
