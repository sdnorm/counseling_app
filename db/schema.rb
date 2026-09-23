# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_23_135713) do
  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "counselor_invites", force: :cascade do |t|
    t.datetime "accepted_at"
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.datetime "expires_at", null: false
    t.integer "invited_by_id"
    t.integer "practice_id"
    t.string "practice_name"
    t.string "role", default: "member", null: false
    t.string "token", null: false
    t.datetime "updated_at", null: false
    t.index ["invited_by_id"], name: "index_counselor_invites_on_invited_by_id"
    t.index ["practice_id"], name: "index_counselor_invites_on_practice_id"
    t.index ["token"], name: "index_counselor_invites_on_token", unique: true
  end

  create_table "counselor_sessions", force: :cascade do |t|
    t.integer "counselor_id", null: false
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.index ["counselor_id"], name: "index_counselor_sessions_on_counselor_id"
  end

  create_table "counselors", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "name", null: false
    t.string "password_digest", null: false
    t.boolean "platform_admin", default: false, null: false
    t.integer "practice_id", null: false
    t.datetime "removed_at"
    t.string "role", default: "member", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_counselors_on_email_address", unique: true
    t.index ["practice_id"], name: "index_counselors_on_practice_id"
  end

  create_table "encrypted_blobs", force: :cascade do |t|
    t.text "ciphertext", null: false
    t.datetime "created_at", null: false
    t.string "nonce", null: false
    t.string "salt"
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_encrypted_blobs_on_user_id", unique: true
  end

  create_table "invite_codes", force: :cascade do |t|
    t.string "code"
    t.integer "counselor_id", null: false
    t.datetime "created_at", null: false
    t.text "email_address"
    t.datetime "updated_at", null: false
    t.boolean "used", default: false, null: false
    t.integer "user_id"
    t.index ["code"], name: "index_invite_codes_on_code", unique: true
    t.index ["counselor_id"], name: "index_invite_codes_on_counselor_id"
    t.index ["user_id"], name: "index_invite_codes_on_user_id"
  end

  create_table "practices", force: :cascade do |t|
    t.string "accent_color"
    t.string "appointment_email"
    t.string "booking_url"
    t.integer "client_limit_per_counselor", default: 30, null: false
    t.datetime "created_at", null: false
    t.string "custom_domain"
    t.string "name", null: false
    t.string "phone"
    t.string "primary_color"
    t.string "slug", null: false
    t.datetime "trial_ends_at"
    t.datetime "updated_at", null: false
    t.string "website_url"
    t.index ["custom_domain"], name: "index_practices_on_custom_domain", unique: true
    t.index ["slug"], name: "index_practices_on_slug", unique: true
  end

  create_table "push_subscriptions", force: :cascade do |t|
    t.string "auth", null: false
    t.datetime "created_at", null: false
    t.string "endpoint", null: false
    t.string "p256dh", null: false
    t.datetime "updated_at", null: false
    t.integer "user_id", null: false
    t.index ["endpoint"], name: "index_push_subscriptions_on_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "resource_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description"
    t.integer "position", default: 0, null: false
    t.integer "practice_id", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["practice_id"], name: "index_resource_links_on_practice_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.integer "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "archived_at"
    t.integer "counselor_id", null: false
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.integer "invite_code_id", null: false
    t.date "last_reminded_on"
    t.datetime "last_synced_at"
    t.string "password_digest", null: false
    t.text "password_wrapped_key", null: false
    t.text "recovery_wrapped_key", null: false
    t.string "reminder_time"
    t.string "time_zone"
    t.datetime "updated_at", null: false
    t.index ["counselor_id"], name: "index_users_on_counselor_id"
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
    t.index ["invite_code_id"], name: "index_users_on_invite_code_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "counselor_invites", "counselors", column: "invited_by_id"
  add_foreign_key "counselor_invites", "practices"
  add_foreign_key "counselor_sessions", "counselors"
  add_foreign_key "counselors", "practices"
  add_foreign_key "encrypted_blobs", "users"
  add_foreign_key "invite_codes", "counselors"
  add_foreign_key "invite_codes", "users"
  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "resource_links", "practices"
  add_foreign_key "sessions", "users"
  add_foreign_key "users", "counselors"
  add_foreign_key "users", "invite_codes"
end
