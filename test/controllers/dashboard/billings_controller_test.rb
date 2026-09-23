# test/controllers/dashboard/billings_controller_test.rb
require "test_helper"

class Dashboard::BillingsControllerTest < ActionDispatch::IntegrationTest
  test "members cannot see billing" do
    sign_in_counselor_as counselors(:jo)
    get counselor_billing_path
    assert_redirected_to counselor_root_path
  end

  test "a practice without a subscription sees the trial offer with both prices" do
    sign_in_counselor_as counselors(:sam)
    get counselor_billing_path
    assert_response :success
    assert_select "form[action=?]", checkout_counselor_billing_path, 2
    assert_match(/\$50/, response.body)
    assert_match(/\$400/, response.body)
    assert_match(/30-day free trial/i, response.body)
  end

  test "checkout redirects to Stripe with the chosen interval" do
    sign_in_counselor_as counselors(:sam)
    captured = nil
    stub_stripe(customer_create: ->(**) { OpenStruct.new(id: "cus_s") },
                checkout_create: ->(params) { captured = params; OpenStruct.new(url: "https://checkout.stripe.com/x") }) do
      post checkout_counselor_billing_path, params: { interval: "year" }
    end
    assert_redirected_to "https://checkout.stripe.com/x"
    assert_equal Rails.application.config.x.stripe.yearly_price_id, captured[:line_items].first[:price]
    assert_match %r{https://riverbend\.example\.com/counselor/billing}, captured[:success_url]
  end

  test "an active practice sees plan, seats, renewal, and the portal" do
    practices(:lakeside).update!(current_period_end: 10.days.from_now)
    sign_in_counselor_as counselors(:lee)
    get counselor_billing_path
    assert_match(/Monthly/, response.body)
    assert_match(/1 seat/, response.body)
    assert_select "form[action=?]", portal_counselor_billing_path

    stub_stripe(portal_create: ->(**) { OpenStruct.new(url: "https://billing.stripe.com/p") }) do
      post portal_counselor_billing_path
    end
    assert_redirected_to "https://billing.stripe.com/p"
  end

  test "a complimentary practice sees no checkout or portal" do
    sign_in_counselor_as counselors(:logan)
    get counselor_billing_path
    assert_match(/Complimentary/, response.body)
    assert_select "form[action=?]", checkout_counselor_billing_path, 0
  end

  test "a canceled practice sees restart and no trial" do
    practices(:lakeside).update!(billing_status: "canceled")
    sign_in_counselor_as counselors(:lee)
    get counselor_billing_path
    assert_match(/Restart/, response.body)
    assert_no_match(/free trial/i, response.body)
  end
end
