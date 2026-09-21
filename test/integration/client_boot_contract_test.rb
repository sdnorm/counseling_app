# test/integration/client_boot_contract_test.rb
require "test_helper"

# Boot decides between "unlocked" and "signed out" on every page load. There
# is no JS harness, so pin the decisions statically.
class ClientBootContractTest < ActiveSupport::TestCase
  SYNC = Rails.root.join("app/javascript/controllers/sync_controller.js")
  LAYOUT = Rails.root.join("app/views/layouts/application.html.erb")

  def boot_body
    SYNC.read[/async boot\s*\(\)\s*\{(.+?)\n  \}/m, 1]
  end

  test "a device without a data key is signed out" do
    assert_match(/if \(!this\.key\) return signOut\(\)/, boot_body)
  end

  test "a blob that will not decrypt signs out with the changed reason and never uploads first" do
    body = boot_body
    assert_match(/signOut\(\{ reason: "changed" \}\)/, body)
    assert_no_match(/this\.save\(\)/, body, "boot must not upload local state before deciding")
  end

  test "a network failure still unlocks with local data" do
    rescue_block = boot_body[/catch \(e\) \{(.+?)\n    \}/m, 1]
    assert rescue_block, "expected a catch block in boot"
    assert_match(/this\.markUnlocked\(\)/, rescue_block)
  end

  test "save uploads only ciphertext and nonce" do
    save = SYNC.read[/async save\(\)\s*\{(.+?)\n  \}/m, 1]
    assert_match(/blob: \{ ciphertext, nonce \}/, save)
    assert_no_match(/salt/, save)
  end

  test "the passphrase overlay is gone" do
    assert_no_match(/unlock-overlay|passphrase/i, LAYOUT.read)
    assert_no_match(/passphrase|deriveKey/i, SYNC.read)
  end
end
