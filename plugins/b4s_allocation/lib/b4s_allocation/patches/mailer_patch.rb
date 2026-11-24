module B4sAllocation
  module Patches
    # Time entry and timesheet approval notifications.
    module MailerPatch
      extend ActiveSupport::Concern

      class_methods do

        # Notifies approvers about a new time entry that needs approval
        def deliver_time_entry_pending_approval(time_entry)
          # Find all users who can approve time entries in this project
          approvers = time_entry.project.members.joins(:roles)
                               .where("#{Role.table_name}.permissions LIKE '%:approve_time_entries%'")
                               .map(&:user).uniq

          # Don't notify the time entry author
          approvers.reject! {|user| user.id == time_entry.user_id}

          approvers.each do |user|
            time_entry_pending_approval(user, time_entry).deliver_later
          end
        end


        # Notifies the time entry author that their entry was approved
        def deliver_time_entry_approved(time_entry)
          time_entry_approved(time_entry.user, time_entry).deliver_later
        end


        # Notifies the time entry author that their entry was rejected
        def deliver_time_entry_rejected(time_entry)
          time_entry_rejected(time_entry.user, time_entry).deliver_later
        end


        # Sends reminders to approvers about pending time entries
        def deliver_time_entry_pending_approval_reminders
          # Group pending time entries by project
          pending_entries_by_project = TimeEntry.pending_approval.group_by(&:project)

          pending_entries_by_project.each do |project, entries|
            # Find all users who can approve time entries in this project
            approvers = project.members.joins(:roles)
                               .where("#{Role.table_name}.permissions LIKE '%:approve_time_entries%'")
                               .map(&:user).uniq

            approvers.each do |user|
              # Only send reminder if there are entries this user can approve
              approvable_entries = entries.select {|entry| entry.can_approve?(user)}
              if approvable_entries.any?
                time_entry_pending_approval_reminder(user, approvable_entries).deliver_later
              end
            end
          end
        end


        # Delivers a timesheet approved notification
        def deliver_timesheet_approved(timesheet)
          timesheet_approved(timesheet).deliver_later
        end


        # Delivers a timesheet rejected notification
        def deliver_timesheet_rejected(timesheet)
          timesheet_rejected(timesheet).deliver_later
        end
      end

      # Builds a mail to notify a user that their time entry needs approval
      def time_entry_pending_approval(user, time_entry)
        redmine_headers 'Project' => time_entry.project.identifier,
                        'Time-Entry-Id' => time_entry.id,
                        'Time-Entry-Author' => time_entry.user.login
        @time_entry = time_entry
        @user = user
        @time_entry_url = url_for(:controller => 'timelog', :action => 'index', :project_id => time_entry.project, :issue_id => time_entry.issue)
        mail :to => user,
          :subject => "[#{time_entry.project.name}] #{l(:mail_subject_time_entry_pending_approval)}: #{time_entry.hours} #{l(:field_hours)}"
      end


      # Builds a mail to notify a user that their time entry was approved
      def time_entry_approved(user, time_entry)
        redmine_headers 'Project' => time_entry.project.identifier,
                        'Time-Entry-Id' => time_entry.id,
                        'Time-Entry-Approver' => time_entry.approved_by.login
        @time_entry = time_entry
        @user = user
        @time_entry_url = url_for(:controller => 'timelog', :action => 'index', :project_id => time_entry.project, :issue_id => time_entry.issue)
        mail :to => user,
          :subject => "[#{time_entry.project.name}] #{l(:mail_subject_time_entry_approved)}: #{time_entry.hours} #{l(:field_hours)}"
      end


      # Builds a mail to notify a user that their time entry was rejected
      def time_entry_rejected(user, time_entry)
        redmine_headers 'Project' => time_entry.project.identifier,
                        'Time-Entry-Id' => time_entry.id,
                        'Time-Entry-Approver' => time_entry.approved_by.login
        @time_entry = time_entry
        @user = user
        @time_entry_url = url_for(:controller => 'timelog', :action => 'index', :project_id => time_entry.project, :issue_id => time_entry.issue)
        mail :to => user,
          :subject => "[#{time_entry.project.name}] #{l(:mail_subject_time_entry_rejected)}: #{time_entry.hours} #{l(:field_hours)}"
      end


      # Builds a mail to remind approvers about pending time entries
      def time_entry_pending_approval_reminder(user, time_entries)
        @time_entries = time_entries
        @user = user
        @time_entries_url = url_for(:controller => 'timelog', :action => 'index', :set_filter => 1, :status => TimeEntry::STATUS_PENDING)
        mail :to => user,
          :subject => "[#{Setting.app_title}] #{l(:mail_subject_time_entry_pending_approval_reminder)}: #{time_entries.size} #{l(:field_time_entries)}"
      end


      # Builds a mail to notify a user that a timesheet is pending approval
      def timesheet_pending_approval(user, timesheet)
        redmine_headers 'Timesheet-Id' => timesheet.id,
                        'Timesheet-Author' => timesheet.user.login
        @timesheet = timesheet
        @user = user
        @timesheet_url = url_for(:controller => 'timesheets', :action => 'show', :id => timesheet.id)
        mail :to => user,
          :subject => "[#{l(:label_timesheet)}] #{l(:mail_subject_timesheet_pending_approval)}: #{timesheet.user.name} (#{timesheet.date_range})"
      end


      # Builds a mail to notify a user that their timesheet was approved
      def timesheet_approved(timesheet)
        redmine_headers 'Timesheet-Id' => timesheet.id,
                        'Timesheet-Approver' => timesheet.approved_by.login
        @timesheet = timesheet
        @user = timesheet.user
        @timesheet_url = url_for(:controller => 'timesheets', :action => 'show', :id => timesheet.id)
        mail :to => timesheet.user,
          :subject => "[#{l(:label_timesheet)}] #{l(:mail_subject_timesheet_approved)}: #{timesheet.date_range}"
      end


      # Builds a mail to notify a user that their timesheet was rejected
      def timesheet_rejected(timesheet)
        redmine_headers 'Timesheet-Id' => timesheet.id,
                        'Timesheet-Approver' => timesheet.approved_by.login
        @timesheet = timesheet
        @user = timesheet.user
        @timesheet_url = url_for(:controller => 'timesheets', :action => 'show', :id => timesheet.id)
        mail :to => timesheet.user,
          :subject => "[#{l(:label_timesheet)}] #{l(:mail_subject_timesheet_rejected)}: #{timesheet.date_range}"
      end
    end
  end
end
