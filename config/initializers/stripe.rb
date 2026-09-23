Stripe.api_key = Rails.application.credentials.dig(:stripe, :secret_key) || ENV["STRIPE_SECRET_KEY"]
Stripe.api_version = "2026-05-27.dahlia"

Rails.application.configure do
  config.x.stripe.monthly_price_id = Rails.application.credentials.dig(:stripe, :monthly_price_id) || ENV["STRIPE_MONTHLY_PRICE_ID"] || "price_monthly_test"
  config.x.stripe.yearly_price_id  = Rails.application.credentials.dig(:stripe, :yearly_price_id)  || ENV["STRIPE_YEARLY_PRICE_ID"]  || "price_yearly_test"
  config.x.stripe.webhook_secret   = Rails.application.credentials.dig(:stripe, :webhook_secret)   || ENV["STRIPE_WEBHOOK_SECRET"]   || "whsec_test"
end
