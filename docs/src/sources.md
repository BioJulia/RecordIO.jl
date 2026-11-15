# Sources

```@setup sources
using RecordIO
include(joinpath(pkgdir(RecordIO), "docs", "src", "line.jl"))
```

A reader parses its records straight from the buffer of a BufferIO reader, which it grows as the parser needs.
A source is either:

- an `IO`, such as an `IOBuffer` or a file opened with `open`, which the reader buffers with a `BufReader`;
- or a BufferIO reader, whose buffer the reader parses from.

The bytes are copied out of the source's buffer only into an owned record, so a reader of views reads its source without allocating for each record, or copying its bytes into a buffer of its own.

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
