const url_postman = "wss://ws.postman-echo.com/raw"
const url_binance_stream = "wss://stream.binance.com:9443/stream?streams=adausdt@depth20@100ms/btcusdt@depth20@100ms"

@testset "Send and receive" begin
    ws1 = cURL2.open_connection("wss://ws.postman-echo.com/raw", connect_timeout=10)

    # Test short message
    short_message = "a"^100
    cURL2.send(ws1, short_message)
    @test cURL2.receive(ws1) == short_message  # Echo server should return the same message

    # Test long message
    long_message = "a"^1000
    cURL2.send(ws1, long_message)
    @test cURL2.receive(ws1) == long_message

    # Test very long message
    very_long_message = "a"^10000
    cURL2.send(ws1, very_long_message)
    @test cURL2.receive(ws1) == very_long_message

    close(ws1)
end

@testset "Ping pong" begin
    cURL2.websocket(url_postman, connect_timeout=10) do connection
        # test if there is initial ping
        @test cURL2.receive_pong(connection, "foo")[1]

        # different message
        @test cURL2.send_ping(connection, "message")
        @test cURL2.receive_pong(connection, "message")[1]
    end
end

@testset "Deflate support" begin
    cURL2.websocket(
        url_binance_stream;
        headers = [
            "User-Agent" => "http-julia",
            "sec-websocket-extensions" => "permessage-deflate"
        ],
    ) do connection
        message = cURL2.receive(connection)
        @test typeof(JSON.parse(String(message))) <: Dict
    end
end

@testset "Connect timeout" begin
    cURL2.websocket(url_postman, connect_timeout=5) do connection
        sleep(10)
        @test cURL2.send_ping(connection, "test")
    end
end

@testset "Raise error" begin
    cURL2.websocket(url_binance_stream) do connection
        @test_throws "Failed sending data to the peer" begin
            while isopen(connection)
                cURL2.send_ping(connection)
            end
        end
    end
end
