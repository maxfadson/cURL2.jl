# test/integration.jl

const query = Dict{String,Any}(
    "echo" => "你好嗎"
)

const headers = Pair{String,String}[
    "User-Agent" => "cURL2.jl",
    "Content-Type" => "application/json",
]

const payload = cURL2.urlencode_query_params(Dict{String,Any}(
    "echo" => "hello"
))

@testset "GET request" begin
    @test_throws "cURLError: Could not resolve hostname" cURL2.get(
        "https://hnweerewrwelirjewirjlew.org/get";
        headers = headers,
        query = query,
        read_timeout = 30,
    )

    request = cURL2.get(
        "httpbin.org/get",
        headers = headers,
        query = query,
        read_timeout = 30,
        retries = 10,
    )

    response = JSON.parse(String(request.body))

    @test request.status === 200
    @test response["url"]  == "http://httpbin.org/get?echo=你好嗎"
    @test response["args"] == query
end

@testset "HEAD request" begin
    request = cURL2.head(
        "httpbin.org/get",
        headers = headers,
        query = query,
        body = payload,
        read_timeout = 30,
        retries = 10,
    )

    @test isempty(request.body)
    @test request.status === 200
end

@testset "POST request" begin
    request = cURL2.post(
        "httpbin.org/post",
        headers = headers,
        query = query,
        body = payload,
        read_timeout = 30,
        retries = 10,
    )

    response = JSON.parse(String(request.body))

    @test request.status === 200
    @test response["url"]  == "http://httpbin.org/post?echo=你好嗎"
    @test response["args"] == query
    @test response["data"] == payload
end

@testset "PUT request" begin
    request = cURL2.put(
        "httpbin.org/put",
        headers = headers,
        query = query,
        body = payload,
        read_timeout = 30,
        retries = 10,
    )

    response = JSON.parse(String(request.body))

    @test request.status === 200
    @test response["url"]  == "http://httpbin.org/put?echo=你好嗎"
    @test response["args"] == query
    @test response["data"] == payload
end

@testset "PATCH request" begin
    request = cURL2.patch(
        "httpbin.org/patch",
        headers = headers,
        query = query,
        body = payload,
        read_timeout = 30,
        retries = 10,
    )

    response = JSON.parse(String(request.body))

    @test request.status === 200
    @test response["url"]  == "http://httpbin.org/patch?echo=你好嗎"
    @test response["args"] == query
    @test response["data"] == payload
end

@testset "DELETE request" begin
    request = cURL2.delete(
        "httpbin.org/delete",
        headers = headers,
        query = query,
        body = payload,
        read_timeout = 30,
        retries = 10,
    )

    response = JSON.parse(String(request.body))

    @test request.status === 200
    @test response["url"]  == "http://httpbin.org/delete?echo=你好嗎"
    @test response["args"] == query
    @test response["data"] == payload
end

@testset "Optional interface" begin
    listener = Sockets.listen(IPv4("127.0.0.1"), 1234)

    @async while true
        body = """
        HTTP/1.1 200 OK
        Server: nginx
        Date: Wed, 10 Aug 2022 22:00:01 GMT
        Content-Type: text/html; charset=utf-8
        Connection: keep-alive
        Set-Cookie: key=1234-1234-1234-1234-1234; SameSite=Strict; HttpOnly; path=/
        Referrer-Policy: origin-when-cross-origin

        <h1>Hello</h1>
        """

        connection = accept(listener)

        @async while isopen(connection)
            echo = Sockets.readavailable(connection)
            println(String(echo))
            write(connection, body)
            close(connection)
        end
    end

    sleep(2.0)

    @test_throws "cURLError: Failed binding local connection end" cURL2.get(
        "http://127.0.0.1:1234",
        headers = headers,
        query = query,
        interface = "10.10.10.10",
        read_timeout = 30,
    )

    req = cURL2.get(
        "http://127.0.0.1:1234",
        headers = headers,
        query = query,
        interface = "0.0.0.0",
        read_timeout = 30,
        retries = 10,
    )

    @test req.status === 200
    @test String(req.body) == "<h1>Hello</h1>\n"

    close(listener)
end
