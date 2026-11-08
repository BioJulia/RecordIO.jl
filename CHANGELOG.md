# Changelog

All notable changes to this project are documented in this file.

This project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

- `RecordReader{T}(source)`, which reads records of type `T` one after another with the parser of the record type, which finds where each record ends while it finds its fields, so that each byte is read once, straight from the buffer of the source, and is an iterator of them.
- `RecordReader{T}(reader)`, a reader that carries on from where another is, through its source and its buffer, as records of another type, by which a package reads the rest of a file as a type that keeps what its records skip, to check it.
- Records of one design, which record packages share: an immutable record type of a package's own, of its bytes and where its fields are in them, which owns its bytes, as `R{RecordIO.Owned}`, or borrows those of the reader's buffer, as `R{RecordIO.Borrowed}`, a view that allocates nothing and is valid until the next record is read; `RecordIO.owned_type` and `RecordIO.borrowed_type` pair the two.
- A reader of views yields views, and one of owned records copies of them; `collect` gives owned records either way.
- The parser of a record type, `RecordIO.read_record(T, stream) -> (x, n)`, which reads a record from a `RecordIO.Stream`, the bytes of the reader's buffer from the first byte of the record, which reads more of the source as the parser goes, and returns the record, or what isn't one, such as `nothing` for a comment, with the bytes it took, or a negative count for a malformed record, so that reading a record enters no `try`.
- `RecordIO.malformation`, why a record is malformed, and `RecordIO.exception`, the errors of a record type.
- `RecordIO.read_next(reader)`, the next record of a reader, by which a package reads records itself, and `RecordIO.parse_record(T, data)`, which parses all of `data` as one record, as a package makes a record of given bytes.
- `RecordIO.AbstractReader{T}`, whose subtypes, parameterised on the records they yield, iterate and `collect` by their `RecordReader{T}`, `RecordIO.records(reader)`; a `RecordReader{T}` is one, whose `records` is itself.
- `RecordIO.parse_field(T, data, range)`, which reads a field by the type wanted, integers, floats, `String`s, `StringView`s and `Char`s, allocating nothing but for a `String`, and `RecordIO.is_missing`, `RecordIO.separated` and `RecordIO.field_equals`.
- Sources: vectors of bytes and regular files, which the reader parses as one view of their bytes, other `IO`s, which it buffers with a BufferIO `BufReader`, and BufferIO readers, whose buffers it parses from, wrapped with `expandable` if their buffers can't grow.
- Decompressing streams of TranscodingStreams, in a package extension, which BufferIO can't read directly.
- `RecordIO.remaining`, the BufferIO reader of the bytes not read as records, for a header before the records or another format after what ends them.
- `RecordIO.LengthPrefixed`, which frames length-prefixed binary records, such as BAM records, with a decoder that returns the exception of a malformed record rather than throwing it.
- `RecordIO.generate_read_record` and `RecordIO.generate_execute_code`, in a package extension of Automa, which generate a parser from a state machine, and its `RecordIO.malformation`, which parses a malformed record again to throw its error, quoting the record; with `skip = true`, a state that loops to itself skips its run of bytes at once, with `RecordIO.skip_while`.
- `RecordIO.RecordError`, with the number of the parse and its offset in the source, and `RecordIO.MalformedRecord`, the errors of a record package, with its messages, at no cost per record.
- `RecordIO.offset`, by which a source of a package's own gives its own kind of offset in errors, such as a virtual offset of a BGZF file.
- `RecordIO.offset(reader)`, `RecordIO.next_offset(reader)` and `RecordIO.number(reader)`, where a reader is in its source: the offset of the record that it last read, that of the next, and the number of its parses.
- `RecordIO.try_parse_field`, which reads a number as `parse_field` does, and gives `nothing` where it throws, and `RecordIO.record_error(reader, cause)`, the error of the record last read, by which a package checks records against the specification of its format.
- `RecordIO.copy_bytes`, the copy of the bytes of a view, for its owned record.
- The parser and the `malformation` of an owned record type follow from those of its views, by `RecordIO.borrowed_type`.
- `RecordIO.parse_field` reads every value of an integer type, its least included, throws an `ArgumentError` for an integer without digits, such as a sign alone, and checks that its range is within the data.
- Requires Julia 1.12, for workspaces.
