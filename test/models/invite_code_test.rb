require "test_helper"

class InviteCodeTest < ActiveSupport::TestCase
  test "claim marks an unused code as used and returns it" do
    code = InviteCode.generate("new@example.com")

    claimed = InviteCode.claim(code.code)

    assert_equal code, claimed
    assert claimed.used?
  end

  test "claim returns nil for a code that is already used" do
    code = InviteCode.generate("new@example.com")
    InviteCode.claim(code.code)

    assert_nil InviteCode.claim(code.code), "a code must only be claimable once"
  end

  test "claim returns nil for an unknown or blank code" do
    assert_nil InviteCode.claim("NOPE1234")
    assert_nil InviteCode.claim("")
    assert_nil InviteCode.claim(nil)
  end

  test "only one of two concurrent claims of the same code succeeds" do
    code = InviteCode.generate("new@example.com")

    results = [ InviteCode.claim(code.code), InviteCode.claim(code.code) ]

    assert_equal 1, results.compact.size,
      "the same invite code must not be claimable twice"
  end
end
