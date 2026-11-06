<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Search and trash

## Search

`search` looks for names across every mount. `SearchOptions` narrows it;
its zero value searches everything with Koofr's default limit (256 hits).

```jennifer
def none as koofr.SearchOptions;
for (def h in koofr.search($c, "invoice", $none)) {
    io.printf("%s %s\n", $h.mountId, $h.path);
}
```

```jennifer
def o as koofr.SearchOptions;
$o.mountId = $m.id;
$o.path = "/photos";
$o.fileType = "image";
$o.limit = koofr.SEARCH_MAX;
def photos as list of koofr.SearchHit init koofr.search($c, "", $o);
```

`fileType` is one of `FILE_TYPES`; `path` needs `mountId`; `tags` holds
`key=value` filters. Page with `offset` and `limit`. `search` throws before
sending for a `limit` outside 0..`SEARCH_MAX`, a negative `offset`, an
unknown `fileType`, a `path` without `mountId` or a tag without a key before
`=`.

## Trash

`remove` moves files to the trash, where Koofr keeps them for
`retentionDays`. `trash` reads one page, up to 1000 files sorted by name,
and hands back the cursor of the next; `trashAll` follows it and stops at a
cursor it has followed before.

```jennifer
def page as koofr.TrashPage init koofr.trash($c, "");
io.printf("kept for %d days\n", $page.retentionDays);

def gone as list of koofr.TrashFile init [];
for (def f in koofr.trashAll($c)) {
    if (strings.startsWith($f.path, "/docs/")) {
        $gone[] = $f;
    }
}
koofr.undelete($c, $gone);
```

`undelete` refuses an empty list, because Koofr reads an empty list as
"everything"; `undeleteAll` sends the empty list on purpose. `emptyTrash`
deletes the trash of every mount for good. All three start a background job
at Koofr and may return before it is done.
