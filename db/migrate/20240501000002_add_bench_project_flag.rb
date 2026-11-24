class AddBenchProjectFlag < ActiveRecord::Migration[6.1]
  def change
    add_column :projects, :bench_project, :boolean, default: false, null: false
  end
end
