module cURL2

using CodecZlib
using LibCURL2

const MAX_REDIRECTIONS = 5
const DEFAULT_CONNECT_TIMEOUT = 60  # seconds
const DEFAULT_READ_TIMEOUT = 300  # seconds

include("Static.jl")
include("StrUtils.jl")
include("HTTP.jl")
include("WebSockets.jl")


end
