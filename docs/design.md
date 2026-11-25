<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Design

## Scope

A client for the Koofr™ cloud storage API v2.1 over HTTPS: the user, limits
and mounts; files by mount id and path (`info`, `exists`, `listFolder`,
`listRecursive`, `mkdir`, `mkdirAll`, `get`, `put`, `remove`, `rename`,
cross-mount `copy` and `move`); search; public links and receivers; the
trash. `call` reaches every other endpoint. The base URL is settable,
because other providers run the same API.

Out of scope for this version, reachable through `call`: file tags,
versions, async jobs, ranged and ZIP downloads, mount users and the OAuth2
login. File synchronisation stays with the bundled `webdav` module, which
speaks Koofr's WebDAV endpoint.

## Decisions

- **The OpenAPI description is the source of truth** (API v2.1); Koofr's Go
  client, which uses the older `/api/v2` paths, settles semantics the
  description leaves open. Where the two spell a parameter differently
  (`overwriteIgnoreNonexistent`) the deck follows the description; the live
  service accepts both.
- **Two authentications.** `withAppPassword` sends HTTP Basic with an app
  password, `withToken` a bearer token. Configuration is copy-returning
  (`withPlainHttp`, `withCaCert`, `withInsecure`, `withTimeout`,
  `withRetries`, `withReplyLimit`).
- **Two URL roots.** JSON calls go to `/api/v2.1`; `get`, `put` and
  `listRecursive` to `/content/api/v2.1`. A file's path is a query
  parameter, not a URL segment.
- **The deck runs its own retry loop.** `http.send` decodes the body as
  UTF-8 and throws without the status, so JSON requests use
  `http.requestWithBytes` and the deck retries GETs on 429 and 5xx (500 ms
  doubling, raised to a numeric `Retry-After`, at most 30 s, up to
  `withRetries` times, `MAX_RETRIES` 10 at most). Writes are never retried,
  and no request follows a redirect: a 3xx is a refusal.
- **Missing means Koofr said missing.** `exists` and `mkdirAll` read the
  status rather than an error message, and count a 404 as "missing" only
  when its body is Koofr's own error object with code `NotFound` (or none).
  A 404 from a proxy, a wrong base path or another code (`DeviceOffline`)
  fails, so a sync script never acts on a false "missing".
- **`mkdirAll` probes once, then creates.** One `info` on the full path; if
  it is not there, it probes prefixes from the top and, after the first
  missing one, creates that one and every one below without probing. A
  prefix that is a file throws.
- **Explicit upload options.** Koofr's `autorename` defaults to true, so
  `put` always sends `overwrite` and `autorename`; the zero `PutOptions`
  refuses an existing file. Conditional overwrites (`overwriteIfHash`,
  `overwriteIfModified`) are sent only when set. Uploads are raw bodies.
- **NDJSON read line by line.** `listRecursive` reads the reply whole, then
  decodes it a line at a time, dropping each JSON value once its `File` is
  built (about a quarter less peak memory than decoding the whole stream at
  once). Item paths are relative to the requested folder, confirmed live; an
  error item in the stream throws.
- **Server names are checked before they become paths.** A listed name of
  `""`, `.`, `..`, one holding `/` or a control character, or a recursive
  entry whose joined path is malformed or names the folder itself, is
  refused. Otherwise `remove` on an entry could hit the parent, and a mirror
  script could leave its root.
- **Caller input is validated before it reaches a URL**: absolute paths
  without empty, `.` or `..` segments, names without `/`, ids against a
  fixed pattern, search filters within range. The root cannot be renamed,
  removed, copied or moved; `call` refuses `#`.
- **Guarding destructive defaults.** `undelete` refuses an empty list
  (Koofr restores everything for `[]`); `undeleteAll` is the explicit way.
  `trashAll` stops at an empty cursor, an empty page or a cursor it has
  seen, and at `MAX_PAGES`.
- **Tolerant readers, fast path for files.** Replies are read with
  accessors that turn an absent or `null` field into the zero value; a file
  object is read through its required fields directly and falls back to the
  tolerant path only when one is missing or mistyped.
- **Validity windows** send only the bounds that are set; Koofr replaces
  both, so an omitted bound is cleared (checked live for links). A window
  that ends before it starts is refused.
- **`limits` returns `json.Value`**: the description gives it no schema.
  `Mount.spaceTotal` and `spaceUsed` are passed through without a unit, since
  the description names none.
