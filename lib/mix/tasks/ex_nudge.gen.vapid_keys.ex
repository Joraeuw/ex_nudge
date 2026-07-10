defmodule Mix.Tasks.ExNudge.Gen.VapidKeys do
  @shortdoc "Generates a VAPID key pair for Web Push"

  @moduledoc """
  Generates a VAPID key pair and prints a ready-to-paste config snippet.

      $ mix ex_nudge.gen.vapid_keys

  The keys identify your application server to push services (RFC 8292).
  Generate them once, keep the private key secret, and configure them —
  typically in `config/runtime.exs` via environment variables.
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    %{public_key: public_key, private_key: private_key} = ExNudge.VAPID.generate_vapid_keys()

    Mix.shell().info("""
    Add the following to your config (e.g. config/runtime.exs), replacing the
    subject with a contact address for your application. Keep the private key
    secret — prefer loading both keys from environment variables.

        config :ex_nudge,
          vapid_subject: "mailto:you@example.com",
          vapid_public_key: "#{public_key}",
          vapid_private_key: "#{private_key}"

    The public key is also what your frontend passes as `applicationServerKey`
    when calling `pushManager.subscribe/1`.
    """)
  end
end
