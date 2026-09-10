require "test_helper"

class ClientResourcesContractTest < ActiveSupport::TestCase
  SOURCE = Rails.root.join("app/javascript/controllers/resources_controller.js")

  test "curated resources render without an opaque feed request" do
    source = SOURCE.read
    assert_no_match(/\bfetch\s*\(/, source)
    assert_no_match(/no-cors/, source)
    assert_includes source, "https://crossroadcounselor.com/"
    assert_includes source, "https://www.therapyportal.com/p/crossroadspc/"
    assert_match(/const RESOURCES\s*=\s*\[/, source)
    assert_includes source, "RESOURCES.map"
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
