# Chiron Telemetry Pipeline — Setup Guide

This document covers everything outside Xcode you need to do to get the
developer-facing telemetry pipeline working end-to-end. The iOS side is
already built (see "Files involved" at the bottom). What's left is:

1. Provision Cloudflare R2 (object store)
2. Deploy a Cloudflare Worker (presigned-URL issuer)
3. Paste the Worker URL into one place in the iOS code
4. Update privacy nutrition labels for TestFlight
5. Wire up local analysis tooling

Order of operations matters — uploads can't run until the Worker URL is in
the iOS build. But you can stand up R2 + Worker first, then ship the iOS
build with the URL filled in, and start collecting data immediately.

---

## 0. Architecture at a glance

```
┌─────────────┐    POST {file_meta}     ┌──────────────────────┐
│  iOS app    │  ─────────────────────► │  Cloudflare Worker   │
│ (Telemetry  │                         │ (issues presigned    │
│  Uploader)  │  ◄─────presigned URL─── │   PUT URL)           │
└─────┬───────┘                         └─────────┬────────────┘
      │                                           │
      │  PUT file (background URLSession)         │  R2 SigV4 keys
      │                                           │  (Worker secrets)
      ▼                                           ▼
┌─────────────────────────────────────────────────────────────┐
│           Cloudflare R2 (S3-compatible bucket)              │
│                                                             │
│  {firebase_user_id}/{exercise_type}/                        │
│    {ISO8601}_{app_build}_{viewpoint}_{session_uuid}.csv     │
│    {ISO8601}_{app_build}_{viewpoint}_{session_uuid}.mp4     │
└─────────────────────────────────────────────────────────────┘
      │
      │  aws s3 sync (your laptop)
      ▼
~/Telemetry/raw/  → Pandas / DuckDB / video player
```

Two things never appear in this diagram, by design: there is no Anthropic-side
service, no Firebase. R2 + Worker + your laptop. Cheapest possible architecture
that's also a strict subset of where it's heading (see "Future migration").

---

## 1. Cloudflare R2 setup

### 1.1 Create the account & bucket

You need a Cloudflare account (free tier is fine for the early going). Then:

1. Go to https://dash.cloudflare.com/ → R2.
2. If R2 isn't enabled yet, click "Enable R2" and accept the terms. R2 is free
   for the first 10 GB-month of storage and 1M Class A operations/month.
3. Click **Create bucket**. Recommended name: `chiron-telemetry`.
   - Region: leave as **Automatic** unless you have a specific compliance need.
   - This bucket name flows into the Worker config.

### 1.2 Generate API credentials

The Worker signs presigned URLs using R2's S3-compatible API, which needs
SigV4 access keys.

1. R2 → **Manage R2 API Tokens** → **Create API Token**.
2. Token name: `chiron-telemetry-worker`.
3. Permissions: **Object Read & Write**.
4. Specify bucket: pick `chiron-telemetry` only (least-privilege).
5. TTL: leave blank (no expiry) for development; set 365d for production hygiene.
6. Click **Create API Token**.
7. Copy down four values immediately — they're only shown once:
   - **Access Key ID**
   - **Secret Access Key**
   - **S3 API endpoint** (looks like `https://<account-id>.r2.cloudflarestorage.com`)
   - **Account ID** (also visible on the R2 home page)

### 1.3 Free-tier limits to know about

- **Storage**: 10 GB free, then $0.015/GB-month. A typical 60-second set
  produces ~3-5 MB (mp4 at MediumQuality preset) + ~150 KB (CSV at 30 fps).
  10 GB ≈ 1,000–1,500 sets. For a single-tester MVP this is comfortable.
- **Class A ops** (PUT/POST/LIST): 1M free/month, then $4.50/million. Each
  set is two PUTs (CSV + mp4).
- **Class B ops** (GET): 10M free/month. You'll mostly download via
  `aws s3 sync`, which is GETs.
- **Egress**: free, period. This is R2's headline feature versus S3.

### 1.4 Viewing/downloading uploaded files

Three options:

- **Cloudflare dashboard**: R2 → bucket → browse. Fine for spot checks.
- **`rclone`** (recommended): see §4.
- **`aws s3` CLI** (works, R2 is S3-compatible): see §4.

---

## 2. Cloudflare Worker setup

The Worker is a small TypeScript service that:

