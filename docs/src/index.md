# RecordIO.jl

RecordIO reads the records of a file one after another, and writes them, with a record parser that finds where each record ends while it finds its fields, so that each byte is read once.

A [`RecordReader`](@ref) parses the records straight from the buffer of a BufferIO reader, which it grows as the parser needs, so the parser never sees where one read from the source ends and the next begins.
Everything but the source follows from the record type: its parser, which of its parses are records, and its errors.
So a reader of an indexed file can answer region queries with the same record type that reads the file from start to end.

## What this package covers

- **Readers:** a `RecordReader{T}` reads records of type `T` from a source, and is an iterator of them.
- **Writers:** a `RecordWriter{T}` writes records of type `T` to a sink, as the record type writes one.
- **Records:** a design of records, of their bytes and where their fields are in them, which own their bytes, as `R{Owned}`, or borrow those of the reader's buffer, as `R{Borrowed}`, which allocates nothing for each.
- **Parsers:** a contract for record parsers, a generator of parsers from Automa state machines, and a framing of length-prefixed binary records.
- **Fields:** functions that read the fields of a record's bytes, by the type wanted.
- **Sources:** `IO`s, which the reader buffers with BufferIO, and BufferIO readers, whose buffers it parses from.

It doesn't parse any format itself: a format's package brings the record type and its parser.

## Installation

```julia
using Pkg
Pkg.add("RecordIO")
```

The versions of Julia and of its dependencies that RecordIO supports are the compat bounds of its `Project.toml`.

## The manual

- [Record types](@ref) describes the design of records, what a record type says by its methods, the parser, generating parsers with Automa, length-prefixed records, checking records against a specification, and where a reader is in its source.
- [Reading records](@ref) describes readers, owned records and views, which bytes each part owns, the readers of a package, and the bytes after the records.
- [Sources](@ref) describes what a reader reads from, and how to make a source of your own.
- [Errors](@ref) describes what a reader throws when a parser fails.
- The [Reference](@ref) lists every documented function and type.

## First steps

A record type, `Line`, is one line of text, which its parser, a method of `RecordIO.read_record`, reads, giving `nothing` for a comment; [Record types](@ref) shows both.
A reader of a few lines, which skips the comments:

```@setup index
using RecordIO
include(joinpath(pkgdir(RecordIO), "docs", "src", "line.jl"))
```

```@example index
reader = RecordReader{Line{Owned}}(IOBuffer("# a header\nfirst\nsecond\n"))
[String(text(line)) for line in reader]
```

A `Line{Owned}` owns its bytes, so it stays as it is after the next record is read, and a `LineView`, a `Line{Borrowed}`, borrows those of the reader's buffer.
`RecordReader` is exported; the other functions are public, and are written here with their module, as `RecordIO.remaining`.
