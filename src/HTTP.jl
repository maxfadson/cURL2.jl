struct cURLError <: Exception
    message::String
end

function cURLError(code::UInt32)
    cURLError(unsafe_string(curl_easy_strerror(code)))
end

Base.show(io::IO, e::cURLError) = print(io, "cURLError: ", e.message)

abstract type HttpMessage end

const Header = Pair{String,String}

#__ struct

mutable struct CurlResponse
    curl_slist::Ptr{Nothing}
    curl_status::Vector{Clong}
    curl_total_time::Vector{Cdouble}
    curl_active::Vector{Cint}
    rx_count::UInt64
    b_data::IOBuffer
    h_data::IOBuffer

    function CurlResponse()
        return new(
            C_NULL,
            Vector{Clong}(undef, 1),
            Vector{Cdouble}(undef, 1),
            Cint[1],
            0x0,
            IOBuffer(),
            IOBuffer(),
        )
    end
end

status(x::CurlResponse) = x.curl_status[1]
request_time(x::CurlResponse) = x.curl_total_time[1]
headers(x::CurlResponse) = parse_headers(String(take!(x.h_data)))
body(x::CurlResponse) = take!(x.b_data)

"""
Represents an HTTP response.

## Fields
- `status::Int64`: The HTTP status code of the response.
- `request_time::Float64`: The time taken for the HTTP request in seconds.
- `headers::Vector{Header}`: Headers received in the HTTP response.
- `body::Vector{UInt8}`: The response body as a vector of bytes.

# Constructor
- `Response(x::CurlResponse)`: Creates a new `Response` object from a `CurlResponse` object.
"""
struct Response
    status::Int64
    request_time::Float64
    headers::Vector{Header}
    body::Vector{UInt8}

    function Response(x::CurlResponse)
        return new(status(x), request_time(x), headers(x), body(x))
    end
end

"""
    status(x::Response) -> Int64

Extracts the HTTP status code from a `Response` object.
"""
status(x::Response) = x.status

"""
    request_time(x::Response) -> Float64

Extracts the request time from a `Response` object.
"""
request_time(x::Response) = x.request_time

"""
    headers(x::Response) -> Vector{Pair{String,String}}

Parses the HTTP headers from a `Response` object.
"""
headers(x::Response) = x.headers

"""
    body(x::Response) -> Vector{UInt8}

Extracts the response body from a `Response` object.
"""
body(x::Response) = x.body

"""
    iserror(x::Response) -> Bool

Does this `Response` have an error status?
"""
iserror(x::Response) = x.status >= 300

function headers(x::Response, key::AbstractString)
    hdrs = String[]
    for (k, v) in x.headers
        key == k && push!(hdrs, v)
    end
    return hdrs
end

function Base.show(io::IO, x::Response)
    println(io, Response)
    println(io, "\"\"\"")
    println(io, "HTTP/1.1 $(x.status) $(get(HTTP_STATUS_CODES, x.status, ""))")
    for (k, v) in x.headers
        println(io, "$k: '$v'")
    end
    println(io, "\"\"\"")
    if length(x.body) > 1000
        v = view(x.body, 1:1000)
        print(io, "    ", strip(String(v)))
        println(io, "\n    ⋮")
    else
        v = view(x.body, 1:length(x.body))
        println(io, "    ", strip(String(v)))
    end
end

"""
Represents an HTTP request.

## Fields

- `method::String`: The HTTP method for the request (e.g., "GET", "POST").
- `url::String`: The URL to which the request is sent.
- `headers::Vector{Pair{String, String}}`: Headers for the HTTP request.
- `body::Vector{UInt8}`: The request body as a vector of bytes.
- `connect_timeout::Real`: The connection timeout for the request.
- `read_timeout::Real`: The read timeout for the response.
- `interface::Union{String, Nothing}`: The network interface to use (or `Nothing` for the default).
- `proxy::Union{String, Nothing}`: The proxy server to use (or `Nothing` for no proxy).
- `accept_encoding::String`: The accepted encoding for the response (e.g., "gzip").
- `ssl_verifypeer::Bool`: Whether to verify SSL certificates.
- `rq_curl::Ptr{CURL}`: A pointer to a cURL handle for the request.
- `rq_multi::Ptr{CURL}`: A pointer to a cURL multi handle for the request.
- `response::CurlResponse`: The HTTP response associated with this request.

```
request = Request("GET", "https://example.com", Pair[]; body = UInt8[], connect_timeout = 10.0, read_timeout = 30.0, interface = nothing, proxy = nothing, accept_encoding = "gzip", ssl_verifypeer = true)
```
"""
struct Request <: HttpMessage
    method::String
    url::String
    headers::Vector{Pair{String,String}}
    body::Vector{UInt8}
    connect_timeout::Real
    read_timeout::Real
    interface::Union{String,Nothing}
    proxy::Union{String,Nothing}
    accept_encoding::String
    ssl_verifypeer::Bool
    rq_curl::Ptr{CURL}
    rq_multi::Ptr{CURL}
    response::CurlResponse
