# API errors and request checks

## Error replies

Every error reply (HTTP status 400 or higher) from every engine — the Mac/Windows/Linux server (`backend/src/server.js`),
the Android bundle (`android/engine/entry.js`) and the iPhone engine (`Router.swift`, `ErrorBody`) — has the same shape:

```json
{ "error": "Not enough stock in batch B12", "message": "Not enough stock in batch B12", "code": "NO_STOCK" }
```

- `error` — unchanged; every app reads it today.
- `message` — the same text. New clients should read `message`; `error` stays for the apps already installed.
- `code` — the reason's own code when it has one (`HAS_STOCK`, `CREDIT_LIMIT`, `DUPLICATE`, `NO_STOCK`, `OFFLINE`,
  `YEAR_EXISTS` …), otherwise one named after the status: `BAD_REQUEST` 400, `UNAUTHORIZED` 401, `PAYMENT_REQUIRED` 402,
  `FORBIDDEN` 403, `NOT_FOUND` 404, `CONFLICT` 409, `TOO_LARGE` 413, `INVALID` 422, `SERVER_ERROR` 500, `BAD_GATEWAY` 502,
  `UNAVAILABLE` 503, else `ERROR`.
- `detail` — on a 500 only, the underlying reason (unchanged).

The rule lives in `backend/src/utils/errors.js` (Node, also bundled for Android) and `ErrorBody` in `Router.swift`
(iPhone). The parity tests compare the full reply, so the three engines must agree; the iPhone golden files carry the
two new fields.

## Request checks (report-only)

`backend/src/utils/validate.js` checks POST/PUT bodies of `/invoices`, `/purchases`, `/parties`, `/items` (ids, numbers,
dates as `yyyy-mm-dd`, required names and bill lines). For now it **only logs** each kind of problem once per run, as
`[validate] POST /invoices lines[].qty is a number sent as text`, and accepts the request as before.

When the logs stay quiet across the app versions in use, set `REJECT = true`: the same checks then answer
`422 { error, message, code: "INVALID" }`. Until then an older app that sends a number as text keeps working.
