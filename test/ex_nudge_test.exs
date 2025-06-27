defmodule ExNudgeTest do
  use ExUnit.Case, async: true

  setup do
    Application.put_env(:ex_nudge, :vapid_subject, "mailto:test@example.com")
    Application.put_env(:ex_nudge, :vapid_public_key, "test_public_key")
    Application.put_env(:ex_nudge, :vapid_private_key, "test_private_key")
  end
end
