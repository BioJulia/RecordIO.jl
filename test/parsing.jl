# Parsing
# =======

@testset "LengthPrefixed" begin
    payloads = ["first", "", "a longer record", repeat("x", 70_000)]
    @test map(payload, RecordReader{Blob{Borrowed}}(IOBuffer(blobs(payloads)))) == payloads
    @test map(payload, collect(RecordReader{Blob{Owned}}(BufReader(IOBuffer(blobs(payloads)), 3)))) == payloads
    # A negative length, and a record that the decoder returns an exception for, are malformed.
    @test thrown(() -> collect(RecordReader{Blob{Borrowed}}(IOBuffer(reinterpret(UInt8, [htol(Int32(-1))]))))) == RecordError(0, 1, ArgumentError("negative record length -1"))
    @test thrown(() -> collect(RecordReader{Blob{Borrowed}}(IOBuffer(blobs(["good", "bad"]))))) == RecordError(8, 2, ArgumentError("a bad blob"))
end

@testset "generate_read_record" begin
    stream(text) = RecordIO.Stream(RecordIO.ViewBuffer(ImmutableMemoryView(Vector{UInt8}(text))))
    # A comment is `nothing`, and a record borrows the bytes of the stream, its newline left out.
    @test RecordIO.read_record(ItemView, stream("#comment\nfirst\t1")) === (nothing, 9)
    item, n = RecordIO.read_record(ItemView, stream("first\t1\nsecond\t2"))
    @test fields(item) == ("first", 1) && n == 8 && String(copy(item.bytes)) == "first\t1"
    # The end of the source ends the last record.
    @test fields(first(RecordIO.read_record(ItemView, stream("second\t2")))) == ("second", 2)
    # A failing machine returns -1, and `malformation` throws its error, which quotes the record and gives the failing byte.
    @test RecordIO.read_record(ItemView, stream("item\tx\n")) === (nothing, -1)
    @test_throws ArgumentError("the record \"item\\tx\\n\" does not match the format at byte 6") RecordIO.malformation(ItemView, stream("item\tx\n"))
    # An `ArgumentError` that `record` throws while checking quotes the record.
    checked = Module()
    Core.eval(checked, :(struct Odd end))
    Core.eval(checked, :(import RecordIO))
    Core.eval(
        checked, generate_read_record(
            checked.Odd, ITEM_MACHINE, ITEM_ACTIONS;
            setup = ITEM_SETUP,
            record = :(checking ? throw(ArgumentError("the number is odd")) : return nothing, -1),
        )
    )
    @test RecordIO.read_record(checked.Odd, stream("a\t1\n")) === (nothing, -1)
    @test_throws ArgumentError("the number is odd in the record \"a\\t1\\n\"") RecordIO.malformation(checked.Odd, stream("a\t1\nb\t2\n"))
    # Another name for the end action, and another error.
    named = Module()
    Core.eval(named, :(struct Name end))
    Core.eval(
        named, generate_read_record(
            named.Name, compile(onexit!(onenter!(RE("[a-z]*"), :mark), :name) * opt(onfinal!(RE("\n"), :newline))), Dict(:mark => :(mark = p), :name => :(range = mark:(p - 1)));
            endaction = :newline,
            setup = :(mark = 0; range = 1:0),
            record = :(String(data[range])),
            error = :(throw(DomainError(p))),
        )
    )
    @test RecordIO.read_record(named.Name, stream("abc\ndef")) == ("abc", 4)
    @test RecordIO.read_record(named.Name, stream("A")) === (nothing, -1)
    @test_throws DomainError(1) RecordIO.malformation(named.Name, stream("A"))
    # The generated code defines the end action.
    @test_throws ArgumentError generate_read_record(ItemView, ITEM_MACHINE, merge(ITEM_ACTIONS, Dict(:end_of_record => :())); record = :nothing)
end

# A machine runs on an iterator of bytes, whose end is the end of its input.
@testset "generate_execute_code" begin
    machine = compile(onexit!(onenter!(RE("[a-z]+"), :mark), :word) * opt(RE(",") * onenter!(RE("[0-9]+"), :digits)) * opt(onfinal!(RE("!"), :stop)))
    actions = Dict(
        :mark => :(start = p),
        :word => :(word = start:(p - 1)),
        :digits => :(digits_at = p),
        :stop => :(@escape),
    )
    # The same machine, with and without skipping runs of bytes.
    @testset "skip = $(skip)" for skip in (false, true)
        # The function is called in the latest world, since it is defined after the tests were compiled, and by a name that Base does not have.
        defined = Core.eval(
            Module(), quote
                function execute(iterator)
                    start = 0
                    word = 1:0
                    digits_at = 0
                    $(RecordIO.generate_execute_code(machine, actions; iterator = :iterator, skip))
                    return cs, p, word, digits_at
                end
            end
        )
        execute = input -> Base.invokelatest(defined, input)
        # Accepted at the end of the input, whose actions at the end run, with `p` after the last byte.
        @test execute(b"abc") == (0, 4, 1:3, 0)
        @test execute(b"abc,42") == (0, 7, 1:3, 5)
        # Any iterator of bytes whose `iterate(iterator, p)` gives the byte at `p`: a vector, a view, and a stream that reads more of a source as it goes.
        @test execute(Vector{UInt8}("word,7")) == (0, 7, 1:4, 6)
        @test execute(ImmutableMemoryView(Vector{UInt8}("word,7"))) == (0, 7, 1:4, 6)
        @test execute(RecordIO.Stream(RecordIO.ViewBuffer(ImmutableMemoryView(Vector{UInt8}("xy"))))) == (0, 3, 1:2, 0)
        # `@escape` stops after its byte, with `p` at the next, in a positive state.
        cs, p, word, _ = execute(b"stop!more")
        @test cs > 0 && p == 6 && word == 1:4
        # A byte that no edge takes fails the machine, at the byte, and an input that ends too soon is rejected at its end.
        cs, p, _, _ = execute(b"ab#")
        @test cs < 0 && p == 3
        cs, p, _, _ = execute(b"ab,")
        @test cs < 0 && p == 4
        @test execute(UInt8[])[1] < 0
        # A run of bytes across many refills of a source.
        long = "a"^100_000 * ",1"
        @test execute(RecordIO.Stream(RecordIO.GrowingBuffer(BufReader(IOBuffer(long), 7)))) == (0, 100_003, 1:100_000, 100_002)
    end
