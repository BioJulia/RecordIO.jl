# Writing
# =======
#
# An item is written as its line, and a comment, which is not a record of the writer's type, as a line too; a blob is written from its payload, after its length.
struct Comment
    text::String
end

RecordIO.write_record(sink, item::Item) = RecordIO.write_line(sink, item.bytes)
RecordIO.write_record(sink, comment::Comment) = write(sink, UInt8('#')) + RecordIO.write_line(sink, codeunits(comment.text))
RecordIO.write_record(sink, payload::Vector{UInt8}) = RecordIO.write_length_prefixed(sink, payload)

# A writer writes what a record type says of one record, to an `IO` or a BufferIO writer, and counts its records and bytes.
@testset "RecordWriter" begin
    items = collect(RecordReader{Item{Owned}}(IOBuffer(TEXT)))
    text = join((string(name, '\t', number, '\n') for (name, number) in ITEMS))
    for sink in (() -> IOBuffer(), () -> BufferIO.BufWriter(IOBuffer()))
        writer = RecordWriter{Item}(sink())
        @test writer isa RecordIO.AbstractWriter{Item}
        @test write(writer, items[1]) == length(items[1].bytes) + 1
        @test write(writer, items[2:end]) + length(items[1].bytes) + 1 == sizeof(text)
        @test RecordIO.number(writer) == length(items)
        @test RecordIO.offset(writer) == sizeof(text)
        flush(writer)
        @test occursin("$(length(items)) records", repr(writer))
    end
    # What is written reads back as it was, from a reader of views too, each written before the next is read.
    io = IOBuffer()
    writer = RecordWriter{Item}(io)
    @test write(writer, RecordReader{ItemView}(IOBuffer(TEXT))) == sizeof(text)
    @test String(take!(io)) == text
    @test write(writer, items[1], items[2]) == sum(item -> length(item.bytes) + 1, items[1:2])
    # Anything else that `write_record` writes is counted in the bytes, not in the records.
    @test write(writer, Comment("note")) == 6
    @test RecordIO.number(writer) == length(items) + 2
    @test String(take!(io)) == join(string(name, '\t', number, '\n') for (name, number) in ITEMS[1:2]) * "#note\n"
    # Given a function, the writer is closed afterwards, whether or not the function throws; a path is opened to write or to append.
    mktempdir() do directory
        path = joinpath(directory, "items.txt")
        @test open(writer -> write(writer, items), RecordWriter{Item}, path) == sizeof(text)
        @test read(path, String) == text
        open(writer -> write(writer, items[1]), RecordWriter{Item}, path; append = true)
        @test length(collect(RecordReader{ItemView}(open(path)))) == length(items) + 1
        file = open(path, "w")
        @test_throws DomainError RecordWriter{Item}(writer -> throw(DomainError(1)), file)
        @test !isopen(file)
        writer = open(RecordWriter{Item}, path)
        @test isopen(writer)
        close(writer)
        @test !isopen(writer)
    end
    # Binary records: little-endian integers, and the framing that `LengthPrefixed` reads.
    io = IOBuffer()
    @test RecordIO.write_le(io, 0x01) + RecordIO.write_le(io, Int16(-2)) + RecordIO.write_le(io, 0x04030201) + RecordIO.write_le(io, Int64(5)) == 15
    @test take!(io) == [0x01; 0xfe; 0xff; 0x01; 0x02; 0x03; 0x04; 0x05; zeros(UInt8, 7)]
    payloads = ["a", "", "longer"]
    writer = RecordWriter{Blob}(io)
    @test sum(payload -> write(writer, Vector{UInt8}(payload)), payloads) == sum(sizeof, payloads) + 4 * length(payloads)
    @test map(payload, RecordReader{Blob{Borrowed}}(IOBuffer(take!(io)))) == payloads
    @test RecordIO.write_bytes(io, b"abcdef", 2:3) == 2
    @test RecordIO.write_bytes(io, codeunits("")) == 0
    @test RecordIO.write_line(io, ImmutableMemoryView(Vector{UInt8}("xy"))) == 3
    @test String(take!(io)) == "bcxy\n"
    @test_throws BoundsError RecordIO.write_bytes(io, b"abc", 2:4)
    # Writing allocates nothing for a record.
    writer = RecordWriter{Item}(IOBuffer(; sizehint = 1024))
    item = items[1]
    write(writer, item)
    @test iszero(@allocated write(writer, item))
    sink = IOBuffer(; sizehint = 1024)
    RecordIO.write_le(sink, Int32(1))
    @test iszero(@allocated RecordIO.write_le(sink, Int32(1)))
end
