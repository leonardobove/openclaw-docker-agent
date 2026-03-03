#!/bin/bash
# Set up cron job for Gmail alerts summarizer
echo "0 8 * * * openclaw python3 /home/openclaw/repo/scripts/gmail_alerts_summarizer.py >> /tmp/gmail_alerts.log 2>&1" > /etc/cron.d/gmail-alerts
chmod 644 /etc/cron.d/gmail-alerts
service cron start || cron
