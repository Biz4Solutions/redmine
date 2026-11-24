module B4sAllocation
  module Patches
    # Allocation fields when adding/editing project members.
    module MembersControllerPatch
      extend ActiveSupport::Concern

      prepended do
        include MembersHelper
      end

      # create and update are copies of the core actions that also save the
      # allocation fields and report validation errors.

      def create
        members = []
        if params[:membership]
          user_ids = Array.wrap(params[:membership][:user_id] || params[:membership][:user_ids])
          user_ids << nil if user_ids.empty?
          user_ids.each do |user_id|
            member = Member.new(:project => @project, :user_id => user_id)
            member.set_editable_role_ids(params[:membership][:role_ids])

            # Set allocation fields
            member.allocation_percentage = params[:membership][:allocation_percentage]
            member.start_date = params[:membership][:start_date]
            member.end_date = params[:membership][:end_date]
            member.billable = params[:membership].has_key?(:billable) ? params[:membership][:billable] == '1' : false

            members << member
          end

          # Try to save all members
          saved = true
          Member.transaction do
            members.each do |member|
              unless member.save
                saved = false
                # Store the error messages from the first failed member
                @member_errors = member.errors.full_messages
                raise ActiveRecord::Rollback
              end
            end

            if saved
              @project.members << members
            end
          end
        end

        respond_to do |format|
          format.html do
            if members.present? && members.all?(&:valid?)
              flash[:notice] = l(:notice_successful_create)
            elsif @member_errors.present?
              flash[:error] = @member_errors.join(", ")
            end
            redirect_to_settings_in_projects
          end
          format.js do
            @members = members
            @member = Member.new
            @member_errors = @member_errors
          end
          format.api do
            @member = members.first
            if @member.try(:valid?)
              render :action => 'show', :status => :created, :location => membership_url(@member)
            else
              render_validation_errors(@member || Member.new)
            end
          end
        end
      end

      def update
        if params[:membership]
          @member.set_editable_role_ids(params[:membership][:role_ids])

          # Update allocation fields
          @member.allocation_percentage = params[:membership][:allocation_percentage] if params[:membership][:allocation_percentage]
          @member.start_date = params[:membership][:start_date] if params[:membership][:start_date]
          @member.end_date = params[:membership][:end_date] if params[:membership][:end_date]
          @member.billable = params[:membership].has_key?(:billable) ? params[:membership][:billable] == '1' : false
        end
        saved = @member.save
        respond_to do |format|
          format.html do
            if saved
              flash[:notice] = l(:notice_successful_update)
            else
              flash[:error] = @member.errors.full_messages.join(", ")
            end
            redirect_to_settings_in_projects
          end
          format.js do
            @roles = Role.givable.to_a unless saved
          end
          format.api do
            if saved
              render_api_ok
            else
              render_validation_errors(@member)
            end
          end
        end
      end

      def max_availability
        user = User.find(params[:user_id])
        regular_allocation = Member.regular_allocation_for_user(user.id)
        max_availability = [100 - regular_allocation, 0].max

        render json: { max_availability: max_availability }
      end
    end
  end
end
