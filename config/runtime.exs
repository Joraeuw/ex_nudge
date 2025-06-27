import Config

if config_env() == :prod do
  config :ex_nudge,
    vapid_subject: System.get_env("VAPID_SUBJECT") || raise("VAPID_SUBJECT not set"),
    vapid_public_key: System.get_env("VAPID_PUBLIC_KEY") || raise("VAPID_PUBLIC_KEY not set"),
    vapid_private_key: System.get_env("VAPID_PRIVATE_KEY") || raise("VAPID_PRIVATE_KEY not set")
end
