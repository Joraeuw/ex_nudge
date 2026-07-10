defmodule ExNudge.HTTPClient.Httpc do
  @moduledoc """
  The default `ExNudge.HTTPClient` adapter, built on Erlang/OTP's `:httpc`.

  Requires no extra dependencies. HTTPS requests verify the server certificate
  against the operating system's trusted CA store, which requires OTP 25 or
  later — on older releases configure a custom `ExNudge.HTTPClient` instead.
  """

  @behaviour ExNudge.HTTPClient

  @default_content_type "application/octet-stream"
  @connect_timeout 5_000
  @receive_timeout 30_000

  @impl true
  def post(url, body, headers) do
    {content_type, headers} = pop_content_type(headers)

    request =
      {String.to_charlist(url), to_httpc_headers(headers), String.to_charlist(content_type), body}

    case :httpc.request(:post, request, http_options(url), body_format: :binary) do
      {:ok, {{_http_version, status, _reason_phrase}, resp_headers, resp_body}} ->
        {:ok,
         %ExNudge.Response{
           status: status,
           headers: from_httpc_headers(resp_headers),
           body: resp_body
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp pop_content_type(headers) do
    case Enum.split_with(headers, fn {name, _} -> String.downcase(name) == "content-type" end) do
      {[{_, content_type} | _], rest} -> {content_type, rest}
      {[], rest} -> {@default_content_type, rest}
    end
  end

  defp to_httpc_headers(headers) do
    Enum.map(headers, fn {name, value} ->
      {String.to_charlist(name), String.to_charlist(value)}
    end)
  end

  defp from_httpc_headers(headers) do
    Enum.map(headers, fn {name, value} -> {to_string(name), to_string(value)} end)
  end

  defp http_options(url) do
    base = [timeout: @receive_timeout, connect_timeout: @connect_timeout]

    case URI.parse(url) do
      %URI{scheme: "https"} -> [{:ssl, ssl_options()} | base]
      _ -> base
    end
  end

  defp ssl_options do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      depth: 3,
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end
end
