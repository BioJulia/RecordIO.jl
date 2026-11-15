# Writing records

```@setup writing
using RecordIO
include(joinpath(pkgdir(RecordIO), "docs", "src", "line.jl"))
```

A [`RecordWriter{T}`](@ref RecordWriter) writes records of type `T` to a sink, and is the mirror of a `RecordReader{T}`.
A record type says how one record is written with a method of [`RecordIO.write_record`](@ref), as it says how one is read with `RecordIO.read_record`.
The `Line` record type of [Record types](@ref) is written as its bytes and a newline:

```julia
RecordIO.write_record(sink, line::Line) = RecordIO.write_line(sink, line.bytes)
```

`write` writes a record, several, or all those of a vector or of a reader, and returns the number of bytes written.
The records of a reader of views are each written before the next is read, so copying a file allocates nothing for each record:

```@example writing
text_of_lines = join(["first", "second", "third"], '\n') * '\n'
output = IOBuffer()
writer = RecordWriter{Line}(output)
write(writer, RecordReader{LineView}(IOBuffer(text_of_lines)))
```

The writer counts the records and the bytes that it has written:

```@example writing
RecordIO.number(writer), RecordIO.offset(writer), String(take!(output))
```

The writer trusts its records, and writes them as they are.
What the specification of a format says of a record is checked when it is asked for, with [`RecordIO.validate`](@ref).

## Sinks

A sink is an `IO` or a BufferIO writer, and `close(writer)` closes it.
Given a function, a writer is closed when the function returns or throws, and `open` makes a writer of a file, to write it or, with `append = true`, to add to it:

```@example writing
path = tempname()
open(RecordWriter{Line}, path) do writer
    write(writer, collect(RecordReader{Line{Owned}}(IOBuffer(text_of_lines))))
end
read(path, String)
```

## What a record type writes

`write_record(sink, record)` writes one record with what ends or frames it, and returns the number of bytes.
These write to any sink, and allocate nothing:

- [`RecordIO.write_bytes`](@ref): a vector or a memory view of bytes, or a range of it;
- [`RecordIO.write_line`](@ref): the same, and a newline;
- [`RecordIO.write_le`](@ref): an integer, in little-endian order, as binary formats store them;
- [`RecordIO.write_length_prefixed`](@ref): bytes after their length, the framing that [`RecordIO.LengthPrefixed`](@ref) reads.

A method of `write_record` for anything else that a file holds, such as a line of a header, is written by the same `write`, and is counted in the bytes of the writer, but not in its records.

## Writers of record packages

A package's writer is a subtype of [`RecordIO.AbstractWriter{T}`](@ref RecordIO.AbstractWriter) that holds a `RecordWriter{T}` in a field named `records`, as its reader holds a `RecordReader{T}`.
It needs only a constructor that takes the sink first, where it may write a header, and has `write`, `close`, `flush`, `open` and the form that takes a function from its supertype:

```@example writing
struct LineWriter{S} <: RecordIO.AbstractWriter{Line}
    records::RecordWriter{Line, S}
end

LineWriter(sink) = LineWriter(RecordWriter{Line}(sink))

output = IOBuffer()
writer = LineWriter(output)
write(writer, RecordIO.parse_record(LineView, codeunits("only")))
String(take!(output))
```