- **Naming.** `list` is a reserved word, so the folder listing is
  `listFolder`.

## Errors

- Every kind `"koofr"` error is a `KoofrError{kind: "koofr", message,
  status, code}`: `status` is the HTTP status (0 for a local check or a
  failure with no answer) and `code` Koofr's `error.code`. The message names
  the route (cut to 200 characters, since a trash cursor is
  server-controlled) and Koofr's reason (cut to 200 printable ASCII
  characters); caller and server strings are cut to 60.
- A reply or download over its cap, a JSON or NDJSON reply past the
  decoder's caps, and `trashAll` past `MAX_PAGES`, are kind `"limit"`; a
  request with no answer by its deadline is kind `"timeout"`, a reply cut
  short kind `"closed"` (each with the request named in the message), and a
  cancelled task stays `"cancelled"`.
- A network failure (refused, reset, unreachable, DNS, TLS) is the
  interpreter's `net.NetError` of kind `"net"`, passed on unchanged so its
  `reason`, `sent` and `replied` fields survive; it is never retried.
- Other transport failures are a `KoofrError` with status 0.

## Security and limits

- **Credentials over plain http only to loopback.** An app password is a
  long-lived credential: every request checks, at send time, that a
  credentialed URL is https unless the host is loopback or `withPlainHttp`
  allows it. `Client.url` is public, so the check reads the URL as it is
  then, not as `client` built it.
- **Address checks.** Scheme http or https, a plain host or bracketed IPv6
  literal, a port 1 to 65535, nothing else in the authority, no query,
  fragment or userinfo. A URL `uri.parse` refuses (newer interpreters throw
  kind `"uri"` for a bad port or IP literal) is kind `"koofr"` too.
- **Caps.** `REPLY_LIMIT` (64 MiB) bounds every reply but downloads,
  changed with `withReplyLimit`; a 310,341-entry recursive listing (66 MiB)
  needs more. `get` takes its own cap (0 means `DOWNLOAD_LIMIT`, 64 MiB; a
  negative cap none). Bodies are held in memory.
- **Deadlines.** An idle timeout per request, 30 s by default.

## Testing and validation

- 63 tests against a loopback fake built on `httpd`, answering scripted
  replies in order (raw-byte bodies, per-reply headers, redirects and
  `Retry-After` included) and recording every request; assertions cover
  exact query strings, JSON bodies and the raw upload body. No network
  beyond loopback, no credentials. The regression tests of the 2026-11-06
  review each fail on the code before their fix.
- Checked live against app.koofr.net on 2026-11-06: `mounts`, `exists`,
  `mkdir`, raw-body `put` of text and 1 MiB of random bytes with `info` and
  `get` matching, the refusal of an existing file under the zero options,
  `listRecursive` of a non-root folder, conditional overwrite of a missing
  name, and creating, changing and listing links. Nothing else was run live;
  receivers, search, trash, copy and move are tested against the fake only.
- Measured on loopback: `listRecursive` of 100,001 entries in about 2.5 s
  and 593 MiB; `listFolder` of 100,000 in about 1.8 s and 655 MiB.
- The examples need a Koofr account; CI only parses them.

## Known limitations and open questions

- Bodies are held in memory both ways until `http` streams (`jennifer`'s
  M30.9).
- `put` reads its reply as text, since `http` has no raw-body request that
  returns bytes; a non-UTF-8 refusal of an upload loses its status.
- The units of a mount's space figures are unconfirmed.
- Returning a large `list of File` rebuilds it at the module boundary
  (`jennifer`'s M29.14), which the deck cannot avoid.

## Dependencies on the interpreter

- Floor `>=0.28.0` (the calls 0.29.0 removes are replaced by their 0.28.0 forms), the default binary and the `net` capability (not
  `jennifer-tiny`). The UTF-8 codecs of `encoding.encode` / `decode` and
  `strings.replicate` arrived in 0.27.0.
- `json.typeOf` returning `"missing"` for an unresolved pointer, `http`'s
  body-only `maxBytes`, `http.requestWithBytes` and
  `http.requestRawBodyTls`.
- Error structs with a kind (M28.50) and caps as kind `"limit"` (M28.54);
  the deck adopted both under M28.57. Network failures as `net.NetError`
  (M28.65).
