class AddTenancyToUsersAndInviteCodes < ActiveRecord::Migration[8.1]
  # Both tables are empty after the one-secret login launch migration, so
  # NOT NULL columns without defaults are safe here.
  def change
    add_reference :users, :counselor, null: false, foreign_key: true
    add_column :users, :archived_at, :datetime
    add_column :users, :last_synced_at, :datetime
    add_reference :invite_codes, :counselor, null: false, foreign_key: true
  end
end
