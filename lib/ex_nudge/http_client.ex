defmodule ExNudge.HTTPClient do
  @moduledoc """
  Behaviour for the HTTP client used to deliver push messages.

  ExNudge ships with a default adapter built on Erlang/OTP's `:httpc`
  (`ExNudge.HTTPClient.Httpc`), so it forces no HTTP library on you. To use
  your favorite client instead, implement this behaviour and configure it:

      config :ex_nudge, http_client: MyApp.ExNudgeClient

  An implementation only has to perform a POST request and normalize the
  result:

      defmodule MyApp.ExNudgeClient do
        @behaviour ExNudge.HTTPClient

        @impl true
        def post(url, body, headers) do
          case Req.post(url, body: body, headers: headers) do
            {:ok, %Req.Response{status: status, headers: headers, body: body}} ->
              {:ok,
               %ExNudge.Response{
                 status: status,
                 headers: flatten_headers(headers),
                 body: to_string(body)
               }}

            {:error, reason} ->
              {:error, reason}
          end
        end
      end

  Any `{:error, reason}` return is wrapped by ExNudge into
  `{:error, %ExNudge.Error{reason: :request_failed, context: reason}}`.
  """

  @callback post(
              url :: String.t(),
              body :: binary(),
              headers :: [{String.t(), String.t()}]
            ) :: {:ok, ExNudge.Response.t()} | {:error, term()}
end
