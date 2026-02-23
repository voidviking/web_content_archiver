class AddResourcesCountToArchives < ActiveRecord::Migration[8.1]
  def change
    add_column :archives, :resources_count, :integer, null: false, default: 0
  end
end
