# Reading records

```@setup reading
using RecordIO
include(joinpath(pkgdir(RecordIO), "docs", "src", "line.jl"))
```

A [`RecordReader{T}`](@ref RecordReader) reads records of type `T` from a source, with the parser of the record type, and is an iterator of them, as a `Vector{T}` is.
The examples read lines with the `Line` record type of [Record types](@ref), whose parser gives `nothing` for a comment, which the reader skips.

```@example reading
text_of_lines = join(["# a header", "first", "second", "# between", "third"], '\n') * '\n'
reader = RecordReader{Line{Owned}}(IOBuffer(text_of_lines))
eltype(reader), [String(text(line)) for line in reader]
```

Iteration ends at the end of the source, and `close(reader)` closes the source.

## Owned records and views

The record type says what iteration yields:

- **`R{Owned}`:** records of their own, each with a copy of its bytes, which stay as they are after the next record is read;
- **`R{Borrowed}`:** views of the reader's buffer, which allocate nothing for each, and are valid until the next record is read.

The owned records are copies of the views, so iterating over a reader of `R{Owned}` is `Iterators.map(copy, views)`.
Reading a field as a view, such as `text`, allocates nothing either, so what a reader of views allocates is the reader itself, with the buffer of its source, whatever the number of records:

```@example reading
total_length(reader) = sum(line -> ncodeunits(text(line)), reader)
views(lines) = RecordReader{LineView}(IOBuffer(lines))
total_length(views(text_of_lines)) # compile it
few, many = text_of_lines, text_of_lines^100
(@allocated total_length(views(few))) == (@allocated total_length(views(many)))
```

### Keeping records

`collect` copies every view, so that a collected vector holds owned records, of [`RecordIO.owned_type`](@ref) of the reader's type:

```@example reading
collected = collect(views(text_of_lines))
eltype(collected), String.(text.(collected))
```

A comprehension, `map` or `push!` of views keeps views of bytes that later reads move or overwrite, so copy each as it comes to keep it:

```@example reading
copies = [copy(line) for line in views(text_of_lines)]
String.(text.(copies))
```

### Who owns which bytes

Each buffer has one owner, and is valid while its owner leaves it as it is:

| Buffer | Owner | Valid |
|:--|:--|:--|
| the bytes of the parser's stream | the buffer of the reader's source | until the next record is read: consuming a record and refilling the buffer move its bytes, and growing it replaces its memory |
| a view | the buffer of the reader's source | until the next record is read |
| an owned record's bytes | the record | as long as the record; `copy(view)` copies the bytes of the record, and no more |
| the source | the reader | from when the reader is made until it is closed; read it only through the reader, or [`RecordIO.remaining`](@ref) |

The bytes are Julia memory, and a view keeps its memory alive, so a view kept too long doesn't read freed memory: it reads the bytes that its owner has put there since.

## Reading one record at a time

[`RecordIO.read_next(reader)`](@ref RecordIO.read_next) reads the next record, skipping what isn't one, and returns `nothing` at the end of the source.
Iteration reads through it, and it is how a package reads records itself, as a query of an indexed file does, which stops at the first record past its region.

```@example reading
reader = RecordReader{LineView}(IOBuffer("first\n# a trailing comment\n"))
first_line = RecordIO.read_next(reader)
String(text(first_line)), RecordIO.read_next(reader)
```

## The readers of a package

A package's reader is parameterised on the records it yields, `Reader{T} <: RecordIO.AbstractReader{T}`, as a `Vector{T}` is on its elements, with a field `records`, the `RecordReader{T}` of its source, which gives it iteration, `eltype` and `collect`: [`RecordIO.AbstractReader`](@ref).
So `Reader{Record{Owned}}` yields owned records and `Reader{Record{Borrowed}}` views, and `collect` gives owned records either way.

```@example reading
struct LineReader{T, R <: RecordReader{T}} <: RecordIO.AbstractReader{T}
    records::R
end

LineReader{T}(source) where {T} = (records = RecordReader{T}(source); LineReader{T, typeof(records)}(records))

reader = LineReader{LineView}(IOBuffer(text_of_lines))
eltype(reader), eltype(collect(reader))
```

A reader that ends its records before the end of its source, as one of a format whose records another format follows does, defines `iterate` itself, with [`RecordIO.read_next`](@ref) of its `records`, and `collect` then gives what it yields.

## The bytes that aren't records

[`RecordIO.remaining(reader)`](@ref) is the BufferIO reader of the bytes that the reader hasn't read as records, from where it is: the buffer that the reader parses from.
A format that starts with a header in another form reads it from there before its records, as BAM files do:

```@example reading
reader = RecordReader{Line{Owned}}(IOBuffer("HEADER:4\nfirst\nsecond\n"))
header = readline(RecordIO.remaining(reader))
header, [String(text(line)) for line in reader]
```

Reading from it moves the reader on, so the records continue after the bytes read, and reading from it may alternate with reading records.

A format that ends in another one stops reading records where the other starts, and reads the rest from there, as GFF3 files hand a trailing FASTA section to a FASTA reader:

```@example reading
reader = RecordReader{Line{Owned}}(IOBuffer("first\nsecond\nEND\nanother format\n"))
lines = String[]
while (line = RecordIO.read_next(reader)) !== nothing && text(line) != "END"
    push!(lines, String(text(line)))
end
lines, read(RecordIO.remaining(reader), String)
```
