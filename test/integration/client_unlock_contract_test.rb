require "test_helper"

# Unlock decides whether to keep or destroy the data already on the device, and
# it runs on every page load. The two branches are not symmetrical:
#
#   200 — the server has a blob, so it is the source of truth. Replacing an
#         unrecognised device costs at most the unsynced delta.
#   404 — the server has nothing. Clearing here destroys the only copy that
#         exists, with nothing to restore from.
#
# Shipping the 404 branch as "clear unless the stamp matches" wiped every
# journal on any device that predated the account stamp. This test pins the
# asymmetry statically, since there is no JS test harness.
class ClientUnlockContractTest < ActiveSupport::TestCase
  SYNC_CONTROLLER = Rails.root.join("app/javascript/controllers/sync_controller.js")

  def discard_body
    SYNC_CONTROLLER.read[/async discardOtherAccountData\s*\([^)]*\)\s*\{(.+?)\n  \}/m, 1]
  end

  test "the no-blob path never clears an unstamped device" do
    body = discard_body
    assert body, "expected a discardOtherAccountData method in sync_controller.js"

    guard = body[/if \s*\((.+?)\)\s*await clearData\(\)/m, 1]
    assert guard, "expected the no-blob path to guard its clearData() call"

    assert_no_match(/stamp\s*===\s*null/, guard,
      "the no-blob path must not clear on a null stamp: the server has nothing to " \
      "restore from, so this destroys the only copy of a pre-existing user's data")
    assert_match(/stamp\s*!==\s*null/, guard,
      "clearing is only safe when a stamp proves the data belongs to another account")
  end

  test "the no-blob path still clears when the stamp names a different account" do
    guard = discard_body[/if \s*\((.+?)\)\s*await clearData\(\)/m, 1]
    assert_match(/stamp\s*!==\s*account/, guard,
      "a device stamped to another account must still be cleared before this " \
      "account's first sync picks the data up")
  end

  test "unlock stamps the device on both the blob and no-blob paths" do
    source = SYNC_CONTROLLER.read
    %w[applyRemoteState discardOtherAccountData].each do |method|
      body = source[/async #{method}\s*\([^)]*\)\s*\{(.+?)\n  \}/m, 1]
      assert body, "expected #{method} in sync_controller.js"
      assert_match(/writeAccountStamp\(/, body,
        "#{method} must stamp the device, or it stays unrecognised and the " \
        "guard can never distinguish accounts")
    end
  end
end
