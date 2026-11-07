# Reading
# =======

# More than one fill of a buffer, so that records span fills.
@test sizeof(TEXT) > 65_536

# A reader yields the records of its type, views or copies of them, and skips what isn't a record.
@testset "reading from $(source)" for (source, open_source) in sources
    reader = RecordReader{ItemView}(open_source())
    # The reader parses from a buffer that can grow: an IO is buffered, and a BufferIO reader that can't grow is wrapped.
    @test BufferIO.is_expandable(typeof(remaining(reader)))
    @test eltype(reader) === ItemView && Base.IteratorSize(reader) == Base.SizeUnknown()
    @test map(item -> fields(copy(item)), reader) == ITEMS
    # At the end of the source, iteration ends, as it does again.
    @test iterate(reader) === nothing && isempty(collect(reader))
    close(reader)
    owned = RecordReader{Item{Owned}}(open_source())
    @test eltype(owned) === Item{Owned}
    items = [item for item in owned]
    @test items isa Vector{Item{Owned}} && map(fields, items) == ITEMS && allunique(item -> pointer(item.bytes), items)
    close(owned)
    # `collect` gives owned records, of views too.
    collected = collect(RecordReader{ItemView}(open_source()))
    @test collected isa Vector{Item{Owned}} && map(fields, collected) == ITEMS
    # `first` takes the next record, and `collect` after it collects the rest.
    reader = RecordReader{ItemView}(open_source())
    first_item = first(reader)
    @test first_item isa ItemView && fields(first_item) == ITEMS[1]
    @test map(fields, collect(reader)) == ITEMS[2:end]
    close(reader)
end

# A source whose bytes are in memory, or can be mapped into memory, is read as one view, which never refills; any other through a buffer that grows.
@testset "buffers" begin
    buffer(source) = RecordReader{ItemView}(source).buffer
    @test buffer(Vector{UInt8}(TEXT)) isa RecordIO.ViewBuffer
    @test buffer(IOBuffer(TEXT)) isa RecordIO.GrowingBuffer
    @test buffer(CursorReader(TEXT)) isa RecordIO.ViewBuffer
    @test buffer(open(plain)) isa RecordIO.ViewBuffer
    @test buffer(BufReader(IOBuffer(TEXT), 7)) isa RecordIO.GrowingBuffer
    @test buffer(trickle(TEXT)) isa RecordIO.GrowingBuffer
    # A file is mapped from its position, and an empty file is no bytes.
    io = open(plain)
    readline(io)
    @test map(fields, collect(RecordReader{ItemView}(io))) == ITEMS
    empty = joinpath(directory, "empty.txt")
    touch(empty)
    @test isempty(collect(RecordReader{ItemView}(open(empty))))
    # Closing a reader of a mapped file closes the file.
    io = open(plain)
    reader = RecordReader{ItemView}(io)
    close(reader)
    @test !isopen(io)
end

# Iteration ends at the end of the source, past what isn't a record, with `nothing`.
@testset "the end of the source" begin
    reader = RecordReader{ItemView}(IOBuffer("a\t1\n# a comment\n# another\n"))
    @test fields(first(reader)) == ("a", 1)
    # Only comments are left, which aren't records.
    @test iterate(reader) === nothing
    @test isempty(collect(RecordReader{Item{Owned}}(IOBuffer("# only a comment\n"))))
    @test isempty(collect(RecordReader{Item{Owned}}(IOBuffer(""))))
    # Records one at a time, with `iterate`.
    reader = RecordReader{ItemView}(IOBuffer("a\t1\nb\t2\n"))
    (item, _) = iterate(reader)
    @test fields(item) == ("a", 1)
    (item, _) = iterate(reader)
    @test fields(item) == ("b", 2) && iterate(reader) === nothing
end

