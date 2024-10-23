using Documenter, cURL

makedocs(
    modules = [cURL],
    sitename = "cURL.jl",
    pages = [
        "Home" => "index.md",
        "pages/reference.md",
    ],
)