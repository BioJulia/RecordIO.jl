# Sources

```@setup sources
using RecordIO
include(joinpath(pkgdir(RecordIO), "docs", "src", "line.jl"))
```

A reader parses its records straight from where their bytes are, which depends on the source:

- a vector of bytes that are contiguous in memory, or a regular file opened with `open`, is parsed as one view of its bytes, the file mapped into memory;
- any other `IO`, such as an `IOBuffer`, is buffered with a `BufReader`, which the reader grows as the parser needs;
- a BufferIO reader is parsed from its own buffer.

The bytes are copied only into an owned record and, for an `IO` that isn't a regular file, into the `BufReader`'s buffer, so a reader of views reads its source without allocating for each record.

## Bytes in memory

```@example sources
reader = RecordReader{Line{Owned}}(Vector{UInt8}("first\nsecond\n"))
[String(text(line)) for line in reader]
```

A vector is parsed where its bytes are, so they need to be contiguous in memory: a vector of a type of which MemoryViews makes a view, such as a `Vector{UInt8}`, a contiguous view of one, or the `codeunits` of a `String`.
Any other vector, such as a strided view or a range, throws an `ArgumentError`; read a copy of it, as a `Vector{UInt8}`, instead.

A regular file opened with `open` is mapped into memory and parsed the same, so its bytes are read as the parser reaches them, and never copied into a buffer.

## `IO`s

```@example sources
reader = RecordReader{Line{Owned}}(IOBuffer("first\nsecond\n"))
[String(text(line)) for line in reader]
```

The `BufReader` starts with BufferIO's buffer size for the `IO`, and grows for a record longer than it.
To choose the size, pass a `BufReader` of your own.
A buffer of 4 bytes makes the lines span many fills, but the parser never sees where one fill ends and the next begins, since its stream grows the buffer and reads on until the line is complete:

```@example sources
using BufferIO: BufReader
reader = RecordReader{Line{Owned}}(BufReader(IOBuffer("a longer first line\nsecond\n"), 4))
[String(text(line)) for line in reader]
```

A decompressing stream of TranscodingStreams, such as `CodecZlib.GzipDecompressorStream`, is an `IO` too.
BufferIO can't read it directly, since two methods of `readbytes!` apply to it, so with TranscodingStreams loaded, a reader reads it through an adapter of its own.
Its bytes are copied once more than a BufferIO reader's would be: from the stream's buffer into the `BufReader`'s.

## BufferIO readers

A BufferIO reader is parsed from its own buffer, such as a `CursorReader` of bytes in memory:

```@example sources
using BufferIO: CursorReader
reader = RecordReader{Line{Owned}}(CursorReader("first\nsecond\n"))
[String(text(line)) for line in reader]
```

A record needs to be whole in the buffer, so a reader whose buffer can't grow, such as one that holds one block of a compressed file, is wrapped with BufferIO's `expandable`.
The wrapper forwards the reader's buffer, and copies bytes into a buffer of its own only for a record that spans the end of it:

```@example sources
using BufferIO.Testing: BoundedReader
source = BoundedReader("a longer first line\nsecond\n", 8) # a buffer of at most 8 bytes
reader = RecordReader{Line{Owned}}(source)
[String(text(line)) for line in reader]
```

A package makes its own kind of source readable by making it a BufferIO reader: a subtype of `AbstractBufReader`, with methods of `get_buffer`, `fill_buffer`, `consume` and `close`, as BufferIO's documentation describes.
It may also say where a record is in errors, with a method of [`RecordIO.offset`](@ref), as the [Errors](errors.md) page shows.

## Taking over the source

The reader takes over its source: read from it only through the reader, or through [`RecordIO.remaining`](@ref), which is the BufferIO reader that the reader parses from.
`close(reader)` closes it, and so the source.
