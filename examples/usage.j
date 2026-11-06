# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * Show the account's mounts with their space, the ten largest files below
 * a folder of the primary mount (default `/`), and the number of files in
 * the trash.
 *
 *   KOOFR_EMAIL=me@example.com KOOFR_PASSWORD=app-password \
 *     jennifer run examples/usage.j [/photos]
 *
 * KOOFR_PASSWORD is an app password (Koofr: Preferences > Password > App passwords).
 * KOOFR_URL selects another provider of the same API.
 */
use io;
use lists;
use os;

import "../src/koofr.j" as koofr;

/**
 * The sort key that puts the largest file first.
 *
 * @param f {koofr.File} the file
 * @return {int} its size, negated
 */
func largestFirst(f as koofr.File) {
    return 0 - $f.size;
}

if (not os.hasEnv("KOOFR_EMAIL") or not os.hasEnv("KOOFR_PASSWORD")) {
    throw Error{kind: "usage", message: "set KOOFR_EMAIL and KOOFR_PASSWORD"};
}
def folder as string init "/";
if (len(os.ARGS) == 2) {
    $folder = os.ARGS[1];
}
def url as string init koofr.DEFAULT_URL;
if (os.hasEnv("KOOFR_URL")) {
    $url = os.getEnv("KOOFR_URL");
}
def c as koofr.Client init koofr.withRetries(koofr.client($url), 2);
$c = koofr.withAppPassword($c, os.getEnv("KOOFR_EMAIL"), os.getEnv("KOOFR_PASSWORD"));

io.printf("%s\n", koofr.user($c).email);
for (def m in koofr.mounts($c)) {
    io.printf("  %s (%s): %d of %d used\n", $m.name, $m.origin, $m.spaceUsed, $m.spaceTotal);
}

def primary as koofr.Mount init koofr.primaryMount($c);
def files as list of koofr.File init [];
for (def f in koofr.listRecursive($c, $primary.id, $folder)) {
    if ($f.type == "file") {
        $files[] = $f;
    }
}
$files = lists.sortBy($files, largestFirst);
def i as int init 0;
while ($i < len($files) and $i < 10) {
    io.printf("%d %s\n", $files[$i].size, $files[$i].path);
    $i = $i + 1;
}

io.printf("trash: %d files\n", len(koofr.trashAll($c)));
