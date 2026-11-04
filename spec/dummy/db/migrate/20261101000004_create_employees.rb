class CreateEmployees < ActiveRecord::Migration[8.1]
  def change
    create_table :employees do |t|
      t.references :tenant, null: false, foreign_key: true, index: false
      t.string :external_id, null: false
      t.string :email, null: false
      t.string :name
      t.string :status, null: false, default: "active"
      t.date :hired_on
      t.timestamps
    end
    # upsert_all's unique_by: the tenant column, then the natural key.
    add_index :employees, %i[tenant_id external_id], unique: true
  end
end
