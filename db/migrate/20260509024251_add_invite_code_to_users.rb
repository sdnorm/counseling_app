class AddInviteCodeToUsers < ActiveRecord::Migration[8.1]
  def change
    add_reference :users, :invite_code, null: false, foreign_key: true
  end
end
