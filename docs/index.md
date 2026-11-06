<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# @deckyard/koofr

A client for the [Koofr](https://koofr.eu/) cloud storage API (`/api/v2.1`).
Typed functions cover the account and its mounts, files and folders
(information, listing, recursive listing, folders, download, upload,
remove, rename, copy, move), search, public links, receivers (upload links)
and the trash. `call` reaches any other endpoint. Another provider of the
same API works with its own base URL.

Plain file sync does not need this deck: Koofr speaks WebDAV at
`https://app.koofr.net/dav/Koofr`, which the interpreter's `webdav` module
reaches with the same app password. This deck covers what WebDAV cannot:
mounts and quotas, search, links, receivers, the trash, copies between
mounts, and conditional uploads.

## Conventions

Snippets assume this import:

```jennifer
import "@deckyard/koofr/" as koofr;

def c as koofr.Client init koofr.client(koofr.DEFAULT_URL);
$c = koofr.withAppPassword($c, "me@example.com", os.getEnv("KOOFR_PASSWORD"));
io.printf("%s\n", koofr.user($c).email);
```

A `Client` is a value. `withAppPassword` and the other `with*` functions
return a changed copy, so assign the result back to `$c`.

Files are addressed by a mount id and an absolute path in that mount:
`koofr.info($c, $m.id, "/docs/a.txt")`. Times are milliseconds since the
epoch, as Koofr sends them.

## Errors

Every failure is `Error{kind: "koofr"}`. A refusal names the request, the
HTTP status, Koofr's message and its error code:

```text
koofr: GET /api/v2.1/mounts/1f2e.../files/info?path=%2Fmissing: HTTP 404: File not found (NotFound)
koofr: a path has no empty, . or .. segments, got "/a/../b"
```

Bad input (a relative path, a `..` segment, an id with a `/`, credentials
over `http://` to a host that is not loopback) is refused before anything is
sent.

## Limits

Bodies are held in memory: `get` reads the whole file (capped by
`maxBytes`), `put` sends it from a `bytes` value, and `listRecursive` reads
the whole stream before parsing it (capped by `REPLY_LIMIT` or
`withReplyLimit`). The interpreter's `http` module does not stream yet.

## Requirements

Jennifer 0.26.0 or newer, the default `jennifer` binary (not
`jennifer-tiny`), and the `net` capability.
