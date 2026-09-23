class CreateCounselorInvites < ActiveRecord::Migration[8.1]
  def change
    create_table :counselor_invites do |t|
      t.string :token, null: false
      t.string :email_address, null: false
      t.string :role, null: false, default: "member"
      t.references :practice, foreign_key: true
      t.string :practice_name
      t.references :invited_by, foreign_key: { to_table: :counselors }
      t.datetime :accepted_at
      t.datetime :expires_at, null: false
      t.timestamps
    end
    add_index :counselor_invites, :token, unique: true
  end
end
