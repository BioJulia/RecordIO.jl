# RecordIO.jl

[![Latest Release](https://img.shields.io/github/release/BioJulia/RecordIO.jl.svg)](https://github.com/BioJulia/RecordIO.jl/releases/latest)
[![MIT license](https://img.shields.io/badge/license-MIT-green.svg)](https://github.com/BioJulia/RecordIO.jl/blob/master/LICENSE)
[![Stable documentation](https://img.shields.io/badge/docs-stable-blue.svg)](https://biojulia.github.io/RecordIO.jl/stable)
[![Latest documentation](https://img.shields.io/badge/docs-dev-blue.svg)](https://biojulia.github.io/RecordIO.jl/dev)
[![Unit Tests](https://github.com/BioJulia/RecordIO.jl/actions/workflows/UnitTests.yml/badge.svg)](https://github.com/BioJulia/RecordIO.jl/actions/workflows/UnitTests.yml)
[![codecov](https://codecov.io/gh/BioJulia/RecordIO.jl/branch/develop/graph/badge.svg)](https://codecov.io/gh/BioJulia/RecordIO.jl)

Read the records of a file one after another, with a record parser that finds where each record ends while it finds its fields, so that each byte is read once.

A `RecordReader` parses the records straight from the buffer of a BufferIO reader, which it grows as the parser needs, so the parser never sees where one read from the source ends and the next begins.
Everything but the source follows from the record type, so a reader of an indexed file can answer region queries with the same record type that reads the file from start to end.

For each part in depth, including record types and their parsers, owned records and views, sources and errors, see the [documentation](https://biojulia.github.io/RecordIO.jl/stable).

## Installation

```julia
using Pkg
Pkg.add("RecordIO")
```

## Usage

A record type is immutable, its bytes and where its fields are in them, and owns its bytes, as `Record{Owned}`, or borrows those of the reader's buffer, as `Record{Borrowed}`:

```julia
using RecordIO
using RecordIO: Owned, Borrowed

struct Record{O <: RecordIO.Ownership}
    bytes::ImmutableMemoryView{UInt8}
    fields::Fields # The ranges of the record's fields in `bytes`.
end

RecordIO.owned_type(::Type{Record{Borrowed}}) = Record{Owned}
RecordIO.borrowed_type(::Type{Record{Owned}}) = Record{Borrowed}
```

Its methods say what a reader needs: `RecordIO.read_record`, its parser, `RecordIO.malformation`, why a record is malformed, and `RecordIO.exception`, its errors.
A record parser is a method of `read_record`:

```julia
RecordIO.read_record(::Type{Record{Borrowed}}, stream::RecordIO.Stream) -> (x, n::Int)
```

It reads one record from the start of `stream`, the bytes of the reader's buffer from the first byte of the record, and returns it, or what isn't one, such as `nothing` for a comment, which the reader skips, with the number of bytes it took.
A negative count says that the record is malformed, so that reading a record enters no `try`.
The stream is iterated as a vector is, and reads more of the source as the parser goes, so the parser never sees where one read from the source ends and the next begins.
`RecordIO.bytes(stream)` is a view of the bytes read so far, which keeps them until the next record is read, so a view of the record borrows them.

A `RecordReader{T}` reads records of type `T` from a source, and is an iterator of them, as a `Vector{T}` is:

```julia
reader = RecordReader{Record{Borrowed}}(open("annotations.bed"))
for record in reader
    # `record` borrows the reader's buffer until the next record is read; `copy(record)` owns its bytes.
end
close(reader)
```

A reader of `Record{Owned}` yields owned records, copies of the views, and `collect` gives owned records either way.
`RecordIO.read_next(reader)` reads the next record, or gives `nothing` at the end of the source.
`RecordIO.parse_record(Record{Owned}, data)` parses all of `data` as one record, and `RecordIO.parse_field` reads a field by the type wanted.

With Automa loaded, `RecordIO.generate_read_record` generates the parser of a record type from a state machine that matches one record and an optional newline, whose action `:end_of_record` marks where a record ends:

```julia
using Automa, RecordIO

machine = compile(record_or_comment * opt(onfinal!(re"\n", :end_of_record)))

@eval $(RecordIO.generate_read_record(Record{Borrowed}, machine, actions;
    setup = :(range = 1:0),                                                           # run before the machine on every call
    record = :(isempty(range) ? nothing : Record{Borrowed}(data[1:(p - 1)], Fields(range))), # the record, once it is complete, or what isn't one
))
```

Length-prefixed binary records, such as BAM records, are framed by `RecordIO.LengthPrefixed(decode)`, where `decode(T, bytes)` decodes the record from `bytes`, length included.

`RecordIO.offset(reader)`, `RecordIO.next_offset(reader)` and `RecordIO.number(reader)` say where a reader is in its source: the offset of the record last read, that of the next, and the number of parses.
A package says how a record breaks the specification of its format with a method of `RecordIO.problem`, from which `RecordIO.is_valid` and `RecordIO.validate` follow, of a record and of a file, which is checked when it is new, rather than as it is read.

`RecordIO.remaining(reader)` is the BufferIO reader of the bytes that the reader has not read as records, from where it is: a header in another form before the records, as in BAM files, or a section of another format after them.
Reading from it moves the reader on, so reading records continues after the bytes read.

If a record is malformed, a `RecordIO.RecordError` gives the number of the parse, which is its line number in a text file of one record a line, and its offset in the source, and the parsers that the generator makes quote the record.
A record type's `RecordIO.exception`, such as `RecordIO.MalformedRecord{ArgumentError}("Malformed record")`, throws an exception of its own instead, at no cost per record.

## Sources

A source is an `IO`, which the reader buffers with a `BufReader`, or a BufferIO reader, whose buffer the reader parses from, wrapped with `expandable` if its buffer can't grow.
To choose the size of the buffer, pass a `BufReader(io, size)`.
With TranscodingStreams loaded, its decompressing streams are read too.
A package makes its own kind of source readable by making it a BufferIO reader, and may give its own kind of offset in errors with a method of `RecordIO.offset`.

## Contributing

We appreciate contributions from users including reporting bugs, fixing issues, improving performance and adding new features.
See the [contributing files](https://github.com/BioJulia/Contributing) for detailed contributor and maintainer guidelines and the code of conduct.

This project follows [semantic versioning](https://semver.org), and records notable changes in [CHANGELOG.md](CHANGELOG.md).
Development happens on the [develop branch](https://github.com/BioJulia/RecordIO.jl/tree/develop), following the [git-flow branching model](https://nvie.com/posts/a-successful-git-branching-model/):
- features branch from `develop`, and merge back into it by pull request;
- hotfixes branch from `master`, and merge back into it by pull request;
- releases and hotfixes branch as `release/vX.Y.Z` and `hotfix/vX.Y.Z`, set that version in `Project.toml`, move the unreleased entries of `CHANGELOG.md` into a `## [X.Y.Z]` section, and merge into `master` by pull request; the Back-merge workflow then opens a pull request from a `back-merge/vX.Y.Z` branch at `master` into `develop`, which brings them back, never one from the release or hotfix branch itself.
  A conflict with `develop` is resolved on the `back-merge/vX.Y.Z` branch, by merging `develop` into it.

The [checks of BioJulia/Workflows](https://github.com/BioJulia/Workflows) enforce this, on pull requests into `master`:
- that it comes from a `release/*` branch of `develop` or a `hotfix/*` branch of `master`, of this repository or a fork;
- that its version is that of the branch's name, a single step up from `master`'s, and the next patch for a hotfix;
- that the changelog describes the version, with its comparison links, and leaves nothing unreleased;
- that a change that breaks the public API, the tests or the compat bounds of `master` takes a breaking version and a `### Breaking` subsection, and that a hotfix doesn't break.

And on pull requests into `develop`: that it doesn't come from a `release/*` or `hotfix/*` branch, and that it adds an entry under `## [Unreleased]`, unless it brings `master` back, or a maintainer has labelled it `skip changelog`, for a change that users won't notice.
Rulesets on `master` and `develop` require these checks; the README of BioJulia/Workflows describes them, their setup, and how to run them locally.

## Testing

The tests read records with a small parser generated with Automa, from every kind of source, across fills of their buffers, and check iteration, the ownership of bytes, allocations, errors and the remaining bytes:

```bash
julia --project -e 'using Pkg; Pkg.test()'
```

## Questions?

If you have a question about contributing or using BioJulia software, join us on [the Julia Slack workspace](https://julialang.org/slack/), or visit the [Bio category on Julia Discourse](https://discourse.julialang.org/c/domain/bio).
