module B4sAllocation
  module Patches
    # Allocation fields on user/group memberships.
    module PrincipalMembershipsControllerPatch
      # Copies of the core actions that also save the allocation fields and
      # report validation errors.

      def create
        membership_params = params[:membership].to_unsafe_hash
        @members = Member.create_principal_memberships(@principal, membership_params)

        # Check if any members have errors
        @member_errors = @members.map { |m| m.errors.full_messages }.flatten.uniq if @members.any? { |m| !m.valid? }

        respond_to do |format|
          format.html do
            if @members.present? && @members.all?(&:valid?)
              flash[:notice] = l(:notice_successful_create)
            else
              flash[:error] = @member_errors.join(", ") if @member_errors.present?
            end
            redirect_to_principal @principal
          end
          format.js
        end
      end

      def update
        membership_params = params.require(:membership).permit(:allocation_percentage, :start_date, :end_date, :billable, :role_ids => [])

        # Update roles
        @membership.attributes = membership_params.slice(:role_ids)

        # Update allocation fields
        @membership.allocation_percentage = membership_params[:allocation_percentage] if membership_params[:allocation_percentage].present?
        @membership.start_date = membership_params[:start_date] if membership_params[:start_date].present?
        @membership.end_date = membership_params[:end_date] if membership_params[:end_date].present?
        # Unchecked checkboxes are not submitted
        @membership.billable = membership_params[:billable] == '1'

        saved = @membership.save
        respond_to do |format|
          format.html do
            if saved
              flash[:notice] = l(:notice_successful_update)
            else
              flash[:error] = @membership.errors.full_messages.join(", ")
            end
            redirect_to_principal @principal
          end
          format.js do
            @roles = Role.givable.to_a if !saved
          end
        end
      end
    end
  end
end
