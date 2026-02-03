class CreateArchives < ActiveRecord::Migration[8.1]
  def change
    create_table :archives do |t|
      t.string :url, null: false
      t.integer :status, null: false, default: 0
      t.text :content
      t.text :error_message
      t.integer :lock_version, null: false, default: 0

      t.timestamps
    end

    add_index :archives, :url, unique: true
    add_index :archives, :status
  end
end