1. Receives the iOS app's POST with file metadata.
2. Validates the request (path-traversal guard, size cap, allowed file types).
3. Rate-limits per IP and per `firebase_user_id`.
4. Signs a presigned PUT URL for R2 with a short TTL.
5. Returns it to the app.

### 2.1 Project scaffolding

You need Node (≥ 18) and `wrangler` (Cloudflare's CLI):

```bash
npm install -g wrangler
wrangler login          # opens a browser; auth via your Cloudflare account
mkdir chiron-telemetry-worker && cd chiron-telemetry-worker
npm init -y
npm install --save-dev typescript @cloudflare/workers-types
npm install aws4fetch
mkdir src
```

### 2.2 `wrangler.toml`

Create `wrangler.toml` at the project root:

```toml
name = "chiron-telemetry"
main = "src/index.ts"
compatibility_date = "2024-11-01"

[vars]
R2_BUCKET_NAME = "chiron-telemetry"
R2_ACCOUNT_ID = "REPLACE_WITH_YOUR_ACCOUNT_ID"

# Secrets are set via CLI, NOT here:
#   wrangler secret put R2_ACCESS_KEY_ID
#   wrangler secret put R2_SECRET_ACCESS_KEY
#
# KV namespace for rate limiting — create with:
#   wrangler kv namespace create RATE_LIMIT_KV
# then paste the returned id below:

[[kv_namespaces]]
binding = "RATE_LIMIT_KV"
id = "REPLACE_WITH_YOUR_KV_NAMESPACE_ID"
```

### 2.3 Worker code (`src/index.ts`)

Drop this in verbatim:

```typescript
import { AwsClient } from "aws4fetch";

interface Env {
  R2_BUCKET_NAME: string;
  R2_ACCOUNT_ID: string;
  R2_ACCESS_KEY_ID: string;
  R2_SECRET_ACCESS_KEY: string;
  RATE_LIMIT_KV?: KVNamespace;
}

interface SigningRequest {
  firebase_user_id: string;
  anonymous_uuid: string;
  filename: string;
  file_type: string;
  file_size_bytes?: number;
  app_build: string;
  schema_version: number;
}

const ALLOWED_EXTENSIONS = new Set(["csv", "mp4", "json", "jsonl"]);
const MAX_FILE_BYTES = 200 * 1024 * 1024; // 200 MB hard ceiling
const PRESIGNED_TTL_SECONDS = 600;        // 10 minutes
const IP_RATE_LIMIT_PER_MINUTE = 100;
const USER_RATE_LIMIT_PER_HOUR = 200;

export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext
  ): Promise<Response> {
    if (request.method === "OPTIONS") {
      return cors(new Response(null, { status: 204 }));
    }
    if (request.method !== "POST") {
      return cors(json({ error: "method-not-allowed" }, 405));
    }

    let body: SigningRequest;
    try {
      body = (await request.json()) as SigningRequest;
    } catch {
      return cors(json({ error: "invalid-json" }, 400));
    }

    const { firebase_user_id, filename, file_type, file_size_bytes } = body;
    if (!firebase_user_id || !filename || !file_type) {
      return cors(json({ error: "missing-required-fields" }, 400));
    }
    if (!ALLOWED_EXTENSIONS.has(file_type.toLowerCase())) {
      return cors(json({ error: "unsupported-file-type" }, 400));
    }
    if (file_size_bytes !== undefined && file_size_bytes > MAX_FILE_BYTES) {
      return cors(json({ error: "file-too-large" }, 413));
    }
    if (filename.includes("..") || filename.startsWith("/")) {
      return cors(json({ error: "invalid-filename" }, 400));
    }
    // Enforce that filename starts with the firebase_user_id prefix so a
    // misbehaving client can't write under another user's directory.
    if (!filename.startsWith(`${firebase_user_id}/`)) {
      return cors(json({ error: "filename-prefix-mismatch" }, 400));
    }

    // Rate limit: best-effort, requires KV. Skips silently if KV unbound.
    if (env.RATE_LIMIT_KV) {
      const ip = request.headers.get("cf-connecting-ip") || "unknown";
      const ipKey = `rl:ip:${ip}:${Math.floor(Date.now() / 60000)}`;
      const userKey = `rl:user:${firebase_user_id}:${Math.floor(
        Date.now() / 3600000
      )}`;
      const ipCount =
        parseInt((await env.RATE_LIMIT_KV.get(ipKey)) || "0") + 1;
      const userCount =
        parseInt((await env.RATE_LIMIT_KV.get(userKey)) || "0") + 1;
      if (
        ipCount > IP_RATE_LIMIT_PER_MINUTE ||
        userCount > USER_RATE_LIMIT_PER_HOUR
      ) {
        return cors(json({ error: "rate-limited" }, 429));
      }
      ctx.waitUntil(
        env.RATE_LIMIT_KV.put(ipKey, String(ipCount), { expirationTtl: 120 })
      );
      ctx.waitUntil(
        env.RATE_LIMIT_KV.put(userKey, String(userCount), {
          expirationTtl: 3700,
        })
      );
    }

    const aws = new AwsClient({
      accessKeyId: env.R2_ACCESS_KEY_ID,
      secretAccessKey: env.R2_SECRET_ACCESS_KEY,
      service: "s3",
      region: "auto",
    });

    const objectURL = `https://${env.R2_ACCOUNT_ID}.r2.cloudflarestorage.com/${env.R2_BUCKET_NAME}/${filename}`;
    const signed = await aws.sign(
      new Request(`${objectURL}?X-Amz-Expires=${PRESIGNED_TTL_SECONDS}`, {
        method: "PUT",
      }),
      { aws: { signQuery: true } }
    );

    return cors(
      json({
        presigned_url: signed.url,
        expires_in_seconds: PRESIGNED_TTL_SECONDS,
      })
    );
  },
};

