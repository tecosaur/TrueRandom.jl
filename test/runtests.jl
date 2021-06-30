using TrueRandom
using Distributions
using Test

@testset "ANU QRNG" begin
    r = ANUQRNG(1024, 768; prefill=false)
    TrueRandom.prefillcache(r)

    @test length(r.cache) == r.batchsize
    @test length(r.cacheprefill) == 0
    @test r.pointer == 1

    @test rand(r, UInt8) isa UInt8
    @test rand(r, UInt8, 2) isa Vector{UInt8}
    @test rand(r, UInt16) isa UInt16
    @test rand(r, UInt16, 2) isa Vector{UInt16}
    @test rand(r, UInt32) isa UInt32
    @test rand(r, UInt32, 2) isa Vector{UInt32}
    @test rand(r, UInt64) isa UInt64
    @test rand(r, UInt64, 2) isa Vector{UInt64}
    @test rand(r, UInt128) isa UInt128
    @test rand(r, UInt128, 2) isa Vector{UInt128}

    @test r.pointer == 48

    @test rand(r, Int8) isa Int8
    @test rand(r, Int8, 2) isa Vector{Int8}
    @test rand(r, Int16) isa Int16
    @test rand(r, Int16, 2) isa Vector{Int16}
    @test rand(r, Int32) isa Int32
    @test rand(r, Int32, 2) isa Vector{Int32}
    @test rand(r, Int64) isa Int64
    @test rand(r, Int64, 2) isa Vector{Int64}
    @test rand(r, Int128) isa Int128
    @test rand(r, Int128, 2) isa Vector{Int128}

    @test r.pointer == 95

    @test rand(r, Float32) isa Float32
    @test rand(r, Float32, 2) isa Vector{Float32}
    @test rand(r, Float64) isa Float64
    @test rand(r, Float64, 2) isa Vector{Float64}

    @test r.pointer == 113
    @test length(r.cacheprefill) == 0

    m = rand(r, Float64, 5, 8)
    @test m isa Matrix{Float64}
    @test 0 <= minimum(m) <= 1
    @test 0 <= maximum(m) <= 1

    p1 = r.pointer
    @test rand(r, UInt16, 1024) isa Any
    @test r.pointer == p1

    @test rand(r, UInt16, 2048) isa Any
    @test r.pointer == p1

    @test randn(r) isa Any
    @test rand(r, Normal()) isa Any
end