end

struct StatusError <: Exception
    message::String
    response::Response

    function StatusError(x::Response)
        return new(get(HTTP_STATUS_CODES, status(x), HTTP_STATUS_CODES[500]), x)
    end
end

Base.show(io::IO, e::StatusError) = print(io, StatusError, "(", status(e.response), " ,", "\"", e.message, "\"", ")")

#__ libcurl

function curl_write_cb(curlbuf::Ptr{UInt8}, s::Csize_t, n::Csize_t, p_ctxt::Ptr{Cvoid})
    response = unsafe_pointer_to_objref(p_ctxt)
    sz = s * n
    response.rx_count += sz
    unsafe_write(response.b_data, curlbuf, sz)
    return sz::Csize_t
end

function curl_header_cb(curlbuf::Ptr{UInt8}, s::Csize_t, n::Csize_t, p_ctxt::Ptr{Cvoid})
    response = unsafe_pointer_to_objref(p_ctxt)
    sz = s * n
    unsafe_write(response.h_data, curlbuf, sz)
    return sz::Csize_t
end

function curl_setup_rq(request::Request)
    curl_easy_setopt(request.rq_curl, CURLOPT_URL, request.url)
    curl_easy_setopt(request.rq_curl, CURLOPT_CAINFO, LibCURL2.cacert)
    curl_easy_setopt(request.rq_curl, CURLOPT_FOLLOWLOCATION, 1)
    curl_easy_setopt(request.rq_curl, CURLOPT_MAXREDIRS, MAX_REDIRECTIONS)
    curl_easy_setopt(request.rq_curl, CURLOPT_CONNECTTIMEOUT, request.connect_timeout)
    curl_easy_setopt(request.rq_curl, CURLOPT_TIMEOUT, request.read_timeout)
    # curl_easy_setopt(request.rq_curl, CURLOPT_WRITEFUNCTION, curl_write_cb)
    curl_easy_setopt(request.rq_curl, CURLOPT_INTERFACE, something(request.interface, C_NULL))
    curl_easy_setopt(request.rq_curl, CURLOPT_ACCEPT_ENCODING, request.accept_encoding)
    curl_easy_setopt(request.rq_curl, CURLOPT_SSL_VERIFYPEER, request.ssl_verifypeer)
    curl_easy_setopt(request.rq_curl, CURLOPT_USERAGENT, "cURL/1.2.0")
    curl_easy_setopt(request.rq_curl, CURLOPT_PROXY, something(request.proxy, C_NULL))

    c_curl_write_cb =
        @cfunction(curl_write_cb, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Cvoid}))

    c_curl_header_cb =
        @cfunction(curl_header_cb, Csize_t, (Ptr{UInt8}, Csize_t, Csize_t, Ptr{Cvoid}))

    curl_easy_setopt(request.rq_curl, CURLOPT_WRITEFUNCTION, c_curl_write_cb)
    curl_easy_setopt(request.rq_curl, CURLOPT_WRITEDATA, pointer_from_objref(request.response))

    curl_easy_setopt(request.rq_curl, CURLOPT_HEADERFUNCTION, c_curl_header_cb)
    curl_easy_setopt(request.rq_curl, CURLOPT_HEADERDATA, pointer_from_objref(request.response))

    for (k,v) in request.headers
        request.response.curl_slist =
            curl_slist_append(request.response.curl_slist, k * ": " * v)
    end

    curl_easy_setopt(request.rq_curl, CURLOPT_HTTPHEADER, request.response.curl_slist)
end