function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  });
}

function cors(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", "*");
  headers.set("access-control-allow-methods", "POST, OPTIONS");
  headers.set("access-control-allow-headers", "content-type");
  return new Response(response.body, { status: response.status, headers });
}
```

### 2.4 Configure secrets and KV

```bash
# R2 credentials (from §1.2):
wrangler secret put R2_ACCESS_KEY_ID
# (paste the Access Key ID, hit enter)
wrangler secret put R2_SECRET_ACCESS_KEY
# (paste the Secret Access Key, hit enter)

# Rate-limit KV namespace:
wrangler kv namespace create RATE_LIMIT_KV
# Output includes an `id` field — copy it into wrangler.toml's
# [[kv_namespaces]] block.
```

### 2.5 Deploy

```bash
wrangler deploy
```

The output prints something like:
`Deployed chiron-telemetry triggers ... https://chiron-telemetry.YOUR-SUBDOMAIN.workers.dev`

That URL is what goes into the iOS code.

### 2.6 Paste the Worker URL into iOS

Open [Chiron/Services/TelemetryUploader.swift](Chiron/Services/TelemetryUploader.swift)
and find:

```swift
private static let workerURL: String = "TODO_REPLACE_WITH_WORKER_URL"
```

Replace `TODO_REPLACE_WITH_WORKER_URL` with the URL from §2.5. That's the
only iOS change needed; rebuild and the pipeline is live.

### 2.7 CORS

The Worker already returns permissive CORS headers (`access-control-allow-origin: *`)
because the iOS client doesn't enforce browser CORS. If you ever build a
web dashboard that calls the Worker, the existing config covers it.

---

## 3. Firebase considerations

### 3.1 Which user ID field?

The current codebase **does not have FirebaseAuth installed** — only
`FirebaseStorage` and `FirebaseFirestore` (see `Podfile`). Every Firestore
write keys off `UserManager.shared.getUserId()`, which returns
`UIDevice.current.identifierForVendor` (or a stored UUID fallback).

The iOS code emits both `firebase_user_id` and `anonymous_uuid` in the
upload payload. **Today both come from `UserManager.shared.getUserId()`.**
When you wire FirebaseAuth in:

1. `pod 'Firebase/Auth'` in `Podfile`, `pod install`.
2. Open [Chiron/Services/TelemetryUploader.swift](Chiron/Services/TelemetryUploader.swift)
   and find the line marked `TODO_FIREBASE_USER_ID_SWAP`.
3. Replace `let firebaseUserId = id` with
   `let firebaseUserId = Auth.auth().currentUser?.uid ?? id` (the fallback
   handles "not signed in" / anonymous-auth cases).
4. The matching site in [Chiron/Services/TelemetryCoordinator.swift](Chiron/Services/TelemetryCoordinator.swift)
   has the same comment marker — update both. The schema and the Worker
   payload don't change at all; downstream files keep landing under
   the same `{firebase_user_id}/` prefix.

Note: existing data in R2 will still be keyed under the old vendor ID. If
you want to consolidate, write a one-time `aws s3 mv` script to rewrite
keys after the swap.

