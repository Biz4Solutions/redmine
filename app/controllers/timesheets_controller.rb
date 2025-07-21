class TimesheetsController < ApplicationController
  before_action :require_login
  before_action :authorize_timesheets,
:only => [:index, :show, :new, :create, :edit, :update, :destroy, :submit, :approve, :reject, :add_time_entry, :remove_time_entry, :edit_time_entry, :update_time_entry, :bulk_submit, :bulk_approve, :bulk_reject, :pending_approval,
          :for_approval]
  before_action :find_timesheet, :only => [:show, :edit, :update, :destroy, :submit, :approve, :reject, :add_time_entry, :remove_time_entry, :edit_time_entry, :update_time_entry]
  before_action :find_timesheets, only: [:bulk_submit, :bulk_approve, :bulk_reject]
  before_action :check_editability, only: [:edit, :update, :destroy, :add_time_entry, :remove_time_entry, :edit_time_entry, :update_time_entry]
  before_action :check_approval_permission, only: [:approve, :reject, :bulk_approve, :bulk_reject, :for_approval]

  helper :timelog
  helper :custom_fields
  helper :queries
  include QueriesHelper

  def index
    @timesheets = timesheets_scope.order(start_date: :desc)
    @timesheet_count = @timesheets.count
    @timesheet_pages = Redmine::Pagination::Paginator.new @timesheet_count, per_page_option, params['page']
    @timesheets = @timesheets.offset(@timesheet_pages.offset).limit(@timesheet_pages.per_page)
  end

  def for_approval
    @timesheets = timesheets_for_approval_scope.order(start_date: :desc)
    @timesheet_count = @timesheets.count
    @timesheet_pages = Redmine::Pagination::Paginator.new @timesheet_count, per_page_option, params['page']
    @timesheets = @timesheets.offset(@timesheet_pages.offset).limit(@timesheet_pages.per_page)
  end

  def show
    @time_entries = @timesheet.time_entries.includes(:project, :issue, :activity).order(:spent_on)
    if @timesheet.user_id == User.current.id && @timesheet.draft?
      @time_entry = TimeEntry.new
      @projects = User.current.memberships.map(&:project).select(&:active?).select { |p| User.current.allowed_to?(:log_time, p) }
    end
  end

  def new
    @timesheet = Timesheet.new
    @time_entry = TimeEntry.new
    @projects = User.current.memberships.map(&:project).select(&:active?).select { |p| User.current.allowed_to?(:log_time, p) }
  end

  def edit
    @time_entry = TimeEntry.new
    @projects = User.current.memberships.map(&:project).select(&:active?).select { |p| User.current.allowed_to?(:log_time, p) }
  end

  def create
    @timesheet = Timesheet.new(timesheet_params)
    @timesheet.user_id = User.current.id
    @timesheet.status = Timesheet::STATUS_DRAFT

    if @timesheet.save
      # Create time entry if provided
      if params[:add_time_entry] && time_entry_params.present?
        @time_entry = TimeEntry.new(time_entry_params)
        @time_entry.user_id = User.current.id
        @time_entry.author_id = User.current.id
        @time_entry.timesheet_id = @timesheet.id

        if @time_entry.save
          flash[:notice] = l(:notice_successful_create)
        else
          flash[:error] = @time_entry.errors.full_messages.join(", ")
        end
      end

      flash[:notice] = l(:notice_successful_create, :scope => :timesheet)
      redirect_to edit_timesheet_path(@timesheet)
    else
      @projects = User.current.memberships.map(&:project).select(&:active?).select { |p| User.current.allowed_to?(:log_time, p) }
      render :new
    end
  end

  def update
    if @timesheet.update(timesheet_params)
      # Create time entry if provided
      if params[:add_time_entry] && time_entry_params.present?
        @time_entry = TimeEntry.new(time_entry_params)
        @time_entry.user_id = User.current.id
        @time_entry.author_id = User.current.id
        @time_entry.timesheet_id = @timesheet.id

        if @time_entry.save
          flash[:notice] = l(:notice_successful_create)
        else
          flash[:error] = @time_entry.errors.full_messages.join(", ")
        end

        # When adding time entry, stay on the edit page
        redirect_to edit_timesheet_path(@timesheet)
        return
      end

      # Only when saving (not adding), go back to list
      flash[:notice] = l(:notice_successful_update, :scope => :timesheet)
      redirect_to timesheets_path
    else
      @projects = User.current.memberships.map(&:project).select(&:active?).select { |p| User.current.allowed_to?(:log_time, p) }
      render :edit
    end
  end

  def destroy
    @timesheet.destroy
    redirect_to timesheets_path, :notice => l(:notice_successful_delete)
  end

  def submit
    if @timesheet.submit
      if @timesheet.status_was == Timesheet::STATUS_REJECTED
        flash[:notice] = l(:notice_timesheet_resubmitted, :scope => :timesheet)
      else
        flash[:notice] = l(:notice_timesheet_submitted, :scope => :timesheet)
      end
    else
      flash[:error] = l(:error_cannot_submit_timesheet, :scope => :timesheet)
    end
    redirect_to timesheet_path(@timesheet)
  end

  def approve
    if @timesheet.approve(User.current)
      flash[:notice] = l(:notice_timesheet_approved)
    else
      flash[:error] = l(:error_cannot_approve_timesheet)
    end
    redirect_to for_approval_timesheets_path
  end

  def reject
    if @timesheet.reject(User.current, params[:rejection_reason])
      flash[:notice] = l(:notice_timesheet_rejected)
    else
      flash[:error] = l(:error_cannot_reject_timesheet)
    end
    redirect_to for_approval_timesheets_path
  end

  def add_time_entry
    @time_entry = TimeEntry.new(time_entry_params)
    @time_entry.user_id = User.current.id
    @time_entry.author_id = User.current.id
    @time_entry.timesheet_id = @timesheet.id

    if @time_entry.save
      flash[:notice] = l(:notice_successful_create)
    else
      flash[:error] = @time_entry.errors.full_messages.join(", ")
    end

    redirect_to edit_timesheet_path(@timesheet)
  end

  def remove_time_entry
    @time_entry = @timesheet.time_entries.find(params[:time_entry_id])

    if @time_entry.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:error_cannot_delete_time_entry)
    end

    redirect_to edit_timesheet_path(@timesheet)
  end

  def edit_time_entry
    @time_entry = @timesheet.time_entries.find(params[:time_entry_id])
    @projects = User.current.memberships.map(&:project).select(&:active?).select { |p| User.current.allowed_to?(:log_time, p) }
    render :edit_time_entry
  end

  def update_time_entry
    @time_entry = @timesheet.time_entries.find(params[:time_entry_id])

    if @time_entry.update(time_entry_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to edit_timesheet_path(@timesheet)
    else
      @projects = User.current.memberships.map(&:project).select(&:active?).select { |p| User.current.allowed_to?(:log_time, p) }
      flash[:error] = @time_entry.errors.full_messages.join(", ")
      render :edit_time_entry
    end
  end

  def bulk_submit
    submitted_count = 0

    @timesheets.each do |timesheet|
      if timesheet.submit
        # Notify approvers
        notify_approvers(timesheet)

        submitted_count += 1
      end
    end

    flash[:notice] = l('notice_timesheets_submitted', count: submitted_count, scope: :timesheet)
    redirect_back_or_default timesheets_path
  end

  def bulk_approve
    approved_count = 0

    @timesheets.each do |timesheet|
      if timesheet.approve(User.current)
        approved_count += 1
      end
    end

    flash[:notice] = l('notice_timesheets_approved', count: approved_count, scope: :timesheet)
    redirect_back_or_default for_approval_timesheets_path
  end

  def bulk_reject
    rejection_reason = params[:rejection_reason]

    if rejection_reason.blank?
      flash[:error] = l(:error_rejection_reason_required)
      redirect_back_or_default for_approval_timesheets_path
      return
    end

    rejected_count = 0

    @timesheets.each do |timesheet|
      if timesheet.reject(User.current, rejection_reason)
        rejected_count += 1
      end
    end

    flash[:notice] = l(:notice_timesheets_rejected, count: rejected_count, scope: :timesheet)
    redirect_back_or_default for_approval_timesheets_path
  end

  def pending_approval
    @timesheets = Timesheet.joins(:time_entries)
                          .joins(:project => :members)
                          .where("#{Member.table_name}.user_id = ?", User.current.id)
                          .joins("INNER JOIN #{MemberRole.table_name} ON #{MemberRole.table_name}.member_id = #{Member.table_name}.id")
                          .joins("INNER JOIN #{Role.table_name} ON #{Role.table_name}.id = #{MemberRole.table_name}.role_id")
                          .where("#{Role.table_name}.permissions LIKE '%:approve_time_entries%'")
                          .where("#{TimeEntry.table_name}.user_id <> ?", User.current.id)
                          .where("#{TimeEntry.table_name}.status = ?", TimeEntry::STATUS_PENDING)
                          .distinct
                          .order("#{Timesheet.table_name}.start_date DESC")

    render :index
  end

  private

  def authorize_timesheets
    # Allow access if user has any of the required permissions
    return true if User.current.admin?
    return true if User.current.allowed_to_globally?(:approve_all_time_entries)
    return true if User.current.allowed_to_globally?(:approve_time_entries)
    return true if User.current.allowed_to?(:log_time, nil, :global => true)

    # Check if user has log_time permission on any project
    return true if User.current.memberships.joins(:roles)
                           .where("#{Role.table_name}.permissions LIKE '%:log_time%'")
                           .exists?

    render_403
    return false
  end

  def find_timesheet
    @timesheet = Timesheet.find(params[:id])

    # Check if user has permission to view this timesheet
    unless can_view_timesheet?(@timesheet)
      render_403
      return false
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_timesheets
    # Use appropriate scope based on the action
    if action_name == 'bulk_approve' || action_name == 'bulk_reject'
      # For approval actions, use the approval scope
      scope = timesheets_for_approval_scope
    else
      # For other actions, use the regular scope
      scope = timesheets_scope
    end

    @timesheets = scope.where(id: params[:id] || params[:ids]).to_a

    raise ActiveRecord::RecordNotFound if @timesheets.empty?

    # Check if user has permission to view all timesheets
    @timesheets.each do |timesheet|
      unless can_view_timesheet?(timesheet)
        render_403
        return false
      end
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def check_editability
    unless @timesheet.user_id == User.current.id && @timesheet.can_edit?
      render_403
      return false
    end
  end

  def check_approval_permission
    unless User.current.admin? ||
           User.current.allowed_to_globally?(:approve_all_time_entries) ||
           User.current.allowed_to_globally?(:approve_time_entries)
      render_403
      return false
    end
  end

  def can_view_timesheet?(timesheet)
    return true if User.current.admin?
    return true if User.current.allowed_to_globally?(:approve_all_time_entries)
    return true if timesheet.user_id == User.current.id
    return true if User.current.allowed_to_globally?(:approve_time_entries) &&
                   timesheet.time_entries.joins(:project => :members)
                           .joins("INNER JOIN #{MemberRole.table_name} ON #{MemberRole.table_name}.member_id = #{Member.table_name}.id")
                           .joins("INNER JOIN #{Role.table_name} ON #{Role.table_name}.id = #{MemberRole.table_name}.role_id")
                           .where("#{Member.table_name}.user_id = ?", User.current.id)
                           .where("#{Role.table_name}.permissions LIKE '%:approve_time_entries%'")
                           .exists?

    false
  end

  def timesheets_scope
    # For the index action (My Timesheets), always show only the current user's timesheets
    scope = Timesheet.where(user_id: User.current.id)

    # Apply additional filters
    # Filter by status
    if params[:status].present?
      scope = scope.where(status: params[:status])
    end

    # Filter by date range
    if params[:start_date].present? && params[:end_date].present?
      start_date = params[:start_date].to_date
      end_date = params[:end_date].to_date
      scope = scope.where('start_date >= ? AND end_date <= ?', start_date, end_date)
    end

    scope
  end

  def timesheets_for_approval_scope
    # Authorization logic based on user permissions
    if User.current.admin?
      # Admins can see all timesheets for approval
      scope = Timesheet.where.not(status: Timesheet::STATUS_DRAFT)
    elsif User.current.allowed_to_globally?(:approve_all_time_entries)
      # Users with "Approve All Time Entries" permission can see all timesheets for approval
      scope = Timesheet.where.not(status: Timesheet::STATUS_DRAFT)
    elsif User.current.allowed_to_globally?(:approve_time_entries)
      # Users with "Approve Time Logs" permission can see timesheets for projects they can approve
      scope = Timesheet.joins(:time_entries => :project)
                      .joins("INNER JOIN #{Member.table_name} ON #{Member.table_name}.project_id = #{Project.table_name}.id")
                      .joins("INNER JOIN #{MemberRole.table_name} ON #{MemberRole.table_name}.member_id = #{Member.table_name}.id")
                      .joins("INNER JOIN #{Role.table_name} ON #{Role.table_name}.id = #{MemberRole.table_name}.role_id")
                      .where("#{Member.table_name}.user_id = ?", User.current.id)
                      .where("#{Role.table_name}.permissions LIKE '%:approve_time_entries%'")
                      .where.not(status: Timesheet::STATUS_DRAFT)
                      .distinct
    else
      # Regular users cannot see approval view
      scope = Timesheet.none
    end

    # Apply additional filters
    # Filter by user (if explicitly requested and user has permission)
    if params[:user_id].present? && (User.current.admin? || User.current.allowed_to_globally?(:approve_all_time_entries) || User.current.allowed_to_globally?(:approve_time_entries))
      scope = scope.where(user_id: params[:user_id])
    end

    # Filter by status
    if params[:status].present?
      scope = scope.where(status: params[:status])
    end

    # Filter by date range
    if params[:start_date].present? && params[:end_date].present?
      start_date = params[:start_date].to_date
      end_date = params[:end_date].to_date
      scope = scope.where('start_date >= ? AND end_date <= ?', start_date, end_date)
    end

    scope
  end

  def notify_approvers(timesheet)
    # Find all users who can approve time entries in the projects
    project_ids = timesheet.time_entries.pluck(:project_id).uniq

    approvers = []
    project_ids.each do |project_id|
      project = Project.find(project_id)
      project_approvers = project.members.joins(:roles)
                                .where("#{Role.table_name}.permissions LIKE '%:approve_time_entries%'")
                                .map(&:user).uniq
      approvers.concat(project_approvers)
    end

    # Remove duplicates and the timesheet owner
    approvers = approvers.uniq.reject { |user| user.id == timesheet.user_id }

    # Send notifications
    approvers.each do |user|
      Mailer.timesheet_pending_approval(user, timesheet).deliver_later
    end
  end

  def timesheet_params
    params.require(:timesheet).permit(:start_date, :end_date)
  end

  def time_entry_params
    if params[:time_entry].present?
      params.require(:time_entry).permit(
        :project_id, :issue_id, :hours, :comments,
        :activity_id, :spent_on, :custom_field_values => {}
      )
    end
  end
end
