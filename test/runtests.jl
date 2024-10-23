using Test, Random, Sockets, JSON

include("../src/cURL2.jl")
using .cURL2

include("unit.jl")
include("integration.jl")
include("websocket.jl")
