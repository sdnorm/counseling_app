# app/controllers/platform/practice_invites_controller.rb
class Platform::PracticeInvitesController < Platform::BaseController
  def new
    @invite = CounselorInvite.new(role: "owner", practice_id: params[:practice_id])
    @practices = Practice.order(:name)
  end

  # Either a brand new practice (practice_name) or an owner for one that
  # already exists (practice_id, used for the seeded Crossroads practice).
  def create
    attrs = params.require(:practice_invite).permit(:email_address, :practice_name, :practice_id)
    @invite = CounselorInvite.new(attrs.merge(role: "owner", invited_by: current_counselor))
    if @invite.save
      CounselorInvitesMailer.invite(@invite).deliver_later
      @setup_url = counselor_setup_url(@invite.token, host: Brand.new(@invite.practice).host, protocol: "https")
      render :show
    else
      @practices = Practice.order(:name)
      render :new, status: :unprocessable_entity
    end
  end
end
