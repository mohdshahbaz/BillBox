/**
 * Every error reply carries { error, message, code } (docs/API_ERRORS.md).
 * `error` stays as it always was (every app reads it); `message` is the same text, and `code` is the reason's own code
 * (HAS_STOCK, CREDIT_LIMIT, DUPLICATE …) or, when the reason has none, one named after the HTTP status.
 * The same rule runs in the iPhone engine (Router.swift, ErrorBody) and the Android bundle (this file).
 */
const STATUS_CODES = {
  400: 'BAD_REQUEST', 401: 'UNAUTHORIZED', 402: 'PAYMENT_REQUIRED', 403: 'FORBIDDEN', 404: 'NOT_FOUND', 405: 'NOT_ALLOWED',
  409: 'CONFLICT', 413: 'TOO_LARGE', 422: 'INVALID', 423: 'LOCKED', 429: 'TOO_MANY', 500: 'SERVER_ERROR', 502: 'BAD_GATEWAY', 503: 'UNAVAILABLE',
};

function errorBody(status, body) {
  if (!(status >= 400) || !body || typeof body !== 'object' || Array.isArray(body) || typeof body.error !== 'string') return body;
  const o = { ...body };
  if (o.message == null) o.message = o.error;
  if (o.code == null) o.code = STATUS_CODES[status] || 'ERROR';
  return o;
}

module.exports = { errorBody, STATUS_CODES };
