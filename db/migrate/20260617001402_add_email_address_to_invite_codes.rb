class AddEmailAddressToInviteCodes < ActiveRecord::Migration[8.1]
  def change
    add_column :invite_codes, :email_address, :text
  end
end
