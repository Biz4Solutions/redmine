class OptimizeTimeEntriesPerformance < ActiveRecord::Migration[6.1]
  def up
    # Add composite indexes for efficient permission checks
    add_index :time_entries, [:user_id, :project_id], name: 'index_time_entries_on_user_id_and_project_id'
    add_index :time_entries, [:project_id, :user_id, :spent_on], name: 'index_time_entries_on_project_user_spent_on'
    add_index :time_entries, [:spent_on, :project_id], name: 'index_time_entries_on_spent_on_and_project_id'
    
    # Add index for approval workflow performance
    add_index :time_entries, [:status, :user_id], name: 'index_time_entries_on_status_and_user_id'
    
    # Add index on spent_on for date range queries
    add_index :time_entries, :spent_on unless index_exists?(:time_entries, :spent_on)
  end

  def down
    remove_index :time_entries, name: 'index_time_entries_on_user_id_and_project_id' if index_exists?(:time_entries, [:user_id, :project_id])
    remove_index :time_entries, name: 'index_time_entries_on_project_user_spent_on' if index_exists?(:time_entries, [:project_id, :user_id, :spent_on])
    remove_index :time_entries, name: 'index_time_entries_on_spent_on_and_project_id' if index_exists?(:time_entries, [:spent_on, :project_id])
    remove_index :time_entries, name: 'index_time_entries_on_status_and_user_id' if index_exists?(:time_entries, [:status, :user_id])
    remove_index :time_entries, :spent_on if index_exists?(:time_entries, :spent_on)
  end
end 