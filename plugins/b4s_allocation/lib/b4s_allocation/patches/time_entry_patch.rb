module B4sAllocation
  module Patches
    # Time entry approval workflow, weekly timesheets and the rule that only
    # project members can log time.
    module TimeEntryPatch
      extend ActiveSupport::Concern

      # Status values for timesheet approval workflow
      STATUS_PENDING = 'pending'
      STATUS_APPROVED = 'approved'
      STATUS_REJECTED = 'rejected'

      prepended do
        belongs_to :approved_by, :class_name => 'User', optional: true
        belongs_to :timesheet, optional: true

        # Scopes for timesheet approval workflow
        scope :pending_approval, -> { where(status: STATUS_PENDING) }
        scope :approved, -> { where(status: STATUS_APPROVED) }
        scope :rejected, -> { where(status: STATUS_REJECTED) }
        scope :for_user, ->(user_id) { where(user_id: user_id) }
        scope :for_project, ->(project_id) { where(project_id: project_id) }
        scope :for_date_range, ->(start_date, end_date) { where("spent_on BETWEEN ? AND ?", start_date, end_date) }
        scope :without_timesheet, -> { where(timesheet_id: nil) }

        # Additional validation for timesheet approval workflow
        validate :cannot_modify_approved_entry, on: :update
        validate :cannot_modify_if_timesheet_submitted, on: :update

        # Callbacks for email notifications
        after_create :send_pending_approval_notification
        after_save :send_approval_notification, if: -> { saved_change_to_status? && status == STATUS_APPROVED }
        after_save :send_rejection_notification, if: -> { saved_change_to_status? && status == STATUS_REJECTED }
        after_create :assign_to_timesheet
        after_update :update_timesheet_assignment, if: -> { saved_change_to_spent_on? }

        validate :validate_member_allocation
      end

      def validate_member_allocation
        return unless user && project && spent_on

        # Find the member record for this user and project
        member = Member.where(user_id: user_id, project_id: project_id).first

        if member.nil?
          errors.add :base, I18n.t(:error_user_not_allocated_to_project)
          return
        end
      end

      # Entries of a submitted (non-draft) timesheet are not editable.
      def editable_by?(usr)
        super && (!timesheet || timesheet.draft?)
      end

      # Returns true if the time entry can be approved or rejected
      def can_approve?(user)
        return false if user.nil? || user.id == self.user_id # Can't approve own time entries
        return false if status != STATUS_PENDING # Can only approve pending entries

        # Check if the user is a manager in the project
        user.allowed_to?(:approve_time_entries, project)
      end

      # Approves the time entry
      def approve(approver)
        return false unless can_approve?(approver)

        self.status = STATUS_APPROVED
        self.approved_by_id = approver.id
        self.approved_on = Time.now
        self.rejection_reason = nil
        save
      end

      # Rejects the time entry with a reason
      def reject(approver, reason)
        return false unless can_approve?(approver)

        self.status = STATUS_REJECTED
        self.approved_by_id = approver.id
        self.approved_on = Time.now
        self.rejection_reason = reason
        save
      end

      # Returns true if the time entry is pending approval
      def pending_approval?
        status == STATUS_PENDING
      end

      # Returns true if the time entry is approved
      def approved?
        status == STATUS_APPROVED
      end

      # Returns true if the time entry is rejected
      def rejected?
        status == STATUS_REJECTED
      end

      private

      # Validation to prevent modification of approved entries
      def cannot_modify_approved_entry
        if status_was == STATUS_APPROVED && (hours_changed? || spent_on_changed? || project_id_changed? || issue_id_changed? || activity_id_changed?)
          errors.add(:base, I18n.t(:error_cannot_modify_approved_time_entry))
        end
      end

      # Validation to prevent modification of entries in submitted timesheets
      def cannot_modify_if_timesheet_submitted
        if timesheet && !timesheet.draft? && (hours_changed? || spent_on_changed? || project_id_changed? || issue_id_changed? || activity_id_changed?)
          errors.add(:base, I18n.t(:error_cannot_modify_time_entry_in_submitted_timesheet))
        end
      end

      # Assigns the time entry to the appropriate timesheet based on the spent_on date
      def assign_to_timesheet
        # Find or create a timesheet for this user and date
        if user && spent_on
          self.timesheet = Timesheet.find_or_create_for_user_and_date(user, spent_on)
          save(validate: false) if timesheet_id_changed?
        end
      end

      # Updates the timesheet assignment if the spent_on date changes
      def update_timesheet_assignment
        # Remove from old timesheet
        old_timesheet = self.timesheet

        # Assign to new timesheet
        assign_to_timesheet

        # Update old timesheet if it exists and is empty
        if old_timesheet && old_timesheet.id != self.timesheet_id && old_timesheet.time_entries.count == 0
          old_timesheet.destroy
        end
      end

      # Send notification to approvers when a time entry is created
      def send_pending_approval_notification
        # Only send notifications for time entries that are part of submitted timesheets
        return unless timesheet && timesheet.pending_approval?

        Mailer.deliver_time_entry_pending_approval(self)
      end

      # Send notification to the time entry author when it's approved
      def send_approval_notification
        Mailer.deliver_time_entry_approved(self)
      end

      # Send notification to the time entry author when it's rejected
      def send_rejection_notification
        Mailer.deliver_time_entry_rejected(self)
      end
    end
  end
end
