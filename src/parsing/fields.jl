# Fields
# ------
#
# The fields of a line are ranges of its bytes, which a record package reads with these, by the type it wants, allocating only for a `String`.

"""
    RecordIO.parse_field(T, data::AbstractVector{UInt8}, range::UnitRange{Int}) -> T

The field of `data` in `range`, as a `T`, which allocates nothing but for a `String`:

| `T` | The field |
|:--|:--|
| `T <: Unsigned` | a decimal of `[0-9]+` |
| `T <: Signed` | a decimal of `[-+]?[0-9]+` |
| `T <: AbstractFloat` | a decimal or scientific number, as `parse` reads it |
| `String` | a copy of the bytes |
| `StringView` | a view of the bytes |
| `Char` | its one byte |

Integers are read as the parser of the record matched them, so their digits aren't checked, but their overflow is, with an `OverflowError`, and every value of `T` can be read, its least included.
A float that isn't one, and an integer without digits, such as an empty field or a sign alone, throw an `ArgumentError`, and a `range` outside `data` throws as indexing `data` there does.
"""
function parse_field end

"""
    RecordIO.try_parse_field(T, data::AbstractVector{UInt8}, range::UnitRange{Int}) -> Union{T, Nothing}

The field of `data` in `range` as a number of type `T`, as [`RecordIO.parse_field`](@ref) reads it, or `nothing` where `parse_field` throws: for an integer that `T` does not hold, an integer without digits, or a float that isn't one.
An accessor reads a field with `parse_field`, and a check of the field with this, which enters no `try`.
A `range` outside `data` throws as indexing `data` there does.
"""
function try_parse_field end

# The decimal digits of `range` as a `T`, taken away rather than added for a negative number, so that the least value of `T` is read, or `nothing` if `T` does not hold them, or there are none.
function digits_value(::Type{T}, data::AbstractVector{UInt8}, range::UnitRange{Int}, negative::Bool = false) where {T <: Integer}
    isempty(range) && return nothing
    checkbounds(data, range)
    value = zero(T)
    for i in range
        digit = (@inbounds(data[i]) - UInt8('0')) % T
        value, overflowed = Base.Checked.mul_with_overflow(value, 10 % T)
        overflowed && return nothing
        value, overflowed = negative ? Base.Checked.sub_with_overflow(value, digit) : Base.Checked.add_with_overflow(value, digit)
        overflowed && return nothing
    end
    return value
end

try_parse_field(::Type{T}, data::AbstractVector{UInt8}, range::UnitRange{Int}) where {T <: Unsigned} = digits_value(T, data, range)

function try_parse_field(::Type{T}, data::AbstractVector{UInt8}, range::UnitRange{Int}) where {T <: Signed}
    isempty(range) && return nothing
    first_byte = data[first(range)]
    negative = first_byte == UInt8('-')
    signed = negative || first_byte == UInt8('+')
    return digits_value(T, data, (first(range) + signed):last(range), negative)
end

try_parse_field(::Type{T}, data::AbstractVector{UInt8}, range::UnitRange{Int}) where {T <: AbstractFloat} = tryparse(T, parse_field(StringView, data, range))

function parse_field(::Type{T}, data::AbstractVector{UInt8}, range::UnitRange{Int}) where {T <: Integer}
    value = try_parse_field(T, data, range)
    value === nothing && not_an_integer(T, data, range)
    return value
end

# Why a field isn't an integer of type `T`: it has no digits, or `T` does not hold them.
@noinline function not_an_integer(::Type{T}, data::AbstractVector{UInt8}, range::UnitRange{Int}) where {T}
    digits = !isempty(range) && data[first(range)] in (UInt8('-'), UInt8('+')) ? ((first(range) + 1):last(range)) : range
    isempty(digits) && throw(ArgumentError("a field without digits is not a number"))
    throw(OverflowError(string("the field ", repr(String(ImmutableMemoryView(data)[range])), " does not fit in ", T)))
end

parse_field(::Type{T}, data::AbstractVector{UInt8}, range::UnitRange{Int}) where {T <: AbstractFloat} = parse(T, parse_field(StringView, data, range))
parse_field(::Type{StringView}, data::AbstractVector{UInt8}, range::UnitRange{Int}) = StringView(ImmutableMemoryView(data)[range])
parse_field(::Type{String}, data::AbstractVector{UInt8}, range::UnitRange{Int}) = String(ImmutableMemoryView(data)[range])
parse_field(::Type{Char}, data::AbstractVector{UInt8}, range::UnitRange{Int}) = Char(data[only_index(range)])

# The index of a field of one byte.
only_index(range::UnitRange{Int}) = length(range) == 1 ? first(range) : throw(ArgumentError("a field of $(length(range)) bytes is not one byte"))

"""
    RecordIO.is_missing(data::AbstractVector{UInt8}, range::UnitRange{Int}, placeholder::UInt8) -> Bool

Whether the field of `data` in `range` is the placeholder of a missing value, one byte of `placeholder`, such as `.` in BED and GFF3 and `*` in SAM.
"""
is_missing(data::AbstractVector{UInt8}, range::UnitRange{Int}, placeholder::UInt8) = length(range) == 1 && data[first(range)] == placeholder

"""
    RecordIO.separated(data::AbstractVector{UInt8}, range::UnitRange{Int}, delimiter::UInt8)

Iterate over the ranges of the values of the field of `data` in `range`, which `delimiter` separates, empty ones included, allocating nothing.
An empty field has one empty value, and a field that ends with `delimiter` an empty last value.
"""
separated(data::AbstractVector{UInt8}, range::UnitRange{Int}, delimiter::UInt8) = Separated(data, range, delimiter)

struct Separated{D <: AbstractVector{UInt8}}
    data::D
    range::UnitRange{Int}
    delimiter::UInt8
end

Base.eltype(::Type{<:Separated}) = UnitRange{Int}
Base.IteratorSize(::Type{<:Separated}) = Base.SizeUnknown()

# Each value runs to the next delimiter within the field, or to its end.
@inline function Base.iterate(values::Separated, start::Int = first(values.range))
    start > last(values.range) + 1 && return nothing
    stop = value_stop(findnext(==(values.delimiter), values.data, start), last(values.range))
    return start:(stop - 1), stop + 1
end

value_stop(::Nothing, last_index::Int) = last_index + 1
value_stop(delimiter::Int, last_index::Int) = min(delimiter, last_index + 1)

"""
    RecordIO.field_equals(data::AbstractVector{UInt8}, range::UnitRange{Int}, text::AbstractString) -> Bool

Whether the field of `data` in `range` is `text`, allocating nothing.
"""
field_equals(data::AbstractVector{UInt8}, range::UnitRange{Int}, text::AbstractString) = length(range) == ncodeunits(text) && all(k -> data[first(range) + k - 1] == codeunit(text, k), 1:ncodeunits(text))
