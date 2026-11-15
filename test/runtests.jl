# Tests of RecordIO.jl
# ====================
#
# The record types of the tests are in records.jl, and the tests of each part of the package in the file of its name.

using Test
using RecordIO
using RecordIO: RecordError, LengthPrefixed, remaining, generate_read_record, Owned, Borrowed, bytes
using Automa
using BufferIO: BufferIO, AbstractBufReader, BufReader, CursorReader, IOError, consume, fill_buffer, get_buffer
using BufferIO.Testing: BoundedReader
using MemoryViews: ImmutableMemoryView, MutableMemoryView
using StringViews: StringView
using CodecZlib: GzipCompressor, GzipDecompressorStream, transcode

include("records.jl")

@testset "RecordIO" begin
    @testset "reading" begin
        include("reading.jl")
    end
    @testset "parsing" begin
        include("parsing.jl")
    end
    @testset "validation" begin
        include("validation.jl")
    end
    @testset "writing" begin
        include("writing.jl")
    end
end

