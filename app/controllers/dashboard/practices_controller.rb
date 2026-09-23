# app/controllers/dashboard/practices_controller.rb
class Dashboard::PracticesController < Dashboard::BaseController
  before_action :require_owner
  before_action :set_practice

  def edit
  end

  def update
    if @practice.update(practice_params)
      redirect_to edit_counselor_practice_path, notice: "Practice saved."
    else
      # Rejected uploads have no signed URL. Show the saved attachments while
      # keeping the validation errors and submitted text fields on the form.
      @practice.attachment_changes.clear
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_practice
    @practice = current_counselor.practice
  end

  # custom_domain is deliberately absent: only a platform admin sets it, since
  # each one needs DNS and a Hatchbox entry.
  def practice_params
    params.require(:practice).permit(
      :name, :slug, :primary_color, :accent_color, :logo, :icon,
      :website_url, :booking_url, :phone, :appointment_email,
      resource_links_attributes: [ :id, :title, :url, :description, :position, :_destroy ]
    )
  end
end
