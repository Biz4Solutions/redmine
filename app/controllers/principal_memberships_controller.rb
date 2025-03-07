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

class PrincipalMembershipsController < ApplicationController
  layout 'admin'
  self.main_menu = false

  helper :members

  before_action :require_admin
  before_action :find_principal, :only => [:new, :create]
  before_action :find_membership, :only => [:edit, :update, :destroy]

  def new
    @projects = Project.active.all
    @roles = Role.find_all_givable
    respond_to do |format|
      format.html
      format.js
    end
  end

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

  def edit
    @roles = Role.givable.to_a
  end

  def update
    membership_params = params.require(:membership).permit(:role_ids => [], :allocation_percentage => nil, :start_date => nil, :end_date => nil)
    
    # Update roles
    @membership.attributes = membership_params.slice(:role_ids)
    
    # Update allocation fields
    @membership.allocation_percentage = membership_params[:allocation_percentage] if membership_params[:allocation_percentage].present?
    @membership.start_date = membership_params[:start_date] if membership_params[:start_date].present?
    @membership.end_date = membership_params[:end_date] if membership_params[:end_date].present?
    
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

  def destroy
    if @membership.deletable?
      @membership.destroy
    end
    respond_to do |format|
      format.html {redirect_to_principal @principal}
      format.js
    end
  end

  private

  def find_principal
    principal_id = params[:user_id] || params[:group_id]
    @principal = Principal.find(principal_id)
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def find_membership
    @membership = Member.find(params[:id])
    @principal = @membership.principal
  rescue ActiveRecord::RecordNotFound
    render_404
  end

  def redirect_to_principal(principal)
    redirect_to edit_polymorphic_path(principal, :tab => 'memberships')
  end
end
