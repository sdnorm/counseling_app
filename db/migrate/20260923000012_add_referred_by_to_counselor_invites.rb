class AddReferredByToCounselorInvites < ActiveRecord::Migration[8.1]
  def change
    add_reference :counselor_invites, :referred_by_practice, foreign_key: { to_table: :practices }
  end
end
