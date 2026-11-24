class AddAllocationFieldsToMembers < ActiveRecord::Migration[6.1]
  def change
    add_column :members, :allocation_percentage, :decimal, precision: 5, scale: 2, default: 100.0, null: false
    add_column :members, :start_date, :date
    add_column :members, :end_date, :date
    
    # Add an index to improve performance when querying active members by date
    add_index :members, [:user_id, :start_date, :end_date]
    
    # Populate start_date and end_date for existing members with project dates
    reversible do |dir|
      dir.up do
        execute <<-SQL
          UPDATE members
          SET start_date = (
            SELECT MIN(start_date) 
            FROM issues 
            WHERE issues.project_id = members.project_id
          ),
          end_date = (
            SELECT MAX(due_date) 
            FROM issues 
            WHERE issues.project_id = members.project_id
          )
        SQL
      end
    end
  end
end 