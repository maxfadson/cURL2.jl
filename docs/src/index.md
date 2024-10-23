![cURL.jl Logo](assets/full-logo.svg)

# cURL.jl Documentation

cURL is a Julia package that provides an interface to the cURL library for making HTTP requests. It is useful for sending HTTP requests, especially when dealing with RESTful APIs.

[![pipeline status](https://gitlab.com/bhft/cURL.jl/badges/master/pipeline.svg)](https://gitlab.com/bhft/cURL.jl/-/commits/master)
[![coverage report](https://gitlab.com/bhft/cURL.jl/badges/master/coverage.svg)](https://gitlab.com/bhft/cURL.jl/-/commits/master)
[![version](https://gitlab.com/bhft/cURL.jl/-/jobs/artifacts/master/raw/version.svg?job=badge-version)](https://gitlab.com/bhft/cURL.jl/-/blob/master/Project.toml)
[![docs](https://img.shields.io/badge/docs-blue.svg)](https://bhft.gitlab.io/cURL.jl)

## Installation
To install cURL, simply use the Julia package manager:

```julia
] add cURL
```

## Usage

Here is an example usage of cURL:

Sending a POST request

```julia
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

interface = "10.20.20.15"

# POST
req = cURL.request("POST", "httpbin.org/post", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 5, connect_timeout = 10, retries = 10)

req.status
String(req.body) |> JSON.parse
```

Sending a GET request

```julia
using cURL, JSON

headers = Pair{String,String}[
    "User-Agent" => "cURL.jl",
    "Content-Type" => "application/json",
]

interface = "10.20.20.15"

# GET
req = cURL.request("GET", "httpbin.org/get", query = "echo=你好嗎",
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

req.status
String(req.body) |> JSON.parse
```

And all other types of requests
```julia
# HEAD
req = cURL.head("httpbin.org/get", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

# PUT
req = cURL.put("httpbin.org/put", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

# PATCH
req = cURL.patch("httpbin.org/patch", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 30, retries = 10)

# DELETE
req = cURL.delete("httpbin.org/delete", body = payload, query = query,
    headers = headers, interface = interface, read_timeout = 30, retries = 10)
```

Url encode/decode functions.

```julia
using cURL

message = "[curl]"

julia> cURL.urlencode(message)
 "%5Bcurl%5D"

julia> cURL.urldecode(cURL.urlencode(message))
 "[curl]"
```

## Contributing
Contributions to cURL are welcome! If you encounter a bug, have a feature request, or would like to contribute code, please open an issue or a pull request on GitLab.

## License
cURL is licensed under the MIT License. See the LICENSE file in the root directory of the repository for more information.