# Records of two lines are read as they are, from sources that split them anywhere.
@testset "records of two lines from $(source)" for (source, open_source) in [
        "IOBuffer" => text -> IOBuffer(text),
        "BufReader" => text -> BufReader(IOBuffer(text), 5),
        "trickle" => text -> trickle(text),
    ]
    expected = [("name$(k)", "value$(k)"^(1 + k % 3)) for k in 1:2_000]
    text = join([">$(name)\n$(value)" for (name, value) in expected], '\n')
    @test map(entry, collect(RecordReader{Entry{Borrowed}}(open_source(text)))) == expected
    @test map(entry, RecordReader{Entry{Owned}}(open_source(text * "\n"))) == expected
    # The errors of a record give its number and its offset in the source.
    @test thrown(() -> collect(RecordReader{Entry{Borrowed}}(open_source(">a\n1\nnot an entry\n2\n")))) == RecordError(5, 2, ArgumentError("the record is malformed"))
end

# Each buffer has one owner: the buffer of the source, which views borrow, or a record's own bytes.
# Where a reader is: the offset of the record that it last read, that of the next, and the number of its parses.
@testset "offsets" begin
    text = "# header\nfirst\t1\n# between\nsecond\t22\n"
    reader = RecordReader{ItemView}(IOBuffer(text))
    @test RecordIO.offset(reader) == 0 && RecordIO.next_offset(reader) == 0 && RecordIO.number(reader) == 0
    first_item = RecordIO.read_next(reader)
    @test fields(first_item) == ("first", 1)
    # The header is 9 bytes, and the item 8, with its newline.
    @test RecordIO.offset(reader) == 9 && RecordIO.next_offset(reader) == 17 && RecordIO.number(reader) == 2
    RecordIO.read_next(reader)
    @test RecordIO.offset(reader) == 27 && RecordIO.next_offset(reader) == sizeof(text) && RecordIO.number(reader) == 4
    # The offsets of successive records are the bytes before them.
    lines = ["item$(k)\t$(k)" for k in 1:50]
    reader = RecordReader{ItemView}(IOBuffer(join(lines, '\n') * '\n'))
    offsets = [(item; RecordIO.offset(reader)) for item in reader]
    @test offsets == cumsum([0; sizeof.(lines[1:(end - 1)]) .+ 1])
    # The error of the record last read, for a cause found after it was read, is the record type's, at its offset.
    reader = RecordReader{ItemView}(IOBuffer(text))
    RecordIO.read_next(reader)
    error = RecordIO.record_error(reader, ArgumentError("the number is odd"))
    @test error isa ArgumentError && error.msg == "Malformed item 2 at offset 9: the number is odd"
end

# A package's reader has them, by the reader of records that it wraps.
@testset "offsets of an AbstractReader" begin
    reader = ItemReader{ItemView}(IOBuffer("first\t1\nsecond\t22\n"))
    first(reader)
    @test RecordIO.offset(reader) == 0 && RecordIO.next_offset(reader) == 8 && RecordIO.number(reader) == 1
    @test RecordIO.record_error(reader, ArgumentError("cause")) isa ArgumentError
end

@testset "ownership" begin
    reader = RecordReader{ItemView}(IOBuffer("first\t1\nsecond\t2\n"))
    view = first(reader)
    kept = copy(view)
    # A copy moves the fields onto a copy of the bytes.
    @test kept isa Item{Owned} && kept.fields === view.fields && kept == view && hash(kept) == hash(view)
    @test pointer(kept.bytes) != pointer(view.bytes) && copy(kept) === kept
    @test fields(kept) == ("first", 1)
    # The owned and borrowed types pair a record type with its views, and a type without views is both.
    @test RecordIO.owned_type(ItemView) === Item{Owned} && RecordIO.borrowed_type(Item{Owned}) === ItemView
    @test RecordIO.owned_type(String) === String && RecordIO.borrowed_type(String) === String
    # A copy keeps its fields after the buffer refills and grows, past a record longer than the buffer.
    long = "long" * "a"^200_000
    text = TEXT * "$(long)\t7\n" * TEXT
    expected = vcat(ITEMS, [(long, 7)], ITEMS)
    @test map(fields, collect(RecordReader{ItemView}(IOBuffer(text)))) == expected
    # A view borrows the buffer, which a trickle overwrites as it is consumed, so a view kept too long shows other bytes.
    reader = RecordReader{ItemView}(trickle(TEXT))
    early = first(reader)
    before = fields(copy(early))
    foreach(_ -> nothing, Iterators.take(reader, 2_000))
    @test before == ITEMS[1] && String(copy(early.bytes)) != "item1\t1"
end

