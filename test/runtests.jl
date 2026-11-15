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

# Quality
# -------
#
# Aqua.jl checks the package for common problems: method ambiguities, type piracy, unbound type parameters, stale dependencies, and missing compat bounds.
# `Aqua.test_all` checks the package module only, so each extension, which the packages loaded above load, is checked for type piracy too: the functions of RecordIO.jl belong to the extensions as much as to the package.
import Aqua

@testset "quality" begin
    Aqua.test_all(RecordIO)
    @testset "piracy in $(name)" for name in [:RecordIOAutomaExt, :RecordIOTranscodingStreamsExt]
        Aqua.test_piracies(Base.get_extension(RecordIO, name); treat_as_own = [getfield(RecordIO, name) for name in names(RecordIO; all = true) if getfield(RecordIO, name) isa Union{Function, Type}])
    end
end
