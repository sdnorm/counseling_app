require "test_helper"

# Pin client-side behavior statically until a JS test harness is available.
class ClientJournalContractTest < ActiveSupport::TestCase
  SOURCE = Rails.root.join("app/javascript/controllers/journal_controller.js")

  test "every nonempty bullet line gets its own prefix including the first" do
    source = SOURCE.read
    assert_no_match(/\.join\("\\n• "\)/, source)
    assert_match(/\.filter\(Boolean\)\.map\(line => `• \$\{line\}`\)\.join\("\\n"\)/, source)
  end

  test "entries display their escaped prompt unless it is free write" do
    body = SOURCE.read[/async loadEntries\(\)\s*\{(.+?)\n  \}/m, 1]
    assert body
    assert_includes body, 'e.prompt && e.prompt !== "Free write"'
    assert_includes body, "escapeHtml(e.prompt)"
  end

  test "long entries have escaped full text and a reversible Stimulus toggle" do
    source = SOURCE.read
    assert_includes source, 'e.content.length > 200'
    assert_includes source, 'escapeHtml(e.content)'
    assert_includes source, 'data-entry-full hidden'
    assert_includes source, 'data-action="click->journal#toggleEntry"'
    assert_includes source, 'card.querySelector("[data-entry-preview]").hidden = expanded'
    assert_includes source, 'card.querySelector("[data-entry-full]").hidden = !expanded'
    assert_includes source, 'button.setAttribute("aria-expanded", String(expanded))'
    assert_includes source, 'button.textContent = expanded ? "Show less" : "Read more"'
    assert_no_match(/onclick\s*=/i, source)
  end
end
