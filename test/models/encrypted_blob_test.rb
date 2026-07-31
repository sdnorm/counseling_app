require "test_helper"

class EncryptedBlobTest < ActiveSupport::TestCase
  def build_blob(**overrides)
    EncryptedBlob.new({
      user: users(:danny),
      ciphertext: "c" * 100,
      nonce: "n" * 16,
      salt: "s" * 24
    }.merge(overrides))
  end

  test "valid with realistic values" do
    assert build_blob.valid?
  end

  test "rejects a ciphertext larger than the maximum" do
    blob = build_blob(ciphertext: "c" * (EncryptedBlob::MAX_CIPHERTEXT_BYTES + 1))
    assert_not blob.valid?
    assert_includes blob.errors[:ciphertext], "is too long (maximum is #{EncryptedBlob::MAX_CIPHERTEXT_BYTES} characters)"
  end

  test "accepts a ciphertext at the maximum" do
    assert build_blob(ciphertext: "c" * EncryptedBlob::MAX_CIPHERTEXT_BYTES).valid?
  end

  test "rejects oversized nonce and salt" do
    assert_not build_blob(nonce: "n" * 200).valid?
    assert_not build_blob(salt: "s" * 200).valid?
  end
end
