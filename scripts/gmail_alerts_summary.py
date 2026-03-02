#!/usr/bin/env python3
"""
Daily Google Alerts summarizer — fetches alerts from Gmail,
extracts article titles/URLs, fetches full PDF where available,
falls back to webpage snippet, summarizes via Claude.
"""

import imaplib
import email
import os
import re
import json
import sys
import io
from email.header import decode_header
from urllib.request import urlopen, Request
from urllib.parse import urlparse, parse_qs, unquote
from bs4 import BeautifulSoup

try:
    from pypdf import PdfReader
    HAS_PYPDF = True
except ImportError:
    HAS_PYPDF = False

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

def get_pdf_url(url):
    """Try to find a PDF URL from a given article URL."""
    # arXiv: convert abs to pdf
    arxiv_abs = re.match(r"https?://arxiv\.org/abs/(\d+\.\d+)", url)
    if arxiv_abs:
        return f"https://arxiv.org/pdf/{arxiv_abs.group(1)}.pdf"

    # arXiv HTML variant
    arxiv_html = re.match(r"https?://arxiv\.org/html/(\d+\.\d+)", url)
    if arxiv_html:
        return f"https://arxiv.org/pdf/{arxiv_html.group(1)}.pdf"

    # Nature: try to get PDF link from page
    if "nature.com" in url or "springer.com" in url or "pmc" in url:
        return None  # will try page scraping for PDF link

    return None

def scrape_pdf_link_from_page(url):
    """Try to find a PDF download link on the article page."""
    try:
        req = Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=8) as resp:
            html = resp.read().decode("utf-8", errors="ignore")
        soup = BeautifulSoup(html, "html.parser")
        for a in soup.find_all("a", href=True):
            href = a["href"]
            text = a.get_text(strip=True).lower()
            if "pdf" in href.lower() or "pdf" in text:
                if href.startswith("http"):
                    return href
                elif href.startswith("/"):
                    parsed = urlparse(url)
                    return f"{parsed.scheme}://{parsed.netloc}{href}"
    except Exception:
        pass
    return None

def fetch_pdf_text(pdf_url, max_chars=4000):
    """Download a PDF and extract its text."""
    if not HAS_PYPDF:
        return None
    try:
        req = Request(pdf_url, headers={"User-Agent": "Mozilla/5.0"})
        with urlopen(req, timeout=15) as resp:
            pdf_data = resp.read()
        reader = PdfReader(io.BytesIO(pdf_data))
        text = ""
        for page in reader.pages:
            text += page.extract_text() or ""
            if len(text) > max_chars:
                break
        text = re.sub(r"\s+", " ", text).strip()
        return text[:max_chars] if text else None
    except Exception as e:
        print(f"    PDF fetch failed ({pdf_url[:60]}): {e}", file=sys.stderr)
        return None

def fetch_webpage_snippet(url, max_chars=1500):
    """Fetch a text snippet from a webpage."""
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

def fetch_best_content(url):
    """Try PDF first, fall back to webpage snippet."""
    # Try direct PDF URL
    pdf_url = get_pdf_url(url)
    if pdf_url:
        print(f"    Trying PDF: {pdf_url[:70]}", file=sys.stderr)
        text = fetch_pdf_text(pdf_url)
        if text:
            return text, "pdf"

    # Try scraping PDF link from page
    pdf_link = scrape_pdf_link_from_page(url)
    if pdf_link:
        print(f"    Found PDF link on page: {pdf_link[:70]}", file=sys.stderr)
        text = fetch_pdf_text(pdf_link)
        if text:
            return text, "pdf"

    # Fall back to webpage
    print(f"    Falling back to webpage snippet", file=sys.stderr)
    return fetch_webpage_snippet(url), "webpage"

def summarize_with_claude(articles_by_topic):
    content_parts = []
    for topic, articles in articles_by_topic.items():
        content_parts.append(f"\n### Topic: {topic}\n")
        for art in articles:
            source_type = art.get("source_type", "webpage")
            content_parts.append(
                f"Title: {art['title']}\n"
                f"URL: {art['url']}\n"
                f"Content source: {source_type}\n"
                f"Content: {art['content']}\n"
            )

    content = "\n".join(content_parts)

    prompt = f"""You are a research assistant. Below are today's Google Alerts articles grouped by topic.
Some articles include full paper text (PDF), others are webpage summaries.

Write a concise but detailed daily digest:
- Start with a brief intro line with today's date
- For each topic, write 3-5 bullet points summarizing key findings, methods, and implications
- For papers with full PDF content, include specific technical details (methods, results, numbers)
- Keep it informative and precise, suitable for a researcher reading on Telegram
- Use emoji bullets to distinguish topics (⚛️ quantum, 🤖 AI/ML, 🔬 science, 💊 medicine, 💰 markets)
- Plain text only, no markdown headers

Articles:
{content}

Write the digest now:"""

    api_key = os.environ.get("ANTHROPIC_API_KEY", "dummy")
    bridge_url = os.environ.get("CLAUDE_API_URL", "http://127.0.0.1:3001/v1/messages")
    payload = {
        "model": "claude-sonnet-4-6",
        "max_tokens": 2048,
        "messages": [{"role": "user", "content": prompt}]
    }
    req = Request(
        bridge_url,
        data=json.dumps(payload).encode(),
        headers={
            "x-api-key": api_key,
            "anthropic-version": "2023-06-01",
            "content-type": "application/json"
        }
    )
    with urlopen(req, timeout=60) as resp:
        result = json.loads(resp.read())
    return result["content"][0]["text"]

def archive_alerts(gmail_address, gmail_password, label="Google Alerts"):
    """Apply label and archive (remove from INBOX) all Google Alerts emails."""
    mail = imaplib.IMAP4_SSL("imap.gmail.com")
    mail.login(gmail_address, gmail_password)
    mail.select("INBOX")

    # Create label if it doesn't exist
    status, existing = mail.list()
    label_exists = any(label.encode() in l for l in existing)
    if not label_exists:
        mail.create(f'"{label}"')
        print(f"  Created label: {label}", file=sys.stderr)

    # Find all Google Alerts in inbox
    status, data = mail.search(None, "FROM", "googlealerts-noreply@google.com")
    ids = data[0].split()
    if not ids:
        mail.logout()
        return 0

    for num in ids:
        # Copy to the label folder
        mail.copy(num, f'"{label}"')
        # Mark as deleted in INBOX (archives it)
        mail.store(num, "+FLAGS", "\\Deleted")

    mail.expunge()
    mail.logout()
    print(f"  Archived {len(ids)} alerts to '{label}'", file=sys.stderr)
    return len(ids)

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
                print(f"  Processing: {art['title'][:65]}", file=sys.stderr)
                content, source_type = fetch_best_content(art["url"])
                art["content"] = content
                art["source_type"] = source_type
                articles_by_topic[topic].append(art)
                existing_urls.add(art["url"])

    mail.logout()

    if not articles_by_topic:
        print("No articles extracted from alerts.")
        return

    print("Summarizing with Claude...", file=sys.stderr)
    summary = summarize_with_claude(articles_by_topic)
    print(summary)

    # Archive processed alerts
    print("Archiving alerts...", file=sys.stderr)
    archive_alerts(gmail_address, gmail_password)

if __name__ == "__main__":
    main()

