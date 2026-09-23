class Platform::PracticeInvitesController < Platform::BaseController
  def new
    @invite = CounselorInvite.new(role: "owner", practice_id: params[:practice_id])
    @practices = Practice.order(:name)
  end

  # Either a brand new practice (practice_name) or an owner for one that
  # already exists (practice_id, used for the seeded Crossroads practice).
  # Redirects rather than rendering: Turbo ignores a 200 to a form post.
  def create
    attrs = params.require(:practice_invite).permit(:email_address, :practice_name, :practice_id, :referred_by_practice_id)
    @invite = CounselorInvite.new(attrs.merge(role: "owner", invited_by: current_counselor))
    if @invite.save
      CounselorInvitesMailer.invite(@invite).deliver_later
      redirect_to platform_practice_invite_path(@invite), notice: "Invite sent to #{@invite.email_address}."
    else
      @practices = Practice.order(:name)
      render :new, status: :unprocessable_entity
    end
  end

  def show
    @invite = CounselorInvite.find(params[:id])
    @setup_url = counselor_setup_url(@invite.token, host: Brand.new(@invite.practice).host, protocol: "https", port: nil)
  end
end
