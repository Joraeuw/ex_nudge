defmodule Mix.Tasks.ExNudge.Gen.VapidKeysTest do
  # Swaps the global Mix shell.
  use ExUnit.Case, async: false

  test "prints a freshly generated key pair as a ready-to-paste config snippet" do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    Mix.Task.rerun("ex_nudge.gen.vapid_keys")

    assert_received {:mix_shell, :info, [output]}

    assert output =~ "config :ex_nudge,"
    assert output =~ "vapid_subject:"

    assert [_, public_key] = Regex.run(~r/vapid_public_key: "([^"]+)"/, output)
    assert [_, private_key] = Regex.run(~r/vapid_private_key: "([^"]+)"/, output)

    assert {:ok, decoded_public} = Base.url_decode64(public_key, padding: false)
    assert byte_size(decoded_public) == 65
    assert {:ok, _decoded_private} = Base.url_decode64(private_key, padding: false)
  end

  test "generates a different pair on every run" do
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)

    Mix.Task.rerun("ex_nudge.gen.vapid_keys")
    assert_received {:mix_shell, :info, [first]}

    Mix.Task.rerun("ex_nudge.gen.vapid_keys")
    assert_received {:mix_shell, :info, [second]}

    refute first == second
  end
end
