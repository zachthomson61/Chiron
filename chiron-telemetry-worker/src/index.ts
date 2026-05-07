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
const MAX_FILE_BYTES = 200 * 1024 * 1024;
const PRESIGNED_TTL_SECONDS = 600;
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
    if (!filename.startsWith(`${firebase_user_id}/`)) {
      return cors(json({ error: "filename-prefix-mismatch" }, 400));
    }

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
