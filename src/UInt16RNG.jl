"""
    abstract type AbstractUInt16RNG <: AbstractRNG
Supertype for an `AbstractRNG` that is fed random UInt16s.
"""
abstract type AbstractUInt16RNG <: AbstractRNG end

"""
    getrand(r::AbstractUInt16RNG, T::Type, n::Integer)

Generate `n` random `T`s using UInt16s from `r`.
"""
function getrand(::AbstractUInt16RNG, ::Type{UInt16}, n::Integer)
    error("NotImplemented: getrand must be implemented for UInt16 as an AbstractUInt16RNG.")
end
getrand(r::AbstractUInt16RNG, ::Type{UInt32}, n::Integer) =
    Vector{UInt32}(getrand(r, UInt16, n)) .<< 16 .+ Vector{UInt32}(getrand(r, UInt16, n))
getrand(r::AbstractUInt16RNG, ::Type{UInt64}, n::Integer) =
    Vector{UInt64}(getrand(r, UInt32, n)) .<< 32 .+ Vector{UInt64}(getrand(r, UInt32, n))
getrand(r::AbstractUInt16RNG, ::Type{UInt128}, n::Integer) =
    Vector{UInt128}(getrand(r, UInt64, n)) .<< 64 .+ Vector{UInt128}(getrand(r, UInt64, n))

function getrand(r::AbstractUInt16RNG, ::Type{UInt8}, n::Integer)
    vals = Vector{UInt8}(undef, n)
    u16s = getrand(r, UInt16, ceil(Int, n / 2))
    for i in 1:length(u16s)-1
        vals[2i-1:2i] = digits(UInt8, u16s[i], base=256, pad=2)
    end
    if n % 2 == 0
        vals[end-1:end] = digits(UInt8, u16s[end], base=256, pad=2)
    else
        vals[end] = u16s[end] % UInt8
    end
    vals
end
function getrand(r::AbstractUInt16RNG, ::Type{Bool}, n::Integer)
    bools = Vector{Bool}(undef, n)
    uint16needed = ceil(Int, n / 16)
    uint16s = getrand(r, UInt16, uint16needed)
    for i in 1:(uint16needed-1)
        bools[16(i-1)+1:16i] = digits(Bool, uint16s[i], base=2, pad=16)
    end
    bools[16*(uint16needed-1)+1:n] = digits(Bool, uint16s[end], base=2, pad=16)[1:n%16]
    bools
end

function rand!(r::AbstractUInt16RNG, A::Array{Bool}, ::Random.SamplerType{Bool})
    A[:] = getrand(r, Bool, length(A))
    A
end

rand(r::AbstractUInt16RNG, ::Random.SamplerType{Bool}) = getrand(r, Bool, 1)[1]

const UInts = (UInt8, UInt16, UInt32, UInt64, UInt128)
const Ints = (Int8, Int16, Int32, Int64, Int128)

for T in UInts
    @eval function rand!(r::AbstractUInt16RNG, A::Array{$T}, ::Random.SamplerType{$T})
        A[:] = getrand(r, $T, length(A))
        A
    end
    @eval rand(r::AbstractUInt16RNG, ::Random.SamplerType{$T}) = getrand(r, $T, 1)[1]
end
for (T, U) in zip(Ints, UInts)
    @eval function rand!(r::AbstractUInt16RNG, A::Array{$T}, ::Random.SamplerType{$T})
        A[:] = reinterpret.($T, getrand(r, $U, length(A)))
        A
    end
    @eval rand(r::AbstractUInt16RNG, ::Random.SamplerType{$T}) = reinterpret.($T, getrand(r, $U, 1))[1]
end

Random.rng_native_52(::AbstractUInt16RNG) = Float64

const F64BITMASK1 = 0b0011111111111111111111111111111111111111111111111111111111111111
const F64BITMASK2 = 0b0011111111110000000000000000000000000000000000000000000000000000

