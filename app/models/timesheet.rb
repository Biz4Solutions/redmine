class Timesheet < ApplicationRecord
  include Redmine::SafeAttributes
  
  belongs_to :user
  belongs_to :approved_by, class_name: 'User', optional: true
  has_many :time_entries, dependent: :nullify
  
  # Status values
  STATUS_DRAFT = 'draft'
  STATUS_PENDING = 'pending'
  STATUS_APPROVED = 'approved'
  STATUS_REJECTED = 'rejected'
  
  # Scopes
  scope :draft, -> { where(status: STATUS_DRAFT) }
  scope :pending_approval, -> { where(status: STATUS_PENDING) }
  scope :approved, -> { where(status: STATUS_APPROVED) }
  scope :rejected, -> { where(status: STATUS_REJECTED) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  
  # Validations
  validates :user_id, :start_date, :end_date, presence: true
  validates :status, inclusion: { in: [STATUS_DRAFT, STATUS_PENDING, STATUS_APPROVED, STATUS_REJECTED] }
  validate :end_date_after_start_date
  validate :no_overlapping_timesheets
  validate :timesheet_duration_is_one_week
  
  # Safe attributes
  safe_attributes 'user_id', 'start_date', 'end_date'
  
  # Returns the total hours for this timesheet
  def total_hours
    time_entries.sum(:hours)
  end
  
  # Returns true if the timesheet can be submitted
  def can_submit?
    status == STATUS_DRAFT && time_entries.any?
  end
  
  # Returns true if the timesheet can be approved or rejected
  def can_approve?(user)
    return false if user.nil? || user.id == self.user_id # Can't approve own timesheets
    return false if status != STATUS_PENDING # Can only approve pending timesheets
    
    # Check if the user has permission to approve timesheets in any of the projects
    project_ids = time_entries.pluck(:project_id).uniq
    project_ids.any? { |project_id| user.allowed_to?(:approve_time_entries, Project.find(project_id)) }
  end
  
  # Submit the timesheet for approval
  def submit
    return false unless can_submit?
    
    self.status = STATUS_PENDING
    save
  end
  
  # Approve the timesheet
  def approve(approver)
    return false unless can_approve?(approver)
    
    Timesheet.transaction do
      self.status = STATUS_APPROVED
      self.approved_by_id = approver.id
      self.approved_on = Time.now
      self.rejection_reason = nil
      
      # Also update all time entries to approved status
      time_entries.each do |entry|
        entry.status = TimeEntry::STATUS_APPROVED
        entry.approved_by_id = approver.id
        entry.approved_on = Time.now
        entry.save(validate: false)
      end
      
      save
    end
  end
  
  # Reject the timesheet with a reason
  def reject(approver, reason)
    return false unless can_approve?(approver)
    return false if reason.blank?
    
    Timesheet.transaction do
      self.status = STATUS_REJECTED
      self.approved_by_id = approver.id
      self.approved_on = Time.now
      self.rejection_reason = reason
      
      # Also update all time entries to rejected status
      time_entries.each do |entry|
        entry.status = TimeEntry::STATUS_REJECTED
        entry.approved_by_id = approver.id
        entry.approved_on = Time.now
        entry.rejection_reason = reason
        entry.save(validate: false)
      end
      
      save
    end
  end
  
  # Returns true if the timesheet is in draft status
  def draft?
    status == STATUS_DRAFT
  end
  
  # Returns true if the timesheet is pending approval
  def pending_approval?
    status == STATUS_PENDING
  end
  
  # Returns true if the timesheet is approved
  def approved?
    status == STATUS_APPROVED
  end
  
  # Returns true if the timesheet is rejected
  def rejected?
    status == STATUS_REJECTED
  end
  
  # Returns the week number for display
  def week_number
    start_date.strftime("Week %W, %Y")
  end
  
  # Returns a formatted date range for display
  def date_range
    "#{format_date(start_date)} - #{format_date(end_date)}"
  end
  
  # Find or create a timesheet for the given user and date
  def self.find_or_create_for_user_and_date(user, date)
    # Find the start of the week (Monday)
    start_date = date.beginning_of_week
    end_date = start_date + 6.days
    
    timesheet = Timesheet.find_by(user_id: user.id, start_date: start_date, end_date: end_date)
    
    unless timesheet
      timesheet = Timesheet.new(
        user_id: user.id,
        start_date: start_date,
        end_date: end_date,
        status: STATUS_DRAFT
      )
      timesheet.save
    end
    
    timesheet
  end
  
  private
  
  def end_date_after_start_date
    return if end_date.blank? || start_date.blank?
    
    if end_date < start_date
      errors.add(:end_date, :greater_than_start_date)
    end
  end
  
  def no_overlapping_timesheets
    return if start_date.blank? || end_date.blank?
    
    overlapping = Timesheet.where(user_id: user_id)
                          .where.not(id: id)
                          .where('(start_date <= ? AND end_date >= ?) OR (start_date <= ? AND end_date >= ?) OR (start_date >= ? AND end_date <= ?)',
                                 end_date, start_date, end_date, start_date, start_date, end_date)
    
    if overlapping.exists?
      errors.add(:base, :overlapping_timesheet)
    end
  end
  
  def timesheet_duration_is_one_week
    return if start_date.blank? || end_date.blank?
    
    duration = (end_date - start_date).to_i + 1
    
    if duration != 7
      errors.add(:base, :timesheet_must_be_one_week)
    end
  end
end 