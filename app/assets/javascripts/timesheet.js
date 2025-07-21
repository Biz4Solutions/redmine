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

  // Enhanced Monday-only date picker for timesheet start date
  setupMondayOnlyDatePicker();
});

// Function to setup Monday-only date picker with enhanced UX
function setupMondayOnlyDatePicker() {
  var startDateField = document.getElementById('timesheet_start_date');
  
  if (startDateField) {
    // Add CSS to style Monday-only date picker
    var style = document.createElement('style');
    style.textContent = `
      .monday-date-picker {
        position: relative;
        display: inline-block;
      }
      
      .monday-date-picker input[type="date"]::-webkit-calendar-picker-indicator {
        cursor: pointer;
        filter: opacity(0.8);
      }
      
      .monday-date-picker input[type="date"]:hover::-webkit-calendar-picker-indicator {
        filter: opacity(1);
      }
      
      .monday-only-hint {
        position: absolute;
        top: 100%;
        left: 0;
        right: 0;
        background: linear-gradient(45deg, #f8f9fa, #e9ecef);
        border: 1px solid #dee2e6;
        border-radius: 4px;
        padding: 8px 10px;
        font-size: 11px;
        color: #495057;
        margin-top: 4px;
        z-index: 10;
        box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        text-align: center;
      }
      
      .monday-only-hint::before {
        content: '📅';
        margin-right: 6px;
      }
      
      .date-picker-success {
        background-color: #d4edda !important;
        border-color: #c3e6cb !important;
        transition: all 0.3s ease;
      }
    `;
    document.head.appendChild(style);

    // Wrap the date field
    var wrapper = document.createElement('div');
    wrapper.className = 'monday-date-picker';
    startDateField.parentNode.insertBefore(wrapper, startDateField);
    wrapper.appendChild(startDateField);

    // Add helpful hint
    var hint = document.createElement('div');
    hint.className = 'monday-only-hint';
    hint.textContent = 'Click to select a Monday - your timesheet will span Monday to Sunday';
    wrapper.appendChild(hint);

    // Enhanced date selection handling
    startDateField.addEventListener('change', function(e) {
      if (e.target.value) {
        var selectedDate = new Date(e.target.value);
        
        if (selectedDate.getDay() !== 1) {
          // Calculate nearest Mondays
          var nextMonday = new Date(selectedDate);
          var daysUntilMonday = (8 - selectedDate.getDay()) % 7;
          if (daysUntilMonday === 0) daysUntilMonday = 7;
          nextMonday.setDate(selectedDate.getDate() + daysUntilMonday);
          
          var prevMonday = new Date(selectedDate);
          var daysSincePrevMonday = selectedDate.getDay() === 0 ? 1 : selectedDate.getDay() - 1;
          prevMonday.setDate(selectedDate.getDate() - daysSincePrevMonday);
          
          // Create date selection modal
          var modal = createDateSelectionModal(prevMonday, nextMonday, function(selectedMonday) {
            var formatted = selectedMonday.getFullYear() + '-' + 
                          String(selectedMonday.getMonth() + 1).padStart(2, '0') + '-' + 
                          String(selectedMonday.getDate()).padStart(2, '0');
            e.target.value = formatted;
            e.target.classList.add('date-picker-success');
            setTimeout(function() {
              e.target.classList.remove('date-picker-success');
            }, 1500);
            // Trigger end date population
            e.target.dispatchEvent(new Event('change'));
          });
          
          document.body.appendChild(modal);
        }
      }
    });

    // Hide hint on focus, show on blur
    startDateField.addEventListener('focus', function() {
      hint.style.opacity = '0';
      hint.style.transform = 'translateY(-10px)';
      hint.style.transition = 'all 0.3s ease';
    });

    startDateField.addEventListener('blur', function() {
      setTimeout(function() {
        hint.style.opacity = '1';
        hint.style.transform = 'translateY(0)';
      }, 100);
    });
  }
}

// Create a nice modal for date selection
function createDateSelectionModal(prevMonday, nextMonday, onSelect) {
  var overlay = document.createElement('div');
  overlay.style.cssText = `
    position: fixed;
    top: 0;
    left: 0;
    width: 100%;
    height: 100%;
    background: rgba(0,0,0,0.5);
    z-index: 10000;
    display: flex;
    justify-content: center;
    align-items: center;
  `;

  var modal = document.createElement('div');
  modal.style.cssText = `
    background: white;
    border-radius: 8px;
    padding: 24px;
    max-width: 400px;
    width: 90%;
    box-shadow: 0 8px 32px rgba(0,0,0,0.2);
    text-align: center;
  `;

  modal.innerHTML = `
    <h3 style="margin: 0 0 16px 0; color: #333;">📅 Select a Monday</h3>
    <p style="margin: 0 0 24px 0; color: #666; line-height: 1.4;">
      Timesheets must start on Monday. Choose from the nearest options:
    </p>
    <div style="display: flex; gap: 12px; justify-content: center; flex-wrap: wrap;">
      <button id="prevMondayBtn" style="
        background: #f8f9fa;
        border: 2px solid #dee2e6;
        border-radius: 6px;
        padding: 12px 16px;
        cursor: pointer;
        transition: all 0.2s;
        min-width: 120px;
      ">
        <div style="font-weight: 600; color: #495057;">Previous</div>
        <div style="font-size: 14px; color: #6c757d;">${prevMonday.toLocaleDateString()}</div>
      </button>
      <button id="nextMondayBtn" style="
        background: #007cba;
        border: 2px solid #007cba;
        color: white;
        border-radius: 6px;
        padding: 12px 16px;
        cursor: pointer;
        transition: all 0.2s;
        min-width: 120px;
      ">
        <div style="font-weight: 600;">Next</div>
        <div style="font-size: 14px; opacity: 0.9;">${nextMonday.toLocaleDateString()}</div>
      </button>
    </div>
    <button id="cancelBtn" style="
      background: none;
      border: none;
      color: #6c757d;
      cursor: pointer;
      margin-top: 16px;
      padding: 8px;
      font-size: 14px;
    ">Cancel</button>
  `;

  overlay.appendChild(modal);

  // Add button interactions
  var prevBtn = modal.querySelector('#prevMondayBtn');
  var nextBtn = modal.querySelector('#nextMondayBtn');
  var cancelBtn = modal.querySelector('#cancelBtn');

  prevBtn.addEventListener('mouseenter', function() {
    this.style.background = '#e9ecef';
    this.style.borderColor = '#adb5bd';
  });
  prevBtn.addEventListener('mouseleave', function() {
    this.style.background = '#f8f9fa';
    this.style.borderColor = '#dee2e6';
  });

  nextBtn.addEventListener('mouseenter', function() {
    this.style.background = '#0056b3';
  });
  nextBtn.addEventListener('mouseleave', function() {
    this.style.background = '#007cba';
  });

  prevBtn.addEventListener('click', function() {
    onSelect(prevMonday);
    document.body.removeChild(overlay);
  });

  nextBtn.addEventListener('click', function() {
    onSelect(nextMonday);
    document.body.removeChild(overlay);
  });

  cancelBtn.addEventListener('click', function() {
    document.body.removeChild(overlay);
  });

  overlay.addEventListener('click', function(e) {
    if (e.target === overlay) {
      document.body.removeChild(overlay);
    }
  });

  return overlay;
} 