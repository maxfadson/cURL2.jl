mutable struct Connection
    request::Request
    response::Response
    isopen::Bool
    isdeflate::Bool
end

Base.isopen(c::Connection) = c.isopen

function Base.close(c::Connection, message::String="close")
    if !isopen(c)
        return nothing
    end
    send(c, message, flags=CURLWS_CLOSE)
    c.isopen = false
    return nothing
end

function check_deflate(headers::Vector{Header})
    return any(headers) do (key, value)
        A = lowercase(key) == "sec-websocket-extensions"
        B = lowercase(value) == "permessage-deflate"
        A && B
    end
end

function open_connection(
    url::AbstractString;
    headers::Vector{Header} = Header[],
    query = nothing,
    connect_timeout::Real = DEFAULT_CONNECT_TIMEOUT,
    read_timeout::Real = DEFAULT_READ_TIMEOUT,
    interface::Union{String,Nothing} = nothing,
    proxy::Union{String,Nothing} = nothing,
    retries::Int64 = 1,
    accept_encoding::String = "gzip",
    ssl_verifypeer::Bool = true,
)
    @label curl_request_retry

    req = Request(
        "CONNECT",
        rq_url(url, query),
        headers,
        to_bytes(nothing),
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
        curl_request(Val(:CONNECT), req)
        response = Response(req.response)
        isdeflate = check_deflate(headers)

        con = Connection(req, response, true, isdeflate)
        finalizer(c -> free(c.request), con)
    catch e
        retries -= 1
        sleep(0.25)
        retries >= 0 && @goto curl_request_retry
        rethrow(e)
    end
end

function websocket(handle,
    url::AbstractString;
    headers::Vector{Header} = Header[],
    query = nothing,
    connect_timeout::Real = DEFAULT_CONNECT_TIMEOUT,
    read_timeout::Real = DEFAULT_READ_TIMEOUT,
    interface::Union{String,Nothing} = nothing,
    proxy::Union{String,Nothing} = nothing,
    retries::Int64 = 1,
    accept_encoding::String = "gzip",
    ssl_verifypeer::Bool = true,
)
    connection = open_connection(url;
        headers,
        query,
        connect_timeout,
        read_timeout,
        interface,
        proxy,
        retries,
        accept_encoding,
        ssl_verifypeer,
    )
    ping_timer = Timer(t -> send_ping(connection), 0; interval = 60)
    return try
        wait(ping_timer)
        handle(connection)
    finally
        close(ping_timer)
        close(connection)
    end
end

function send(connection::Connection, message::Vector{UInt8}=UInt8[]; flags = CURLWS_BINARY)
    easy_handle = connection.request.rq_curl

    sent = Ref{Csize_t}(0)
    result = curl_ws_send(easy_handle, message, length(message), sent, 0, flags)

    if result != CURLE_OK
        connection.isopen = false
        error(cURLError(result))
    end
    return true
end

function send(connection::Connection, message::AbstractString; flags=CURLWS_TEXT)
    return send(connection, Vector{UInt8}(message); flags)
end

function send_ping(connection::Connection, message = "foo")
    return send(connection, message; flags = CURLWS_PING)
end

function send_pong(connection::Connection, message)
    return send(connection, message; flags = CURLWS_PONG)
end

function recv_one_frame(connection::Connection)
    read_timer = Timer(connection.request.read_timeout)
    easy_handle = connection.request.rq_curl

    received = Ref{Csize_t}(0)
    meta_ptr = [Ptr{curl_ws_frame}(0)]
    buffer_size = 256
    buffer = zeros(UInt8, buffer_size)
    yield()
    result = curl_ws_recv(easy_handle, buffer, buffer_size, received, meta_ptr)
    while result == CURLE_AGAIN
        if !isopen(read_timer)
            error(cURLError("Read timeout is reached"))
        end
        sleep(0.01)
        yield()
        result = curl_ws_recv(easy_handle, buffer, buffer_size, received, meta_ptr)
    end

    if result != CURLE_OK
        connection.isopen = false
        error(cURLError(result))
    end

    message = GC.@preserve buffer unsafe_string(pointer(buffer), received[])
    frame = unsafe_load(meta_ptr[1], 1)
    return message, frame
end

function message_type(frame::curl_ws_frame)
    flags = frame.flags
    return if (flags & CURLWS_PING) != 0
        "PING"
    elseif (flags & CURLWS_PONG) != 0
        "PONG"
    elseif (flags & CURLWS_TEXT) != 0
        "TEXT"
    elseif (flags & CURLWS_BINARY) != 0
        "BINARY"
    elseif (flags & CURLWS_CLOSE) != 0
        "CLOSE"
    else
        "MISSING"
    end
end

function receive_any(connection::Connection)
    full_message, frame = recv_one_frame(connection)
    while frame.bytesleft > 0
        message, frame = recv_one_frame(connection)
        full_message *= message
    end

    return full_message, message_type(frame)
end

function receive(connection::Connection)
    message, message_type = receive_any(connection)
    if message_type ∉ ("TEXT", "BINARY")
        control_handler(Val(Symbol(message_type)), message, connection)
        if !isopen(connection) # Connection was closed without error.
            return message
        end
        return receive(connection) # User gets only text or binary messages.
    end

    if connection.isdeflate
        message = decompress(message)
    end

    return message
end

function control_handler(::Val{:PING}, message, connection::Connection)
    @debug "Received ping message, send pong message: $message"
    send_pong(connection, message)
    return nothing
end

function control_handler(::Val{:PONG}, message, connection::Connection)
    @debug "Received pong message: $message"
    return nothing
end

function control_handler(::Val{:CLOSE}, message, connection::Connection)
    @debug "Server closed connection: $message"
    close(connection)
    return nothing
end

function control_handler(::Val{:MISSING}, message, connection::Connection)
    @warn "Received unknown message type: $message"
    return nothing
end

function control_handler(::Val{x}, message, connection::Connection) where {x}
    error(cURLError("Non control message: $(x)"))
end

function receive_pong(connection, message = "foo")
    data, message_type = receive_any(connection)
    if message_type != "PONG"
        @warn "receive_pong: expected pong, but received data"
        return false, data
    end

    if data != message
        error(cURLError("Expected $(message), got $(data)."))
    end

    return true, data
end

function decompress(deflate_message::AbstractVector{UInt8})
    # add some magic bytes, taken from WebSockets.jl
    append!(deflate_message, [0x00, 0x00, 0xff, 0xff, 0x03, 0x00])
    return transcode(DeflateDecompressor, deflate_message)
end

decompress(deflate_message::AbstractString) = decompress(Vector{UInt8}(deflate_message))
