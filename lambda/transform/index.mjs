import { createHash } from "node:crypto";

import { GetObjectCommand, S3Client } from "@aws-sdk/client-s3";
import sharp from "sharp";

const BUCKET = process.env.ASSETS_BUCKET;

// Lambda Function URLs cap a buffered response at 6 MB, and the payload is
// base64-encoded on the way out (~4/3 expansion), so the real binary ceiling
// is around 4.5 MB. Stay under it rather than emitting an opaque 502.
const MAX_RESPONSE_BYTES = 4_000_000;

const MAX_DIMENSION = 4000;
const DEFAULT_MAX_DIMENSION = 2000;
const DEFAULT_QUALITY = 82;

const FORMATS = {
  webp: { encoder: "webp", contentType: "image/webp" },
  avif: { encoder: "avif", contentType: "image/avif" },
  jpeg: { encoder: "jpeg", contentType: "image/jpeg" },
  jpg: { encoder: "jpeg", contentType: "image/jpeg" },
  png: { encoder: "png", contentType: "image/png" },
};

const s3 = new S3Client({});

class BadRequest extends Error {}

function parseDimension(raw, name) {
  if (raw === undefined) return undefined;

  const value = Number(raw);
  if (!Number.isInteger(value) || value < 1 || value > MAX_DIMENSION) {
    throw new BadRequest(`${name} must be an integer between 1 and ${MAX_DIMENSION}`);
  }
  return value;
}

function parseParams(query) {
  const width = parseDimension(query.w, "w");
  const height = parseDimension(query.h, "h");

  let format;
  if (query.fmt !== undefined) {
    format = FORMATS[query.fmt.toLowerCase()];
    if (!format) {
      throw new BadRequest(`fmt must be one of: ${Object.keys(FORMATS).join(", ")}`);
    }
  }

  let quality;
  if (query.q !== undefined) {
    quality = Number(query.q);
    if (!Number.isInteger(quality) || quality < 1 || quality > 100) {
      throw new BadRequest("q must be an integer between 1 and 100");
    }
  }

  return { width, height, format, quality };
}

function response(statusCode, body, headers = {}) {
  return {
    statusCode,
    headers: { "content-type": "text/plain; charset=utf-8", ...headers },
    body,
  };
}

export async function handler(event) {
  const key = decodeURIComponent((event.rawPath ?? "").replace(/^\/+/, ""));

  // CloudFront only routes /photo/* here, but the Lambda must not depend on an
  // upstream path pattern for its own access control.
  if (!key.startsWith("photo/") || key.includes("..")) {
    return response(404, "Not found");
  }

  let params;
  try {
    params = parseParams(event.queryStringParameters ?? {});
  } catch (error) {
    if (error instanceof BadRequest) return response(400, error.message);
    throw error;
  }

  let object;
  try {
    object = await s3.send(new GetObjectCommand({ Bucket: BUCKET, Key: key }));
  } catch (error) {
    // The role deliberately has no s3:ListBucket, so S3 reports a missing key
    // as AccessDenied rather than NoSuchKey. Granting ListBucket purely to tell
    // the two apart would widen the role for no benefit, and both mean the same
    // thing to a caller, so they collapse into one 404.
    const status = error.$metadata?.httpStatusCode;
    if (["NoSuchKey", "NotFound", "AccessDenied"].includes(error.name) || status === 403 || status === 404) {
      return response(404, "Not found");
    }
    throw error;
  }

  const { width, height, format, quality } = params;

  // A bare request still gets normalized: oriented, stripped of metadata, and
  // capped, so the origin never serves a 6000px camera original.
  const resize = width || height ? { width, height } : { width: DEFAULT_MAX_DIMENSION, height: DEFAULT_MAX_DIMENSION, fit: "inside" };

  const source = sharp(await object.Body.transformToByteArray(), { failOn: "error" });
  const sourceFormat = (await source.metadata()).format;

  // Without fmt, re-encode as the source format, falling back to JPEG for
  // anything sharp can read but this endpoint doesn't advertise.
  const encoder = format?.encoder ?? FORMATS[sourceFormat]?.encoder ?? "jpeg";
  const contentType = format?.contentType ?? FORMATS[sourceFormat]?.contentType ?? "image/jpeg";

  const output = await source
    .rotate()
    .resize({ ...resize, withoutEnlargement: true })
    .toFormat(encoder, encoder === "png" ? {} : { quality: quality ?? DEFAULT_QUALITY })
    .toBuffer();

  if (output.length > MAX_RESPONSE_BYTES) {
    return response(413, "Rendered image is too large to return; request a smaller w/h or a lower q");
  }

  const etag = `"${createHash("sha1").update(object.ETag ?? key).update(JSON.stringify(params)).digest("hex")}"`;

  if (event.headers?.["if-none-match"] === etag) {
    return { statusCode: 304, headers: { etag } };
  }

  return {
    statusCode: 200,
    headers: {
      "content-type": contentType,
      // Browsers recheck daily; CloudFront holds it until the sync workflow
      // invalidates, so a redeploy propagates without waiting out the TTL.
      "cache-control": "public, max-age=86400, s-maxage=31536000",
      etag,
    },
    body: output.toString("base64"),
    isBase64Encoded: true,
  };
}
