<!-- SPDX-License-Identifier: LGPL-3.0-only -->
<!-- SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev> -->

# koofr cheatsheet

Every export of `@deckyard/koofr`. Guides are listed in
[the introduction](index.md).

```jennifer
import "@deckyard/koofr/" as koofr;
```

Every function that sends a request throws `Error{kind: "koofr"}` when it
fails. A `mountId` comes from `mounts` or `primaryMount`; a `path` is
absolute in its mount (`/docs/a.txt`, `/` for the root). Times are
milliseconds since the epoch.

## Constants

| Constant | Value | Meaning |
|---|---|---|
| `ERROR_KIND` | `"koofr"` | the `kind` of every error the deck throws |
| `DEFAULT_URL` | `"https://app.koofr.net"` | Koofr's own service |
| `DOWNLOAD_LIMIT` | `67108864` | the largest reply `get` accepts with `maxBytes` 0 (64 MiB), head included |
| `REPLY_LIMIT` | `67108864` | the largest reply of every other request with `Client.replyLimit` 0 (64 MiB), head included |
| `MAX_RETRIES` | `10` | the most retries `withRetries` accepts |
| `SEARCH_MAX` | `1000` | the most results one `search` asks for |
| `MAX_PAGES` | `1000` | pages `trashAll` follows before it refuses |
| `FILE_TYPES` | `["file", "folder", "pdf", "document", "sheet", "presentation", "archive", "code", "text", "audio", "video", "image"]` | the values of `SearchOptions.fileType` |

## Types

A literal of a deck struct names every field, so build `PutOptions` and
`SearchOptions` from the zero value: `def o as koofr.PutOptions;` then set
fields.

### `Client`

| Field | Meaning |
|---|---|
| `url as string` | `https://host[:port][/path]`, without `/api/v2.1` |
| `auth as string` | the `Authorization` header value; `""` for none |
| `tls as http.TlsOptions` | certificate checking |
| `timeoutMs as int` | idle timeout per request; 0 for 30 s, never negative |
| `retries as int` | retries of a GET answered 429 or 5xx, 0 to `MAX_RETRIES` |
| `replyLimit as int` | the largest reply of every request but `get`; 0 for `REPLY_LIMIT`, negative for none |
| `plainHttp as bool` | send credentials over `http://` to a host that is not loopback |

Build a `Client` with `client` and the `with*` functions, not a literal.

### `User`

| Field | Meaning |
|---|---|
| `id as string` | the user id |
| `firstName as string` | the first name |
| `lastName as string` | the last name |
| `email as string` | the e-mail address |
| `level as int` | the account level Koofr reports |

### `Mount`

| Field | Meaning |
|---|---|
| `id as string` | the mount id |
| `name as string` | the name, e.g. `Koofr` |
| `type as string` | e.g. `device` or `export` |
| `origin as string` | e.g. `hosted`, `dropbox`, `share` |
| `owner as string` | the owner's name |
| `isPrimary as bool` | whether it is the account's primary storage |
| `isShared as bool` | whether it is shared with others |
| `online as bool` | whether it can be reached |
| `canWrite as bool` | whether the account may change it |
| `canUpload as bool` | whether the account may upload to it |
| `spaceTotal as int` | the quota as Koofr reports it (the API description names no unit); 0 when unreported |
| `spaceUsed as int` | the space used, in the unit of `spaceTotal` |
| `overQuota as bool` | whether it is over its quota |

### `File`

| Field | Meaning |
|---|---|
| `name as string` | the name; `""` for the root of a mount |
| `path as string` | the path in its mount |
| `type as string` | `file` or `dir` |
| `size as int` | bytes; 0 for a folder |
| `modified as int` | the modification time |
| `contentType as string` | the media type; `""` for a folder |
| `hash as string` | the content hash (MD5); `""` for a folder |

### `PutOptions`

| Field | Meaning |
|---|---|
| `overwrite as bool` | replace an existing file |
| `autorename as bool` | store under a free name when the name is taken |
| `overwriteIfHash as string` | replace only if the existing file has this hash; `""` for no condition |
| `overwriteIfModified as int` | replace only if the existing file has this time; 0 for no condition |
| `overwriteIgnoreNonexistent as bool` | with a condition, create the file when there is none |
| `modified as int` | the modification time to set; 0 for now |