const F32BITMASK1 = 0b00111111111111111111111111111111
const F32BITMASK2 = 0b00111111100000000000000000000000

function rand!(r::AbstractUInt16RNG, A::Array{Float64}, ::Random.SamplerTrivial{Random.CloseOpen01{Float64}, Float64})
    A[:] = reinterpret.(Float64, getrand(r, UInt64, length(A)) .& F64BITMASK1 .| F64BITMASK2) .- 1
    A
end
function rand(r::AbstractUInt16RNG, ::Random.CloseOpen12{Float64})
    reinterpret(Float64, getrand(r, UInt64, 1)[1] & F64BITMASK1 | F64BITMASK2)
end

function rand!(r::AbstractUInt16RNG, A::Array{Float32}, ::Random.SamplerTrivial{Random.CloseOpen01{Float32}, Float32})
    A[:] = reinterpret.(Float32, getrand(r, UInt32, length(A)) .& F32BITMASK1 .| F32BITMASK2) .- 1
    A
end

# Online and cached UInt16 sources

mutable struct OnlineUInt16RNG <: AbstractUInt16RNG
    label::String
    batchsize::Integer
    cache::Vector{UInt16}
    pointer::Integer
    fetchrand::Function
    prefillthreshold::Integer
    cacheprefill::Vector{UInt16}
    currentlyprefilling::Bool
    function OnlineUInt16RNG(label::String, fetchrand::Function, batchsize::Integer,
                             prefillthreshold::Integer; prefill=prefillthreshold > 0)
        rng = new(label, batchsize, UInt16[], 1, fetchrand,
                  prefillthreshold, UInt16[], false)
        if prefill
            Threads.@spawn prefillcache(rng)
        end
        rng
    end
end

const term256greentored = [119, 190, 220, 221, 215, 208, 202, 160, 124]
function show(io::IO, r::OnlineUInt16RNG)
    print(io, "$(r.label). ")
    unusedcached = length(r.cache) - r.pointer + 1
    color = if r.prefillthreshold == 0
        [:red, :yellow, :green][round(Int, 3*unusedcached/r.batchsize)]
    elseif unusedcached > r.prefillthreshold
        :green
    elseif unusedcached > 0.5r.prefillthreshold
        :yellow
    else
        :red
    end
    printstyled(io, unusedcached; color)
    if r.currentlyprefilling
        printstyled(io, '*'; color=:light_black)
    end
    printstyled(io, '/', r.batchsize; bold=true)
    print(io, " UInt16s cached.")
end

function getrand(r::OnlineUInt16RNG, ::Type{UInt16}, n::Integer)
    if r.batchsize ≤ 0
        r.fetchrand(n)
    else
        ncached = length(r.cache) - r.pointer + 1
        if ncached > n
            r.pointer += n
            if length(r.cacheprefill) == 0 &&
                length(r.cache) - r.pointer + 1 < r.prefillthreshold &&
                ! r.currentlyprefilling
                Threads.@spawn prefillcache(r)
            end
            r.cache[r.pointer-n:r.pointer-1]
        elseif ncached + length(r.cacheprefill) > n
            oldcache = r.cache[r.pointer:end]
            r.cache = r.cacheprefill
            r.cacheprefill = []
            r.pointer = 1
            [oldcache; getrand(r, UInt16, n - length(oldcache))]
        else
            rands = r.fetchrand(n - ncached + r.batchsize)
            res = [r.cache[r.pointer:end]; rands[r.batchsize+1:end]]
            r.cache = rands[1:r.batchsize]
            res
        end
    end
end

function prefillcache(r::OnlineUInt16RNG)
    r.currentlyprefilling = true
    if length(r.cache) == 0
        r.cache = r.fetchrand(r.batchsize)
    else
        r.cacheprefill = r.fetchrand(r.batchsize)
    end
    r.currentlyprefilling = false
end
