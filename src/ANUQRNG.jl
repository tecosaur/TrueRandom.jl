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

"""
    ANUQRNG(batchsize=1024, prefillthreshold=round(Int, 0.75*batchsize); prefill=true)

Create a new random number generator based on the ANU QRNG API which fetches random UInt16s in
batches of `bachsize`. As long as `prefill` is true, the next batch will be pre-fetched when
less than `prefillthreshold` UInt16s in the batch are unused.
"""
function ANUQRNG(batchsize=1024, prefillthreshold=round(Int, 0.75*batchsize); prefill=true)
    if batchsize == 0
        @warn "Setting `batchsize` to 0 is a really bad idea. Please reconsider."
    end
    OnlineUInt16RNG("ANU Quantum Random Number service",
                    nANUrand, batchsize, prefillthreshold; prefill)
end
