defmodule ExNudge.Utils do
  @moduledoc """
  Utility functions for the ExNudge library.
  """

  @spec url_encode(binary()) :: String.t()
  def url_encode(data) when is_binary(data) do
    Base.url_encode64(data, padding: false)
  end

  @spec safe_url_decode(String.t()) :: {:ok, binary()} | {:error, :invalid_base64}
  def safe_url_decode(string) when is_binary(string) do
    case Base.url_decode64(string, padding: false) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, :invalid_base64}
    end
  end

  def safe_url_decode(_), do: {:error, :invalid_input}
end
