namespace :allocations do
  desc "Update end dates for expired allocations based on last time entry"
  task update_end_dates: :environment do
    puts "Updating end dates for expired allocations based on last time entry..."

    

    # Find all expired memberships (either by end_date or project status)
    expired_memberships = Member.joins(:project)
                              .where("projects.status IN (?)", 
                                    [Project::STATUS_CLOSED, Project::STATUS_ARCHIVED, Project::STATUS_SCHEDULED_FOR_DELETION])
                              .includes(:project)

    total = expired_memberships.count
    puts "Found #{total} expired memberships to process"

    expired_memberships.find_each.with_index(1) do |membership, index|
      project = membership.project
      
      # Skip if project doesn't exist
      unless project
        puts "[#{index}/#{total}] Skipping membership ##{membership.id} - project not found"
        next
      end
      membership.update_column(:start_date, project.created_on)
      membership.update_column(:allocation_percentage, 100.00)
      
      # If project is closed, archived, or scheduled for deletion, use last time entry date
      if project.closed? || project.archived? || project.scheduled_for_deletion?
        # Find the last time entry for this user in this project
        last_time_entry = TimeEntry.where(user_id: membership.user_id, project_id: project.id)
                                 .order(spent_on: :desc)
                                 .first
        
        if !last_time_entry
          #if project closed and no time entries, use the last time entry for the project
          last_time_entry = TimeEntry.where(project_id: project.id)
                                 .order(spent_on: :desc)
                                 .first
        end
        if last_time_entry
          membership.update_column(:end_date, last_time_entry.spent_on)
    
          puts "[#{index}/#{total}] Updated membership ##{membership.id} end date to #{last_time_entry.spent_on} due to project status: #{project.status}"
        else
          #if not timesheet entry for the project, use the last updated date of the project
          membership.update_column(:end_date, project.updated_on)
          puts "[#{index}/#{total}] No time entries found for membership ##{membership.id} in closed/archived project"
        end
        next
      end
    end

    puts "Finished updating end dates for expired allocations"
  end

  desc "Update active allocations with end dates, start dates, and recalculate percentages"
  task update_active_allocations: :environment do
    puts "Updating active allocations..."

    # Find all active memberships
    active_memberships = Member.joins(:project)
                              .where("projects.status IN (?)" , [Project::STATUS_ACTIVE])
                              .includes(:user, :project)

    total = active_memberships.count
    puts "Found #{total} active memberships to process"

    # Group memberships by user to calculate total allocations
    user_allocations = {}
    active_memberships.each do |membership|
      user_allocations[membership.user_id] ||= []
      user_allocations[membership.user_id] << membership
    end

    # Process each membership
    active_memberships.find_each.with_index(1) do |membership, index|
      project = membership.project
      
      # Skip if project doesn't exist
      unless project
        puts "[#{index}/#{total}] Skipping membership ##{membership.id} - project not found"
        next
      end
      

      # Find the first time entry for this user in this project
      #first_time_entry = TimeEntry.where(user_id: membership.user_id, project_id: membership.project_id)
      #                           .order(spent_on: :asc)
      #                           .first

      # Calculate new allocation percentage
      #user_total_allocations = user_allocations[membership.user_id].sum(&:allocation_percentage)
      #new_allocation = (membership.allocation_percentage.to_f / user_total_allocations * 100).round(2)

      user_total_allocations = user_allocations[membership.user_id].count
      if user_total_allocations > 0 
        new_allocation = (100 / user_total_allocations).round(2)
      else
        new_allocation = 100
      end

      # Update the membership
      membership.update_columns(
        start_date: membership.created_on,
        end_date: '2025-12-31',
        allocation_percentage: new_allocation
      )

      puts "[#{index}/#{total}] Updated membership ##{membership.id}:"
      puts "  - Start date: #{membership.start_date}"
      puts "  - End date: #{membership.end_date}"
      puts "  - New allocation: #{new_allocation}%"
    end

    puts "Finished updating active allocations"
  end
end