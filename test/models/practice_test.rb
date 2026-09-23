require "test_helper"

class PracticeTest < ActiveSupport::TestCase
  test "slug derives from the name and stays unique" do
    a = Practice.create!(name: "Calm Waters Counseling")
    b = Practice.create!(name: "Calm Waters Counseling")
    assert_equal "calm-waters-counseling", a.slug
    assert_equal "calm-waters-counseling-2", b.slug
  end

  test "slug format is enforced" do
    practice = practices(:riverbend)
    practice.slug = "Not Valid!"
    assert_not practice.valid?
  end

  test "host prefers the custom domain" do
    assert_equal "app.crossroadcounselor.com", practices(:crossroads).host
    assert_equal "riverbend.example.com", practices(:riverbend).host
  end

  test "for_host resolves custom domains, slugs, and nothing else" do
    assert_equal practices(:crossroads), Practice.for_host("app.crossroadcounselor.com")
    assert_equal practices(:crossroads), Practice.for_host("APP.CROSSROADCOUNSELOR.COM")
    assert_equal practices(:riverbend), Practice.for_host("riverbend.example.com")
    assert_nil Practice.for_host("example.com")
    assert_nil Practice.for_host("nobody.example.com")
    assert_nil Practice.for_host("deep.riverbend.example.com")
  end

  test "colors must be hex" do
    practice = practices(:riverbend)
    practice.primary_color = "blue"
    assert_not practice.valid?
    practice.primary_color = "#ABCDEF"
    assert practice.valid?
    assert_equal "#abcdef", practice.primary_color
  end

  test "active client count is usage based and pooled across counselors" do
    practice = practices(:crossroads)
    users(:danny).update_columns(last_synced_at: 2.days.ago, created_at: 90.days.ago)
    users(:maria).update_columns(last_synced_at: nil, created_at: 90.days.ago)
    assert_equal 1, practice.active_client_count

    users(:maria).update_columns(created_at: 3.days.ago)
    assert_equal 2, practice.active_client_count, "a newly invited client counts before their first sync"

    users(:danny).archive!
    assert_equal 2, practice.active_client_count, "archiving must not change the count"
  end

  test "client limit multiplies by active counselors" do
    practice = practices(:crossroads)
    assert_equal 60, practice.client_limit
    counselors(:jo).remove!
    assert_equal 30, practice.client_limit
    assert_not practice.at_client_limit?
    practice.update!(client_limit_per_counselor: 1)
    users(:danny).update_columns(last_synced_at: 1.hour.ago)
    assert practice.at_client_limit?
  end

  test "icon must be a square PNG of at least 512 pixels" do
    practice = practices(:riverbend)
    practice.icon = png_upload(300, 200)
    assert_not practice.valid?
    assert_includes practice.errors[:icon], "must be square"

    practice.icon = png_upload(256)
    assert_not practice.valid?
    assert_includes practice.errors[:icon], "must be at least 512 pixels"

    practice.icon = png_upload(512)
    assert practice.valid?, practice.errors.full_messages.to_sentence
  end

  test "resource links are ordered and removable through nested attributes" do
    practice = practices(:riverbend)
    practice.update!(resource_links_attributes: [
      { title: "Second", url: "https://b.example", position: 2 },
      { title: "First", url: "https://a.example", position: 1 },
      { title: "", url: "", description: "", position: 0 }
    ])
    assert_equal %w[First Second], practice.resource_links.map(&:title)
    first = practice.resource_links.first
    practice.update!(resource_links_attributes: [ { id: first.id, _destroy: "1" } ])
    assert_equal %w[Second], practice.reload.resource_links.map(&:title)
  end
end