# A reader of a package wraps a reader of records, whose methods it takes.
@testset "AbstractReader" begin
    @test eltype(ItemReader(IOBuffer(TEXT))) === Item{Owned} && eltype(ItemReader{ItemView}(IOBuffer(TEXT))) === ItemView
    @test only(Base.return_types(iterate, (typeof(ItemReader{ItemView}(IOBuffer(TEXT))),))) == Union{Nothing, Tuple{ItemView, Nothing}}
    @test map(fields, collect(ItemReader{ItemView}(IOBuffer(TEXT)))) == ITEMS
    # A reader of records is one too, which wraps itself.
    plain_reader = RecordReader{ItemView}(IOBuffer(TEXT))
    @test plain_reader isa RecordIO.AbstractReader{ItemView} && RecordIO.records(plain_reader) === plain_reader
    reader = ItemReader(IOBuffer("a\t1\n# end\n"))
    @test fields(first(reader)) == ("a", 1) && iterate(reader) === nothing
end

# Reading views allocates nothing per record: many records allocate no more than a few.
@testset "allocations" begin
    total(reader) = sum(item -> ncodeunits(name(item)) + number(item), reader; init = 0)
    allocations(n) = (reader = RecordReader{ItemView}(IOBuffer(join(LINES[1:n], '\n') * '\n')); @allocated total(reader))
    allocations(100)
    allocations(length(LINES))
    @test allocations(length(LINES)) - allocations(100) < 10_000
    # An owned record allocates its bytes, and nothing else.
    owned_total(reader) = sum(number, reader; init = 0)
    owned_allocations(n) = (reader = RecordReader{Item{Owned}}(IOBuffer(join(LINES[1:n], '\n') * '\n')); @allocated owned_total(reader))
    owned_allocations(100)
    @test owned_allocations(length(LINES)) / length(ITEMS) < 64
end

@testset "remaining from $(source)" for (source, open_source) in sources
    reader = RecordReader{ItemView}(open_source())
    foreach(_ -> iterate(reader), 1:999)
    # The header comment and 999 items have been read, so the rest starts at the 1,001st line.
    rest = join(LINES[1_001:end], '\n') * '\n'
    io = remaining(reader)
    @test peek(io, UInt8) == UInt8(first(rest))
    @test read(io, UInt8) == UInt8(first(rest))
    @test String(read(io, 10)) == rest[2:11]
    # Reading records continues after the bytes read from `remaining`.
    @test readline(io) == LINES[1_001][12:end]
    @test fields(first(reader)) == ITEMS[1_001]
    @test read(io, String) == join(LINES[1_003:end], '\n') * '\n'
    @test eof(io) && iterate(reader) === nothing
    @test_throws IOError read(io, UInt8)
    # It is open while its source is.
    @test isopen(io)
    close(io)
end

# A reader yields the parses of its type, and skips the others, of the same parser.
@testset "kinds of records" begin
    text = "a\t1\n#first\nb\t2\n#second\n"
    @test eltype(RecordReader{Note}(IOBuffer(text))) === Note
    @test [note.text for note in RecordReader{Note}(IOBuffer(text))] == ["first", "second"]
    @test [String(copy(line.bytes)) for line in RecordReader{Marked{Borrowed}}(IOBuffer(text))] == ["a\t1", "b\t2"]
    @test collect(RecordReader{Marked{Borrowed}}(IOBuffer(text))) isa Vector{Marked{Owned}}
    # A record type of its own owns its records already, which `collect` keeps as they are.
    @test collect(RecordReader{Note}(IOBuffer(text))) isa Vector{Note}
    # Iteration ends past the other kind.
    reader = RecordReader{Note}(IOBuffer("#only\na\t1\n"))
    @test first(reader).text == "only" && iterate(reader) === nothing
end

# A record longer than the buffer is parsed once: the parser asks for more bytes, and runs on from where it was.
@testset "long records" begin
    long_name = "long" * "a"^2_000_000
    text = "short\t1\n$(long_name)\t2\nafter\t3\n"
    for (source, open_source) in ["IOBuffer" => () -> IOBuffer(text), "BufReader" => () -> BufReader(IOBuffer(text), 7), "trickle" => () -> trickle(text)]
        ITEM_RUNS[] = 0
        @test (source => map(fields, collect(RecordReader{ItemView}(open_source())))) == (source => [("short", 1), (long_name, 2), ("after", 3)])
        # One run of the machine for each record, the long one included, which spans many refills.
        @test (source => ITEM_RUNS[]) == (source => 3)
    end
