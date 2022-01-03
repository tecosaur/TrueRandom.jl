module TrueRandom

using Random
import Random: rand, rand!, _rand52

import Base.show

using Base.Threads

using HTTP
using JSON3

include("UInt16RNG.jl")

export ANUQRNG

include("ANUQRNG.jl")

end
