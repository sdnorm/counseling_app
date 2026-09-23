# app/controllers/dashboard/clients_controller.rb
class Dashboard::ClientsController < Dashboard::BaseController
  before_action :set_client, only: %i[ archive unarchive ]

  # Only this counselor's clients, ever. The practice-wide number is a count,
  # never a list: the owner sees how many, not who.
  def index
    clients = current_counselor.clients.order(created_at: :desc)
    @active = clients.unarchived
    @archived = clients.archived
    @practice = current_counselor.practice
  end

  def archive
    @client.archive!
    redirect_to counselor_root_path, notice: "Archived. They keep full access to the app."
  end

  def unarchive
    @client.unarchive!
    redirect_to counselor_root_path, notice: "Reactivated."
  end

  private

  def set_client
    @client = current_counselor.clients.find(params[:id])
  end
end
