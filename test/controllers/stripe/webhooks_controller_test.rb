require "test_helper"

class Stripe::WebhooksControllerTest < ActionDispatch::IntegrationTest
  # OpenStruct#to_h is shallow: nested structs leak and serialize as their
  # @table. Deep-convert so the JSON looks like a real Stripe event payload.
  def deep_to_h(obj)
    case obj
    when OpenStruct then obj.to_h.transform_values { |v| deep_to_h(v) }
    when Array then obj.map { |v| deep_to_h(v) }
    else obj
    end
  end

  def post_event(type, data, id: "evt_#{SecureRandom.hex(4)}")
    payload = { id: id, type: type, data: { object: data } }.to_json
    post stripe_webhooks_path, params: payload, headers: { "Content-Type" => "application/json", "Stripe-Signature" => stripe_signature(payload) }
  end

  test "rejects a bad signature" do
    payload = { id: "evt_x", type: "invoice.paid", data: { object: {} } }.to_json
    post stripe_webhooks_path, params: payload, headers: { "Content-Type" => "application/json", "Stripe-Signature" => "t=1,v1=bad" }
    assert_response :bad_request
  end

  test "checkout completed links the subscription to the practice" do
    p = practices(:riverbend)
    stub_stripe(subscription_retrieve: ->(_id) { fake_subscription(id: "sub_new", status: "trialing") }) do
      post_event("checkout.session.completed", { client_reference_id: p.id.to_s, subscription: "sub_new", customer: "cus_r" })
    end
    assert_response :success
    p.reload
    assert_equal "sub_new", p.stripe_subscription_id
    assert_equal "trialing", p.billing_status
  end

  test "subscription updated and deleted mirror status" do
    p = practices(:lakeside)
    post_event("customer.subscription.updated", deep_to_h(fake_subscription(id: "sub_lakeside", status: "past_due")).merge(metadata: { practice_id: p.id.to_s }).deep_stringify_keys)
    assert_equal "past_due", p.reload.billing_status
    post_event("customer.subscription.deleted", deep_to_h(fake_subscription(id: "sub_lakeside", status: "canceled", trial_end: nil)).deep_stringify_keys)
    assert_equal "canceled", p.reload.billing_status
  end

  test "invoice paid records the first payment and evaluates referrals" do
    referrer = practices(:lakeside)
    p = Practice.create!(name: "P", referrer: referrer, stripe_customer_id: "cus_p")
    Practice.create!(name: "Q", referrer: referrer, first_paid_at: 1.day.ago)
    credits = []
    stub_stripe(balance_transaction: ->(cus, **params) { credits << cus }) do
      post_event("invoice.paid", { customer: "cus_p", subscription: nil })
    end
    assert p.reload.first_paid_at
    assert_equal [ "cus_lakeside" ], credits
  end

  test "payment failed marks past due" do
    post_event("invoice.payment_failed", { customer: "cus_lakeside" })
    assert_equal "past_due", practices(:lakeside).reload.billing_status
  end

  test "duplicate events are acknowledged and ignored" do
    p = practices(:lakeside)
    post_event("invoice.payment_failed", { customer: "cus_lakeside" }, id: "evt_dup")
    # reload first: p still holds the fixture's in-memory "active", so a bare
    # update! would see nothing to change and never write.
    p.reload.update!(billing_status: "active")
    post_event("invoice.payment_failed", { customer: "cus_lakeside" }, id: "evt_dup")
    assert_response :success
    assert_equal "active", p.reload.billing_status
  end

  test "unknown events and unknown customers are 200" do
    post_event("charge.refunded", { customer: "cus_nobody" })
    assert_response :success
    post_event("invoice.paid", { customer: "cus_nobody" })
    assert_response :success
  end
end
