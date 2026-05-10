class CreateEncryptedBlobs < ActiveRecord::Migration[8.1]
  def change
    create_table :encrypted_blobs do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.text :ciphertext, null: false
      t.string :nonce, null: false
      t.string :salt, null: false

      t.timestamps
    end
  end
end
