# test/unit.jl

@testset "Url encode params" begin
    result = cURL2.urlencode_query_params(Dict{String,Any}())
    @test result == ""

    result = cURL2.urlencode_query_params(Dict{String,Any}("a" => "b"))
    @test result == "a=b"

    result = cURL2.urlencode_query_params(
        Dict{String,Any}("a" => "1", "b" => "2", "c" => "c")
    )
    @test result == "c=c&b=2&a=1"

    result = cURL2.urlencode_query_params(
        Dict{String,Any}("a" => 1, "b" => 1.0, "c" => 'c')
    )
    @test result == "c=c&b=1.0&a=1"

    result = cURL2.urlencode_query_params(
        Dict{String,Any}("a" => "b", "a" => nothing, "c" => missing),
    )

    @test result == "c=missing&a=nothing"
end

@testset "Url encode" begin
    result = cURL2.urlencode("")
    @test result == ""

    result = cURL2.urlencode("aaa")
    @test result == "aaa"

    result = cURL2.urlencode("http://blabla.mge:9000?c=c&b=1.0&a=1")
    @test result == "http%3A%2F%2Fblabla.mge%3A9000%3Fc%3Dc%26b%3D1.0%26a%3D1"

    result = cURL2.urlencode("http://blabla.mge:9000?")
    @test result == "http%3A%2F%2Fblabla.mge%3A9000%3F"

    result = cURL2.urlencode(SubString("http://blabla.mge:9000?c=c&b=1.0&a=1", 2))
    @test result == "ttp%3A%2F%2Fblabla.mge%3A9000%3Fc%3Dc%26b%3D1.0%26a%3D1"
end

@testset "Url decode" begin
    result = cURL2.urldecode("")
    @test result == ""

    result = cURL2.urldecode("aaa")
    @test result == "aaa"

    result = cURL2.urldecode(
        "http%3A%2F%2Fblabla.mge%3A9000%3Fc%3Dc%26b%3D1.0%26a%3D1"
    )
    @test result == "http://blabla.mge:9000?c=c&b=1.0&a=1"

    result = cURL2.urldecode("http%3A%2F%2Fblabla.mge%3A9000%3F")
    @test result == "http://blabla.mge:9000?"

    result = cURL2.urlencode(SubString("http://blabla.mge:9000?c=c&b=1.0&a=1", 2))
    @test result == "ttp%3A%2F%2Fblabla.mge%3A9000%3Fc%3Dc%26b%3D1.0%26a%3D1"
end

@testset "Encode decode random test" begin
    chars = map(Char, 32:126)

    for i = 1:1000
        str = randstring(chars, 30)
        @test str == cURL2.urldecode(cURL2.urlencode(str))
    end
end