mutable struct CurlMsg
    msg::CURLMSG
    easy_handle::Ptr{CURL}
    data::Ptr{Any}
end

function free(request::Request)
    curl_multi_remove_handle(request.rq_multi, request.rq_curl)
    curl_multi_cleanup(request.rq_multi)
    curl_slist_free_all(request.response.curl_slist)
    curl_easy_cleanup(request.rq_curl)
end

function curl_rq_handle(request::Request)
    try
        curl_multi_add_handle(request.rq_multi, request.rq_curl)
        curl_multi_perform(request.rq_multi, request.response.curl_active)

        while (request.response.curl_active[1] > 0)
            rx_count_before = request.response.rx_count
            multi_perf = curl_multi_perform(request.rq_multi, request.response.curl_active)
            rx_count_after = request.response.rx_count
            if multi_perf != CURLE_OK
                throw(cURLError(unsafe_string(curl_multi_strerror(multi_perf))))
            end
            if !(rx_count_after > rx_count_before)
                sleep(0.001)
            end
        end

        msgs_in_queue = Vector{Int32}(undef, 1)
        ptr_msg::Ptr{CurlMsg} = curl_multi_info_read(request.rq_multi, msgs_in_queue)

        while ptr_msg != C_NULL
            msg = unsafe_load(ptr_msg)
            ptr_msg = curl_multi_info_read(request.rq_multi, msgs_in_queue)
            msg.msg != CURLMSG_DONE && continue
            msg_data = convert(Int64, msg.data)
            if msg_data != CURLE_OK
                throw(cURLError(unsafe_string(curl_easy_strerror(msg_data))))
            end
        end

        curl_easy_getinfo(request.rq_curl, CURLINFO_RESPONSE_CODE, request.response.curl_status)
        curl_easy_getinfo(request.rq_curl, CURLINFO_TOTAL_TIME, request.response.curl_total_time)
    catch ex
        rethrow(ex)
    end
end

function curl_request(::Val{:GET}, request::Request)
    try
        curl_setup_rq(request)
        curl_easy_setopt(request.rq_curl, CURLOPT_HTTPGET, 1)
        curl_rq_handle(request)
    catch ex
        rethrow(ex)
    end
end

function curl_request(::Val{:HEAD}, request::Request)
    try
        curl_setup_rq(request)
        curl_easy_setopt(request.rq_curl, CURLOPT_NOBODY, 1);
        curl_rq_handle(request)
    catch ex
        rethrow(ex)
    end
end

function curl_request(::Val{:POST}, request::Request)
    try
        curl_setup_rq(request)
        curl_easy_setopt(request.rq_curl, CURLOPT_POST, 1)
        curl_easy_setopt(request.rq_curl, CURLOPT_POSTFIELDSIZE, length(request.body))
        curl_easy_setopt(request.rq_curl, CURLOPT_COPYPOSTFIELDS, pointer(request.body))
        curl_rq_handle(request)
    catch ex
        rethrow(ex)
    end
end

function curl_request(::Val{:PUT}, request::Request)
    try
        curl_setup_rq(request)
        curl_easy_setopt(request.rq_curl, CURLOPT_POSTFIELDS, request.body)
        curl_easy_setopt(request.rq_curl, CURLOPT_POSTFIELDSIZE, length(request.body))
        curl_easy_setopt(request.rq_curl, CURLOPT_CUSTOMREQUEST, "PUT")
        curl_rq_handle(request)
    catch ex
        rethrow(ex)
    end
end

function curl_request(::Val{:PATCH}, request::Request)
    try
        curl_setup_rq(request)
        curl_easy_setopt(request.rq_curl, CURLOPT_POSTFIELDS, request.body)
        curl_easy_setopt(request.rq_curl, CURLOPT_POSTFIELDSIZE, length(request.body))
        curl_easy_setopt(request.rq_curl, CURLOPT_CUSTOMREQUEST, "PATCH");
        curl_rq_handle(request)
    catch ex
        rethrow(ex)
    end
end

function curl_request(::Val{:DELETE}, request::Request)
    try
        curl_setup_rq(request)
        curl_easy_setopt(request.rq_curl, CURLOPT_POSTFIELDS, request.body)
        curl_easy_setopt(request.rq_curl, CURLOPT_CUSTOMREQUEST, "DELETE")
        curl_rq_handle(request)
    catch ex
        rethrow(ex)
    end
