defmodule ExNudge.Response do
  @moduledoc """
  A normalized HTTP response from the push service.

  ExNudge never exposes the response struct of the underlying HTTP client.
  Whatever adapter is configured (see `ExNudge.HTTPClient`), successful
  deliveries always return `{:ok, %ExNudge.Response{}}`.
  """

  @type t :: %__MODULE__{
          status: non_neg_integer(),
          headers: [{String.t(), String.t()}],
          body: binary()
        }

  @enforce_keys [:status]
  defstruct status: nil, headers: [], body: ""
end
