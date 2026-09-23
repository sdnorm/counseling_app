class CreatePractices < ActiveRecord::Migration[8.1]
  def change
    create_table :practices do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.string :custom_domain
      t.datetime :trial_ends_at
      t.string :primary_color
      t.string :accent_color
      t.string :website_url
      t.string :booking_url
      t.string :phone
      t.string :appointment_email
      t.integer :client_limit_per_counselor, null: false, default: 30
      t.timestamps
    end
    add_index :practices, :slug, unique: true
    add_index :practices, :custom_domain, unique: true
  end
end
