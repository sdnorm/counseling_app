class CreateCounselors < ActiveRecord::Migration[8.1]
  def change
    create_table :counselors do |t|
      t.references :practice, null: false, foreign_key: true
      t.string :email_address, null: false
      t.string :password_digest, null: false
      t.string :name, null: false
      t.string :role, null: false, default: "member"
      t.boolean :platform_admin, null: false, default: false
      t.datetime :removed_at
      t.timestamps
    end
    add_index :counselors, :email_address, unique: true
  end
end