end

function curl_request(::Val{:CONNECT}, request::Request)
    try
        curl_setup_rq(request)
        curl_easy_setopt(request.rq_curl, CURLOPT_CONNECT_ONLY, 2)
        curl_rq_handle(request)
    catch ex
        rethrow(ex)
    end
end

function curl_request(::Val{x}, request::Request) where {x}
    return throw(cURLError("`$(x)` method not supported"))
end

#__ request

to_query_decode(::Nothing) = ""
to_query_decode(x::S) where {S<:AbstractString} = x
to_query_decode(x::AbstractDict) = urlencode_query_params(x)

to_bytes(::Nothing) = Vector{UInt8}()
to_bytes(x::S) where {S<:AbstractString} = Vector{UInt8}(x)
to_bytes(x::Vector{UInt8}) = x

function rq_url(url::AbstractString, query)
    kv = to_query_decode(query)
    return isempty(kv) ? url : url * "?" * kv
end

"""
request(method, url [, headers [, body]]; <keyword arguments>]) -> [`cURL.Response`](@ref)

Send a HTTP Request Message and receive a HTTP Response Message.

## Arguments

- url::String: The base URL for the request.
- headers::Vector{Pair{String,String}} = Header[]: The headers for the request.
- query = nothing: The query string for the request.
- body = nothing: The body for the request.
- interface = nothing: The interface for the request.
- status_exception::Bool = true: Whether to throw an exception if the response status code indicates an error.
- connect_timeout::Real = 60: The connect timeout for the request.
- read_timeout::Real = 300: The read timeout for the request.
- retries::Int64 = 1: The number of times to retry the request if an error occurs.
- proxy::Union{String,Nothing} = nothing: Which proxy to use for the request.
- accept_encoding::String = "gzip": Encoding to accept.
- ssl_verifypeer::Bool = true: Whether peer need to be verified.

## Returns

The response to the request.

```julia
julia> req = cURL.request("GET", "https://jsonplaceholder.typicode.com/todos/1")

julia> req.status
200

julia> String(req.body)
"{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false\n}"
```
"""
function request(
    method::AbstractString,
    url::AbstractString;
    headers::Vector{Header} = Header[],
    query = nothing,
    body = nothing,
    connect_timeout::Real = DEFAULT_CONNECT_TIMEOUT,
    read_timeout::Real = DEFAULT_READ_TIMEOUT,
    interface::Union{String,Nothing} = nothing,
    proxy::Union{String,Nothing} = nothing,
    retries::Int64 = 1,
    status_exception::Bool = true,
    accept_encoding::String = "gzip",
    ssl_verifypeer::Bool = true,
)
    @label curl_request_retry

    req = Request(
        method,
        rq_url(url, query),
        headers,
        to_bytes(body),
        connect_timeout,
        read_timeout,
        interface,
        proxy,
        accept_encoding,
        ssl_verifypeer,
        curl_easy_init(),
        curl_multi_init(),
        CurlResponse(),
    )
    return try
        curl_request(Val(Symbol(req.method)), req)
        response = Response(req.response)
        if status_exception && iserror(response)
            throw(StatusError(response))
        end
        response
    catch e
        retries -= 1
        sleep(0.25)
        retries >= 0 && @goto curl_request_retry
        rethrow(e)
    finally
        free(req)
    end
end

"""
get(url; kw...) -> [`cURL.Response`](@ref)

Send an HTTP GET request and return the response.

## Arguments

- url::String: The base URL for the request.
- headers::Vector{Pair{String,String}} = Header[]: The headers for the request.
- query = nothing: The query string for the request.
- body = nothing: The body for the request.
- interface = nothing: The interface for the request.
- status_exception::Bool = true: Whether to throw an exception if the response status code indicates an error.
- read_timeout::Real = 86400: The read timeout for the request.
- retries::Int64 = 5: The number of times to retry the request if an error occurs.

## Returns

The response to the request.

```julia
julia> req = cURL.get("https://jsonplaceholder.typicode.com/todos/1")

julia> req.status
200

julia> String(req.body)
"{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false\n}"
```
"""
Base.get(url; kw...)::Response = request("GET", url; kw...)

