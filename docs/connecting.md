<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Getting started

## The address

`client` takes the service's base URL: `DEFAULT_URL` for Koofr, or another
provider's. A bare host gets `https://`; trailing `/`, `/api/v2.1` and
`/content/api/v2.1` are dropped, a sub-path is kept:

```jennifer
def c as koofr.Client init koofr.client(koofr.DEFAULT_URL);
$c = koofr.client("https://storage.example.com");
```

`client` throws for a URL with a query, a fragment or a user, a scheme other
than `http` or `https`, no host, or a port outside 1-65535.

`withCaCert` trusts a service's own CA; `withInsecure` turns certificate
checking off.

## App passwords

Create an app password in Koofr under Preferences > Password > App
passwords, and pass it with the account's e-mail address. It is sent as HTTP
Basic authentication; it also works for WebDAV and can be revoked on its
own.

```jennifer
$c = koofr.withAppPassword($c, "me@example.com", os.getEnv("KOOFR_PASSWORD"));
io.printf("%s %s\n", koofr.user($c).firstName, koofr.user($c).lastName);
```

A bearer token obtained elsewhere (OAuth) goes in with `withToken`. The deck
does not run the OAuth flow.

Credentials go over plain `http://` only to a loopback host (`localhost`,
`127.0.0.0/8`, `[::1]`). For any other `http://` host each request throws
before it connects; `withPlainHttp` lifts that, and the app password or
token then crosses the network unencrypted:

```jennifer
$c = koofr.withPlainHttp(koofr.withToken(koofr.client("http://koofr.lan:8080"), $token));
```

## Mounts

Every file lives on a mount: the account's own storage (the primary mount),
a connected device or cloud, or a folder others shared with the account.

```jennifer
for (def m in koofr.mounts($c)) {
    io.printf("%s %s %s\n", $m.id, $m.name, $m.origin);
}
def home as koofr.Mount init koofr.primaryMount($c);
io.printf("%d of %d used\n", $home.spaceUsed, $home.spaceTotal);
```

`limits` returns the account's limits undecoded: Koofr's API description
defines no schema for that reply.

## Any endpoint

`call` takes the path under `/api/v2.1` with its query string, and the body
as JSON text:

```jennifer
def places as json.Value init koofr.call($c, "GET", "/places", "");
koofr.call($c, "PUT", "/user", '{"firstName":"Ada"}');
```

## Timeouts, retries and reply size

`withTimeout` sets each request's idle timeout, 30 s by default; a negative
value throws. `withRetries` retries GETs (`listRecursive` included) answered
429 or 5xx, waiting 500 ms, then twice as long each time, or longer for a
`Retry-After` in seconds, at most 30 s. It takes 0 to `MAX_RETRIES` (10).
Writes, `get` and `put` are never retried.

Every reply but `get`'s is refused over `REPLY_LIMIT` (64 MiB), status line
and headers included. `withReplyLimit` sets another cap, or none with a
negative value. A recursive listing of a large mount is the reply most likely
to need it:

```jennifer
$c = koofr.withReplyLimit($c, 256 * 1024 * 1024);
```
