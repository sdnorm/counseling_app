# The product's own host and name. Practices live at <slug>.<product_host>
# unless they have a custom domain; the bare product host wears the generic
# brand. Test uses example.com so integration tests can hit
# crossroads.example.com; development uses lvh.me, which resolves every
# subdomain to 127.0.0.1 without DNS setup.
Rails.application.configure do
  config.x.product_host = ENV.fetch("PRODUCT_HOST") { Rails.env.test? ? "example.com" : "lvh.me" }
  config.x.product_name = ENV.fetch("PRODUCT_NAME", "Counseling App")
end