end

# A skip over bytes of a set ends at the first byte outside it, or after the last byte.
@testset "skip_while" begin
    letter(byte) = (byte >= UInt8('a')) & (byte <= UInt8('z'))
    text = "ab" * "x"^100 * "1end"
    @test RecordIO.skip_while(letter, Vector{UInt8}(text), 1) == 103
    @test RecordIO.skip_while(letter, Vector{UInt8}(text), 103) == 103
    @test RecordIO.skip_while(letter, Vector{UInt8}(text), 104) == 107
    @test RecordIO.skip_while(letter, Vector{UInt8}("abc"), 1) == 4
    # A stream skips across refills of its buffer, of 7 bytes at first, and to the end of the source.
    streamed(text) = RecordIO.Stream(RecordIO.GrowingBuffer(BufReader(IOBuffer(text), 7)))
    @test RecordIO.skip_while(letter, streamed(text), 1) == 103
    @test RecordIO.skip_while(letter, streamed("z"^1_000), 1) == 1_001
    @test RecordIO.skip_while(letter, RecordIO.Stream(RecordIO.ViewBuffer(ImmutableMemoryView(Vector{UInt8}(text)))), 3) == 103
end

# The fields of a record, read by the type wanted, allocating only for a `String`.
@testset "fields" begin
    data = ImmutableMemoryView(Vector{UInt8}("chr1\t-12\t+7\t300\t3.5e2\t.\tx,,y,\tA"))
    field(T, range) = RecordIO.parse_field(T, data, range)
    @test field(Int, 6:8) === -12 && field(Int32, 10:11) === Int32(7) && field(UInt16, 13:15) === UInt16(300)
    @test field(Float64, 17:21) === 350.0 && field(Float32, 17:21) === 350.0f0
    @test field(String, 1:4) == "chr1" && field(StringView, 1:4) == "chr1" && field(StringView, 1:4) isa StringView
    @test field(Char, 31:31) === 'A'
    @test_throws OverflowError field(Int8, 13:15)
    @test_throws ArgumentError field(Float64, 1:4)
    @test_throws ArgumentError field(Char, 1:4)
    # Every value of an integer type is read, its least included, and what overflows it is not.
    limits = ImmutableMemoryView(Vector{UInt8}("-128\t127\t128\t-129\t-\t+\t255"))
    limit(T, range) = RecordIO.parse_field(T, limits, range)
    @test limit(Int8, 1:4) === typemin(Int8) && limit(Int8, 6:8) === typemax(Int8) && limit(UInt8, 23:25) === typemax(UInt8)
    @test_throws OverflowError limit(Int8, 10:12)
    @test_throws OverflowError limit(Int8, 14:17)
    # A field without digits is not a number, and a range outside the data is out of bounds.
    @test_throws ArgumentError limit(Int, 19:19)
    @test_throws ArgumentError limit(Int, 21:21)
    @test_throws ArgumentError limit(Int, 1:0)
    @test_throws ArgumentError limit(UInt, 1:0)
    @test_throws BoundsError RecordIO.parse_field(UInt, collect(limits), 24:40)
    @test_throws BoundsError RecordIO.parse_field(Int, collect(limits), 24:40)
    @test_throws Exception limit(UInt, 24:40)
    # A check of a field reads it without throwing: `nothing` where `parse_field` throws.
    attempt(T, range) = RecordIO.try_parse_field(T, limits, range)
    @test attempt(Int8, 1:4) === typemin(Int8) && attempt(UInt8, 23:25) === typemax(UInt8)
    @test attempt(Int8, 10:12) === nothing && attempt(Int8, 14:17) === nothing && attempt(UInt8, 1:4) === nothing
    @test attempt(Int, 19:19) === nothing && attempt(Int, 1:0) === nothing && attempt(UInt, 1:0) === nothing
    @test RecordIO.try_parse_field(Float64, data, 17:21) === 350.0 && RecordIO.try_parse_field(Float64, data, 1:4) === nothing
    @test (@allocated attempt(Int8, 10:12)) == 0
    @test RecordIO.is_missing(data, 23:23, UInt8('.')) && !RecordIO.is_missing(data, 1:4, UInt8('.'))
    @test collect(RecordIO.separated(data, 25:29, UInt8(','))) == [25:25, 27:26, 28:28, 30:29]
    @test collect(RecordIO.separated(data, 25:24, UInt8(','))) == [25:24]
    @test RecordIO.field_equals(data, 1:4, "chr1") && !RecordIO.field_equals(data, 1:4, "chr2") && !RecordIO.field_equals(data, 1:4, "chr")
    reading(data) = field(Int, 6:8) + field(Float64, 17:21) + ncodeunits(field(StringView, 1:4)) + sum(length, RecordIO.separated(data, 25:29, UInt8(',')))
    reading(data)
    @test @allocated(reading(data)) == 0
end