The zero value refuses an existing file (HTTP 409).

### `SearchOptions`

| Field | Meaning |
|---|---|
| `offset as int` | results to skip |
| `limit as int` | results to return, up to `SEARCH_MAX`; 0 for Koofr's default (256) |
| `mountId as string` | only this mount; `""` for all |
| `path as string` | only below this folder; needs `mountId` |
| `contentType as string` | only this media type |
| `fileType as string` | one of `FILE_TYPES`; `""` for any |
| `tags as list of string` | only files with these tags, `key=value` with a non-empty key |

### `SearchHit`

| Field | Meaning |
|---|---|
| `mountId as string` | the mount it is on |
| `path as string` | the path in that mount |
| `name as string` | the name |
| `type as string` | `file` or `dir` |
| `size as int` | bytes |
| `modified as int` | the modification time |
| `contentType as string` | the media type |
| `score as float` | the relevance |

### `Link`

| Field | Meaning |
|---|---|
| `id as string` | the link id |
| `name as string` | the name of what it points at |
| `mountId as string` | the mount |
| `path as string` | the path in the mount |
| `url as string` | the link |
| `shortUrl as string` | the short form of the link |
| `counter as int` | how often it was opened |
| `hasPassword as bool` | whether it asks for a password |
| `downloadable as bool` | whether visitors may download |
| `message as string` | the message shown to visitors |
| `created as int` | when it was made |
| `validFrom as int` | 0 for no start |
| `validTo as int` | 0 for no end |

### `Receiver`

| Field | Meaning |
|---|---|
| `id as string` | the receiver id |
| `name as string` | the name of the folder |
| `mountId as string` | the mount |
| `path as string` | the folder in the mount |
| `url as string` | the link |
| `shortUrl as string` | the short form of the link |
| `counter as int` | how often it was used |
| `hasPassword as bool` | whether it asks for a password |
| `alert as bool` | whether the owner is told of uploads |
| `message as string` | the message shown to visitors |
| `created as int` | when it was made |
| `validFrom as int` | 0 for no start |
| `validTo as int` | 0 for no end |

### `TrashFile`

| Field | Meaning |
|---|---|
| `mountId as string` | the mount it was deleted from |
| `path as string` | its path there |
| `name as string` | the name |
| `size as int` | bytes |
| `deleted as int` | when it was deleted |
| `contentType as string` | the media type |
| `versionId as string` | the deleted version |

### `TrashPage`

| Field | Meaning |
|---|---|
| `files as list of TrashFile` | the files |
| `cursor as string` | the cursor of the next page; `""` on the last |
| `retentionDays as int` | how long the trash keeps a file |

## Connecting

| Function | Returns | Does |
|---|---|---|
| `koofr.client(baseUrl)` | `Client` | a client without credentials; refuses a URL with a query, fragment or user, a scheme other than `http`/`https`, no host or a bad port |
| `koofr.withAppPassword(c, email, password)` | `Client` | authenticate with an app password (HTTP Basic) |
| `koofr.withToken(c, token)` | `Client` | authenticate with a bearer token |
| `koofr.withPlainHttp(c)` | `Client` | allow credentials over `http://` to a host that is not loopback |
| `koofr.withCaCert(c, pem)` | `Client` | trust a PEM certificate (`bytes`); undoes `withInsecure` |
| `koofr.withInsecure(c)` | `Client` | accept any certificate |
| `koofr.withTimeout(c, ms)` | `Client` | set the idle timeout; refuses a negative `ms` |
| `koofr.withRetries(c, n)` | `Client` | retry GETs answered 429 or 5xx, `n` 0 to `MAX_RETRIES`; not `get` |
| `koofr.withReplyLimit(c, maxBytes)` | `Client` | cap every reply but `get`'s; 0 for `REPLY_LIMIT`, negative for none |
| `koofr.call(c, method, path, body)` | `json.Value` | any endpoint under `/api/v2.1`; `body` is JSON text |

