defmodule ExampleExNudge.Models.PushSubscription do
  use Ecto.Schema
  import Ecto.Changeset

  @attrs [:endpoint, :p256dh_key, :auth_key]

  schema "push_subscriptions" do
    field(:endpoint, :string)
    field(:auth_key, :string)
    field(:p256dh_key, :string)
  end

  def changeset(struct, attrs \\ %{}) do
    struct
    |> cast(attrs, @attrs)
    |> validate_required(@attrs)
    |> unique_constraint(:endpoint)
  end
end
