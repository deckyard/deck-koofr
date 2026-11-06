# @deckyard/koofr

[![test](https://github.com/deckyard/deck-koofr/actions/workflows/test.yml/badge.svg)](https://github.com/deckyard/deck-koofr/actions/workflows/test.yml)
[![Documentation](https://img.shields.io/badge/docs-github%20pages-blue)](https://deckyard.github.io/deck-koofr/)
[![release](https://img.shields.io/github/v/release/deckyard/deck-koofr)](https://github.com/deckyard/deck-koofr/releases/latest)

A client for the [Koofr](https://koofr.eu/) cloud storage API, for
[Jennifer](https://jennifer-lang.dev/) programs: the account and its mounts,
files and folders (list, recursive list, download, upload with overwrite
conditions, rename, copy and move across mounts), search, public links,
receivers (upload links) and the trash. `call` reaches any other endpoint.
Other providers running the same API work with their own base URL.

Plain file sync can use the interpreter's `webdav` module against
`https://app.koofr.net/dav/Koofr` with the same app password; this deck
covers what WebDAV cannot.

**[Documentation](https://deckyard.github.io/deck-koofr/)**

## Install

```sh
jvc add @deckyard/koofr
```

This vendors the deck to `vendor/deckyard/koofr/`. Without `jvc`, unpack the
`src/` subtree of a release archive (`deckyard-koofr-<version>.tar.gz`) there.

## Usage

```jennifer
use fs;
use io;
use os;

import "@deckyard/koofr/" as koofr;

def c as koofr.Client init koofr.client(koofr.DEFAULT_URL);
$c = koofr.withAppPassword($c, "me@example.com", os.getEnv("KOOFR_PASSWORD"));
def m as koofr.Mount init koofr.primaryMount($c);

koofr.mkdirAll($c, $m.id, "/backups/2026");
def opts as koofr.PutOptions;
$opts.overwrite = true;
koofr.put($c, $m.id, "/backups/2026/db.sql", fs.readBytes("db.sql"), $opts);
io.printf("%s\n", koofr.createLink($c, $m.id, "/backups/2026/db.sql").shortUrl);
```

## Requirements

Jennifer 0.26.0 or newer, the default `jennifer` binary (not
`jennifer-tiny`), and the `net` capability. Uploads and downloads are held
in memory: the interpreter's `http` module does not stream yet.

## Development

```sh
tools/check-all.sh                   # the full gate, as CI runs it
jennifer test src/koofr_test.j       # the test overlay
tools/check-docs.sh                  # docs against the code
tools/pack.sh dist                   # build the release archive
```

## Licence

LGPL-3.0-only, see [LICENSE](LICENSE). Copyright (C) 2026 mplx &lt;mplx@jennifer-lang.dev&gt;.

`tools/check-headers.sh` checks every source file's SPDX header against
`deck.toml`.
