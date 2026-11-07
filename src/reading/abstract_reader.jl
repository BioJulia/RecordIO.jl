# The Supertype of Readers
# -------------------------

"""
    RecordIO.AbstractReader{T}

The supertype of the readers of records of type `T`: [`RecordReader{T}`](@ref RecordReader) itself, and the readers of a record package, which wrap one, `RecordIO.records(reader)`, by default their field `records`:

- iterating yields its records of type `T`;
- `eltype` is `T`;
- `collect` gives records of [`RecordIO.owned_type(T)`](@ref RecordIO.owned_type);
- [`RecordIO.offset`](@ref), [`RecordIO.next_offset`](@ref), [`RecordIO.number`](@ref) and [`RecordIO.record_error`](@ref) are those of the `RecordReader` it wraps.

A package's reader is `Reader{T, …} <: RecordIO.AbstractReader{T}`, so that `Reader{Record{Borrowed}}` reads views, as a `Vector{T}` holds elements of type `T`.
"""
abstract type AbstractReader{T} end

"""
    RecordIO.records(reader::RecordIO.AbstractReader{T}) -> RecordReader{T}

The reader of records that `reader` wraps; of a `RecordReader`, the reader itself.
"""
records(reader::AbstractReader) = reader.records

offset(reader::AbstractReader) = offset(records(reader))
next_offset(reader::AbstractReader) = next_offset(records(reader))
number(reader::AbstractReader) = number(records(reader))
record_error(reader::AbstractReader, cause) = record_error(records(reader), cause)

Base.eltype(::Type{<:AbstractReader{T}}) where {T} = T
Base.IteratorSize(::Type{<:AbstractReader}) = Base.SizeUnknown()
@inline Base.iterate(reader::AbstractReader, state...) = iterate(records(reader), state...)
# Collecting iterates the reader itself, so that a package's reader that ends its records before the end of the source, as at a section in another format, collects what it yields.
Base.collect(reader::AbstractReader{T}) where {T} = collect(owned_type(T), Iterators.map(x -> owned(T, x), reader))
