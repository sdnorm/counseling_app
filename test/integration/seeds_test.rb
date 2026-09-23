# test/integration/seeds_test.rb
require "test_helper"

class SeedsTest < ActiveSupport::TestCase
  test "seeds are idempotent and recreate Crossroads exactly" do
    ENV["PLATFORM_ADMIN_EMAIL"] = "ops@example.com"
    2.times { Rails.application.load_seed }

    crossroads = Practice.find_by!(slug: "crossroads")
    assert_equal "app.crossroadcounselor.com", crossroads.custom_domain
    assert_equal "#32b1c3", crossroads.primary_color
    assert crossroads.icon.attached?
    assert_equal 2, crossroads.resource_links.count
    assert_equal "https://www.therapyportal.com/p/crossroadspc/", crossroads.booking_url

    platform = Practice.find_by!(slug: "platform")
    admin = Counselor.find_by!(email_address: "ops@example.com")
    assert admin.platform_admin?
    assert_equal platform, admin.practice
    assert_equal 1, Counselor.where(email_address: "ops@example.com").count, "re-running seeds must not duplicate the admin"
  ensure
    ENV.delete("PLATFORM_ADMIN_EMAIL")
  end
end
