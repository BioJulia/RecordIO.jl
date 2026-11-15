# Errors

```@setup errors
using RecordIO
include(joinpath(pkgdir(RecordIO), "docs", "src", "line.jl"))
```

A parser says that a record is malformed by returning a negative count, rather than by throwing, so that reading a well-formed record enters no `try`.
The reader then asks why, with [`RecordIO.malformation(T, stream)`](@ref RecordIO.malformation), which may parse the record again, and throws the error of the record type, [`RecordIO.exception(T)`](@ref RecordIO.exception), with where the record is.

## A record type's errors

By default, the error is a [`RecordIO.RecordError`](@ref), with the offset of the record in the source, the number of the parse, and the cause.
A record of a number, whose parser rejects anything else:

```@example errors
struct Value{O <: Ownership}
    bytes::ImmutableMemoryView{UInt8}
end

@inline function RecordIO.read_record(::Type{Value{Borrowed}}, stream::RecordIO.Stream)
    line, n = RecordIO.read_record(LineView, stream)
    line === nothing && return nothing, n
    all(byte -> UInt8('0') <= byte <= UInt8('9'), line.bytes) || return nothing, -1
    return Value{Borrowed}(line.bytes), n
end

RecordIO.malformation(::Type{Value{Borrowed}}, stream::RecordIO.Stream) = ArgumentError("the value is not a number")

try
    collect(RecordReader{Value{Borrowed}}(IOBuffer("12\n# a comment\nthirteen\n")))
catch error
    error
end
```

The number counts every parse, what isn't a record, such as the comment, included, and the offset is that of the start of the record.

A package gives its records its own errors with [`RecordIO.MalformedRecord`](@ref), which turns a cause of the types it names into an error with the package's message, at no cost per record:

```@example errors
RecordIO.exception(::Type{<:Value}) = RecordIO.MalformedRecord{ArgumentError}("Malformed value")

try
    collect(RecordReader{Value{Borrowed}}(IOBuffer("12\n# a comment\nthirteen\n")))
catch error
    error
end
```

## Where a record is

The offset of an error is [`RecordIO.offset(source, bytes)`](@ref RecordIO.offset): by default, the number of bytes of the source before the record, counted from where reading started, and those read through [`RecordIO.remaining`](@ref), such as a header, are counted too.
A source of a package's own gives its own kind of offset with a method for its type, as a source of the chunks of a BGZF file gives virtual offsets.
It is called only when a record fails, so it costs nothing per record.

## The end of the source

A record that the source ends inside is truncated, which is an error of the record type too.
A parser that reads lines accepts a last line without a newline, and one of length-prefixed records, [`RecordIO.LengthPrefixed`](@ref), throws for a record shorter than its length says:

```@example errors
struct Blob{O <: Ownership}
    bytes::ImmutableMemoryView{UInt8}
end

decode_blob(::Type{Blob{Borrowed}}, bytes) = Blob{Borrowed}(bytes[5:end])

RecordIO.read_record(::Type{Blob{Borrowed}}, stream::RecordIO.Stream) = RecordIO.LengthPrefixed(decode_blob)(Blob{Borrowed}, stream)
RecordIO.malformation(::Type{Blob{Borrowed}}, stream::RecordIO.Stream) = RecordIO.malformation(RecordIO.LengthPrefixed(decode_blob), Blob{Borrowed}, stream)

# A length of 10 bytes, and 3 bytes after it.
truncated = [reinterpret(UInt8, [htol(Int32(10))]); codeunits("abc")]
try
    collect(RecordReader{Blob{Borrowed}}(IOBuffer(truncated)))
catch error
    error
end
```

## Parsers from machines

The parsers of [`RecordIO.generate_read_record`](@ref) quote the record and give the byte where the machine fails, with [`RecordIO.malformed_record`](@ref), and an `ArgumentError` that the `record` expression throws while `checking` gains the quoted record too.
