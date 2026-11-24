module B4sAllocation
  module Patches
    # Time entry approve/reject/submit actions.
    module TimelogControllerPatch
      extend ActiveSupport::Concern

      prepended do
        # Own callback names: re-declaring :find_time_entry, :find_time_entries
        # or :authorize here would replace core's callbacks and their :only lists.
        before_action :find_time_entry_for_approval, :only => [:approve, :reject]
        before_action :find_time_entries_for_approval, :only => [:bulk_approve, :bulk_reject]
        before_action :authorize_approval, :only => [:approve, :reject, :bulk_approve, :bulk_reject]
        before_action :check_approval_permission, :only => [:approve, :reject, :bulk_approve, :bulk_reject]

        accept_api_auth(*(accept_api_auth_actions + [:approve, :reject]))
      end

      def approve
        if @time_entry.approve(User.current)
          respond_to do |format|
            format.html do
              flash[:notice] = l(:notice_time_entry_approved)
              redirect_back_or_default project_time_entries_path(@time_entry.project)
            end
            format.api { render_api_ok }
          end
        else
          respond_to do |format|
            format.html do
              flash[:error] = @time_entry.errors.full_messages.join(", ")
              redirect_back_or_default project_time_entries_path(@time_entry.project)
            end
            format.api { render_validation_errors(@time_entry) }
          end
        end
      end

      def reject
        rejection_reason = params[:rejection_reason]
        if @time_entry.reject(User.current, rejection_reason)
          respond_to do |format|
            format.html do
              flash[:notice] = l(:notice_time_entry_rejected)
              redirect_back_or_default project_time_entries_path(@time_entry.project)
            end
            format.api { render_api_ok }
          end
        else
          respond_to do |format|
            format.html do
              flash[:error] = @time_entry.errors.full_messages.join(", ")
              redirect_back_or_default project_time_entries_path(@time_entry.project)
            end
            format.api { render_validation_errors(@time_entry) }
          end
        end
      end

      def bulk_approve
        approved_count = 0

        @time_entries.each do |time_entry|
          if time_entry.can_approve?(User.current) && time_entry.approve(User.current)
            approved_count += 1
          end
        end

        respond_to do |format|
          format.html do
            flash[:notice] = l(:notice_time_entries_approved, :count => approved_count)
            redirect_back_or_default project_time_entries_path(@projects.first)
          end
          format.api { render_api_ok }
        end
      end

      def bulk_reject
        rejection_reason = params[:rejection_reason]

        if rejection_reason.blank?
          flash[:error] = l(:error_rejection_reason_required)
          redirect_back_or_default project_time_entries_path(@projects.first)
          return
        end

        rejected_count = 0

        @time_entries.each do |time_entry|
          if time_entry.can_approve?(User.current) && time_entry.reject(User.current, rejection_reason)
            rejected_count += 1
          end
        end

        respond_to do |format|
          format.html do
            flash[:notice] = l(:notice_time_entries_rejected, :count => rejected_count)
            redirect_back_or_default project_time_entries_path(@projects.first)
          end
          format.api { render_api_ok }
        end
      end

      # Show time entries that are pending submission
      def pending_submission
        @query = TimeEntryQuery.new(:name => '_')
        @query.filters = {'status' => {:operator => '=', :values => [TimeEntry::STATUS_PENDING]}}

        if params[:user_id] == 'me' || params[:user_id].blank?
          @query.filters['user_id'] = {:operator => '=', :values => ['me']}
        end

        @query.sort_criteria = [['spent_on', 'desc']]
        @query.column_names = [:project, :spent_on, :user, :activity, :issue, :comments, :hours]

        @entries = @query.results_scope

        respond_to do |format|
          format.html { render :action => 'pending_submission' }
        end
      end

      # Submit a time entry for approval
      def submit
        @time_entry = TimeEntry.find(params[:id])

        if @time_entry.user_id != User.current.id
          flash[:error] = l(:error_not_your_time_entry)
          redirect_back_or_default pending_submission_time_entries_path
          return
        end

        if @time_entry.status != TimeEntry::STATUS_PENDING
          flash[:error] = l(:error_time_entry_already_submitted)
          redirect_back_or_default pending_submission_time_entries_path
          return
        end

        # Time entry is already in pending status, so we just need to notify approvers
        Mailer.deliver_time_entry_pending_approval(@time_entry)

        flash[:notice] = l(:notice_time_entry_submitted)
        redirect_back_or_default pending_submission_time_entries_path
      end

      # Submit multiple time entries for approval
      def bulk_submit
        submitted_count = 0

        TimeEntry.where(:id => params[:ids]).each do |time_entry|
          if time_entry.user_id == User.current.id && time_entry.status == TimeEntry::STATUS_PENDING
            # Time entry is already in pending status, so we just need to notify approvers
            Mailer.deliver_time_entry_pending_approval(time_entry)
            submitted_count += 1
          end
        end

        flash[:notice] = l(:notice_time_entries_submitted, :count => submitted_count)
        redirect_back_or_default pending_submission_time_entries_path
      end

      private

      def find_time_entry_for_approval
        find_time_entry
      end

      def find_time_entries_for_approval
        find_time_entries
      end

      def authorize_approval
        authorize
      end

      def check_approval_permission
        unless User.current.allowed_to?(:approve_time_entries, @project || @projects)
          deny_access
          return false
        end
      end
    end
  end
end
