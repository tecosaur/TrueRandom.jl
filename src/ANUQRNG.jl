mutable struct ANUQRNG <: AbstractRNG
    batchsize::Integer
    cache::Vector{UInt16}
    pointer::Integer
    prefillthreshold::Integer
    cacheprefill::Vector{UInt16}
    currentlyprefilling::Bool
    function ANUQRNG(batchsize=1024,prefillthreshold=round(Int, 0.75*batchsize); prefill=true)
        if batchsize == 0
            @warn "Setting `batchsize` to 0 is a really bad idea. Please reconsider."
        end
        r = new(batchsize,[],1,prefillthreshold,[],false)
        if prefill
            Threads.@spawn prefillcache(r)
        end
        r
    end
end

function show(io::IO, r::ANUQRNG)
    print(io, "ANU Quantum Random Number service. $(length(r.cache) - r.pointer)/$(r.batchsize) UInt16s cached.")
end

const ANUQRNGAPI = "https://qrng.anu.edu.au/API/jsonI.php"
const ANUQRNGLIMIT = 1024

function ANUrand(arraysize::Integer)
    if arraysize > ANUQRNGLIMIT
        @warn "Requests for more that $ANUQRNGLIMIT numbers are not supported"
    end
    req = HTTP.request("GET", string(ANUQRNGAPI, "?length=", arraysize, "&type=uint16"))
    if req.status != 200
        error("The ANU Quantum Random Number Generator service is currently not responding.")
    end
    res = req.body |> String |> JSON3.read
    if ! res.success
        error("The request to the ANU Quantum Random Number Generator service failed")
    end
    Vector{UInt16}(res.data)
end

function nANUrand(n::Integer)
    result = Vector{UInt16}(undef, n)
    current = 0
    while current < n
        nfetch = min(ANUQRNGLIMIT, n - current)
        result[current+1:current+nfetch] = ANUrand(nfetch)
        current += nfetch
    end
    result
end

function nANUrand(::Type{UInt16}, n::Integer, r::ANUQRNG)
    if r.batchsize ≤ 0
        nANUrand(n)
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
            [oldcache; nANUrand(UInt16, n - length(oldcache), r)]
        else
            rands = nANUrand(n - ncached + r.batchsize)
            res = [r.cache[r.pointer:end]; rands[r.batchsize+1:end]]
            r.cache = rands[1:r.batchsize]
            res
        end
    end
end

function prefillcache(r::ANUQRNG)
    r.currentlyprefilling = true
    if length(r.cache) == 0
        r.cache = nANUrand(r.batchsize)
    else
        r.cacheprefill = nANUrand(r.batchsize)
    end
    r.currentlyprefilling = false
end

function nANUrand(::Type{UInt32}, n::Integer, r::ANUQRNG)
    Vector{UInt32}(nANUrand(UInt16, n, r)) .<< 16 .+ Vector{UInt32}(nANUrand(UInt16, n, r))
end
function nANUrand(::Type{UInt64}, n::Integer, r::ANUQRNG)
    Vector{UInt64}(nANUrand(UInt32, n, r)) .<< 32 .+ Vector{UInt64}(nANUrand(UInt32, n, r))
end
function nANUrand(::Type{UInt128}, n::Integer, r::ANUQRNG)
    Vector{UInt128}(nANUrand(UInt64, n, r)) .<< 64 .+ Vector{UInt128}(nANUrand(UInt64, n, r))
end

function nANUrand(::Type{UInt8}, n::Integer, r::ANUQRNG)
    vals = Vector{UInt8}(undef, n)
    u16s = nANUrand(UInt16, ceil(Int, n / 2), r)
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

function nANUrand(::Type{Bool}, n::Integer, r::ANUQRNG)
    bools = Vector{Bool}(undef, n)
    uint16needed = ceil(Int, n / 16)
    uint16s = nANUrand(UInt16, uint16needed, r)
    for i in 1:(uint16needed-1)
        bools[16(i-1)+1:16i] = digits(Bool, uint16s[i], base=2, pad=16)
    end
    bools[16*(uint16needed-1)+1:n] = digits(Bool, uint16s[end], base=2, pad=16)[1:n%16]
    bools
end

function rand!(r::ANUQRNG, A::Array{Bool}, sp::Random.SamplerType{Bool})
    A[:] = nANUrand(Bool, length(A), r)
    A
end

const UInts = (UInt8, UInt16, UInt32, UInt64, UInt128)
const Ints = (Int8, Int16, Int32, Int64, Int128)

for T in UInts
    @eval function rand!(r::ANUQRNG, A::Array{$T}, sp::Random.SamplerType{$T})
        A[:] = nANUrand($T, length(A), r)
        A
    end
    @eval rand(r::ANUQRNG, sp::Random.SamplerType{$T}) = nANUrand($T, 1, r)[1]
end
for (T, U) in zip(Ints, UInts)
    @eval function rand!(r::ANUQRNG, A::Array{$T}, sp::Random.SamplerType{$T})
        A[:] = reinterpret.($T, nANUrand($U, length(A), r))
        A
    end
    @eval rand(r::ANUQRNG, sp::Random.SamplerType{$T}) = reinterpret.($T, nANUrand($U, 1, r))[1]
end

Random.rng_native_52(::ANUQRNG) = Float64

const F64BITMASK1 = 0b0011111111111111111111111111111111111111111111111111111111111111
const F64BITMASK2 = 0b0011111111110000000000000000000000000000000000000000000000000000

const F32BITMASK1 = 0b00111111111111111111111111111111
const F32BITMASK2 = 0b00111111100000000000000000000000

function rand!(r::ANUQRNG, A::Array{Float64}, sp::Random.SamplerTrivial{Random.CloseOpen01{Float64}, Float64})
    A[:] = reinterpret.(Float64, nANUrand(UInt64, length(A), r) .& F64BITMASK1 .| F64BITMASK2) .- 1
    A
end
function rand(r::ANUQRNG, X::Random.CloseOpen12{Float64})
    reinterpret(Float64, nANUrand(UInt64, 1, r)[1] & F64BITMASK1 | F64BITMASK2)
end

function rand!(r::ANUQRNG, A::Array{Float32}, sp::Random.SamplerTrivial{Random.CloseOpen01{Float32}, Float32})
    A[:] = reinterpret.(Float32, nANUrand(UInt32, length(A), r) .& F32BITMASK1 .| F32BITMASK2) .- 1
    A
end
