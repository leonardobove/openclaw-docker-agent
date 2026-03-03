#!/usr/bin/env python3
"""
Gmail Google Alerts Summarizer
--------------------------------
- Connects to Gmail via IMAP (app password)
- Finds unread emails from Google Alerts
- Extracts links to papers/PDFs
- Downloads PDFs and extracts text, or scrapes abstracts from web pages
- Summarizes each paper using Claude (Anthropic API)
- Sends a Telegram digest
- Labels emails as "Google Alerts/Processed" and archives them

Requirements:
    pip install --user google-api-python-client google-auth-httplib2 google-auth-oauthlib \
                        anthropic requests pdfplumber beautifulsoup4 lxml

Usage:
    python3 gmail_alerts_summarizer.py
"""

import imaplib
import email
import re
import os
import json
import logging
import urllib.request
import urllib.parse
import io
import time
from email.header import decode_header

# ── Logging ──────────────────────────────────────────────────────────────────
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
)
log = logging.getLogger(__name__)

# ── Config ───────────────────────────────────────────────────────────────────
GMAIL_ADDRESS      = os.environ.get("GMAIL_ADDRESS", "leonardo.bove01@gmail.com")
GMAIL_APP_PASSWORD = os.environ.get("GMAIL_APP_PASSWORD", "dzsb nbbc hlkd xybs")
ANTHROPIC_API_KEY  = os.environ.get("ANTHROPIC_API_KEY", "")
TELEGRAM_BOT_TOKEN = os.environ.get("TELEGRAM_BOT_TOKEN", "")
TELEGRAM_CHAT_ID   = os.environ.get("TELEGRAM_CHAT_ID", "5858268203")

ALERTS_SENDER      = "googlealerts-noreply@google.com"
LABEL_PROCESSED    = "Google Alerts/Processed"
MAX_PDF_BYTES      = 5 * 1024 * 1024   # 5 MB
MAX_TEXT_CHARS     = 8000              # chars sent to Claude per paper
MAX_PAPERS         = 10               # cap per run


# ── Telegram ─────────────────────────────────────────────────────────────────
def send_telegram(text: str):
    if not TELEGRAM_BOT_TOKEN:
        log.warning("No TELEGRAM_BOT_TOKEN — skipping Telegram send")
        print(text)
        return
    chunks = [text[i:i+4000] for i in range(0, len(text), 4000)]
    for chunk in chunks:
        payload = json.dumps({
            "chat_id":    TELEGRAM_CHAT_ID,
            "text":       chunk,
            "parse_mode": "Markdown",
        }).encode()
        url = f"https://api.telegram.org/bot{TELEGRAM_BOT_TOKEN}/sendMessage"
        try:
            req = urllib.request.Request(
                url, data=payload,
                headers={"Content-Type": "application/json"},
                method="POST",
            )
            urllib.request.urlopen(req, timeout=15)
        except Exception as e:
            log.error(f"Telegram send failed: {e}")
        time.sleep(0.5)


# ── Claude summarizer ─────────────────────────────────────────────────────────
def summarize_with_claude(title: str, text: str) -> str:
    if not ANTHROPIC_API_KEY:
        return "(No ANTHROPIC_API_KEY set — skipping summary)"
    try:
        import anthropic
        client = anthropic.Anthropic(api_key=ANTHROPIC_API_KEY)
        prompt = (
            f"You are a scientific paper summarizer. "
            f"Summarize the following paper in 3-5 concise sentences, "
            f"highlighting the main finding, method, and significance.\n\n"
            f"Title: {title}\n\n"
            f"Content:\n{text[:MAX_TEXT_CHARS]}"
        )
        message = client.messages.create(
            model="claude-haiku-4-5-20251001",
            max_tokens=300,
            messages=[{"role": "user", "content": prompt}]
        )
        return message.content[0].text.strip()
    except Exception as e:
        log.error(f"Claude summarization failed: {e}")
        return f"(Summarization failed: {e})"


