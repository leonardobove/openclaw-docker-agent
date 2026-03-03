#!/bin/bash
export GMAIL_ADDRESS="leonardo.bove01@gmail.com"
export GMAIL_APP_PASSWORD="dzsb nbbc hlkd xybs"
export ANTHROPIC_API_KEY="$(grep ANTHROPIC_API_KEY /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep ANTHROPIC | cut -d= -f2-)"
export TELEGRAM_BOT_TOKEN="$(grep TELEGRAM_BOT_TOKEN /proc/1/environ 2>/dev/null | tr '\0' '\n' | grep TELEGRAM | cut -d= -f2-)"
export TELEGRAM_CHAT_ID="5858268203"
python3 /home/openclaw/repo/scripts/gmail_alerts_summarizer.py >> /tmp/gmail_alerts.log 2>&1
