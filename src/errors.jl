# Errors
# ------

"""
    RecordIO.RecordError(offset, number, exception)

Thrown when a record parser finds a record malformed, or when the source ends inside a record.

- `offset`: where the record starts in the source, as [`RecordIO.offset`](@ref) gives it; by default, the number of bytes of the source before it, counted from where reading started.
- `number`: the number of the parse, counting those read before it, what isn't a record, such as a comment, included.
- `exception`: the cause, which [`RecordIO.malformation`](@ref) gives, or what describes an incomplete record.
"""
struct RecordError{O} <: Exception
    offset::O
    number::Int
    exception::Any
end

function Base.showerror(io::IO, error::RecordError)
    print(io, "RecordError: record ", error.number, " at offset ", error.offset, ": ")
    return showerror(io, error.exception)
end

"""
    RecordIO.MalformedRecord{C}(prefix::String)

An error of a record package: a function of `(offset, number, cause)`, as [`RecordIO.exception`](@ref) returns, that turns the failure of its parser into the package's own error.

A cause of a type in `C`, such as `ArgumentError`, becomes `ArgumentError("\$(prefix) \$(number) at offset \$(offset): \$(message)")`, as in `MalformedRecord{ArgumentError}("Malformed record")`, and any other cause a [`RecordIO.RecordError`](@ref).
The offset is the record's in the source, as [`RecordIO.offset`](@ref) gives it, such as a virtual offset in a query of an indexed file.
"""
struct MalformedRecord{C}
    prefix::String
end

(malformed::MalformedRecord{C})(offset, number, cause) where {C} = malformed_error(malformed, offset, number, cause, cause isa C)

malformed_error(malformed::MalformedRecord, offset, number, cause, known::Bool) = known ? ArgumentError(string(malformed.prefix, " ", number, " at offset ", offset, ": ", cause.msg)) : RecordError(offset, number, cause)

# The text of a record in an error: from its start to `stop`, cut after 100 bytes.
function quoted(data::AbstractVector{UInt8}, stop::Int)
    shown = min(stop, length(data), 100)
    text = String(ImmutableMemoryView(data)[1:shown])
    return shown < min(stop, length(data)) ? string(repr(text), "…") : repr(text)
end
