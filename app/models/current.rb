class Current < ActiveSupport::CurrentAttributes
  attribute :session
  attribute :counselor_session
  attribute :practice
  delegate :user, to: :session, allow_nil: true
  delegate :counselor, to: :counselor_session, allow_nil: true
end
