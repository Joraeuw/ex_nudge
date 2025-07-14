defmodule ExampleExNudge.Repo.Migrations.CreatePushNotificationsTable do
  use Ecto.Migration

  def change do
    create table(:push_subscriptions) do
      ### Essential Data for the notification
      add :endpoint, :text, null: false
      add :p256dh_key, :string, null: false
      add :auth_key, :string, null: false
      ### You would usually have this reference a user
      # add :user_id, references(:users, on_delete: :delete_all), null: false
      ### Additional metadata
      # add :platform, :string
      # add :user_agent, :text
      # add :device_name, :string
      # add :active, :boolean, default: true
      # add :last_used_at, :utc_datetime
      # timestamps()
    end

    ### Sometimes you might want to store some logs
    # create table(:notification_logs) do
    #   add :subscription_id, references(:push_subscriptions, on_delete: :delete_all)
    #   add :title, :string, null: false
    #   add :body, :text, null: false
    #   add :data, :map
    #   add :status, :string, default: "pending"
    #   add :error_message, :text
    #   add :sent_at, :utc_datetime
    # end
  end
end
