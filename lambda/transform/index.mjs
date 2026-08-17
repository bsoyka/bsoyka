import { createHash } from "node:crypto";

import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import sharp from "sharp";

const BUCKET = process.env.ASSETS_BUCKET;

const DEFAULT_QUALITY = 82;

// The extension in the URL is the only thing that selects the output format,
// and doubles as the list of extensions a stored original may use.
const FORMATS = {
  webp: { encoder: "webp", contentType: "image/webp" },
  avif: { encoder: "avif", contentType: "image/avif" },
  jpeg: { encoder: "jpeg", contentType: "image/jpeg" },
  jpg: { encoder: "jpeg", contentType: "image/jpeg" },
  png: { encoder: "png", contentType: "image/png" },
};

const SOURCE_EXTENSIONS = Object.keys(FORMATS);

const s3 = new S3Client({});

class BadRequest extends Error {}

// No upper bound: resizing never enlarges, so an oversized request just yields
// the source dimensions rather than a bigger render. Only genuine nonsense
// (zero, negative, fractional, non-numeric) is rejected.
function parseSize(raw) {
  if (raw === undefined) return undefined;

  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1) {
    throw new BadRequest("s must be a positive integer");
  }
  return value;
}

function parseParams(query) {
  const size = parseSize(query.s);

  let quality;
  if (query.q !== undefined) {
    quality = Number(query.q);
    if (!Number.isInteger(quality) || quality < 1 || quality > 100) {
      throw new BadRequest("q must be an integer between 1 and 100");
    }
  }

  return { size, quality };
}

function splitExtension(key) {
  const dot = key.lastIndexOf(".");
  if (dot <= key.lastIndexOf("/")) return { base: key, ext: "" };
  return { base: key.slice(0, dot), ext: key.slice(dot + 1).toLowerCase() };
}

// The role deliberately has no s3:ListBucket, so S3 reports a missing key as
// AccessDenied rather than NoSuchKey. Granting ListBucket purely to tell the
// two apart would widen the role for no benefit.
function isMissing(error) {
  const status = error.$metadata?.httpStatusCode;
  return ["NoSuchKey", "NotFound", "AccessDenied"].includes(error.name) || status === 403 || status === 404;
}

// The extension names the format the caller wants, which need not be the one
// the image is stored as, so fall back to the other known extensions for the
// same base name before giving up.
async function fetchSource(base, ext) {
  const candidates = [ext, ...SOURCE_EXTENSIONS.filter((e) => e !== ext)];

  for (const candidate of candidates) {
    try {
      return await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: `${base}.${candidate}` }));
    } catch (error) {
      if (!isMissing(error)) throw error;
    }
  }
  return null;
}

function error(statusCode, message) {
  return {
    statusCode,
    headers: { "content-type": "text/plain; charset=utf-8" },
    body: message,
  };
}

// Kept separate from the streaming wrapper so the whole transform path can be
// exercised without the awslambda runtime global.
export async function render(event) {
  const key = decodeURIComponent((event.rawPath ?? "").replace(/^\/+/, ""));

  // CloudFront only routes /photo/* here, but the Lambda must not depend on an
  // upstream path pattern for its own access control.
  if (!key.startsWith("photo/") || key.includes("..")) {
    return error(404, "Not found");
  }

  const { base, ext } = splitExtension(key);
  const format = FORMATS[ext];
  if (!format) {
    return error(400, `path must end in one of: ${SOURCE_EXTENSIONS.join(", ")}`);
  }

  let params;
  try {
    params = parseParams(event.queryStringParameters ?? {});
  } catch (err) {
    if (err instanceof BadRequest) return error(400, err.message);
    throw err;
  }

  const object = await fetchSource(base, ext);
  if (!object) return error(404, "Not found");

  const etag = `"${createHash("sha1").update(object.ETag ?? "").update(key).update(JSON.stringify(params)).digest("hex")}"`;

  if (event.headers?.["if-none-match"] === etag) {
    return { statusCode: 304, headers: { etag } };
  }

  const { size, quality } = params;

  // A bare request still gets normalized: oriented, stripped of metadata, and
  // re-encoded, but at full source resolution — there's no response-size cap
  // to protect since the function URL streams.
  let pipeline = sharp(await object.Body.transformToByteArray(), { failOn: "error" }).rotate();
  if (size) {
    pipeline = pipeline.resize({ width: size, height: size, fit: "inside", withoutEnlargement: true });
  }

  const output = await pipeline
    .toFormat(format.encoder, format.encoder === "png" ? {} : { quality: quality ?? DEFAULT_QUALITY })
    .toBuffer();

  return {
    statusCode: 200,
    headers: {
      "content-type": format.contentType,
      // Browsers recheck daily; CloudFront holds it until the sync workflow
      // invalidates, so a redeploy propagates without waiting out the TTL.
      "cache-control": "public, max-age=86400, s-maxage=31536000",
      etag,
    },
    body: output,
  };
}

// The function URL runs in RESPONSE_STREAM mode, which raises the response
// ceiling from 6 MB to 200 MB and writes raw bytes instead of base64 — without
// it, a full-size PNG doesn't fit in a buffered response.
async function stream(event, responseStream) {
  const { statusCode, headers, body } = await render(event);

  const httpStream = awslambda.HttpResponseStream.from(responseStream, { statusCode, headers });
  if (body) httpStream.write(body);
  httpStream.end();
}

// The AWS SDK's own telemetry code stubs globalThis.awslambda = {} as a
// bookkeeping object outside Lambda, so testing for streamifyResponse itself
// rather than the object's mere presence is what actually detects the runtime.
export const handler = globalThis.awslambda?.streamifyResponse
  ? globalThis.awslambda.streamifyResponse(stream)
  : stream;
