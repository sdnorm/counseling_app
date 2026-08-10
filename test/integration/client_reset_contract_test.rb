require "test_helper"

# Passphrase reset has two branches with opposite stakes:
#
#   re-key    — the device holds the data; reset must keep it (encrypt under
#               the new passphrase) and must never clear anything.
#   start-over — the device holds nothing; reset wipes the server backup, so
#               the local discard may only run after the server said yes.
#
# Pinned statically because there is no JS test harness.
class ClientResetContractTest < ActiveSupport::TestCase
  SYNC_CONTROLLER = Rails.root.join("app/javascript/controllers/sync_controller.js")

  def source
    @source ||= SYNC_CONTROLLER.read
  end

  def method_body(name)
    source[/async #{name}\s*\([^)]*\)\s*\{(.+?)\n  \}/m, 1]
  end

  test "the branch choice comes from comparing the device stamp to the account" do
    body = method_body("openResetPanel")
    assert body, "expected an openResetPanel method in sync_controller.js"
    assert_match(/stamp\s*!==\s*null\s*&&\s*stamp\s*===\s*this\.resetAccount/, body,
      "re-keying is only safe when a stamp proves the local data belongs to " \
      "the account being reset")
  end

  test "the panel never opens without a definite account" do
    body = method_body("openResetPanel")
    assert_match(/!response\.ok\s*&&\s*response\.status\s*!==\s*404/, body,
      "a 5xx or unexpected response must not open the panel: an undefined " \
      "account turns the lossless re-key path into a both-copies wipe")
    assert_match(/this\.resetAccount\s*===\s*undefined/, body,
      "an unparseable response body must be rejected, not treated as a fresh device")
  end

  test "the re-key branch encrypts local state and never clears it" do
    body = method_body("performReset")
    assert body, "expected a performReset method in sync_controller.js"

    keep = body[/if\s*\(this\.resetKeepsData\)\s*\{(.*?)\n      \}/m, 1]
    assert keep, "expected a resetKeepsData branch that builds the new blob"
    assert_match(/exportState/, keep, "re-key must upload the state the device already holds")
    assert_no_match(/clearData|discardOtherAccountData|importState/, keep,
      "the re-key branch must not touch local data — it is the only copy")
  end

  test "submit re-verifies the account and branch before posting" do
    body = method_body("performReset")
    recheck_at = body.index("/api/sync\"")
    post_at = body.index("/api/sync/reset")
    assert recheck_at, "expected a pre-flight GET of /api/sync inside performReset"
    assert post_at, "expected the reset POST inside performReset"
    assert recheck_at < post_at,
      "the panel can sit open while the session changes: submit must re-verify " \
      "the account before anything is uploaded or wiped"
    assert_match(/account\s*!==\s*this\.resetAccount/, body,
      "a session that changed accounts must abort the reset")
    assert_match(/keeps\s*!==\s*this\.resetKeepsData/, body,
      "a keep/wipe decision that flipped must abort so the warning matches the path")
  end

  test "the start-over branch discards local data only after the server accepted" do
    body = method_body("performReset")
    discard_at = body.index("discardOtherAccountData")
    ok_check_at = body.index("!response.ok")
    assert discard_at, "expected the start-over branch to run the first-time discard"
    assert ok_check_at, "expected reset to bail out on a non-ok response"
    assert ok_check_at < discard_at,
      "local data must never be discarded before the server confirmed the reset: " \
      "a failed reset must leave the device exactly as it was"
  end

  test "reset uploads only ciphertext" do
    body = method_body("performReset")
    assert_match(/blob\s*=\s*\{\s*ciphertext,\s*nonce,\s*salt:/, body,
      "the reset payload must be the encrypted blob shape — plaintext state " \
      "must never be posted")
    assert_no_match(/body\.state|plaintext/, body,
      "no unencrypted state may appear in the reset request body")
  end
end
