# frozen_string_literal: true

# Redmine - project management software
# Copyright (C) 2006-  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class TimeEntry < ApplicationRecord
  include Redmine::SafeAttributes
  # could have used polymorphic association
  # project association here allows easy loading of time entries at project level with one database trip
  belongs_to :project
  belongs_to :issue
  belongs_to :user
  belongs_to :author, :class_name => 'User'
  belongs_to :activity, :class_name => 'TimeEntryActivity'
  belongs_to :approved_by, :class_name => 'User', optional: true

  # Status values for timesheet approval workflow
  STATUS_PENDING = 'pending'
  STATUS_APPROVED = 'approved'
  STATUS_REJECTED = 'rejected'
  
  # Scopes for timesheet approval workflow
  scope :pending_approval, -> { where(status: STATUS_PENDING) }
  scope :approved, -> { where(status: STATUS_APPROVED) }
  scope :rejected, -> { where(status: STATUS_REJECTED) }
  scope :for_user, ->(user_id) { where(user_id: user_id) }
  scope :for_project, ->(project_id) { where(project_id: project_id) }
  scope :for_date_range, ->(start_date, end_date) { where("spent_on BETWEEN ? AND ?", start_date, end_date) }
  
  # Additional validation for timesheet approval workflow
  validate :cannot_modify_approved_entry, on: :update
  
  # Callbacks for email notifications
  after_create :send_pending_approval_notification
  after_save :send_approval_notification, if: -> { saved_change_to_status? && status == STATUS_APPROVED }
  after_save :send_rejection_notification, if: -> { saved_change_to_status? && status == STATUS_REJECTED }
  
  acts_as_customizable
  acts_as_event(
    :title =>
      Proc.new do |o|
        related   = o.issue if o.issue && o.issue.visible?
        related ||= o.project
        "#{l_hours(o.hours)} (#{related.event_title})"
      end,
    :url =>
      Proc.new do |o|
        {:controller => 'timelog', :action => 'index', :project_id => o.project, :issue_id => o.issue}
      end,
    :author => :user,
    :group => :issue,
    :description => :comments
  )
  acts_as_activity_provider :timestamp => "#{table_name}.created_on",
                            :author_key => :user_id,
                            :scope => proc {joins(:project).preload(:project)}

  validates_presence_of :author_id, :user_id, :activity_id, :project_id, :hours, :spent_on
  validates_presence_of :issue_id, :if => lambda {Setting.timelog_required_fields.include?('issue_id')}
  validates_presence_of :comments, :if => lambda {Setting.timelog_required_fields.include?('comments')}
  validates_numericality_of :hours, :allow_nil => true, :message => :invalid
  validates_length_of :comments, :maximum => 1024, :allow_nil => true
  validates :spent_on, :date => true
  before_validation :set_project_if_nil
  # TODO: remove this, author should be always explicitly set
  before_validation :set_author_if_nil
  validate :validate_time_entry
  validate :validate_member_allocation

  scope :visible, (lambda do |*args|
    joins(:project).
    where(TimeEntry.visible_condition(args.shift || User.current, *args))
  end)
  scope :left_join_issue, (lambda do
    joins(
      "LEFT OUTER JOIN #{Issue.table_name}" \
      " ON #{Issue.table_name}.id = #{TimeEntry.table_name}.issue_id" \
      " AND (#{Issue.visible_condition(User.current)})"
    )
  end)
  scope :on_issue, (lambda do |issue|
    joins(:issue).
    where("#{Issue.table_name}.root_id = #{issue.root_id} AND #{Issue.table_name}.lft >= #{issue.lft} AND #{Issue.table_name}.rgt <= #{issue.rgt}")
  end)

  safe_attributes 'user_id', 'hours', 'comments', 'project_id',
                  'issue_id', 'activity_id', 'spent_on',
                  'custom_field_values', 'custom_fields'

  # Returns a SQL conditions string used to find all time entries visible by the specified user
  def self.visible_condition(user, options={})
    Project.allowed_to_condition(user, :view_time_entries, options) do |role, user|
      if role.time_entries_visibility == 'all'
        nil
      elsif role.time_entries_visibility == 'own' && user.id && user.logged?
        "#{table_name}.user_id = #{user.id}"
      else
        '1=0'
      end
    end
  end

  # Returns true if user or current user is allowed to view the time entry
  def visible?(user=nil)
    (user || User.current).allowed_to?(:view_time_entries, self.project) do |role, user|
      if role.time_entries_visibility == 'all'
        true
      elsif role.time_entries_visibility == 'own'
        self.user == user
      else
        false
      end
    end
  end

  def initialize(attributes=nil, *args)
    super
    if new_record? && self.activity.nil?
      self.activity_id = TimeEntryActivity.default_activity_id(User.current, self.project)
      self.hours = nil if hours == 0
    end
  end

  def safe_attributes=(attrs, user=User.current)
    if attrs
      attrs = super(attrs)
      if issue_id_changed? && issue
        if issue.visible?(user) && user.allowed_to?(:log_time, issue.project)
          if attrs[:project_id].blank? && issue.project_id != project_id
            self.project_id = issue.project_id
          end
          @invalid_issue_id = nil
        elsif user.allowed_to?(:log_time, issue.project) && issue.assigned_to_id_changed? && issue.previous_assignee == User.current
          current_assignee = issue.assigned_to
          issue.assigned_to = issue.previous_assignee
          unless issue.visible?(user)
            @invalid_issue_id = issue_id
          end
          issue.assigned_to = current_assignee
        else
          @invalid_issue_id = issue_id
        end
      end
      if user_id_changed? && user_id != author_id && !user.allowed_to?(:log_time_for_other_users, project)
        @invalid_user_id = user_id
      else
        @invalid_user_id = nil
      end

      # Delete assigned custom fields not visible by the user
      editable_custom_field_ids = editable_custom_field_values(user).map {|v| v.custom_field_id.to_s}
      self.custom_field_values.delete_if do |c|
        !editable_custom_field_ids.include?(c.custom_field.id.to_s)
      end
    end

    attrs
  end

  def set_project_if_nil
    self.project = issue.project if issue && project.nil?
  end

  def set_author_if_nil
    self.author = User.current if author.nil?
  end

  def validate_time_entry
    if hours
      errors.add :hours, :invalid if hours < 0
      errors.add :hours, :invalid if hours == 0.0 && hours_changed? && !Setting.timelog_accept_0_hours?

      max_hours = Setting.timelog_max_hours_per_day.to_f
      if hours_changed? && max_hours > 0.0
        logged_hours = other_hours_with_same_user_and_day
        if logged_hours + hours > max_hours
          errors.add(
            :base,
            I18n.t(:error_exceeds_maximum_hours_per_day,
                   :logged_hours => format_hours(logged_hours),
                   :max_hours => format_hours(max_hours)))
        end
      end
    end
    errors.add :project_id, :invalid if project.nil?
    if @invalid_user_id || (user_id_changed? && user_id != author_id && !self.assignable_users.map(&:id).include?(user_id))
      errors.add :user_id, :invalid
    end
    errors.add :issue_id, :invalid if (issue_id && !issue) || (issue && project!=issue.project) || @invalid_issue_id
    errors.add :activity_id, :inclusion if activity_id_changed? && project && !project.activities.include?(activity)
    if spent_on && spent_on_changed? && user
      errors.add :base, I18n.t(:error_spent_on_future_date) if !Setting.timelog_accept_future_dates? && (spent_on > user.today)
    end
  end

  def validate_member_allocation
    return unless user && project && spent_on
    
    # Find the member record for this user and project
    member = Member.where(user_id: user_id, project_id: project_id).first
    
    if member.nil?
      errors.add :base, I18n.t(:error_user_not_allocated_to_project)
      return
    end
    
    # Check if the spent_on date is within the member's allocation period
    unless member.active_on?(spent_on)
      if member.start_date && spent_on < member.start_date
        errors.add :spent_on, I18n.t(:error_spent_on_before_allocation_start, 
                                     :start_date => format_date(member.start_date))
      elsif member.end_date && spent_on > member.end_date
        errors.add :spent_on, I18n.t(:error_spent_on_after_allocation_end, 
                                     :end_date => format_date(member.end_date))
      else
        errors.add :spent_on, I18n.t(:error_user_not_allocated_to_project_on_date)
      end
      return
    end
    
    # Check if the hours exceed the user's allocation percentage
    if member.allocation_percentage < 100
      # Calculate the maximum hours allowed per day based on allocation percentage
      # Assuming 8-hour workday as standard
      max_hours_per_day = 8.0 * (member.allocation_percentage / 100.0)
      
      # Get all time entries for this user on this date
      total_hours_on_date = TimeEntry.where(
        user_id: user_id, 
        spent_on: spent_on
      ).where.not(id: id).sum(:hours).to_f
      
      # Add the current hours
      total_hours_on_date += hours.to_f
      
      if total_hours_on_date > max_hours_per_day
        errors.add :hours, I18n.t(:error_exceeds_allocation_percentage, 
                                  :max_hours => format_hours(max_hours_per_day),
                                  :allocation => member.allocation_percentage)
      end
    end
  end

  def hours=(h)
    write_attribute :hours, (h.is_a?(String) ? (h.to_hours || h) : h)
  end

  def hours
    h = read_attribute(:hours)
    if h.is_a?(Float)
      # Convert the float value to a rational with a denominator of 60 to
      # avoid floating point errors.
      #
      # Examples:
      #  0.38333333333333336 => (23/60)   # 23m
      #  0.9913888888888889  => (59/60)   # 59m 29s is rounded to 59m
      #  0.9919444444444444  => (1/1)     # 59m 30s is rounded to 60m
      (h * 60).round / 60r
    else
      h
    end
  end

  # tyear, tmonth, tweek assigned where setting spent_on attributes
  # these attributes make time aggregations easier
  def spent_on=(date)
    super
    self.tyear = spent_on ? spent_on.year : nil
    self.tmonth = spent_on ? spent_on.month : nil
    self.tweek = spent_on ? Date.civil(spent_on.year, spent_on.month, spent_on.day).cweek : nil
  end

  # Returns true if the time entry can be edited by usr, otherwise false
  def editable_by?(usr)
    visible?(usr) && (
      (usr == user && usr.allowed_to?(:edit_own_time_entries, project)) || usr.allowed_to?(:edit_time_entries, project)
    )
  end

  # Returns the custom_field_values that can be edited by the given user
  def editable_custom_field_values(user=nil)
    visible_custom_field_values(user)
  end

  # Returns the custom fields that can be edited by the given user
  def editable_custom_fields(user=nil)
    editable_custom_field_values(user).map(&:custom_field).uniq
  end

  def visible_custom_field_values(user = nil)
    user ||= User.current
    custom_field_values.select do |value|
      value.custom_field.visible_by?(project, user)
    end
  end

  def assignable_users
    users = []
    if project
      users = project.members.active.preload(:user)
      users = users.map(&:user).select{|u| u.allowed_to?(:log_time, project)}
    end
    users << User.current if User.current.logged? && !users.include?(User.current)
    users
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

  # Returns the hours that were logged in other time entries for the same user and the same day
  def other_hours_with_same_user_and_day
    if user_id && spent_on
      TimeEntry.
        where(:user_id => user_id, :spent_on => spent_on).
        where.not(:id => id).
        sum(:hours).to_f
    else
      0.0
    end
  end
  
  # Send notification to approvers when a time entry is created
  def send_pending_approval_notification
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
