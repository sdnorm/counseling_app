require "test_helper"

class BrandTest < ActiveSupport::TestCase
  test "generic brand uses product config" do
    brand = Brand.generic
    assert brand.generic?
    assert_equal "Counseling App", brand.name
    assert_equal "example.com", brand.host
    assert_equal Brand::DEFAULT_PRIMARY, brand.primary_color
    assert_nil brand.logo
    assert_nil brand.icon_variant(192)
    assert_equal [], brand.resources
    assert_equal({}, brand.schedule)
  end

  test "practice brand falls back per field" do
    practice = practices(:riverbend)
    practice.update!(accent_color: "#112233", booking_url: "https://book.example")
    brand = Brand.new(practice)
    assert_equal "Riverbend Therapy", brand.name
    assert_equal Brand::DEFAULT_PRIMARY, brand.primary_color
    assert_equal "#112233", brand.accent_color
    assert brand.custom_colors?
    assert_equal({ booking_url: "https://book.example" }, brand.schedule)
    assert_equal "Journal · Riverbend Therapy", brand.title("Journal")
  end

  test "icon variants exist only with an attached icon" do
    practice = practices(:riverbend)
    practice.icon.attach(png_upload(512))
    practice.save!
    assert Brand.new(practice).icon_variant(512)
    assert_raises(ArgumentError) { Brand.new(practice).icon_variant(64) }
  end

  test "practice content json carries resources and schedule" do
    practice = practices(:crossroads)
    practice.resource_links.create!(title: "Site", url: "https://crossroadcounselor.com/", description: "About")
    json = JSON.parse(Brand.new(practice).practice_content_json)
    assert_equal "Site", json["resources"].first["title"]
    assert_equal "(225) 341-4147", json["schedule"]["phone"]
  end
end
