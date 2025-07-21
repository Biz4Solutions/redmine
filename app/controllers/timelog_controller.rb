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

class TimelogController < ApplicationController
  menu_item :time_entries

  before_action :find_time_entry, :only => [:show, :edit, :update]
  before_action :check_editability, :only => [:edit, :update]
  before_action :find_time_entries, :only => [:bulk_edit, :bulk_update, :destroy]
  before_action :authorize, :only => [:show, :edit, :update, :bulk_edit, :bulk_update, :destroy]
  before_action :check_spent_time_read_only_access, :only => [:new, :create, :edit, :update, :destroy, :bulk_edit, :bulk_update]

  before_action :find_optional_issue, :only => [:new, :create]
  before_action :find_optional_project, :only => [:index, :report]

  accept_atom_auth :index
  accept_api_auth :index, :show, :create, :update, :destroy

  rescue_from Query::StatementInvalid, :with => :query_statement_invalid
  rescue_from Query::QueryError, :with => :query_error

  helper :issues
  include TimelogHelper
  helper :custom_fields
  include CustomFieldsHelper
  helper :queries
  include QueriesHelper

  def index
    # Performance monitoring wrapper
    Redmine::PerformanceLogger.log_time_entry_query('time_entries_index', User.current) do
      retrieve_time_entry_query

      # Performance optimization: Get count separately to avoid complex joins in count query
      @entry_count = time_entry_scope.select('time_entries.id').count
      @entry_pages = Paginator.new @entry_count, per_page_option, params['page']

      # Performance optimization: More efficient preloading
      scope = time_entry_scope.
        includes(:project, :user, :activity).
        includes(:issue => [:project, :tracker, :status, :assigned_to, :priority]).
        offset(@entry_pages.offset).
        limit(@entry_pages.per_page)

      respond_to do |format|
        format.html do
          @entries = scope.to_a
          render :layout => !request.xhr?
        end
        format.api do
          @offset, @limit = api_offset_and_limit
          @entries = time_entry_scope.
            includes(:project, :user, :activity).
            includes(:issue => [:project, :tracker, :status]).
            includes(:custom_values => :custom_field).
            offset(@offset).limit(@limit).to_a
        end
        format.atom do
          entries = scope.limit(Setting.feeds_limit.to_i).reorder("#{TimeEntry.table_name}.created_on DESC").to_a
          render_feed(entries, :title => l(:label_spent_time))
        end
        format.csv do
          # Export all entries
          entries = time_entry_scope.includes(:project, :user, :activity, :issue).to_a
          send_data(query_to_csv(entries, @query, params), :type => 'text/csv; header=present', :filename => "#{filename_for_export(@query, 'timelog')}.csv")
        end
      end
    end
  end

  def report
    # Performance monitoring wrapper
    Redmine::PerformanceLogger.log_time_entry_query('time_entries_report', User.current) do
      retrieve_time_entry_query
      scope = time_entry_scope

      @report = Redmine::Helpers::TimeReport.new(@project, params[:criteria], params[:columns], scope)

      respond_to do |format|
        format.html {render :layout => !request.xhr?}
        format.csv do
          send_data(report_to_csv(@report), :type => 'text/csv; header=present',
                    :filename => 'timelog.csv')
        end
      end
    end
  end

  def show
    respond_to do |format|
      # TODO: Implement html response
      format.html {head :not_acceptable}
      format.api
    end
  end

  def new
    @time_entry ||=
      TimeEntry.new(:project => @project, :issue => @issue,
                    :author => User.current, :spent_on => User.current.today)
    @time_entry.safe_attributes = params[:time_entry]
  end

  def create
    @time_entry ||=
      TimeEntry.new(:project => @project, :issue => @issue,
                    :author => User.current, :user => User.current,
                    :spent_on => User.current.today)
    @time_entry.safe_attributes = params[:time_entry]
    if @time_entry.project && !User.current.allowed_to?(:log_time, @time_entry.project)
      render_403
      return
    end

    call_hook(:controller_timelog_edit_before_save,
              {:params => params, :time_entry => @time_entry})

    if @time_entry.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_create)
          if params[:continue]
            options = {
              :time_entry => {
                :project_id => params[:time_entry][:project_id],
                :issue_id => @time_entry.issue_id,
                :spent_on => @time_entry.spent_on,
                :activity_id => @time_entry.activity_id
              },
              :back_url => params[:back_url]
            }
            if params[:project_id] && @time_entry.project
              options[:time_entry][:project_id] ||= @time_entry.project.id
              redirect_to new_project_time_entry_path(@time_entry.project, options)
            elsif params[:issue_id] && @time_entry.issue
              redirect_to new_issue_time_entry_path(@time_entry.issue, options)
            else
              redirect_to new_time_entry_path(options)
            end
          else
            redirect_back_or_default project_time_entries_path(@time_entry.project)
          end
        end
        format.api do
          render :action => 'show', :status => :created, :location => time_entry_url(@time_entry)
        end
      end
    else
      respond_to do |format|
        format.html {render :action => 'new'}
        format.api  {render_validation_errors(@time_entry)}
      end
    end
  end

  def edit
    @time_entry.safe_attributes = params[:time_entry]
  end

  def update
    @time_entry.safe_attributes = params[:time_entry]
    call_hook(:controller_timelog_edit_before_save,
              {:params => params, :time_entry => @time_entry})

    if @time_entry.save
      respond_to do |format|
        format.html do
          flash[:notice] = l(:notice_successful_update)
          redirect_back_or_default project_time_entries_path(@time_entry.project)
        end
        format.api  {render_api_ok}
      end
    else
      respond_to do |format|
        format.html {render :action => 'edit'}
        format.api  {render_validation_errors(@time_entry)}
      end
    end
  end

  def bulk_edit
    @target_projects = Project.allowed_to(:log_time).to_a
    @custom_fields = TimeEntry.first.available_custom_fields.select {|field| field.format.bulk_edit_supported}
    if params[:time_entry]
      @target_project = @target_projects.detect {|p| p.id.to_s == params[:time_entry][:project_id].to_s}
    end
    if @target_project
      @available_activities = @target_project.activities
    else
      @available_activities = @projects.map(&:activities).reduce(:&)
    end
    @time_entry_params = params[:time_entry] || {}
    @time_entry_params[:custom_field_values] ||= {}
  end

  def bulk_update
    attributes = parse_params_for_bulk_update(params[:time_entry])

    unsaved_time_entries = []
    saved_time_entries = []

    @time_entries.each do |time_entry|
      time_entry.reload
      time_entry.safe_attributes = attributes
      call_hook(
        :controller_time_entries_bulk_edit_before_save,
        {:params => params, :time_entry => time_entry}
      )
      if time_entry.save
        saved_time_entries << time_entry
      else
        unsaved_time_entries << time_entry
      end
    end

    if unsaved_time_entries.empty?
      flash[:notice] = l(:notice_successful_update) unless saved_time_entries.empty?
      redirect_back_or_default project_time_entries_path(@projects.first)
    else
      @saved_time_entries = @time_entries
      @unsaved_time_entries = unsaved_time_entries
      @time_entries = TimeEntry.where(:id => unsaved_time_entries.map(&:id)).
        preload(:project => :time_entry_activities).
        preload(:user).to_a

      bulk_edit
      render :action => 'bulk_edit'
    end
  end

  def destroy
    destroyed = TimeEntry.transaction do
      @time_entries.each do |t|
        unless t.destroy && t.destroyed?
          raise ActiveRecord::Rollback
        end
      end
    end

    respond_to do |format|
      format.html do
        if destroyed
          flash[:notice] = l(:notice_successful_delete)
        else
          flash[:error] = l(:notice_unable_delete_time_entry)
        end
        redirect_back_or_default project_time_entries_path(@projects.first), :referer => true
      end
      format.api do
        if destroyed
          render_api_ok
        else
          render_validation_errors(@time_entries)
        end
      end
    end
  end

  def get_activities
    @project = Project.find(params[:project_id])
    @activities = @project.activities
    render :partial => 'activities', :locals => { :activities => @activities }
  end

  private

  def find_time_entry
    @time_entry = TimeEntry.find(params[:id])
    @project = @time_entry.project
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def check_editability
    unless @time_entry.editable_by?(User.current)
      render_403
      return false
    end
  end

  def find_time_entries
    @time_entries = TimeEntry.where(:id => params[:id] || params[:ids]).
      preload(:project => :time_entry_activities).
      preload(:user).to_a

    raise ActiveRecord::RecordNotFound if @time_entries.empty?
    raise Unauthorized unless @time_entries.all? {|t| t.editable_by?(User.current)}

    @projects = @time_entries.filter_map(&:project).uniq
    @project = @projects.first if @projects.size == 1
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_optional_issue
    if params[:issue_id].present?
      @issue = Issue.find(params[:issue_id])
      @project = @issue.project
      authorize
    else
      find_optional_project
    end
  end

  # Returns the TimeEntry scope for index and report actions
  def time_entry_scope(options={})
    @query.results_scope(options)
  end

  def retrieve_time_entry_query
    retrieve_query(TimeEntryQuery, false, :defaults => @default_columns_names)
  end

  def query_error(exception)
    session.delete(:time_entry_query)
    super
  end

  def check_spent_time_read_only_access
    # Allow regular users to log time from issue pages
    return true if params[:issue_id].present?

    # Spent Time tab is now read-only - only Manager and Administrator roles can create/edit/delete time entries
    # All time entry modifications should be done through Timesheets
    unless User.current.has_manager_or_admin_role_privileges?(@project)
      flash[:error] = l(:error_spent_time_read_only_use_timesheets)
      if @project
        redirect_to timesheets_path(:project_id => @project.id)
      else
        redirect_to timesheets_path
      end
      return false
    end
    true
  end
end
