using cURL, JSON

query = Dict{String,Any}(
    "echo" => "你好嗎"
)

headers = Pair{String,String}[
    "User-Agent" => "cURL.jl",
    "Content-Type" => "application/json",
]

payload = JSON.json(Dict{String,Any}(
    "echo" => "hi"
))

interface = "0.0.0.0"

# POST
req = cURL.post( "httpbin.org/post", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 5, connect_timeout = 10, retries = 10)

req.status
String(req.body) |> JSON.parse

# GET
req = cURL.get("httpbin.org/get", query = "echo=你好嗎",
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

req.status
String(req.body) |> JSON.parse

# HEAD
req = cURL.head("httpbin.org/get", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

req.status
isempty(String(req.body))

# PUT
req = cURL.put("httpbin.org/put", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

req.status
String(req.body) |> JSON.parse

# PATCH
req = cURL.patch("httpbin.org/patch", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

req.status
String(req.body) |> JSON.parse

# DELETE
req = cURL.delete("httpbin.org/delete", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

req.status
String(req.body) |> JSON.parse

# Bad Request
req = cURL.request("GET", "httpbin.org/status/400", query = "echo=你好嗎",
    headers = headers, interface = interface, read_timeout = 30, retries = 1)

req.status
String(req.body) |> JSON.parse

# Proxy

# ENV["http_proxy"] = "socks5://user:pass@127.0.0.0:8888"
# ENV["https_proxy"] = "socks5://user:pass@127.0.0.0:8888"

# req = cURL.request("GET", "httpbin.org/status/400", query = "echo=你好嗎",
#     headers = headers, proxy = "socks5://user:pass@127.0.0.0:8888", read_timeout = 30, retries = 1)

# req.status
# String(req.body) |> JSON.parse
