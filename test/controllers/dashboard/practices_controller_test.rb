# test/controllers/dashboard/practices_controller_test.rb
require "test_helper"

class Dashboard::PracticesControllerTest < ActionDispatch::IntegrationTest
  test "members cannot open practice settings" do
    sign_in_counselor_as counselors(:jo)
    get edit_counselor_practice_path
    assert_redirected_to counselor_root_path
  end

  test "owner updates brand, profile, and resource links" do
    sign_in_counselor_as counselors(:sam)
    patch counselor_practice_path, params: { practice: {
      name: "Riverbend Therapy", slug: "riverbend", primary_color: "#112233", accent_color: "#445566",
      website_url: "https://riverbend.example", booking_url: "https://book.example", phone: "555-0100", appointment_email: "hi@riverbend.example",
      resource_links_attributes: { "0" => { title: "Site", url: "https://riverbend.example", description: "About us", position: 1 } }
    } }
    assert_redirected_to edit_counselor_practice_path
    practice = practices(:riverbend).reload
    assert_equal "#112233", practice.primary_color
    assert_equal "Site", practice.resource_links.first.title
  end

  test "icon upload is validated and stored" do
    sign_in_counselor_as counselors(:sam)
    patch counselor_practice_path, params: { practice: { icon: png_upload(300, 200) } }
    assert_response :unprocessable_entity
    assert_match(/must be square/, response.body)

    patch counselor_practice_path, params: { practice: { icon: png_upload(512) } }
    assert_redirected_to edit_counselor_practice_path
    assert practices(:riverbend).reload.icon.attached?
  end

  test "changing the slug is refused when taken" do
    sign_in_counselor_as counselors(:sam)
    patch counselor_practice_path, params: { practice: { slug: "crossroads" } }
    assert_response :unprocessable_entity
  end

  test "the edit page shows the practice's web address" do
    sign_in_counselor_as counselors(:sam)
    get edit_counselor_practice_path
    assert_select "code", "riverbend.example.com"
  end
end
