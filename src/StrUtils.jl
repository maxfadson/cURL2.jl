# StrUtils

function urlencode_query_params(params::AbstractDict{String,T}) where {T<:Any}
    str = ""
    for (k, v) in params
        if v !== ""
            ep = urlencode(string(k)) * "=" * urlencode(string(v))
        else
            ep = urlencode(string(k))
        end
        if str == ""
            str = ep
        else
            str *= "&" * ep
        end
    end
    return str
end

function urlencode(s::AbstractString)
    return urlencode_query(curl_easy_init(), s)
end

function urlencode_query(curl, s::AbstractString)
    b_arr = curl_easy_escape(curl, s, sizeof(s))
    esc_s = unsafe_string(b_arr)
    curl_free(b_arr)
    return esc_s
end

function urldecode(s::AbstractString)
    return urldecode_query(curl_easy_init(), s)
end

function urldecode_query(curl, s::AbstractString)
    b_arr = curl_easy_unescape(curl, s, 0, C_NULL)
    esc_s = unsafe_string(b_arr)
    curl_free(b_arr)
    return esc_s
end

function joinurl(basepart::AbstractString, parts::AbstractString...)::String
    return join(String[basepart, parts...], "/")
end

function parse_headers(headers::AbstractString)
    matches = match.(r"^(.*?):\s*(.*?)$", split(headers, "\r\n"))
    result = Pair{String,String}[]
    for m in matches
        isnothing(m) && continue
        push!(result, m[1] => m[2])
    end
    return result
end
