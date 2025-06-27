import Config

if Mix.env() == :dev do
  config :ex_nudge,
    vapid_subject: "mailto:dev@yourapp.com",
    vapid_public_key:
      "BGXqlzfDzajG-wFpzsp0dk5mwn_lwZfaeo2tzAbWHn4yJpFktuq-OIIVY_F0kQYJrBzx2VOBGKAiK03qYUeBkho",
    vapid_private_key: "4JakvSlrE8VG1Ft6C5SiEwz45lCI2dY36JoNM0ok27Q"
end
