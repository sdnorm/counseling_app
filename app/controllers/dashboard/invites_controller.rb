# app/controllers/dashboard/invites_controller.rb
class Dashboard::InvitesController < Dashboard::BaseController
  def index
    load_index
  end

  # The one place the client limit is enforced. Nothing else ever blocks a
  # client; a practice over its limit simply cannot add more until people go
  # quiet or a seat is added.
  def create
    practice = current_counselor.practice
    if practice.at_client_limit?
      load_index
      flash.now[:alert] = "Your practice has #{practice.active_client_count} active clients this month, which is your limit. " \
                          "Wait for clients to go quiet or add a counselor seat."
      return render :index, status: :unprocessable_entity
    end

    code = InviteCode.generate(invite_params[:email_address].presence, counselor: current_counselor)
    InvitesMailer.invite(code).deliver_later if code.email_address.present?
    redirect_to counselor_invites_path(highlight: code.id), notice: "Invite created. Share the link or code with your client."
  end

  private

  def load_index
    @codes = current_counselor.invite_codes.includes(:user).order(created_at: :desc)
    @highlight = @codes.find_by(id: params[:highlight])
    @practice = current_counselor.practice
  end

  def invite_params
    params.fetch(:invite, {}).permit(:email_address)
  end

  helper_method def signup_link(code)
    new_user_url(code: code.code, host: current_counselor.practice.host, protocol: "https")
  end
end
