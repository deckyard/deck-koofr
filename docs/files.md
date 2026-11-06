<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Files

Every file function takes a mount id and an absolute path in that mount.
Paths start with `/` and have no empty, `.` or `..` segments, no control
characters and no trailing `/` (except the root, `/`).

```jennifer
def m as koofr.Mount init koofr.primaryMount($c);
```

## Reading

```jennifer
def f as koofr.File init koofr.info($c, $m.id, "/docs/report.pdf");
io.printf("%s %d bytes, %s\n", $f.path, $f.size, $f.hash);

if (koofr.exists($c, $m.id, "/docs/old.pdf")) {
    koofr.remove($c, $m.id, "/docs/old.pdf");
}

for (def e in koofr.listFolder($c, $m.id, "/docs")) {
    io.printf("%s %s\n", $e.type, $e.path);
}
```

`exists` is false for a 404 with Koofr's JSON error object whose code is
`NotFound`, empty or absent. A 404 with another code, such as
`DeviceOffline` for a device that is not connected, throws: it says nothing
about the file. So does a 404 without that JSON body (an HTML page from a
proxy, a wrong base URL path).

`listFolder` and `listRecursive` throw on a name or path from the server
that would not address an entry inside the folder: an empty name, `.`, `..`,
a `/` in a name, or a recursive item path that is empty, `/` (after the
first item), or holds `..` or empty segments.

`listRecursive` returns everything below a folder in one request, the
folder itself first, each with its full path. Koofr ends the stream with an
error item when it breaks off (a device went offline); the deck then throws
instead of returning a partial list. It also throws on an entry without a
`path` or `file`. Item paths are relative to the requested folder. The stream is read whole and capped by the client's reply
limit (`REPLY_LIMIT`, 64 MiB; see `withReplyLimit` in
[Getting started](connecting.md)).

```jennifer
def total as int init 0;
for (def e in koofr.listRecursive($c, $m.id, "/photos")) {
    $total = $total + $e.size;
}
```

## Downloading

`get` returns the file as `bytes`. `maxBytes` caps the body: 0 for
`DOWNLOAD_LIMIT` (64 MiB), a negative number for no cap.

```jennifer
def data as bytes init koofr.get($c, $m.id, "/docs/report.pdf", 0);
fs.writeBytes("report.pdf", $data);
```

## Uploading

`put` takes the full path of the file; its folder must exist (`mkdirAll`
makes it). The content is sent as the raw request body
(`application/octet-stream`) with the name in the `filename` query
parameter. `PutOptions` says what happens when the name is taken. Its zero
value refuses (HTTP 409):

```jennifer
koofr.mkdirAll($c, $m.id, "/backups/2026");
def opts as koofr.PutOptions;
$opts.overwrite = true;
def stored as koofr.File init koofr.put($c, $m.id, "/backups/2026/db.sql", fs.readBytes("db.sql"), $opts);
```

`autorename` stores the file under a free name instead (`db (1).sql`); the
returned `File` carries the name it got. `overwriteIfHash` and
`overwriteIfModified` replace a file only if it is still the version the
program saw, so two writers do not overwrite each other:

```jennifer
def seen as koofr.File init koofr.info($c, $m.id, "/notes.txt");
def guarded as koofr.PutOptions;
$guarded.overwriteIfHash = $seen.hash;
koofr.put($c, $m.id, "/notes.txt", fs.readBytes("notes.txt"), $guarded);
```

## Changing

```jennifer
koofr.mkdir($c, $m.id, "/docs/2026");
koofr.rename($c, $m.id, "/docs/draft.md", "final.md");
koofr.copy($c, $m.id, "/docs/final.md", $m.id, "/archive/final.md");
koofr.move($c, $m.id, "/inbox/scan.pdf", $other.id, "/scans/scan.pdf");
koofr.remove($c, $m.id, "/tmp");
```

`mkdirAll` asks for the full path first and returns when it is a folder.
Otherwise it asks for each parent from the top until one is missing, then
makes that one and every folder below it without asking again.

`copy` and `move` take the full target path and may target another mount.
They return the name Koofr gave the result. Every function that changes a
path (`mkdir`, `put`, `remove`, `rename`, `copy`, `move`) refuses the root.
`remove` moves to the trash; see
[Search and trash](search.md).