"""
head(url; kw...) -> [`cURL.Response`](@ref)

Send an HTTP HEAD request and return the response.

## Arguments

- url::String: The base URL for the request.
- headers::Vector{Pair{String,String}} = Header[]: The headers for the request.
- query = nothing: The query string for the request.
- body = nothing: The body for the request.
- interface = nothing: The interface for the request.
- status_exception::Bool = true: Whether to throw an exception if the response status code indicates an error.
- read_timeout::Real = 86400: The read timeout for the request.
- retries::Int64 = 5: The number of times to retry the request if an error occurs.

## Returns

The response to the request.

```julia
julia>  req = cURL.head("https://jsonplaceholder.typicode.com/todos/1")

julia> req.status
200

julia> isempty(String(req.body))
true
```
"""
head(url; kw...)::Response = request("HEAD", url; kw...)

"""
post(url; kw...) -> [`cURL.Response`](@ref)

Send an HTTP POST request and return the response.

## Arguments

- url::String: The base URL for the request.
- headers::Vector{Pair{String,String}} = Header[]: The headers for the request.
- query = nothing: The query string for the request.
- body = nothing: The body for the request.
- interface = nothing: The interface for the request.
- status_exception::Bool = true: Whether to throw an exception if the response status code indicates an error.
- read_timeout::Real = 86400: The read timeout for the request.
- retries::Int64 = 5: The number of times to retry the request if an error occurs.

## Returns

The response to the request.

```julia
julia> req = cURL.post("https://jsonplaceholder.typicode.com/todos/1")

julia> req.status
200

julia> String(req.body)
"{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false\n}"
```
"""
post(url; kw...)::Response = request("POST", url; kw...)

"""
put(url; kw...) -> [`cURL.Response`](@ref)

Send an HTTP PUT request and return the response.

## Arguments

- url::String: The base URL for the request.
- headers::Vector{Pair{String,String}} = Header[]: The headers for the request.
- query = nothing: The query string for the request.
- body = nothing: The body for the request.
- interface = nothing: The interface for the request.
- status_exception::Bool = true: Whether to throw an exception if the response status code indicates an error.
- read_timeout::Real = 86400: The read timeout for the request.
- retries::Int64 = 5: The number of times to retry the request if an error occurs.

## Returns

The response to the request.

```julia
julia>  req = cURL.put("https://jsonplaceholder.typicode.com/posts/1")

julia> req.status
200

julia> String(req.body)
"{\n  \"id\": 1\n}"
```
"""
put(url; kw...)::Response = request("PUT", url; kw...)

"""
patch(url; kw...) -> [`cURL.Response`](@ref)

Send an HTTP PATCH request and return the response.

## Arguments

- url::String: The base URL for the request.
- headers::Vector{Pair{String,String}} = Header[]: The headers for the request.
- query = nothing: The query string for the request.
- body = nothing: The body for the request.
- interface = nothing: The interface for the request.
- status_exception::Bool = true: Whether to throw an exception if the response status code indicates an error.
- read_timeout::Real = 86400: The read timeout for the request.
- retries::Int64 = 5: The number of times to retry the request if an error occurs.

## Returns

The response to the request.

```julia
julia> req = cURL.patch("https://jsonplaceholder.typicode.com/todos/1")

julia> req.status
200

julia> String(req.body)
"{\n  \"userId\": 1,\n  \"id\": 1,\n  \"title\": \"delectus aut autem\",\n  \"completed\": false\n}"
```
"""
patch(url; kw...)::Response = request("PATCH", url; kw...)

"""
delete(url; kw...) -> [`cURL.Response`](@ref)

Send an HTTP DELETE request and return the response.

## Arguments

- url::String: The base URL for the request.
- headers::Vector{Pair{String,String}} = Header[]: The headers for the request.
- query = nothing: The query string for the request.
- body = nothing: The body for the request.
- interface = nothing: The interface for the request.
- status_exception::Bool = true: Whether to throw an exception if the response status code indicates an error.
- read_timeout::Real = 86400: The read timeout for the request.
- retries::Int64 = 5: The number of times to retry the request if an error occurs.

## Returns

The response to the request.

```julia
julia> req = cURL.delete("https://jsonplaceholder.typicode.com/posts/1")

julia> req.status
200

julia> String(req.body)
"{}"
```
"""
delete(url; kw...)::Response = request("DELETE", url; kw...)
