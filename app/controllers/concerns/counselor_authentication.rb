# app/controllers/concerns/counselor_authentication.rb
#
# Counselor login, kept apart from the client Authentication concern: a
# separate cookie and session table so one browser can hold both a client
# and a counselor login without either leaking into the other.
module CounselorAuthentication
  extend ActiveSupport::Concern

  included do
    before_action :require_counselor
    helper_method :current_counselor, :counselor_signed_in?
  end

  class_methods do
    def allow_unauthenticated_counselor_access(**options)
      skip_before_action :require_counselor, **options
    end
  end

  private
    def counselor_signed_in?
      resume_counselor_session.present?
    end

    def current_counselor
      Current.counselor
    end

    def require_counselor
      resume_counselor_session || redirect_to(new_counselor_session_path)
    end

    def require_owner
      return if current_counselor.owner?
      redirect_to counselor_root_path, alert: "Only the practice owner can do that."
    end

    def resume_counselor_session
      Current.counselor_session ||= find_counselor_session_by_cookie
    end

    # A removed counselor's sessions are destroyed by remove!, but check
    # anyway so a race can't keep them logged in.
    def find_counselor_session_by_cookie
      id = cookies.signed[:counselor_session_id]
      return unless id
      session = CounselorSession.active.find_by(id: id)
      session if session && !session.counselor.removed?
    end

    def start_new_counselor_session_for(counselor)
      counselor.sessions.create!(user_agent: request.user_agent, ip_address: request.remote_ip).tap do |session|
        Current.counselor_session = session
        cookies.signed.permanent[:counselor_session_id] = { value: session.id, httponly: true, same_site: :lax }
      end
    end

    def terminate_counselor_session
      Current.counselor_session&.destroy
      cookies.delete(:counselor_session_id)
    end
end
