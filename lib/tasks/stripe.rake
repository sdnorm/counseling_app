namespace :stripe do
  desc "Create the product and the two tiered prices; prints the IDs for credentials"
  task setup: :environment do
    product = Stripe::Product.create(name: Rails.application.config.x.product_name)
    tiers = ->(solo, group) { [ { up_to: 2, unit_amount: solo }, { up_to: "inf", unit_amount: group } ] }
    monthly = Stripe::Price.create(product: product.id, currency: "usd", recurring: { interval: "month" },
      billing_scheme: "tiered", tiers_mode: "volume", tax_behavior: "exclusive", tiers: tiers.call(5000, 4000))
    yearly = Stripe::Price.create(product: product.id, currency: "usd", recurring: { interval: "year" },
      billing_scheme: "tiered", tiers_mode: "volume", tax_behavior: "exclusive", tiers: tiers.call(40000, 32000))
    puts "stripe:\n  monthly_price_id: #{monthly.id}\n  yearly_price_id: #{yearly.id}"
  end
end
