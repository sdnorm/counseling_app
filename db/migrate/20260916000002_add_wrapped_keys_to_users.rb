class AddWrappedKeysToUsers < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :password_wrapped_key, :text, null: false
    add_column :users, :recovery_wrapped_key, :text, null: false
    change_column_null :encrypted_blobs, :salt, true
  end
end
