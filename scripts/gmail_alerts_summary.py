#!/usr/bin/env python3
"""
Daily Google Alerts summarizer — fetches alerts from Gmail,
extracts article titles/URLs, fetches snippets, summarizes via Claude.
"""

import imaplib
import email
import os
import re
import json
import sys
from email.header import decode_header
from urllib.request import urlopen, Request
from urllib.parse import urlparse, parse_qs, unquote
from bs4 import BeautifulSoup

def load_env():
    env_path = os.path.join(os.path.dirname(__file__), "../config/gmail.env")
    if os.path.exists(env_path):
        with open(env_path) as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#") and "=" in line:
                    k, v = line.split("=", 1)
                    os.environ[k.strip()] = v.strip()

def decode_google_url(url):
    try:
        parsed = urlparse(url)
        qs = parse_qs(parsed.query)
        if "url" in qs:
            return unquote(qs["url"][0])
    except Exception:
        pass
    return url

def fetch_articles_from_alert(msg):
    articles = []
    for part in msg.walk():
        if part.get_content_type() == "text/html":
            html = part.get_payload(decode=True).decode("utf-8", errors="ignore")
            soup = BeautifulSoup(html, "html.parser")
            for a in soup.find_all("a", href=True):
                title = a.get_text(strip=True)
                href = a["href"]
                if (title and len(title) > 20
                        and "google.com/alerts" not in href
                        and "http" in href):
                    real_url = decode_google_url(href)
                    articles.append({"title": title, "url": real_url})
            break
    return articles

def fetch_snippet(url, max_chars=800):
    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=8) as resp:
            html = resp.read().decode("utf-8", errors="ignore")
        soup = BeautifulSoup(html, "html.parser")
        for tag in soup(["script", "style", "nav", "footer", "header"]):
            tag.decompose()
        text = soup.get_text(separator=" ", strip=True)
        text = re.sub(r"\s+", " ", text)
        return text[:max_chars]
    except Exception as e:
        return f"[Could not fetch: {e}]"

def summarize_with_claude(articles_by_topic):
    content_parts = []
    for topic, articles in articles_by_topic.items():
        content_parts.append(f"\n### Topic: {topic}\n")
        for art in articles:
            content_parts.append(f"Title: {art['title']}\nURL: {art['url']}\nSnippet: {art['snippet']}\n")

    content = "\n".join(content_parts)

    prompt = f"""You are a research assistant. Below are today's Google Alerts articles grouped by topic.

Write a concise daily digest:
- Start with a brief intro line with today's date
- For each topic, write 2-4 bullet points summarizing key news/findings
- Keep it informative but brief, suitable for a Telegram message
- Use emoji bullets to distinguish topics (e.g. ⚛️ for quantum, 🤖 for AI)
- Plain text only, no markdown headers

Articles:
{content}

Write the digest now:"""

    api_key = os.environ.get("ANTHROPIC_API_KEY", "")
    payload = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 1024,
        "messages": [{"role": "user", "content": prompt}]
    }
    req = Request(
        "https://api.anthropic.com/v1/messages",
        data=json.dumps(payload).encode(),
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
    )
    with urlopen(req, timeout=30) as resp:
        result = json.loads(resp.read())
    return result["content"][0]["text"]

def main():
    load_env()
    gmail_address = os.environ.get("GMAIL_ADDRESS", "")
    gmail_password = os.environ.get("GMAIL_APP_PASSWORD", "")

    print("Connecting to Gmail...", file=sys.stderr)
    mail = imaplib.IMAP4_SSL("imap.gmail.com")
    mail.login(gmail_address, gmail_password)
    mail.select("INBOX")

    status, data = mail.search(None, "FROM", "googlealerts-noreply@google.com")
    ids = data[0].split()

    if not ids:
        print("No Google Alerts found.")
        return

    print(f"Found {len(ids)} alert emails", file=sys.stderr)

    articles_by_topic = {}

    for num in ids:
        status, msg_data = mail.fetch(num, "(RFC822)")
        msg = email.message_from_bytes(msg_data[0][1])

        subject_raw, enc = decode_header(msg["Subject"])[0]
        if isinstance(subject_raw, bytes):
            subject = subject_raw.decode(enc or "utf-8")
        else:
            subject = subject_raw

        topic = subject.replace("Google Alert - ", "").strip()
        articles = fetch_articles_from_alert(msg)
        if not articles:
            continue

        if topic not in articles_by_topic:
            articles_by_topic[topic] = []

        existing_urls = {a["url"] for a in articles_by_topic[topic]}
        for art in articles[:3]:
            if art["url"] not in existing_urls:
                print(f"  Fetching snippet: {art['title'][:60]}", file=sys.stderr)
                art["snippet"] = fetch_snippet(art["url"])
                articles_by_topic[topic].append(art)
                existing_urls.add(art["url"])

    mail.logout()

    if not articles_by_topic:
        print("No articles extracted from alerts.")
        return

    print("Summarizing with Claude...", file=sys.stderr)
    summary = summarize_with_claude(articles_by_topic)
    print(summary)

if __name__ == "__main__":
    main()
