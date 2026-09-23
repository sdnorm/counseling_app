# app/controllers/dashboard/billings_controller.rb
class Dashboard::BillingsController < Dashboard::BaseController
  before_action :require_owner
  skip_before_action :require_billing_open

  def show
    @practice = current_counselor.practice
    @referrals = @practice.referred_practices.order(:created_at)
  end

  def checkout
    interval = params[:interval] == "year" ? "year" : "month"
    session = current_counselor.practice.checkout_session(
      interval: interval,
      success_url: counselor_billing_url(host: current_counselor.practice.host, protocol: "https", port: nil, started: 1),
      cancel_url: counselor_billing_url(host: current_counselor.practice.host, protocol: "https", port: nil)
    )
    redirect_to session.url, allow_other_host: true
  end

  def portal
    session = current_counselor.practice.portal_session(return_url: counselor_billing_url(host: current_counselor.practice.host, protocol: "https", port: nil))
    redirect_to session.url, allow_other_host: true
  end
end
