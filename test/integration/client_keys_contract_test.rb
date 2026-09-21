# test/integration/client_keys_contract_test.rb
require "test_helper"

# The one-secret model rests on properties of the browser code that no server
# test can observe. There is no JS harness, so pin them statically.
class ClientKeysContractTest < ActiveSupport::TestCase
  KEYS = Rails.root.join("vendor/javascript/lib/keys.js")
  AUTH_CONTROLLERS = %w[signup login password_reset].map do |name|
    Rails.root.join("app/javascript/controllers/#{name}_controller.js")
  end

  test "PBKDF2 uses at least 600000 rounds" do
    src = KEYS.read
    rounds = src[/PBKDF2_ROUNDS\s*=\s*(\d+)/, 1].to_i
    assert_operator rounds, :>=, 600_000
    assert_match(/iterations:\s*PBKDF2_ROUNDS/, src, "the stretch must use the exported constant")
  end

  test "the data key kept on the device is never extractable" do
    src = KEYS.read
    lock = src[/async function lockDataKey[^{]*\{(.+?)\n\}/m, 1]
    assert lock, "expected a lockDataKey function"
    assert_match(/importKey\("raw", raw, AES, false/, lock, "lockDataKey must import as non-extractable")
    assert_match(/extractable = false/, src, "unwrapDataKey must default to non-extractable")
  end

  test "auth controllers send the derived auth hash, never the password field" do
    AUTH_CONTROLLERS.each do |path|
      src = path.read
      assert_match(/password: authHash/, src, "#{path.basename} must send the auth hash as password")
      assert_no_match(/password:\s*(this\.)?password(Target)?(\.value)?\b(?!Hash)/, src,
        "#{path.basename} must never put the raw password in a request body")
    end
  end
end
