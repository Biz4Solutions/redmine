$(document).ready(function() {
  // Initialize form if project is selected
  var projectId = $('#time_entry_project_id').val();
  if (projectId) {
    updateTimeEntryForm(projectId);
  }
  
  // Initialize autocomplete for issue field
  if ($('#time_entry_issue_id').length) {
    observeAutocompleteField('time_entry_issue_id', $('#time_entry_issue_id').data('autocomplete-url'));
  }
  
  // Add confirmation dialog for time entry deletion
  $('.time-entry .icon-del').on('click', function(e) {
    if (!confirm($(this).data('confirm'))) {
      e.preventDefault();
    }
  });
}); 