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

ActiveRecord::Schema[8.1].define(version: 2026_11_03_205806) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "busbar_run_transitions", force: :cascade do |t|
    t.bigint "run_id", null: false
    t.string "to_state", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "sort_key", null: false
    t.boolean "most_recent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["run_id", "most_recent"], name: "index_busbar_run_transitions_on_run_id_and_most_recent", unique: true, where: "most_recent"
    t.index ["run_id", "sort_key"], name: "index_busbar_run_transitions_on_run_id_and_sort_key", unique: true
    t.index ["run_id"], name: "index_busbar_run_transitions_on_run_id"
  end

  create_table "busbar_runs", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "template_id"
    t.integer "template_version"
    t.jsonb "template_snapshot", default: {}, null: false
    t.string "schema_key", null: false
    t.string "state", default: "received", null: false
    t.string "load_mode", default: "incremental", null: false
    t.boolean "review_required", default: true, null: false
    t.string "filename"
    t.string "checksum"
    t.jsonb "options", default: {}, null: false
    t.integer "row_count", default: 0, null: false
    t.integer "chunk_count", default: 0, null: false
    t.integer "chunks_done", default: 0, null: false
    t.integer "created_count", default: 0, null: false
    t.integer "updated_count", default: 0, null: false
    t.integer "unchanged_count", default: 0, null: false
    t.integer "skipped_count", default: 0, null: false
    t.integer "invalid_count", default: 0, null: false
    t.integer "failed_count", default: 0, null: false
    t.jsonb "deactivated_keys", default: [], null: false
    t.bigint "created_by_id"
    t.bigint "approved_by_id"
    t.datetime "approved_at"
    t.datetime "checks_enqueued_at"
    t.datetime "finalize_enqueued_at"
    t.datetime "started_at"
    t.datetime "finished_at"
    t.string "after_ingestion_state"
    t.text "error"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["template_id"], name: "index_busbar_runs_on_template_id"
    t.index ["tenant_id", "state"], name: "index_busbar_runs_on_tenant_id_and_state"
    t.index ["tenant_id"], name: "index_busbar_runs_on_tenant_id"
  end

  create_table "busbar_staged_rows", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "run_id", null: false
    t.integer "chunk", null: false
    t.integer "row_number", null: false
    t.jsonb "raw", default: {}, null: false
    t.jsonb "data", default: {}, null: false
    t.jsonb "natural_key"
    t.string "natural_key_digest"
    t.string "status", default: "pending", null: false
    t.string "action"
    t.jsonb "row_errors", default: [], null: false
    t.bigint "record_id"
    t.datetime "handled_at"
    t.index ["run_id", "chunk", "status"], name: "index_busbar_staged_rows_on_run_id_and_chunk_and_status"
    t.index ["run_id", "natural_key_digest"], name: "index_busbar_staged_rows_on_run_id_and_natural_key_digest"
    t.index ["run_id", "row_number"], name: "index_busbar_staged_rows_on_run_id_and_row_number", unique: true
    t.index ["run_id", "status", "action"], name: "index_busbar_staged_rows_on_run_id_and_status_and_action"
  end

  create_table "busbar_templates", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "schema_key", null: false
    t.string "name", null: false
    t.jsonb "column_map", default: {}, null: false
    t.jsonb "transforms", default: [], null: false
    t.jsonb "value_maps", default: {}, null: false
    t.jsonb "options", default: {}, null: false
    t.jsonb "natural_key", default: [], null: false
    t.string "load_mode", default: "incremental", null: false
    t.integer "version", default: 1, null: false
    t.bigint "created_by_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "schema_key"], name: "index_busbar_templates_on_tenant_id_and_schema_key"
    t.index ["tenant_id"], name: "index_busbar_templates_on_tenant_id"
  end

  create_table "employees", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "external_id", null: false
    t.string "email", null: false
    t.string "name"
    t.string "status", default: "active", null: false
    t.date "hired_on"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "external_id"], name: "index_employees_on_tenant_id_and_external_id", unique: true
  end

  create_table "identities", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.bigint "user_id", null: false
    t.string "provider", null: false
    t.bigint "identity_provider_id"
    t.string "uid", null: false
    t.string "email"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "provider", "identity_provider_id", "uid"], name: "index_identities_on_tenant_provider_and_uid", unique: true, nulls_not_distinct: true
    t.index ["user_id"], name: "index_identities_on_user_id"
  end

  create_table "tenants", force: :cascade do |t|
    t.string "name", null: false
    t.string "subdomain", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["subdomain"], name: "index_tenants_on_subdomain", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.bigint "tenant_id", null: false
    t.string "email", null: false
    t.string "password_digest", null: false
    t.boolean "verified", default: false, null: false
    t.boolean "otp_required_for_sign_in", default: false, null: false
    t.string "otp_secret", null: false
    t.string "webauthn_id", null: false
    t.string "name"
    t.string "time_zone", default: "Etc/UTC", null: false
    t.string "theme", default: "system", null: false
    t.string "public_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["public_id"], name: "index_users_on_public_id", unique: true
    t.index ["tenant_id", "email"], name: "index_users_on_tenant_id_and_email", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "busbar_run_transitions", "busbar_runs", column: "run_id"
  add_foreign_key "busbar_runs", "busbar_templates", column: "template_id"
  add_foreign_key "busbar_runs", "tenants"
  add_foreign_key "busbar_staged_rows", "busbar_runs", column: "run_id"
  add_foreign_key "busbar_templates", "tenants"
  add_foreign_key "employees", "tenants"
  add_foreign_key "identities", "tenants"
  add_foreign_key "identities", "users"
  add_foreign_key "users", "tenants"
end
