# The record type of the manual's examples, which the pages load in their setup; the Record types page shows and runs the same code.
using RecordIO
using RecordIO: Ownership, Owned, Borrowed
using MemoryViews: ImmutableMemoryView
using StringViews: StringView

# A line of text, which owns its bytes, as a `Line{Owned}`, or borrows those of the reader's buffer, as a `LineView`.
struct Line{O <: Ownership}
    bytes::ImmutableMemoryView{UInt8}
end

const LineView = Line{Borrowed}

# The text, as a view of the record's bytes, which allocates nothing.
text(line::Line) = StringView(line.bytes)

# A view becomes an owned record with a copy of its bytes, and the two types are paired.
Base.copy(line::LineView) = Line{Owned}(ImmutableMemoryView(collect(line.bytes)))
Base.copy(line::Line{Owned}) = line
RecordIO.owned_type(::Type{LineView}) = Line{Owned}
RecordIO.borrowed_type(::Type{Line{Owned}}) = LineView

# Read one line from the start of the stream, without its newline, and return it with the bytes it took, its newline included.
# A comment or a blank line isn't a record, so it is `nothing`, which a reader skips.
@inline function RecordIO.read_record(::Type{LineView}, stream::RecordIO.Stream)
    p = RecordIO.skip_while(!=(UInt8('\n')), stream, 1)
    data = RecordIO.bytes(stream)
    # At the end of the source, `p` is after the last byte.
    taken = min(p, length(data))
    n = data[taken] == UInt8('\n') ? taken - 1 : taken
    is_line = n > 0 && data[1] != UInt8('#')
    return (is_line ? LineView(data[1:n]) : nothing), taken
end

# A line is written as its bytes and a newline.
RecordIO.write_record(sink, line::Line) = RecordIO.write_line(sink, line.bytes)