## Account

| Function | Returns | Does |
|---|---|---|
| `koofr.user(c)` | `User` | the credentials' account |
| `koofr.limits(c)` | `json.Value` | the account's limits, undecoded |
| `koofr.mounts(c)` | `list of Mount` | storage, devices and shared folders |
| `koofr.mount(c, id)` | `Mount` | one mount |
| `koofr.primaryMount(c)` | `Mount` | the account's primary storage |

## Files

| Function | Returns | Does |
|---|---|---|
| `koofr.info(c, mountId, path)` | `File` | one file or folder |
| `koofr.exists(c, mountId, path)` | `bool` | false on HTTP 404 with error code `NotFound` or none; another 404 throws |
| `koofr.listFolder(c, mountId, path)` | `list of File` | the entries of a folder |
| `koofr.listRecursive(c, mountId, path)` | `list of File` | everything below a folder, the folder first |
| `koofr.mkdir(c, mountId, path)` | - | make a folder in an existing parent |
| `koofr.mkdirAll(c, mountId, path)` | - | make a folder and its missing parents; 1 request when it exists |
| `koofr.get(c, mountId, path, maxBytes)` | `bytes` | download; `maxBytes` caps the reply, head included, 0 for `DOWNLOAD_LIMIT`, negative for none |
| `koofr.put(c, mountId, path, data, opts)` | `File` | upload as a raw `application/octet-stream` body |
| `koofr.remove(c, mountId, path)` | - | move a file or folder to the trash; not `/` |
| `koofr.rename(c, mountId, path, name)` | - | rename in place; not `/` |
| `koofr.copy(c, mountId, path, toMountId, toPath)` | `string` | copy, also to another mount; the copy's name |
| `koofr.move(c, mountId, path, toMountId, toPath)` | `string` | move, also to another mount; the new name |

## Search

| Function | Returns | Does |
|---|---|---|
| `koofr.search(c, query, opts)` | `list of SearchHit` | search names across mounts |

## Public links

| Function | Returns | Does |
|---|---|---|
| `koofr.links(c, mountId)` | `list of Link` | the links of a mount |
| `koofr.allLinks(c)` | `list of Link` | the links of every mount |
| `koofr.createLink(c, mountId, path)` | `Link` | share a file or folder |
| `koofr.link(c, mountId, id)` | `Link` | one link |
| `koofr.deleteLink(c, mountId, id)` | - | delete a link |
| `koofr.setLinkPassword(c, mountId, id, password)` | `Link` | ask visitors for a password |
| `koofr.clearLinkPassword(c, mountId, id)` | `Link` | remove the password |
| `koofr.setLinkValidity(c, mountId, id, validFrom, validTo)` | `Link` | limit when it works; 0 for no bound |

## Receivers

| Function | Returns | Does |
|---|---|---|
| `koofr.receivers(c, mountId)` | `list of Receiver` | the receivers of a mount |
| `koofr.allReceivers(c)` | `list of Receiver` | the receivers of every mount |
| `koofr.createReceiver(c, mountId, path)` | `Receiver` | let others upload into a folder |
| `koofr.receiver(c, mountId, id)` | `Receiver` | one receiver |
| `koofr.deleteReceiver(c, mountId, id)` | - | delete a receiver |
| `koofr.setReceiverPassword(c, mountId, id, password)` | `Receiver` | ask uploaders for a password |
| `koofr.clearReceiverPassword(c, mountId, id)` | `Receiver` | remove the password |
| `koofr.setReceiverValidity(c, mountId, id, validFrom, validTo)` | `Receiver` | limit when it accepts uploads; 0 for no bound |

## Trash

| Function | Returns | Does |
|---|---|---|
| `koofr.trash(c, cursor)` | `TrashPage` | one page of up to 1000 files by name, ascending; `cursor` `""` for the first |
| `koofr.trashAll(c)` | `list of TrashFile` | every page; stops at a cursor it followed before |
| `koofr.undelete(c, files)` | - | restore these files; refuses an empty list |
| `koofr.undeleteAll(c)` | - | restore everything |
| `koofr.emptyTrash(c)` | - | delete the trash for good |
