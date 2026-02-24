# Web Content Archiver

A Rails API that archives web pages with their full asset content. When a URL is
submitted, the application fetches the page, uploads every referenced asset
(CSS, JavaScript, images, fonts) to S3 (or local disk in development), rewrites
all asset URLs to their storage locations, and recursively inlines iframe content
— producing a fully self-contained HTML snapshot.

---

## Table of Contents

- [Tech Stack](#tech-stack)
- [Architecture Overview](#architecture-overview)
- [Setup](#setup)
- [Running the Application](#running-the-application)
- [API Reference](#api-reference)
- [Running the Test Suite](#running-the-test-suite)
- [Design Decisions](#design-decisions)
- [Known Limitations & Future Work (ShadowDomCapturer)](#known-limitations--future-work)

---

## Tech Stack

| Layer | Technology |
|---|---|
| Framework | Rails 8.1 (API mode) |
| Language | Ruby 3.4 |
| Database | PostgreSQL |
| Background jobs | Sidekiq 7 |
| Job queue broker | Redis |
| Distributed locking | Redlock (Redis-backed) |
| HTTP client | HTTParty + Addressable |
| HTML parsing | Nokogiri |
| Asset storage | AWS S3 (production) / local filesystem (development) |
| Concurrency | Ruby threads + `concurrent-ruby` |

---

## Architecture Overview

```
POST /api/v1/archives
        │
        ▼
ArchivesController
  ├── DistributedLock.acquire   (prevent duplicate URL race)
  ├── Archive.create!            (persist with :pending status)
  └── ArchiveProcessorJob.perform_later(archive.id)
              │
              ▼
      ArchiveProcessorJob  (Sidekiq worker)
        │
        ├─ 1. HtmlFetcher.call(url)
        │       └── HTTParty GET with retry + exponential backoff
        │
        ├─ 2. ResourceExtractor.call(html, base_url:)
        │       └── Nokogiri — extracts CSS, JS, images, fonts, srcsets
        │
        ├─ 3. ParallelResourceFetcher.call(resources)
        │       └── Ruby threads, DomainRateLimiter (max 5/domain)
        │
        ├─ 4. upload_assets  →  Storage::AdapterFactory (S3 or Local)
        │       └── Archive.increment_counter(:resources_count)  ← atomic
        │
        ├─ 5. IframeProcessor.call(html, ...)
        │       └── Recursive: fetch iframe → extract → upload → rewrite
        │           → inline as srcdoc  (capped at depth 3)
        │
        └─ 6. UrlRewriter.call(html, mapping)
                └── Nokogiri — rewrites src/href/srcset/style url(...)
```

### Service objects

Every unit of work follows the `ServiceClass.call(...)` pattern for clear
single-responsibility boundaries:

| Service | Responsibility |
|---|---|
| `HtmlFetcher` | Fetch a page's raw HTML with redirect following and retry |
| `ResourceExtractor` | Parse HTML and return all external asset URLs with types |
| `ResourceFetcher` | Fetch a single binary asset (CSS, image, font, …) |
| `ParallelResourceFetcher` | Coordinate parallel asset fetching with rate limiting |
| `DomainRateLimiter` | Cap concurrent requests per domain (mutex + condition variable) |
| `UrlRewriter` | Rewrite asset URLs in HTML to storage URLs |
| `IframeProcessor` | Recursively inline iframe content as srcdoc |
| `DistributedLock` | Redis-backed Redlock for cross-process mutual exclusion |
| `Storage::LocalAdapter` | Write/read assets from the local filesystem |
| `Storage::S3Adapter` | Upload/read assets from AWS S3 |
| `Storage::AdapterFactory` | Select the correct adapter via `STORAGE_ADAPTER` env var |

---

## Setup

### Prerequisites

- Ruby 3.4
- PostgreSQL 14+
- Redis 7+

### 1. Install dependencies

```bash
bundle install
```

### 2. Configure environment variables

Copy and fill in the required values:

```bash
cp .env.example .env   # if present, or set manually
```

| Variable | Default | Description |
|---|---|---|
| `DATABASE_URL` | _(from database.yml)_ | PostgreSQL connection string |
| `REDIS_URL` | `redis://localhost:6379/1` | Redis connection for Sidekiq and locks |
| `STORAGE_ADAPTER` | `local` | `local` or `s3` |
| `LOCAL_STORAGE_PATH` | `tmp/storage` | Root path for local adapter |
| `AWS_ACCESS_KEY_ID` | — | Required when `STORAGE_ADAPTER=s3` |
| `AWS_SECRET_ACCESS_KEY` | — | Required when `STORAGE_ADAPTER=s3` |
| `AWS_REGION` | — | Required when `STORAGE_ADAPTER=s3` |
| `S3_BUCKET` | — | Required when `STORAGE_ADAPTER=s3` |

### 3. Create and migrate the database

```bash
bin/rails db:create db:migrate
```

---

## Running the Application

Start all three processes (Rails, Sidekiq, Redis must already be running):

```bash
# Terminal 1 — Rails API server
bin/rails server

# Terminal 2 — Sidekiq worker
bundle exec sidekiq

# Terminal 3 — Redis (if not running as a system service)
redis-server
```

A Sidekiq Web UI is available at `http://localhost:3000/sidekiq` in development.

---

## API Reference

### Create an archive

```
POST /api/v1/archives
Content-Type: application/json

{ "url": "https://example.com" }
```

**Response `201 Created`**
```json
{
  "id": 1,
  "url": "https://example.com",
  "status": "pending"
}
```

The archive is processed asynchronously. Poll the status endpoint until
`status` is `"completed"` or `"failed"`.

**Response `200 OK`** — returned when the URL was already archived.

**Response `503 Service Unavailable`** — returned when a distributed lock could
not be acquired (another process is already handling the same URL right now).

---

### Get archive status

```
GET /api/v1/archives/:id
```

**Response `200 OK`**
```json
{
  "id": 1,
  "url": "https://example.com",
  "status": "completed",
  "resources_count": 14,
  "content": "<html>…fully rewritten HTML…</html>"
}
```

Possible `status` values: `pending` · `processing` · `completed` · `failed`

---

## Running the Test Suite

```bash
# Full suite
bundle exec rspec

# Single file
bundle exec rspec spec/services/iframe_processor_spec.rb

# With documentation format
bundle exec rspec --format documentation
```

The suite uses:
- **RSpec** for test structure
- **FactoryBot** for test data
- **Shoulda Matchers** for model validations
- **WebMock** for HTTP stubbing (no real network calls)
- **ActiveJob::TestAdapter** so jobs never touch Redis in tests

---

## Design Decisions

### Duplicate URL prevention

Two layers guard against concurrent `POST /api/v1/archives` requests for the
same URL:

1. **Database unique index** on `archives.url` — the last line of defence,
   raises `ActiveRecord::RecordNotUnique` if anything slips through.
2. **Redis distributed lock** (`DistributedLock` / Redlock) wrapping the
   check-then-create block in the controller — prevents the race window between
   the `find_by` check and the `save`.

### Atomic status transitions

`ArchiveProcessorJob` never calls `archive.update!` directly. Instead it uses
conditional `update_all`:

```ruby
Archive.where(id: id, status: :pending).update_all(status: :processing)
```

Only the worker whose `WHERE` clause matches will write; all others get
`rows_updated == 0` and exit cleanly. This eliminates both duplicate-processing
and lost-update races without needing application-level locks.

### Atomic resource counter

`Archive.increment_counter(:resources_count, archive.id)` issues a single
`UPDATE … SET resources_count = resources_count + 1` statement. Multiple
threads uploading assets for the same archive never lose a count because there
is no read-modify-write cycle at the application layer.

### In-process domain rate limiting

`DomainRateLimiter` uses a Ruby `Mutex` + `ConditionVariable` to cap concurrent
requests per domain at 5. This is intentionally in-process for simplicity.
In a multi-process deployment a Redis-backed token bucket (e.g. `redis-throttle`
or `rack-attack`) would be the production-grade choice.

### Retry with exponential backoff

The `Retryable` concern (included by `HtmlFetcher` and `ResourceFetcher`)
retries transient errors with jittered exponential backoff. Sidekiq's own retry
policy (`retry: 3`) provides a second layer at the job level.

### Storage adapter pattern

`Storage::AdapterFactory.build` returns either `LocalAdapter` or `S3Adapter`
based on the `STORAGE_ADAPTER` environment variable. Both share the `Storage::Base`
interface (`upload`, `url_for`), so the rest of the application is oblivious to
where assets land.

---

## Known Limitations & Future Work

### Shadow DOM support

Shadow DOM content is attached to the live DOM by JavaScript at runtime. Nokogiri
parses static HTML and never sees it, so the current pipeline silently omits any
content rendered inside a shadow root.

**Planned approach — `ShadowDomCapturer` service using Ferrum**

[Ferrum](https://github.com/rubycdp/ferrum) is a pure-Ruby CDP (Chrome DevTools
Protocol) client that drives a real headless Chrome/Chromium process. The service
would:

1. Open the target URL in a Ferrum browser page (full JavaScript execution).
2. After `DOMContentLoaded`, evaluate a JavaScript snippet that walks every
   element in the document, checks for a `shadowRoot`, and serialises its
   `innerHTML` back as a visible `<div data-shadow-host="…">` wrapper injected
   adjacent to the host element.

```javascript
// Injected via Ferrum page.evaluate(...)
(function pierceAll(root) {
  root.querySelectorAll('*').forEach(el => {
    if (el.shadowRoot) {
      const wrapper = document.createElement('div');
      wrapper.setAttribute('data-shadow-host', el.tagName.toLowerCase());
      wrapper.innerHTML = el.shadowRoot.innerHTML;
      el.insertAdjacentElement('afterend', wrapper);
      pierceAll(el.shadowRoot); // recurse into nested shadow roots
    }
  });
})(document);
```

3. Retrieve the fully enriched `document.documentElement.outerHTML` and hand it
   to the existing `ResourceExtractor → ParallelResourceFetcher → UrlRewriter`
   pipeline unchanged.

**Integration point in the job:**

```ruby
# Step 1 (replaces plain HtmlFetcher when shadow DOM capture is enabled)
html     = ShadowDomCapturer.call(@archive.url)   # Ferrum-based
base_url = @archive.url

# Steps 2-6 remain identical
```

**Why it was not shipped**

- Requires Chromium installed in the runtime environment.
- Adds process lifecycle management (browser launch, crash recovery, timeouts).
- Significantly harder to test in CI without a real browser or a Ferrum-level
  stub.
- The feature can be added as an opt-in flag per archive
  (`capture_shadow_dom: true`) without touching any existing code paths.
