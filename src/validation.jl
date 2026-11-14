# Validation
# ----------
#
# A parser finds the fields of a record by its syntax, and a reader yields what it finds.
# What the specification of a format says of the values of the fields is checked when it is asked for, of a record or of a file, with these, which each record package gives its own `problem`.

"""
    RecordIO.problem(record) -> Union{Nothing, String}

How `record` breaks the specification of its format, or `nothing` if it honours it.
A record package defines it for its record types, by reading the fields of the record as its accessors do, with [`RecordIO.try_parse_field`](@ref) for its numbers; [`RecordIO.is_valid`](@ref) and [`RecordIO.validate`](@ref) follow from it.
"""
function problem end

"""
    RecordIO.is_valid(record) -> Bool

Whether `record` honours the specification of its format, as [`RecordIO.problem`](@ref) tells.
"""
is_valid(record) = problem(record) === nothing

"""
    RecordIO.description(record) -> String

What the error of a record that breaks the specification quotes of it, such as its line; by default nothing.
A record package defines it for its record types.
"""
description(record) = ""

"""
    RecordIO.description(bytes::AbstractVector{UInt8}) -> String

The bytes of a record, quoted, and cut after 100 bytes, as the errors of this package quote a record.
"""
description(bytes::AbstractVector{UInt8}) = quoted(bytes, length(bytes))

# The error of a record that breaks the specification.
function invalid(message::AbstractString, record)
    quote_of_record = description(record)
    return ArgumentError(isempty(quote_of_record) ? String(message) : string(message, " in the record ", quote_of_record))
end

"""
    RecordIO.validate(record) -> record
    RecordIO.validate(reader) -> Int
    RecordIO.validate(R, source) -> Int

Check that a record, or every record of a file, honours the specification of its format, and throw an `ArgumentError` that says how the first that doesn't breaks it.

- Of a record, it returns the record, which [`RecordIO.problem`](@ref) has nothing to say of.
- Of a reader of a record package, it reads the records that are left, and returns how many it checked; the package defines it, with the loop below.
- Of a type of reader `R <: RecordIO.AbstractReader` and a source, it opens the source with `R`, checks it, and closes it, as in `validate(Reader, "records.txt")`.

A reader does not check records as it reads them, so a file that is new is checked once, and then read as it is.
"""
function validate(record)
    message = problem(record)
    message === nothing || throw(invalid(message, record))
    return record
end

"""
    RecordIO.Stop()

What the step of [`RecordIO.validate`](@ref) returns where the records end before the source does.
"""
struct Stop end

"""
    RecordIO.validate(step, reader::RecordReader, state) -> Int

Check the records that `reader` has left, and return how many it checked: the loop by which a record package checks a file.

`step(state, record)` checks a record, with what the records before it left in `state`, such as the number of fields that every record of a file has, and returns:

- the next state, for a record that honours the specification;
- a `String` that says how the record breaks it, which is thrown as the error of the record, [`RecordIO.record_error`](@ref), with its number and its offset in the source;
- [`RecordIO.Stop()`](@ref RecordIO.Stop), where the records end before the source does, as at a section in another format.
"""
function validate(step::F, reader::RecordReader, state) where {F}
    checked = 0
    while true
        record = read_next(reader)
        record === nothing && break
        result = step(state, record)
        result isa Stop && break
        result isa String && throw(record_error(reader, invalid(result, record)))
        state = result
        checked += 1
    end
    return checked
end

function validate(::Type{R}, source; kwargs...) where {R <: AbstractReader}
    reader = R(source; kwargs...)
    try
        return validate(reader)
    finally
        close(reader)
    end
end
