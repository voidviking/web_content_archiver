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

ActiveRecord::Schema[8.1].define(version: 2026_02_03_095155) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "archives", force: :cascade do |t|
    t.text "content"
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "lock_version", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "url", null: false
    t.index ["status"], name: "index_archives_on_status"
    t.index ["url"], name: "index_archives_on_url", unique: true
  end

  create_table "resources", force: :cascade do |t|
    t.bigint "archive_id", null: false
    t.string "content_type"
    t.datetime "created_at", null: false
    t.integer "file_size"
    t.string "original_url", null: false
    t.integer "resource_type", default: 0, null: false
    t.string "storage_key"
    t.string "storage_url"
    t.datetime "updated_at", null: false
    t.index ["archive_id", "original_url"], name: "index_resources_on_archive_id_and_original_url"
    t.index ["archive_id"], name: "index_resources_on_archive_id"
  end

  add_foreign_key "resources", "archives"
end
