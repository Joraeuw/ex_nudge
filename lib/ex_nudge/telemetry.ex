defmodule ExNudge.Telemetry do
  @moduledoc """
  Telemetry events emitted by ExNudge.

  ## Events

  ### `[:ex_nudge, :send_notification]`
  This event is emitted when a notification has completed both successfully and with an error.

  #### Measurements
  * `:duration` - The time taken in milliseconds from sending the notification to receiving a response.
  * `:payload_size` - Size of the payload in bytes

  #### Metadata
  * `:endpoint` - Sanitized push service endpoint
  * `:status` - Operation status (`:success` or `:error`)
  * `:http_status_code` - HTTP response status code or nil
  * `:error_reason` - Error reason or nil

  ## Example Usage

      :telemetry.attach("my-handler", [:ex_nudge, :send_notification], fn name, measurements, metadata, config ->
        case metadata.status do
          :success ->
            Logger.info("Notification sent successfully",
              duration: measurements.duration,
              endpoint: metadata.endpoint)
          :error ->
            Logger.error("Notification failed",
              error: metadata.error_reason,
              http_status: metadata.http_status_code)
        end
      end, nil)
  """

  @doc false
  def emit_notification_sent(start_time, subscription, payload_size, result) do
    duration = System.monotonic_time(:millisecond) - start_time

    {status, http_status_code, error_reason} = parse_result(result)

    metadata = %{
      endpoint: sanitize_endpoint(subscription.endpoint),
      status: status,
      http_status_code: http_status_code,
      error_reason: error_reason
    }

    measurements = %{
      duration: duration,
      payload_size: payload_size
    }

    :telemetry.execute([:ex_nudge, :send_notification], measurements, metadata)
  end

  defp parse_result(result) do
    case result do
      %HTTPoison.Response{status_code: status_code} when status_code in 200..299 ->
        {:success, status_code, nil}

      %HTTPoison.Response{status_code: status_code, body: reason} ->
        {:error, status_code, reason}

      {:error, reason} when is_atom(reason) ->
        {:error, nil, reason}

      {:error, reason} ->
        {:error, nil, inspect(reason)}
    end
  end

  defp sanitize_endpoint(endpoint) when is_binary(endpoint) do
    case URI.parse(endpoint) do
      %URI{host: host, path: path, scheme: scheme} when not is_nil(host) ->
        sanitized_path = sanitize_path(path)
        "#{scheme}://#{host}#{sanitized_path}"

      _ ->
        "invalid_endpoint"
    end
  end

  defp sanitize_endpoint(_), do: "invalid_endpoint"

  defp sanitize_path(nil), do: ""

  defp sanitize_path(path) do
    path
    |> String.split("/")
    |> Enum.map(fn segment ->
      cond do
        String.length(segment) > 50 -> "[TOKEN]"
        String.match?(segment, ~r/^[A-Za-z0-9_-]{20,}$/) -> "[ID]"
        true -> segment
      end
    end)
    |> Enum.join("/")
  end
end