end

@testset "errors" begin
    # An error gives the number of the parse, comments included, its offset in the source, and quotes the record.
    invalid = vcat(LINES[1:2], ["item\tnot_a_number"], LINES[3:end])
    offset = sizeof(LINES[1]) + sizeof(LINES[2]) + 2
    @test thrown(() -> collect(RecordReader{ItemView}(IOBuffer(join(invalid, '\n'))))) == ArgumentError("Malformed item 3 at offset $(offset): the record \"item\\tnot_a_number\\nitem2\\t2\\n\" does not match the format at byte 6")
    # A long record is quoted up to 100 bytes.
    @test occursin(repr("x"^100) * "…", thrown(() -> collect(RecordReader{ItemView}(IOBuffer("x"^150 * "\tnumber\n")))).msg)
    # Without an exception of its own, a record type's errors are `RecordError`s, with the cause.
    exception = thrown(() -> collect(RecordReader{Entry{Borrowed}}(IOBuffer(">a\n1\nbroken\n"))))
    @test exception isa RecordError && exception.number == 2 && exception.offset == 5
    @test startswith(sprint(showerror, exception), "RecordError: record 2 at offset 5: ")
    # A record that the source ends inside is truncated, or malformed for a machine that doesn't accept it.
    @test thrown(() -> collect(RecordReader{ItemView}(IOBuffer("a\t1\nb\t")))) == ArgumentError("Malformed item 2 at offset 4: the record \"b\\t\" does not match the format at byte 3")
    exception = thrown(() -> collect(RecordReader{Blob{Borrowed}}(IOBuffer([0x08, 0x00, 0x00, 0x00, 0x01]))))
    @test exception isa RecordError && occursin("truncated", sprint(showerror, exception))
    # A source may say where a record is, through `RecordIO.offset`, though the reader wraps it.
    @test !(remaining(RecordReader{ItemView}(Located(CursorReader("")))) isa Located)
    @test thrown(() -> collect(RecordReader{Entry{Borrowed}}(Located(CursorReader(">a\n1\nbroken\n"))))).offset == (5, 5)
    # The offset counts the bytes read from `remaining` too, as a header before the records is.
    reader = RecordReader{Entry{Borrowed}}(IOBuffer("@header\n>a\n1\nbroken\n"))
    readline(remaining(reader))
    exception = thrown(() -> collect(reader))
    @test exception isa RecordError && exception.number == 2 && exception.offset == 13
    # Other sources are rejected with an explanation.
    @test_throws ArgumentError RecordReader{ItemView}([1, 2])
end

@testset "MalformedRecord" begin
    malformed = RecordIO.MalformedRecord{ArgumentError}("Malformed thing")
    @test malformed(10, 3, ArgumentError("bad")) == ArgumentError("Malformed thing 3 at offset 10: bad")
    @test malformed(10, 3, DomainError(1)) == RecordError(10, 3, DomainError(1))
end

# One record of given bytes, parsed as the end of a source.
@testset "parse_record" begin
    item = RecordIO.parse_record(Item{Owned}, Vector{UInt8}("name\t12"))
    @test item isa Item{Owned} && fields(item) == ("name", 12)
    @test RecordIO.parse_record(ItemView, Vector{UInt8}("name\t12\n")) == item
    @test_throws ArgumentError("the record \"name\\tx\" does not match the format at byte 6") RecordIO.parse_record(Item{Owned}, Vector{UInt8}("name\tx"))
    @test_throws ArgumentError("\"# a comment\" is not a record") RecordIO.parse_record(Item{Owned}, Vector{UInt8}("# a comment"))
    @test_throws ArgumentError("bytes are left after the record, from byte 9") RecordIO.parse_record(Item{Owned}, Vector{UInt8}("name\t12\nother\t1"))
    # No bytes are no record.
    @test_throws ArgumentError("\"\" is not a record") RecordIO.parse_record(Note, UInt8[])
end
