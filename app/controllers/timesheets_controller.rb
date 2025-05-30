class TimesheetsController < ApplicationController
  before_action :require_login
  before_action :find_timesheet, only: [:show, :edit, :update, :submit, :destroy]
  before_action :find_timesheets, only: [:bulk_submit, :bulk_approve, :bulk_reject]
  before_action :check_editability, only: [:edit, :update, :destroy]
  before_action :check_approval_permission, only: [:bulk_approve, :bulk_reject]
  
  helper :timelog
  helper :custom_fields
  helper :queries
  include QueriesHelper
  
  def index
    @timesheets = timesheets_scope.order(start_date: :desc)
    
    # Use Redmine's pagination helper instead of relying on page method
    @limit = per_page_option
    @timesheet_count = @timesheets.count
    @timesheet_pages = Paginator.new @timesheet_count, @limit, params['page']
    @offset ||= @timesheet_pages.offset
    @timesheets = @timesheets.limit(@limit).offset(@offset)
  end
  
  def show
    @time_entries = @timesheet.time_entries.order(spent_on: :desc)
  end
  
  def new
    @timesheet = Timesheet.new
    @timesheet.user_id = User.current.id
    @timesheet.start_date = Date.today.beginning_of_week
    @timesheet.end_date = @timesheet.start_date + 6.days
  end
  
  def create
    @timesheet = Timesheet.new(timesheet_params)
    @timesheet.user_id = User.current.id
    @timesheet.status = Timesheet::STATUS_DRAFT
    
    if @timesheet.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to timesheet_path(@timesheet)
    else
      render :new
    end
  end
  
  def edit
  end
  
  def update
    if @timesheet.update(timesheet_params)
      flash[:notice] = l(:notice_successful_update)
      redirect_to timesheet_path(@timesheet)
    else
      render :edit
    end
  end
  
  def destroy
    if @timesheet.destroy
      flash[:notice] = l(:notice_successful_delete)
    else
      flash[:error] = l(:error_unable_delete_timesheet)
    end
    redirect_to timesheets_path
  end
  
  def submit
    if @timesheet.submit
      # Notify approvers
      notify_approvers(@timesheet)
      
      flash[:notice] = l(:notice_timesheet_submitted)
      redirect_to timesheet_path(@timesheet)
    else
      flash[:error] = l(:error_timesheet_submit)
      redirect_to timesheet_path(@timesheet)
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
    
    flash[:notice] = l(:notice_timesheets_submitted, count: submitted_count)
    redirect_back_or_default timesheets_path
  end
  
  def bulk_approve
    approved_count = 0
    
    @timesheets.each do |timesheet|
      if timesheet.approve(User.current)
        approved_count += 1
      end
    end
    
    flash[:notice] = l(:notice_timesheets_approved, count: approved_count)
    redirect_back_or_default timesheets_path
  end
  
  def bulk_reject
    rejection_reason = params[:rejection_reason]
    
    if rejection_reason.blank?
      flash[:error] = l(:error_rejection_reason_required)
      redirect_back_or_default timesheets_path
      return
    end
    
    rejected_count = 0
    
    @timesheets.each do |timesheet|
      if timesheet.reject(User.current, rejection_reason)
        rejected_count += 1
      end
    end
    
    flash[:notice] = l(:notice_timesheets_rejected, count: rejected_count)
    redirect_back_or_default timesheets_path
  end
  
  def pending_approval
    @timesheets = Timesheet.pending_approval.order(start_date: :desc)
    
    # Use Redmine's pagination helper
    @limit = per_page_option
    @timesheet_count = @timesheets.count
    @timesheet_pages = Paginator.new @timesheet_count, @limit, params['page']
    @offset ||= @timesheet_pages.offset
    @timesheets = @timesheets.limit(@limit).offset(@offset)
    
    render :index
  end
  
  private
  
  def timesheet_params
    params.require(:timesheet).permit(:start_date, :end_date)
  end
  
  def find_timesheet
    @timesheet = Timesheet.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def find_timesheets
    @timesheets = Timesheet.where(id: params[:id] || params[:ids]).to_a
    
    raise ActiveRecord::RecordNotFound if @timesheets.empty?
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def check_editability
    unless @timesheet.user_id == User.current.id && @timesheet.draft?
      render_403
      return false
    end
  end
  
  def check_approval_permission
    unless User.current.allowed_to_globally?(:approve_time_entries)
      render_403
      return false
    end
  end
  
  def timesheets_scope
    scope = Timesheet.all
    
    # Filter by user
    if params[:user_id] == 'me'
      scope = scope.where(user_id: User.current.id)
    elsif params[:user_id].present?
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
end 