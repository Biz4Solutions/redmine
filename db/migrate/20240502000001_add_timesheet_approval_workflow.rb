class AddTimesheetApprovalWorkflow < ActiveRecord::Migration[6.1]
  def change
    # Add status field to time_entries
    add_column :time_entries, :status, :string, default: 'pending', null: false
    add_column :time_entries, :approved_by_id, :integer
    add_column :time_entries, :approved_on, :datetime
    add_column :time_entries, :rejection_reason, :text
    
    # Add index for faster queries
    add_index :time_entries, :status
    add_index :time_entries, :approved_by_id
  end
end 