### 3.2 Anonymous-auth fallback

When `Auth.auth().currentUser` is nil (user hasn't signed in yet), keep
falling back to `UserManager.shared.getUserId()`. The `anonymous_uuid` field
exists exactly so you can correlate this case. Never let the field be empty
— the Worker rejects requests with missing `firebase_user_id`.

### 3.3 Privacy policy

The privacy policy needs to disclose:

- That the app captures a screen recording (camera + on-screen pose overlay)
  during workouts, with the user's explicit opt-in.
- That a CSV of pose-detection metrics is captured per workout set.
- Where it's stored (Cloudflare R2, your control).
- That it's linked to the device's anonymous identifier (or Firebase user ID
  once that lands).
- That the user can request deletion (provide an email contact).
- Data retention: until you decide otherwise. State this explicitly.
- That **no audio is captured** — this is a common reviewer concern; spell it out.

Apple's Privacy Nutrition Label fields you'll need to update — see §5.2.

---

## 4. Local analysis setup on your desktop

### 4.1 Install `rclone` (recommended) or `aws s3`

`rclone` handles R2 natively and supports incremental sync without
configuration gymnastics:

```bash
brew install rclone
rclone config
# n) New remote
# name> chiron-r2
# Storage> 5 (Amazon S3 Compliant)
# provider> Cloudflare
# env_auth> false
# access_key_id> (paste from §1.2)
# secret_access_key> (paste from §1.2)
# region> auto
# endpoint> https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
# location_constraint> (leave blank)
# acl> (leave blank)
# (accept defaults for the rest)
```

Alternatively, `aws s3` works with one extra env var:

```bash
brew install awscli
aws configure --profile chiron
# Access Key ID: (from §1.2)
# Secret Access Key: (from §1.2)
# Region: auto
# Output: json

# All commands need --endpoint-url:
export AWS_ENDPOINT_URL=https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com
```

### 4.2 Suggested local layout

```
~/Telemetry/
├── raw/                           # mirrored from R2 — never edit
│   └── {firebase_user_id}/
│       └── {exercise_type}/
│           ├── {ts}_{build}_{viewpoint}_{session}.csv
│           └── {ts}_{build}_{viewpoint}_{session}.mp4
├── notebooks/                     # Pandas / DuckDB analysis
│   ├── viewpoint-tuning.ipynb
│   └── rep-rejection-audit.ipynb
└── exports/                       # plots, summary CSVs (committed to git if useful)
```

### 4.3 One-line sync (rclone)

```bash
rclone sync chiron-r2:chiron-telemetry ~/Telemetry/raw --progress
```

Or with `aws`:

```bash
aws s3 sync s3://chiron-telemetry ~/Telemetry/raw \
  --endpoint-url https://YOUR_ACCOUNT_ID.r2.cloudflarestorage.com \
  --profile chiron
```

Tip: Add to a cron / launchd job that runs every hour while you're testing,
so files appear without thinking about it.

### 4.4 Reading the CSV in Pandas

The header line uses `# {json}` so pandas can skip it cleanly:

```python
import pandas as pd

df = pd.read_csv(
    "~/Telemetry/raw/.../some_session.csv",
    comment="#",
)
# Header metadata can be parsed separately:
import json
with open("~/Telemetry/raw/.../some_session.csv") as f:
    meta = json.loads(f.readline().lstrip("# ").strip())
```

---

## 5. TestFlight rollout checklist

### 5.1 TestFlight build description (paste into App Store Connect)

> **What to test:** Settings → "Help Improve Chiron" — toggle "Share Workout
> Data with Developer" on. Run a few sets in Track. Each set will record a
> short screen capture (camera + on-screen overlay) and upload it on Wi-Fi.
>
> **Data collected when on:** screen recording during sets only, plus a CSV
> of pose-detection metrics. **No audio.** Linked to your anonymous user ID;
> can be deleted on request. Toggle off any time.

### 5.2 Privacy nutrition label fields

In App Store Connect → app → Privacy:

- **Audio Data**: NOT collected.
- **Photos or Videos**: collected when telemetry is on. Purposes:
  *App Functionality*, *Developer's Advertising or Marketing* (NO),
  *Analytics* (YES), *Product Personalization* (NO), *Other Purposes* (NO).
  Linked to user: **YES** (anonymous device ID, but Apple treats that as
  linked). Used for tracking: **NO**.
- **Diagnostics > Other Diagnostic Data**: collected (the CSV). Same
  purpose/linkage as above.
- **Identifiers > Device ID**: collected. Linked: **YES**. Used for tracking: **NO**.

If you also collect *crash data* via another channel, fill that in too. The
telemetry pipeline alone doesn't require any other field.

### 5.3 Suggested in-UI consent copy (already in the SettingsView)

Already written into [Chiron/Views/SettingsView.swift](Chiron/Views/SettingsView.swift)'s
`telemetryFooterCopy`. Keep this text in sync with whatever you write in
the privacy policy and the TestFlight description — the wording should
match across all three surfaces.

---

## 6. Testing the pipeline end-to-end

### 6.1 Happy path — verify uploads land

1. Build and run on a real device (Simulator can't do ReplayKit).
2. Settings → "Share Workout Data with Developer" → on.
3. Track tab → start a set → do a few reps → end set.
4. Wait ~10 seconds for ReplayKit to finalize and the background URLSession
   to PUT.
5. Refresh the R2 dashboard or `rclone lsd chiron-r2:chiron-telemetry`. You
   should see `{your_device_id}/{exercise_type}/{timestamp}_*.{csv,mp4}`.
6. Pull locally: `rclone sync chiron-r2:chiron-telemetry ~/Telemetry/raw`.
7. Open the CSV in your editor; line 1 starts with `# {json metadata}`,
   line 2 is column headers, then one row per frame.

### 6.2 Crash recovery — verify resumePendingUploads

1. With telemetry on, start a set.
2. Mid-set, kill the app (swipe up in the app switcher, drag the card off).
3. Relaunch the app. `ChironAppDelegate.didFinishLaunching` runs
   `TelemetryUploader.shared.resumePendingUploads()` which scans
   `Application Support/Telemetry/Pending/` and re-enqueues every orphaned
   file.
4. Files in Pending/ are partial (CSV truncated at the last fsync, no mp4
   because ReplayKit lost the session) — they still upload as-is. The CSV
   header line + whatever rows survived the last 5-second flush are present.

### 6.3 Offline → online — verify retry resumes

1. Telemetry on. Toggle airplane mode ON.
2. Run a set. The uploader will fail to fetch a presigned URL and schedule a
   retry with reason `no-network`. Console log: `[TelemetryUploader]
   Retrying ... in 30s ...`.
3. Toggle airplane mode OFF. The retry timer fires after 30 s; upload
   succeeds. (Or trigger immediately by relaunching the app — that calls
   `resumePendingUploads()` afresh.)

### 6.4 Wi-Fi-only gate — verify cellular blocking

1. Telemetry on, "Allow Cellular" off (the default).
2. Disable Wi-Fi on the device, leave cellular on.
3. Run a set. Console: `Retrying ... reason: wifi-only-and-on-cellular`.
4. Re-enable Wi-Fi → upload completes within the next backoff cycle.

### 6.5 Size guardrail — verify big-file deferral

If you ever produce a >50 MB single file (you won't with current MediumQuality
preset under typical set lengths, but stress-test it with a 30-min synthetic
session): with cellular allowed, the upload will still defer with reason
`size-exceeds-cellular-cap (...)` until on Wi-Fi.

---

## 7. Future migration notes

These are the four expansion paths that are already baked into the current
schema. Everything written today is a strict subset of these — nothing gets
thrown away when you move to them.

### Per-rep structured JSONL

The hooks are already wired: `TelemetryCoordinator.recordRepEvent(repIndex:)`
and `recordRepRejection(reason:)` fire on every rep boundary inside
`OnDevicePoseManager.handleMediaPipeResult`. Today both are no-ops because
the per-frame CSV already carries `rep_validated_this_frame` and
`rep_rejected_reason_this_frame` columns. When you want richer per-rep
records (form score at rep completion, eccentric/concentric durations, ROM
peak), add a `SessionJSONLWriter` parallel to `SessionCSVWriter` that the
coordinator opens at session start and forwards `recordRepEvent` /
`recordRepRejection` to. The new file lands in the same Pending/ directory
under `{...}_per-rep.jsonl`. The Worker already accepts `jsonl` in
`ALLOWED_EXTENSIONS`. Nothing in the existing CSV path changes.

### JSONL → Parquet conversion Worker

Once you have JSONL (per-rep rows) and CSV (per-frame rows), querying many
sessions at once is painful. The clean path: a second Cloudflare Worker
triggered on R2 object-create events that converts new CSV/JSONL into
Parquet keyed `parquet/{firebase_user_id}/{exercise_type}/...`. The Worker
reads the metadata header line off the CSV, uses those values as Parquet
column metadata + partition columns, and writes via Apache Arrow's WASM
build. Schema versioning is the load-bearing piece here — the Worker reads
`schema_version` from the header and routes to the right parser. Today's
schema is `1`; bump when the column set changes.

### Sampling for per-frame data at scale

Per-frame CSV rows are cheap when you have one tester. With 100+ TestFlight
testers each doing 10 sets/week, you'll be ingesting ~10 MB CSV/week per
user (~1 GB/week total) — manageable, but fat to query. The expansion path
is a sampling layer in `SessionCSVWriter.recordFrame`: a `frameSampler`
property that decides per frame whether to write (e.g., always write the
first 100 rows after a rep boundary, then 1-in-3 thereafter). Add an
`is_sampled_in: bool` column so downstream knows the sampling decision.
Per-rep JSONL stays unsampled (small per-rep cardinality). Existing
unsampled sessions remain valid — readers just see `is_sampled_in=true`
on every row.

### Postgres analytical layer

When you want SQL over the whole corpus rather than scanning Parquet files
manually, the move is: add a third Cloudflare Worker (or a daily
GitHub-Action job) that ingests Parquet from R2 into a managed Postgres
(Neon / Supabase / Fly Postgres). One table per schema_version; partition
by `(firebase_user_id, started_at_day)`. Don't denormalize — keep the
Parquet files as the system of record so a schema change is a re-ingest,
not a migration. The existing partition columns
(`firebase_user_id`, `exercise_type`, `viewpoint_profile`, `app_build`)
become indexes.

### Why none of this throws away today's code

- Filename convention `{user}/{exercise}/{ts}_{build}_{viewpoint}_{session}.{ext}`
  — same partition columns, just more files alongside it.
- Header line metadata + `schema_version` — Parquet ingester reads these
  fields. Add new keys; readers ignore unknowns.
- TelemetryCoordinator hooks (recordRepEvent, recordRepRejection) — already
  in OnDevicePoseManager, already callable from any thread, just no-op
  today. The expansion is "stop being a no-op," nothing else.
- TelemetryUploader's path-blind `enqueue(relativePath:)` — works on any
  file dropped into Pending/. JSONL needs no new uploader code.
- TelemetryFilesystem.relativePath uses the Pending/ → R2 mirror trick — a
  new file extension just adds a new file at the same path.

---

## Files involved (iOS)

Created:

- [Chiron/Services/TelemetryPreferencesManager.swift](Chiron/Services/TelemetryPreferencesManager.swift) — opt-in flags
- [Chiron/Services/TelemetryFilesystem.swift](Chiron/Services/TelemetryFilesystem.swift) — Pending/Uploaded layout
- [Chiron/Services/SessionCSVWriter.swift](Chiron/Services/SessionCSVWriter.swift) — per-frame CSV
- [Chiron/Services/SessionVideoRecorder.swift](Chiron/Services/SessionVideoRecorder.swift) — mp4 transcode + move
- [Chiron/Services/TelemetryUploader.swift](Chiron/Services/TelemetryUploader.swift) — background URLSession queue
- [Chiron/Services/TelemetryCoordinator.swift](Chiron/Services/TelemetryCoordinator.swift) — single entry point

Modified:

- [Chiron/ChironApp.swift](Chiron/ChironApp.swift) — AppDelegate adapter for background URLSession
- [Chiron/OnDevicePoseManager.swift](Chiron/OnDevicePoseManager.swift) — three-line observation hook in `handleMediaPipeResult`
- [Chiron/Views/SettingsView.swift](Chiron/Views/SettingsView.swift) — "Help Improve Chiron" section
- [Chiron/Views/TrackView.swift](Chiron/Views/TrackView.swift) — startSession / endSession / attachRecordedVideo

Outstanding TODOs in code (grep markers):

- `TODO_REPLACE_WITH_WORKER_URL` — the Worker URL after §2.5
- `TODO_FIREBASE_USER_ID_SWAP` — when you wire FirebaseAuth (see §3.1)
- `TODO_TELEMETRY_TRANSCODE` — if you ever want strict 480p/15fps via
  AVAssetReader/Writer instead of the MediumQuality preset
