require "test_helper"

class StripeEventTest < ActiveSupport::TestCase
  test "record! is true once and false after" do
    assert StripeEvent.record!("evt_1", "invoice.paid")
    assert_not StripeEvent.record!("evt_1", "invoice.paid")
  end
end
