require "test_helper"

# The Resources screen renders the counselor's links from the JSON blob the
# layout embeds; nothing is fetched and nothing is hardcoded. Pinned
# statically since there is no JS harness.
class ClientResourcesContractTest < ActiveSupport::TestCase
  SOURCE = Rails.root.join("app/javascript/controllers/resources_controller.js")

  test "resources come from the embedded practice content, never a request" do
    source = SOURCE.read
    assert_no_match(/\bfetch\s*\(/, source)
    assert_no_match(/no-cors/, source)
    assert_includes source, "practice-content"
    assert_match(/GENERIC_RESOURCES/, source, "an empty practice must still render something")
  end

  test "resource cards include safe new-tab links and descriptions" do
    source = SOURCE.read
    assert_includes source, 'class="card"'
    assert_includes source, 'target="_blank" rel="noopener"'
    %w[title url description].each do |field|
      assert_includes source, "escapeHtml(resource.#{field})"
    end
    assert_includes Rails.root.join("app/views/screens/resources.html.erb").read,
      "Helpful articles and tools."
  end
end
