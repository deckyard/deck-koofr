# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * Upload a local file into a folder of the primary mount, replacing an
 * older copy, and print a public link to it.
 *
 *   KOOFR_EMAIL=me@example.com KOOFR_PASSWORD=app-password \
 *     jennifer run examples/backup.j report.pdf /backups/2026
 *
 * KOOFR_PASSWORD is an app password (Koofr: Preferences > Password).
 * KOOFR_URL selects another provider of the same API.
 */
use fs;
use io;
use os;
use path;

import "../src/koofr.j" as koofr;

if (len(os.ARGS) != 3) {
    throw Error{kind: "usage", message: "usage: backup.j <file> </folder>"};
}
if (not os.hasEnv("KOOFR_EMAIL") or not os.hasEnv("KOOFR_PASSWORD")) {
    throw Error{kind: "usage", message: "set KOOFR_EMAIL and KOOFR_PASSWORD"};
}
def url as string init koofr.DEFAULT_URL;
if (os.hasEnv("KOOFR_URL")) {
    $url = os.getEnv("KOOFR_URL");
}
def c as koofr.Client init koofr.withRetries(koofr.client($url), 2);
$c = koofr.withAppPassword($c, os.getEnv("KOOFR_EMAIL"), os.getEnv("KOOFR_PASSWORD"));

def m as koofr.Mount init koofr.primaryMount($c);
def folder as string init os.ARGS[2];
koofr.mkdirAll($c, $m.id, $folder);

def opts as koofr.PutOptions;
$opts.overwrite = true;
def target as string init $folder + "/" + path.base(os.ARGS[1]);
def f as koofr.File init koofr.put($c, $m.id, $target, fs.readBytes(os.ARGS[1]), $opts);
io.printf("stored %s, %d bytes, hash %s\n", $f.path, $f.size, $f.hash);

def l as koofr.Link init koofr.createLink($c, $m.id, $f.path);
io.printf("link %s\n", $l.shortUrl);
