# Validation
# ==========

# What the checks of records read of an item: its number is at most 255, and its line is what an error quotes of it.
RecordIO.problem(item::Item) = RecordIO.try_parse_field(UInt8, item.bytes, item.fields.number) === nothing ? "the number is above 255" : nothing
RecordIO.description(item::Item) = RecordIO.description(item.bytes)
RecordIO.validate(reader::ItemReader) = RecordIO.validate(ascending_or_equal, reader.records, 0)

# The step of the check of a file of items: each is at most 255, and no less than the one before it.
function ascending_or_equal(last_number::Int, item::Item)
    message = RecordIO.problem(item)
    message === nothing || return message
    return number(item) >= last_number ? number(item) : "the numbers are not ascending"
end

# The checks of records against a specification, which a record package gives its `problem`, and a reader's loop.
@testset "validation" begin
    text = "first\t1\n# a comment\nsecond\t22\nthird\t256\nfourth\t4\n"
    items = collect(RecordReader{Item{Owned}}(IOBuffer(text)))
    @test map(RecordIO.problem, items) == [nothing, nothing, "the number is above 255", nothing]
    @test map(RecordIO.is_valid, items) == [true, true, false, true]
    @test RecordIO.validate(items[1]) === items[1]
    # The error of a record quotes what its package describes of it.
    error = try
        RecordIO.validate(items[3])
    catch error
        error
    end
    @test error isa ArgumentError && error.msg == "the number is above 255 in the record \"third\\t256\""
    @test RecordIO.description(UInt8[]) == "\"\""
    @test endswith(RecordIO.description(Vector{UInt8}("a"^300)), "…") || length(RecordIO.description(Vector{UInt8}("a"^300))) < 300

    # The loop over a reader: the step checks each record with the state that those before it left, and the error gives the number and the offset of the record.
    ascending(last_number, item) = (message = RecordIO.problem(item); message !== nothing ? message : number(item) > last_number ? number(item) : "the numbers are not ascending")
    @test RecordIO.validate(ascending, RecordReader{ItemView}(IOBuffer("first\t1\n# a comment\nsecond\t22\n")), 0) == 2
    error = try
        RecordIO.validate(ascending, RecordReader{ItemView}(IOBuffer(text)), 0)
    catch error
        error
    end
    @test error isa ArgumentError && error.msg == "Malformed item 4 at offset 30: the number is above 255 in the record \"third\\t256\""
    error = try
        RecordIO.validate(ascending, RecordReader{ItemView}(IOBuffer("first\t5\nsecond\t2\n")), 0)
    catch error
        error
    end
    @test error.msg == "Malformed item 2 at offset 8: the numbers are not ascending in the record \"second\\t2\""
    # A reader made from another carries on from where it is, as another type of record, with its count of records and of bytes.
    owned = RecordReader{Item{Owned}}(IOBuffer("first\t1\nsecond\t2\nthird\t3\nfourth\t2\n"))
    @test name(first(owned)) == "first"
    views = RecordReader{ItemView}(owned)
    @test eltype(views) == ItemView && name(first(views)) == "second"
    error = try
        RecordIO.validate(ascending, views, 2)
    catch error
        error
    end
    @test error.msg == "Malformed item 4 at offset 25: the numbers are not ascending in the record \"fourth\\t2\""
    # A step that returns `Stop()` ends the records before the source does, whatever the state is.
    until_stop(state, item) = name(item) == "stop" ? RecordIO.Stop() : state
    reader = RecordReader{ItemView}(IOBuffer("first\t1\nstop\t0\nthird\t999\n"))
    @test RecordIO.validate(until_stop, reader, nothing) == 1
    # The loop allocates nothing for each record.
    many(count) = RecordReader{ItemView}(IOBuffer(("item\t1\n")^count))
    RecordIO.validate(ascending_or_equal, many(10), 0)
    # What a longer source adds is the growth of its buffer, less than an allocation for each record would be.
    @test (@allocated RecordIO.validate(ascending_or_equal, many(1000), 0)) - (@allocated RecordIO.validate(ascending_or_equal, many(10), 0)) < 16 * 990

    # A type of reader and a source: the source is opened, checked and closed.
    @test RecordIO.validate(ItemReader{ItemView}, IOBuffer("first\t1\nsecond\t22\n")) == 2
    @test_throws "Malformed item 4 at offset 30" RecordIO.validate(ItemReader{ItemView}, IOBuffer(text))

    # A copy of the bytes of a view is in memory of its own.
    bytes = ImmutableMemoryView(Vector{UInt8}("bytes"))
    copied_bytes = RecordIO.copy_bytes(bytes)
    @test copied_bytes == bytes && copied_bytes isa ImmutableMemoryView{UInt8} && pointer(copied_bytes) != pointer(bytes)
end
