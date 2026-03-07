from celery.schedules import crontab

CELERY_BEAT_SCHEDULE: dict = {
    "invoice-chaser-daily": {
        "task": "app.workers.tasks.run_invoice_chaser_all",
        "schedule": crontab(hour=9, minute=0),
        "description": "Chase overdue invoices every day at 9am",
    },
    "appointment-reminder-daily": {
        "task": "app.workers.tasks.run_appointment_reminder_all",
        "schedule": crontab(hour=7, minute=0),
        "description": "Send appointment reminders at 7am",
    },
    "review-requester-daily": {
        "task": "app.workers.tasks.run_review_requester_all",
        "schedule": crontab(hour=11, minute=0),
        "description": "Request reviews at 11am",
    },
    "daily-summary": {
        "task": "app.workers.tasks.run_daily_summary_all",
        "schedule": crontab(hour=18, minute=0),
        "description": "Send daily summary at 6pm",
    },
    "quote-follow-up-daily": {
        "task": "app.workers.tasks.run_quote_follow_up_all",
        "schedule": crontab(hour=10, minute=0),
        "description": "Follow up on quotes at 10am",
    },
}