# ── PDF extraction ────────────────────────────────────────────────────────────
def extract_pdf_text(url: str) -> str:
    try:
        import pdfplumber
        log.info(f"Downloading PDF: {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = resp.read(MAX_PDF_BYTES)
        with pdfplumber.open(io.BytesIO(data)) as pdf:
            text = "\n".join(
                page.extract_text() or "" for page in pdf.pages[:10]
            )
        return text.strip()
    except Exception as e:
        log.warning(f"PDF extraction failed for {url}: {e}")
        return ""


# ── Web page extraction ───────────────────────────────────────────────────────
def extract_page_text(url: str) -> tuple[str, str]:
    """Returns (title, text)."""
    try:
        from bs4 import BeautifulSoup
        log.info(f"Fetching page: {url}")
        req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
        with urllib.request.urlopen(req, timeout=20) as resp:
            html = resp.read(500_000).decode("utf-8", errors="replace")
        soup = BeautifulSoup(html, "lxml")
        title = soup.title.string.strip() if soup.title else url

        # Try to get abstract or main content
        for selector in [
            ("div", {"id": "abstract"}),
            ("section", {"class": re.compile(r"abstract", re.I)}),
            ("div", {"class": re.compile(r"abstract", re.I)}),
            ("p", {"class": re.compile(r"abstract", re.I)}),
            ("article", {}),
            ("main", {}),
        ]:
            tag, attrs = selector
            el = soup.find(tag, attrs)
            if el:
                text = el.get_text(separator=" ", strip=True)
                if len(text) > 200:
                    return title, text
        # fallback: all paragraphs
        paras = soup.find_all("p")
        text = " ".join(p.get_text(strip=True) for p in paras)
        return title, text
    except Exception as e:
        log.warning(f"Page extraction failed for {url}: {e}")
        return url, ""


# ── URL helpers ───────────────────────────────────────────────────────────────
PAPER_PATTERNS = [
    r"arxiv\.org",
    r"pubmed\.ncbi",
    r"doi\.org",
    r"researchgate\.net",
    r"semanticscholar\.org",
    r"biorxiv\.org",
    r"medrxiv\.org",
    r"nature\.com",
    r"science\.org",
    r"cell\.com",
    r"springer\.com",
    r"wiley\.com",
    r"plos\.org",
    r"frontiersin\.org",
    r"mdpi\.com",
    r"\.pdf($|\?)",
]

def is_paper_url(url: str) -> bool:
    return any(re.search(p, url, re.I) for p in PAPER_PATTERNS)

def is_pdf_url(url: str) -> bool:
    return bool(re.search(r"\.pdf($|\?)", url, re.I)) or "arxiv.org/pdf" in url

def extract_urls(text: str) -> list[str]:
    return re.findall(r"https?://[^\s<>\"']+", text)

def resolve_google_redirect(url: str) -> str:
    """Unwrap Google alert redirect URLs."""
    if "google.com/url" in url or "google.com/alerts/preview" in url:
        parsed = urllib.parse.urlparse(url)
        params = urllib.parse.parse_qs(parsed.query)
        if "url" in params:
            return params["url"][0]
        if "q" in params:
            return params["q"][0]
    return url


# ── IMAP helpers ──────────────────────────────────────────────────────────────
def imap_connect():
    log.info("Connecting to Gmail IMAP...")
    mail = imaplib.IMAP4_SSL("imap.gmail.com")
    mail.login(GMAIL_ADDRESS, GMAIL_APP_PASSWORD)
    return mail

def get_email_body(msg) -> str:
    body = ""
    if msg.is_multipart():
        for part in msg.walk():
            ct = part.get_content_type()
            if ct in ("text/plain", "text/html"):
                try:
                    body += part.get_payload(decode=True).decode("utf-8", errors="replace")
                except Exception:
                    pass
    else:
        try:
            body = msg.get_payload(decode=True).decode("utf-8", errors="replace")
        except Exception:
            pass
    return body

def ensure_label(mail, label: str):
    """Create the label if it doesn't exist."""
    parts = label.split("/")
    for i in range(1, len(parts) + 1):
        partial = "/".join(parts[:i])
        try:
            mail.create(f'"{partial}"')
        except Exception:
            pass  # already exists

def label_and_archive(mail, uid: bytes, label: str):
    """Apply label and remove from INBOX."""
    try:
        mail.uid("COPY", uid, f'"{label}"')
        mail.uid("STORE", uid, "+FLAGS", "\\Deleted")
        mail.expunge()
        log.info(f"Labelled and archived message {uid}")
    except Exception as e:
        log.error(f"Failed to label/archive {uid}: {e}")


# ── Main ──────────────────────────────────────────────────────────────────────
def main():
    send_telegram("📬 *Google Alerts Summarizer started* — fetching your emails...")

    mail = imap_connect()
    mail.select("INBOX")

    # Search for unread Google Alerts emails
    _, data = mail.uid("SEARCH", None, f'(UNSEEN FROM "{ALERTS_SENDER}")')
    uids = data[0].split()
    log.info(f"Found {len(uids)} unread Google Alerts email(s)")

    if not uids:
        send_telegram("✅ No new Google Alerts emails found.")
        mail.logout()
        return

    send_telegram(f"📧 Found *{len(uids)}* Google Alerts email(s) — processing...")

    ensure_label(mail, LABEL_PROCESSED)

    all_summaries = []
    processed_uids = []
    paper_count = 0

    for uid in uids:
        if paper_count >= MAX_PAPERS:
            break

        # Fetch email
        _, msg_data = mail.uid("FETCH", uid, "(RFC822)")
        raw = msg_data[0][1]
        msg = email.message_from_bytes(raw)

        subject_raw = msg.get("Subject", "No Subject")
        subject, enc = decode_header(subject_raw)[0]
        if isinstance(subject, bytes):
            subject = subject.decode(enc or "utf-8", errors="replace")

        log.info(f"Processing: {subject}")
        body = get_email_body(msg)

        # Extract URLs
        urls = extract_urls(body)
        resolved = [resolve_google_redirect(u) for u in urls]
        paper_urls = [u for u in resolved if is_paper_url(u)]

        log.info(f"  Found {len(paper_urls)} paper URL(s)")

        email_summaries = []
        for url in paper_urls[:3]:  # max 3 papers per alert email
            if paper_count >= MAX_PAPERS:
                break
            paper_count += 1

            if is_pdf_url(url):
                text = extract_pdf_text(url)
                title = url.split("/")[-1] or url
            else:
                title, text = extract_page_text(url)

            if not text or len(text) < 100:
                log.warning(f"  Insufficient text from {url} — skipping")
                continue

            log.info(f"  Summarizing: {title[:60]}")
            summary = summarize_with_claude(title, text)
            email_summaries.append(f"📄 *{title[:100]}*\n{summary}\n🔗 {url}")

        if email_summaries:
            all_summaries.append(f"*Alert: {subject}*\n\n" + "\n\n---\n\n".join(email_summaries))

        processed_uids.append(uid)

    # Send digest
    if all_summaries:
        digest = f"🧬 *Daily Science Digest — {paper_count} paper(s)*\n\n" + "\n\n═══════════════\n\n".join(all_summaries)
        send_telegram(digest)
    else:
        send_telegram("ℹ️ Google Alerts emails were found but no paper links could be extracted.")

    # Label and archive processed emails
    for uid in processed_uids:
        label_and_archive(mail, uid, LABEL_PROCESSED)

    mail.logout()
    send_telegram(f"✅ Done! Processed *{len(processed_uids)}* alert email(s), found *{paper_count}* paper(s).")
    log.info("Done.")


if __name__ == "__main__":
    main()
