# Records That Own or Borrow Their Bytes
# --------------------------------------

"""
    RecordIO.Ownership

Whether a record owns its bytes, [`RecordIO.Owned`](@ref), or borrows those of the buffer it was parsed from, [`RecordIO.Borrowed`](@ref), as the parameter of a record type of a package's own, such as `Record{O <: RecordIO.Ownership}`.

A `Record{Borrowed}` is a view of the bytes, which borrow the buffer of the reader's source, and is only valid until the next record is read from the source; a `Record{Owned}` holds a copy of them, and stays valid as long as it is kept.
The package defines both, how a view becomes an owned record, with `copy`, and [`RecordIO.owned_type`](@ref) and [`RecordIO.borrowed_type`](@ref), which pair them.
"""
abstract type Ownership end

"""
    RecordIO.Owned

The [`RecordIO.Ownership`](@ref) of a record that owns its bytes, in memory of its own.
"""
struct Owned <: Ownership end

"""
    RecordIO.Borrowed

The [`RecordIO.Ownership`](@ref) of a record that borrows the bytes of the buffer it was parsed from, which are valid until the next record is read from the source.
"""
struct Borrowed <: Ownership end

"""
    RecordIO.owned_type(T) -> Type

The type of the records that own their bytes of the records of type `T`, which `collect` of a reader of `T` gives, by `copy` of each.
By default, it is `T`, whose records are their own; a package defines it for the views of its records, as `RecordIO.owned_type(::Type{Record{Borrowed}}) = Record{Owned}`.
"""
owned_type(::Type{T}) where {T} = T

"""
    RecordIO.borrowed_type(T) -> Type

The type of the views of the records of type `T`, which borrow their bytes, so that a reader that drops some of the records it reads, such as a query of a region, reads views and copies only those it keeps.
By default, it is `T`, whose records have no views; a package defines it for its owned records, as `RecordIO.borrowed_type(::Type{Record{Owned}}) = Record{Borrowed}`, the reverse of [`RecordIO.owned_type`](@ref).
"""
borrowed_type(::Type{T}) where {T} = T

"""
    RecordIO.copy_bytes(bytes::ImmutableMemoryView{UInt8}) -> ImmutableMemoryView{UInt8}

A copy of the bytes of a record, in memory of its own, for the owned copy of a view, which a record package's `copy` makes.
"""
function copy_bytes(bytes::ImmutableMemoryView{UInt8})
    memory = Memory{UInt8}(undef, length(bytes))
    copyto!(MutableMemoryView(memory), bytes)
    return ImmutableMemoryView(memory)
end

# A record of `owned_type(T)`: a copy of a record that borrows its bytes, and any other as it is.
owned(::Type{T}, x) where {T} = owned_type(T) === T ? x : copy(x)
