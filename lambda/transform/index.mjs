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

  let quality;
  if (query.q !== undefined) {
    quality = Number(query.q);
    if (!Number.isInteger(quality) || quality < 1 || quality > 100) {
      throw new BadRequest("q must be an integer between 1 and 100");
    }
  }

  return { width, height, quality };
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

  const { base, ext } = splitExtension(key);
  const format = FORMATS[ext];
  if (!format) {
    return response(400, `path must end in one of: ${SOURCE_EXTENSIONS.join(", ")}`);
  }

  let params;
  try {
    params = parseParams(event.queryStringParameters ?? {});
  } catch (error) {
    if (error instanceof BadRequest) return response(400, error.message);
    throw error;
  }

  const object = await fetchSource(base, ext);
  if (!object) return response(404, "Not found");

  const { width, height, quality } = params;

  // A bare request still gets normalized: oriented, stripped of metadata, and
  // capped, so the origin never serves a 6000px camera original.
  const resize = width || height ? { width, height } : { width: DEFAULT_MAX_DIMENSION, height: DEFAULT_MAX_DIMENSION, fit: "inside" };

  const output = await sharp(await object.Body.transformToByteArray(), { failOn: "error" })
    .rotate()
    .resize({ ...resize, withoutEnlargement: true })
    .toFormat(format.encoder, format.encoder === "png" ? {} : { quality: quality ?? DEFAULT_QUALITY })
    .toBuffer();

  if (output.length > MAX_RESPONSE_BYTES) {
    return response(413, "Rendered image is too large to return; request a smaller w/h or a lower q");
  }

  const etag = `"${createHash("sha1").update(object.ETag ?? "").update(key).update(JSON.stringify(params)).digest("hex")}"`;

  if (event.headers?.["if-none-match"] === etag) {
    return { statusCode: 304, headers: { etag } };
  }

  return {
    statusCode: 200,
    headers: {
      "content-type": format.contentType,
      // Browsers recheck daily; CloudFront holds it until the sync workflow
      // invalidates, so a redeploy propagates without waiting out the TTL.
      "cache-control": "public, max-age=86400, s-maxage=31536000",
      etag,
    },
    body: output.toString("base64"),
    isBase64Encoded: true,
  };
}
