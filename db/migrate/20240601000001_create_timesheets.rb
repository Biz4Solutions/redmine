class CreateTimesheets < ActiveRecord::Migration[6.1]
  def change
    create_table :timesheets do |t|
      t.integer :user_id, null: false
      t.date :start_date, null: false
      t.date :end_date, null: false
      t.string :status, default: 'draft', null: false
      t.integer :approved_by_id
      t.datetime :approved_on
      t.text :rejection_reason
      
      t.timestamps
    end
    
    add_index :timesheets, :user_id
    add_index :timesheets, :status
    add_index :timesheets, [:user_id, :start_date, :end_date], unique: true
    
    # Add timesheet_id to time_entries
    add_column :time_entries, :timesheet_id, :integer
    add_index :time_entries, :timesheet_id
  end
end 