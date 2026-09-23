ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "minitest/mock"

# What the browser sends as the "password": a 43-char base64url auth hash.
AUTH_HASH = "a" * 43
NEW_AUTH_HASH = "b" * 43
WRAPPED_KEY = '{"nonce":"bm9uY2U=","ciphertext":"Y2lwaGVy"}'
COUNSELOR_PASSWORD = "counselor-secret-123"

# A real PNG for logo and icon uploads, made on the fly so no binary fixture
# is committed. Available in model and integration tests alike.
module ImageFixtures
  def png_upload(width, height = width, name: "icon.png")
    data = Vips::Image.black(width, height, bands: 3).write_to_buffer(".png")
    Rack::Test::UploadedFile.new(StringIO.new(data), "image/png", original_filename: name)
  end
end

module WebPushTestHelpers
  FakeResponse = Struct.new(:code, :message, :body)

  # Builds a real WebPush error (e.g. WebPush::ExpiredSubscription) the way the
  # gem raises it: initialized with an HTTP-response-shaped object and a host.
  def web_push_error(klass, code, message)
    klass.new(FakeResponse.new(code, message, ""), "push.example.com")
  end
end

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all

    include WebPushTestHelpers
    include ImageFixtures
  end
end

class ActionDispatch::IntegrationTest
  def sign_in_as(user, password: AUTH_HASH)
    post session_path, params: { email_address: user.email_address, password: password }
  end

  def sign_in_counselor_as(counselor, password: COUNSELOR_PASSWORD)
    post counselor_session_path, params: { email_address: counselor.email_address, password: password }
  end
end
