namespace :redmine do
  namespace :timesheet_approval do
    desc 'Send reminders about pending time entries'
    task :send_reminders => :environment do
      Mailer.deliver_time_entry_pending_approval_reminders
      puts "Sent timesheet approval reminders at #{Time.now}"
    end
  end
end 