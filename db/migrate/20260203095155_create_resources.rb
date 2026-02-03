class CreateResources < ActiveRecord::Migration[8.1]
  def change
    create_table :resources do |t|
      t.references :archive, null: false, foreign_key: true, index: true
      t.string :original_url, null: false
      t.string :storage_key
      t.string :storage_url
      t.integer :resource_type, null: false, default: 0
      t.string :content_type
      t.integer :file_size

      t.timestamps
    end

    add_index :resources, [ :archive_id, :original_url ]
  end
end
