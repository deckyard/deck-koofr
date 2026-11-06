<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# Links and receivers

## Public links

A public link lets anyone with the URL see or download a file or folder.

```jennifer
def l as koofr.Link init koofr.createLink($c, $m.id, "/docs/report.pdf");
io.printf("%s\n", $l.shortUrl);
```

Protect it with a password, or limit when it works (milliseconds since the
epoch; 0 for no bound):

```jennifer
$l = koofr.setLinkPassword($c, $m.id, $l.id, "s3cret");
$l = koofr.setLinkValidity($c, $m.id, $l.id, 0, $endOfMonth);
$l = koofr.clearLinkPassword($c, $m.id, $l.id);
```

`links` lists the links of one mount, `allLinks` those of every mount.
`deleteLink` removes a link and leaves the file.

```jennifer
for (def old in koofr.allLinks($c)) {
    if ($old.counter == 0) {
        koofr.deleteLink($c, $old.mountId, $old.id);
    }
}
```

## Receivers

A receiver is the other direction: a link through which others upload files
into a folder of the account.

```jennifer
def r as koofr.Receiver init koofr.createReceiver($c, $m.id, "/inbox");
$r = koofr.setReceiverPassword($c, $m.id, $r.id, "upload-here");
io.printf("send files to %s\n", $r.url);
```

The functions mirror the links: `receivers`, `allReceivers`, `receiver`,
`deleteReceiver`, `setReceiverPassword`, `clearReceiverPassword`,
`setReceiverValidity`.

Koofr limits how many links and receivers an account has; past it, creating
one fails with HTTP 429.
