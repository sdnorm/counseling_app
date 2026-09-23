# app/controllers/dashboard/setups_controller.rb
#
# Where a counselor invite becomes a counselor: the setup link from a
# platform (owner) or member invite lands here.
class Dashboard::SetupsController < Dashboard::BaseController
  allow_unauthenticated_counselor_access
  before_action :set_invite

  def show
  end

  def create
    counselor = @invite.accept!(name: params[:name].to_s, password: params[:password].to_s)
    start_new_counselor_session_for counselor
    redirect_to counselor_root_url(host: counselor.practice.host, protocol: "https"), allow_other_host: true
  rescue ActiveRecord::RecordInvalid => e
    @errors = e.record.errors.full_messages
    render :show, status: :unprocessable_entity
  end

  private

  def set_invite
    @invite = CounselorInvite.find_by(token: params[:token])
    return if @invite&.usable?

    @reason = if @invite.nil? then "This invite link isn't valid."
    elsif @invite.accepted? then "This invite has already been used."
    else "This invite has expired. Ask for a new one."
    end
    render :invalid, status: :not_found
  end

  def brand
    @brand ||= Brand.new(@invite&.practice || Current.practice)
  end
end
