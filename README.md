## Timesheet Approval Workflow

The timesheet approval workflow allows project managers to approve or reject time entries submitted by team members.

### Features

- Time entries require approval before they are considered final
- Project managers can approve or reject individual time entries
- Bulk approval/rejection of multiple time entries
- Rejection requires providing a reason
- Email notifications for submission, approval, and rejection
- API support for the approval workflow

### Permissions

- The `approve_time_entries` permission is required to approve or reject time entries
- By default, this permission is assigned to the Manager role
- Users cannot approve their own time entries

### Email Notifications

The system sends email notifications for the following events:

1. When a time entry is submitted and needs approval
2. When a time entry is approved
3. When a time entry is rejected (with rejection reason)
4. Reminder emails for pending approvals

### Setting up Reminder Emails

To set up automatic reminder emails for pending time entries, add the following to your crontab:

```
# Send timesheet approval reminders every day at 9:00 AM
0 9 * * * cd /path/to/redmine && bundle exec rake redmine:timesheet_approval:send_reminders RAILS_ENV=production
```

You can adjust the frequency as needed. 