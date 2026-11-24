require_relative '../test_helper'

class MembersNewFormTest < Redmine::ControllerTest
  tests MembersController
  include B4sAllocation::TestHelpers

  fixtures :roles, :users, :email_addresses, :enumerations, :user_preferences

  def test_new_member_form_lists_users_as_radios_with_availability
    @request.session[:user_id] = 1
    project = create_project!('PROJ-NF')
    user = create_user!('nf_user')
    add_member!(create_project!('PROJ-NF2'), user, 70)
    get :new, params: {project_id: project.id}, xhr: true
    assert_response :success
    assert_include "membership[user_id]", response.body
    assert_include "nf_user Test (30.0%)", response.body
  end
end
