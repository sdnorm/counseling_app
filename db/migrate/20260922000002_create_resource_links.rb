class CreateResourceLinks < ActiveRecord::Migration[8.1]
  def change
    create_table :resource_links do |t|
      t.references :practice, null: false, foreign_key: true
      t.string :title, null: false
      t.string :url, null: false
      t.string :description
      t.integer :position, null: false, default: 0
      t.timestamps
    end
  end
end
