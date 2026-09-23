# app/controllers/dashboard/members_controller.rb
class Dashboard::MembersController < Dashboard::BaseController
  before_action :require_owner

  def index
    load_index
  end

  def create
    invite = current_counselor.practice.counselor_invites.new(
      email_address: params.dig(:member, :email_address), role: "member", invited_by: current_counselor
    )
    if invite.save
      CounselorInvitesMailer.invite(invite).deliver_later
      redirect_to counselor_members_path, notice: "Invite sent to #{invite.email_address}."
    else
      load_index
      flash.now[:alert] = invite.errors.full_messages.to_sentence
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    member = current_counselor.practice.counselors.find(params[:id])
    if member == current_counselor
      return redirect_to counselor_members_path, alert: "You can't remove yourself."
    end
    member.remove!
    redirect_to counselor_members_path, notice: "#{member.name} removed."
  end

  private

  def load_index
    @members = current_counselor.practice.counselors.order(:name)
    @pending = current_counselor.practice.counselor_invites.pending.order(:created_at)
  end
end
