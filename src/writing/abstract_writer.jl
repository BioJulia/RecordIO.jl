# The Supertype of Writers
# -------------------------

"""
    RecordIO.AbstractWriter{T}

The supertype of the writers of records of type `T`: [`RecordWriter{T}`](@ref RecordWriter) itself, and the writers of a record package, which wrap one, as its readers wrap a `RecordReader`, the mirror of [`RecordIO.AbstractReader`](@ref).

A subtype has its `RecordWriter{T}` in a field named `records`, or defines [`RecordIO.records`](@ref) for it, and a constructor that takes the sink first.
It then writes with `write`, is closed with `close` and flushed with `flush`, and has:

- `W(f::Function, sink, args...)`, which calls `f` with the writer and closes it afterwards;
- `open(W, path, args...; append = false)` and `open(f, W, path, args...; append = false)`, which open the file at `path` to write it, or to append to it;
- [`RecordIO.number`](@ref) and [`RecordIO.offset`](@ref), the records and the bytes it has written.
"""
abstract type AbstractWriter{T} end

records(writer::AbstractWriter) = writer.records

@inline Base.write(writer::AbstractWriter, x) = write_counted!(records(writer), x)
@inline Base.write(writer::AbstractWriter, x, xs...) = write(writer, x) + write(writer, xs...)

# The records of a vector or of a reader, each written as it comes, so that those of a reader of views are written before the next is read.
function Base.write(writer::AbstractWriter{T}, records::Union{AbstractVector{<:T}, AbstractReader{<:T}}) where {T}
    n = 0
    for record in records
        n += write(writer, record)
    end
    return n
end

Base.close(writer::AbstractWriter) = close(records(writer))
Base.flush(writer::AbstractWriter) = flush(records(writer))
Base.isopen(writer::AbstractWriter) = isopen(records(writer))

"""
    RecordIO.number(writer) -> Int

The number of records that `writer` has written.
"""
number(writer::AbstractWriter) = records(writer).number

"""
    RecordIO.offset(writer) -> Int

The number of bytes that `writer` has written to its sink, which is the offset of the next record from where the writer began.
"""
offset(writer::AbstractWriter) = records(writer).offset

function (::Type{W})(f::Function, sink, args...; kwargs...) where {W <: AbstractWriter}
    writer = W(sink, args...; kwargs...)
    try
        return f(writer)
    finally
        close(writer)
    end
end

# A path is opened for writing, or for appending with `append = true`, and closed if the writer can't be made.
function Base.open(::Type{W}, path::AbstractString, args...; append::Bool = false, kwargs...) where {W <: AbstractWriter}
    io = open(path, append ? "a" : "w")
    try
        return W(io, args...; kwargs...)
    catch
        close(io)
        rethrow()
    end
end

function Base.open(f::Function, ::Type{W}, path::AbstractString, args...; kwargs...) where {W <: AbstractWriter}
    writer = open(W, path, args...; kwargs...)
    try
        return f(writer)
    finally
        close(writer)
    end
end
