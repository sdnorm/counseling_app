# db/seeds.rb
#
# Idempotent. Run on every deploy that needs it:
#   PLATFORM_ADMIN_EMAIL=you@example.com bin/rails db:seed
#
# 1. The Crossroads practice, exactly as the app looked before practices
#    existed, on its own domain. Finds by slug, so re-running updates rather
#    than duplicates. Never overwrites an icon the owner has since replaced.
crossroads = Practice.find_or_initialize_by(slug: "crossroads")
crossroads.assign_attributes(
  name: "Crossroads Professional Counseling",
  custom_domain: "app.crossroadcounselor.com",
  primary_color: "#32b1c3",
  accent_color: "#f06623",
  website_url: "https://crossroadcounselor.com/",
  booking_url: "https://www.therapyportal.com/p/crossroadspc/",
  phone: "(225) 341-4147",
  appointment_email: "logan@crossroadcounselor.com"
)
crossroads.trial_ends_at ||= 10.years.from_now
unless crossroads.icon.attached?
  crossroads.icon.attach(io: File.open(Rails.root.join("db/seeds/crossroads/icon-512.png")), filename: "icon-512.png", content_type: "image/png")
end
crossroads.save!
if crossroads.resource_links.none?
  crossroads.resource_links.create!([
    { title: "Crossroads Counseling Website", url: "https://crossroadcounselor.com/",
      description: "Learn about Crossroads Counseling and the services available.", position: 1 },
    { title: "Schedule an Appointment", url: "https://www.therapyportal.com/p/crossroadspc/",
      description: "Visit the client portal to schedule a counseling appointment.", position: 2 }
  ])
end

# 2. The operator's own practice and the platform admin. The password is
#    random and never printed; set it through the reset link printed below.
if (email = ENV["PLATFORM_ADMIN_EMAIL"].presence)
  platform = Practice.find_or_create_by!(slug: "platform") do |p|
    p.name = Rails.application.config.x.product_name
    p.trial_ends_at = 100.years.from_now
  end
  unless Counselor.exists?(email_address: email)
    admin = platform.counselors.create!(
      email_address: email, name: "Platform admin", role: "owner", platform_admin: true,
      password: SecureRandom.base58(32)
    )
    url = Rails.application.routes.url_helpers.edit_counselor_password_url(
      admin.password_reset_token, host: Rails.application.config.x.product_host, protocol: "https"
    )
    puts "Platform admin #{email} created. Set a password within 15 minutes at:\n#{url}"
  end
end
