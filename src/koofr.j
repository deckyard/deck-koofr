# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0
# pragma-jennifer-capability: net

/**
 * A client for the Koofr cloud storage API (`/api/v2.1`).
 *
 * Account and mounts, files by mount id and path (info, list, recursive
 * list, folders, download, upload, remove, rename, copy, move), search,
 * public links, receivers (upload links) and the trash. `call` reaches any
 * other endpoint. Another provider of the same API works with its own base
 * URL.
 *
 * A `Client` authenticates with an app password (`withAppPassword`, HTTP
 * Basic) or a bearer token (`withToken`). Every failure is
 * `Error{kind: "koofr"}`. Bodies are held in memory; `get` refuses a file over
 * `DOWNLOAD_LIMIT` (64 MiB) unless `maxBytes` says otherwise, and every other
 * reply is refused over `REPLY_LIMIT` (64 MiB) unless `withReplyLimit` says
 * otherwise. Credentials go over plain `http://` only to a loopback host or
 * after `withPlainHttp`.
 *
 * @module koofr
 * @see https://app.koofr.net/developers
 * @example
 *   def c as koofr.Client init koofr.client(koofr.DEFAULT_URL);
 *   $c = koofr.withAppPassword($c, "me@example.com", $password);
 *   def m as koofr.Mount init koofr.primaryMount($c);
 *   for (def f in koofr.listFolder($c, $m.id, "/")) {
 *       io.printf("%s %d\n", $f.name, $f.size);
 *   }
 */
use convert;
use json;
use lists;
use maps;
use regex;
use strings;
import "http.j" as http;
import "jsonl.j" as jsonl;
import "uri.j" as uri;

/** The `kind` of every error the deck throws. */
export def const ERROR_KIND as string init "koofr";

/** Koofr's own service, the usual argument of `client`. */
export def const DEFAULT_URL as string init "https://app.koofr.net";

/** The largest download `get` accepts when `maxBytes` is 0: 64 MiB. */
export def const DOWNLOAD_LIMIT as int init 67108864;

/**
 * The largest reply body of every request but `get` when `Client.replyLimit`
 * is 0: 64 MiB. It bounds `listRecursive`, `listFolder`, `search`, `trash`
 * and `call`.
 */
export def const REPLY_LIMIT as int init 67108864;

/** The most retries `withRetries` accepts. */
export def const MAX_RETRIES as int init 10;

/** The most results one `search` asks for. */
export def const SEARCH_MAX as int init 1000;

/** The most pages `trashAll` follows before it refuses. */
export def const MAX_PAGES as int init 1000;

/** The values `SearchOptions.fileType` takes besides "". */
export def const FILE_TYPES as list of string init [
    "file",
    "folder",
    "pdf",
    "document",
    "sheet",
    "presentation",
    "archive",
    "code",
    "text",
    "audio",
    "video",
    "image"
];

/**
 * A connection to one Koofr service.
 *
 * @field url {string} `https://host[:port][/path]`, without `/api/v2.1`
 * @field auth {string} the `Authorization` header value; "" for none
 * @field tls {http.TlsOptions} certificate checking
 * @field timeoutMs {int} the idle timeout of each request; 0 for 30 s, never
 *   negative
 * @field retries {int} retries of a GET answered 429 or 5xx, 0 to
 *   `MAX_RETRIES`
 * @field replyLimit {int} the largest reply body of every request but `get`;
 *   0 for `REPLY_LIMIT`, negative for none
 * @field plainHttp {bool} send credentials over `http://` to a host that is
 *   not loopback
 */
export def struct Client {
    url as string,
    auth as string,
    tls as http.TlsOptions,
    timeoutMs as int,
    retries as int,
    replyLimit as int,
    plainHttp as bool
};

/**
 * An account.
 *
 * @field id {string} the user id
 * @field firstName {string} the first name
 * @field lastName {string} the last name
 * @field email {string} the e-mail address
 * @field level {int} the account level Koofr reports
 */
export def struct User {
    id as string,
    firstName as string,
    lastName as string,
    email as string,
    level as int
};

/**
 * A mount: the account's own storage, a connected device or a folder shared
 * with the account. Files are addressed by mount id and path.
 *
 * @field id {string} the mount id
 * @field name {string} the name, e.g. `Koofr`
 * @field type {string} e.g. `device` or `export`
 * @field origin {string} e.g. `hosted`, `dropbox`, `share`
 * @field owner {string} the owner's name
 * @field isPrimary {bool} whether it is the account's primary storage
 * @field isShared {bool} whether it is shared with others
 * @field online {bool} whether it can be reached
 * @field canWrite {bool} whether the account may change it
 * @field canUpload {bool} whether the account may upload to it
 * @field spaceTotal {int} the quota as Koofr reports it (the API description
 *   names no unit); 0 when unreported
 * @field spaceUsed {int} the space used, in the unit of `spaceTotal`
 * @field overQuota {bool} whether it is over its quota
 */
export def struct Mount {
    id as string,
    name as string,
    type as string,
    origin as string,
    owner as string,
    isPrimary as bool,
    isShared as bool,
    online as bool,
    canWrite as bool,
    canUpload as bool,
    spaceTotal as int,
    spaceUsed as int,
    overQuota as bool
};

/**
 * A file or folder.
 *
 * @field name {string} the name; "" for the root of a mount
 * @field path {string} the path in its mount, e.g. `/docs/a.txt`
 * @field type {string} `file` or `dir`
 * @field size {int} bytes; 0 for a folder
 * @field modified {int} the modification time, ms since the epoch
 * @field contentType {string} the media type; "" for a folder
 * @field hash {string} the content hash Koofr keeps (MD5); "" for a folder
 */
export def struct File {
    name as string,
    path as string,
    type as string,
    size as int,
    modified as int,
    contentType as string,
    hash as string
};

/**
 * How `put` treats a file that already exists. The zero value refuses it
 * (HTTP 409).
 *
 * @field overwrite {bool} replace an existing file
 * @field autorename {bool} store under a free name, e.g. `a (1).txt`, when
 *   the name is taken
 * @field overwriteIfHash {string} replace only if the existing file has this
 *   hash; "" for no condition
 * @field overwriteIfModified {int} replace only if the existing file has this
 *   modification time (ms); 0 for no condition
 * @field overwriteIgnoreNonexistent {bool} with a condition, create the file
 *   when there is none to compare with
 * @field modified {int} the modification time to set (ms); 0 for now
 */
export def struct PutOptions {
    overwrite as bool,
    autorename as bool,
    overwriteIfHash as string,
    overwriteIfModified as int,
    overwriteIgnoreNonexistent as bool,
    modified as int
};

/**
 * Filters of a `search`. The zero value searches everything with Koofr's
 * default limit.
 *
 * @field offset {int} results to skip
 * @field limit {int} results to return, up to `SEARCH_MAX`; 0 for Koofr's
 *   default (256)
 * @field mountId {string} only this mount; "" for all
 * @field path {string} only below this folder; needs `mountId`
 * @field contentType {string} only this media type, e.g. `image/png`
 * @field fileType {string} one of `FILE_TYPES`; "" for any
 * @field tags {list of string} only files with these tags, `key=value` with
 *   a non-empty key
 */
export def struct SearchOptions {
    offset as int,
    limit as int,
    mountId as string,
    path as string,
    contentType as string,
    fileType as string,
    tags as list of string
};

/**
 * A search result.
 *
 * @field mountId {string} the mount it is on
 * @field path {string} the path in that mount
 * @field name {string} the name
 * @field type {string} `file` or `dir`
 * @field size {int} bytes
 * @field modified {int} ms since the epoch
 * @field contentType {string} the media type
 * @field score {float} the relevance
 */
export def struct SearchHit {
    mountId as string,
    path as string,
    name as string,
    type as string,
    size as int,
    modified as int,
    contentType as string,
    score as float
};

/**
 * A public link to a file or folder.
 *
 * @field id {string} the link id
 * @field name {string} the name of what it points at
 * @field mountId {string} the mount
 * @field path {string} the path in the mount
 * @field url {string} the link
 * @field shortUrl {string} the short form of the link
 * @field counter {int} how often it was opened
 * @field hasPassword {bool} whether it asks for a password
 * @field downloadable {bool} whether visitors may download
 * @field message {string} the message shown to visitors
 * @field created {int} ms since the epoch
 * @field validFrom {int} ms since the epoch; 0 for no start
 * @field validTo {int} ms since the epoch; 0 for no end
 */
export def struct Link {
    id as string,
    name as string,
    mountId as string,
    path as string,
    url as string,
    shortUrl as string,
    counter as int,
    hasPassword as bool,
    downloadable as bool,
    message as string,
    created as int,
    validFrom as int,
    validTo as int
};

/**
 * A receiver: a link others upload files to a folder through.
 *
 * @field id {string} the receiver id
 * @field name {string} the name of the folder
 * @field mountId {string} the mount
 * @field path {string} the folder in the mount
 * @field url {string} the link
 * @field shortUrl {string} the short form of the link
 * @field counter {int} how often it was used
 * @field hasPassword {bool} whether it asks for a password
 * @field alert {bool} whether the owner is told of uploads
 * @field message {string} the message shown to visitors
 * @field created {int} ms since the epoch
 * @field validFrom {int} ms since the epoch; 0 for no start
 * @field validTo {int} ms since the epoch; 0 for no end
 */
export def struct Receiver {
    id as string,
    name as string,
    mountId as string,
    path as string,
    url as string,
    shortUrl as string,
    counter as int,
    hasPassword as bool,
    alert as bool,
    message as string,
    created as int,
    validFrom as int,
    validTo as int
};

/**
 * A file in the trash.
 *
 * @field mountId {string} the mount it was deleted from
 * @field path {string} its path there
 * @field name {string} the name
 * @field size {int} bytes
 * @field deleted {int} when it was deleted, ms since the epoch
 * @field contentType {string} the media type
 * @field versionId {string} the deleted version
 */
export def struct TrashFile {
    mountId as string,
    path as string,
    name as string,
    size as int,
    deleted as int,
    contentType as string,
    versionId as string
};

/**
 * One page of the trash.
 *
 * @field files {list of TrashFile} the files
 * @field cursor {string} the cursor of the next page; "" on the last
 * @field retentionDays {int} how long the trash keeps a file
 */
export def struct TrashPage {
    files as list of TrashFile,
    cursor as string,
    retentionDays as int
};

# The API under the base URL.
def const API as string init "/api/v2.1";

# The content API (downloads, uploads, recursive lists) under the base URL.
def const CONTENT as string init "/content/api/v2.1";

# A mount, link or receiver id.
def const ID_PATTERN as string init "^[A-Za-z0-9_-]+$";

# How much of a string an error message repeats.
def const SHOWN as int init 60;

# How much of the server's reason for a refusal an error message repeats.
def const REASON as int init 200;

# The idle timeout a `timeoutMs` of 0 stands for, as `http.send` has it.
def const DEFAULT_TIMEOUT_MS as int init 30000;

func fail(message as string) {
    throw Error{kind: ERROR_KIND, message: "koofr: " + $message};
}

/**
 * A string fit for an error message: cut to `most` characters, with
 * anything but printable ASCII as `?`, so a message stays one line and
 * carries no terminal escape into a log.
 *
 * @param text {string} a caller's or the server's string
 * @param most {int} the characters kept
 * @return {string} the text
 */
func plain(text as string, most as int) {
    def cut as string init $text;
    def more as string init "";
    if (len($text) > $most) {
        $cut = strings.substring($text, 0, $most);
        $more = "...";
    }
    return regex.replace("[^ -~]", $cut, "?") + $more;
}

/**
 * A string as an error message quotes it: `plain`, cut to `SHOWN`.
 *
 * @param text {string} a caller's or the server's string
 * @return {string} the text in double quotes
 */
func shown(text as string) {
    return "\"" + plain($text, SHOWN) + "\"";
}

/**
 * A path without its trailing slashes.
 *
 * @param path {string} a URL path
 * @return {string} the path
 */
func trimSlashes(path as string) {
    def out as string init $path;
    while (strings.endsWith($out, "/")) {
        $out = strings.substring($out, 0, len($out) - 1);
    }
    return $out;
}

/**
 * The base URL for a host name or URL, checked with `uri.parse`. A bare host
 * gets `https://`. The scheme is lower-cased; trailing slashes and a trailing
 * `/content/api/v2.1` or `/api/v2.1` are dropped.
 *
 * @param address {string} `app.koofr.net` or a full URL
 * @return {string} `http[s]://host[:port][/path]`
 */
func normalUrl(address as string) {
    def url as string init strings.trim($address);
    if ($url == "") {
        fail("the base URL is empty");
    }
    if (regex.matches("[\\s\\x00-\\x1f\\x7f]", $url)) {
        fail("a base URL holds no spaces or control characters, got " + shown($url));
    }
    if (not strings.contains($url, "://")) {
        $url = "https://" + $url;
    }
    if (strings.contains($url, "?") or strings.contains($url, "#")) {
        fail("a base URL has no query or fragment, got " + shown($url));
    }
    def u as uri.Uri init uri.parse($url);
    def scheme as string init strings.lower($u.scheme);
    if ($scheme != "http" and $scheme != "https") {
        fail("a base URL is http:// or https://, got " + shown($url));
    }
    def rest as string init strings.substring($url, strings.indexOf($url, "://") + 3, len($url));
    if (strings.contains($rest, "/")) {
        $rest = strings.substring($rest, 0, strings.indexOf($rest, "/"));
    }
    if (strings.contains($rest, "@")) {
        fail("a base URL holds no user or password, got " + shown($url));
    }
    if (not regex.matches('^([A-Za-z0-9._-]+|\[[0-9A-Fa-f:.]+\])$', $u.host)) {
        fail("a base URL names a host, got " + shown($url));
    }
    def port as string init "";
    if ($u.port != "" or strings.endsWith($rest, ":")) {
        if (not regex.matches('^[0-9]{1,5}$', $u.port) or convert.toInt($u.port) == 0 or
            convert.toInt($u.port) > 65535) {
            fail("a base URL port is 1 to 65535, got " + shown($url));
        }
        $port = ":" + $u.port;
    }
    def path as string init trimSlashes($u.path);
    if (strings.endsWith($path, CONTENT)) {
        $path = trimSlashes(strings.substring($path, 0, len($path) - len(CONTENT)));
    } elseif (strings.endsWith($path, API)) {
        $path = trimSlashes(strings.substring($path, 0, len($path) - len(API)));
    }
    return $scheme + "://" + $u.host + $port + $path;
}

/**
 * A client for a Koofr service, without credentials.
 *
 * @param baseUrl {string} `DEFAULT_URL`, another provider's URL, or a bare
 *   host (gets `https://`); a trailing `/api/v2.1` or `/content/api/v2.1` is
 *   dropped
 * @return {Client} the client; full certificate checking
 * @throws {Error} kind `"koofr"` when the URL is empty, holds spaces or
 *   control characters, a query, a fragment or a user, has a scheme other
 *   than `http`/`https`, no host or a port outside 1-65535
 * @example
 *   def c as koofr.Client init koofr.client(koofr.DEFAULT_URL);
 */
export func client(baseUrl as string) {
    def c as Client;
    $c.url = normalUrl($baseUrl);
    return $c;
}

/**
 * Refuse a credential that would break the header it goes into.
 *
 * @param text {string} the credential
 * @param what {string} what it is, for the error message
 */
func checkSecret(text as string, what as string) {
    if ($text == "" or regex.matches("[\\x00-\\x1f\\x7f]", $text)) {
        fail("a " + $what + " is not empty and holds no control characters");
    }
}

/**
 * Authenticate with an app password (HTTP Basic), made in Koofr under
 * Preferences > Password > App passwords. It works for the API and WebDAV
 * alike; revoke it there. Each request refuses to send it over `http://` to
 * a host that is not loopback, unless `withPlainHttp` was set.
 *
 * @param c {Client} the client
 * @param email {string} the account's e-mail address
 * @param password {string} the app password
 * @return {Client} the changed copy
 * @throws {Error} kind `"koofr"` when either is empty or holds control
 *   characters, or the e-mail holds `:`
 */
export func withAppPassword(c as Client, email as string, password as string) {
    checkSecret($email, "e-mail address");
    checkSecret($password, "password");
    if (strings.contains($email, ":")) {
        fail("an e-mail address holds no :");
    }
    $c.auth = http.basic($email, $password);
    return $c;
}

/**
 * Authenticate with a bearer token, e.g. an OAuth access token obtained
 * elsewhere. Sent over `http://` under the same rule as `withAppPassword`.
 *
 * @param c {Client} the client
 * @param token {string} the token
 * @return {Client} the changed copy
 * @throws {Error} kind `"koofr"` when the token is empty or holds spaces or
 *   control characters
 */
export func withToken(c as Client, token as string) {
    if ($token == "" or regex.matches("[\\s\\x00-\\x1f\\x7f]", $token)) {
        fail("a token is not empty and holds no spaces or control characters");
    }
    $c.auth = "Bearer " + $token;
    return $c;
}

/**
 * Trust a certificate (PEM) in addition to the system's, for a service with
 * a private CA or a self-signed certificate. Undoes `withInsecure`.
 *
 * @param c {Client} the client
 * @param pem {bytes} the certificate
 * @return {Client} the changed copy
 */
export func withCaCert(c as Client, pem as bytes) {
    $c.tls.caCert = $pem;
    $c.tls.skipVerify = false;
    return $c;
}

/**
 * Accept any certificate. The connection is still encrypted but no longer
 * authenticated; prefer `withCaCert`.
 *
 * @param c {Client} the client
 * @return {Client} the changed copy
 */
export func withInsecure(c as Client) {
    $c.tls.skipVerify = true;
    return $c;
}

/**
 * Allow credentials over plain `http://` to a host that is not loopback
 * (127.0.0.0/8, `::1`, `localhost`). Without it, every request with
 * credentials to such a host throws before it connects. The app password or
 * token then crosses the network unencrypted.
 *
 * @param c {Client} the client
 * @return {Client} the changed copy
 */
export func withPlainHttp(c as Client) {
    $c.plainHttp = true;
    return $c;
}

/**
 * Set the idle timeout of each request.
 *
 * @param c {Client} the client
 * @param ms {int} milliseconds; 0 for the default, 30 s
 * @return {Client} the changed copy
 * @throws {Error} kind `"koofr"` when `ms` is negative
 */
export func withTimeout(c as Client, ms as int) {
    if ($ms < 0) {
        fail("a timeout is 0 or more ms, got " + convert.toString($ms));
    }
    $c.timeoutMs = $ms;
    return $c;
}

/**
 * Set the largest reply body of every request but `get` (which takes its own
 * `maxBytes`). A larger reply throws; the cap counts the status line and
 * headers too, as `http` reads them. A recursive listing of a whole mount
 * is the reply most likely to reach it: an NDJSON line of a file named
 * `01ab.jpg` at the top is 193 bytes, so `REPLY_LIMIT` holds about 340,000
 * such entries, fewer with longer paths.
 *
 * @param c {Client} the client
 * @param maxBytes {int} the cap; 0 for `REPLY_LIMIT`, negative for none
 * @return {Client} the changed copy
 */
export func withReplyLimit(c as Client, maxBytes as int) {
    $c.replyLimit = $maxBytes;
    return $c;
}

/**
 * Retry a GET answered 429 or 5xx, `listRecursive` included. The first
 * retry waits 500 ms, each further one twice as long, longer for a
 * `Retry-After` in seconds, at most 30 s. Writes are never retried (they
 * need not be idempotent), nor are `get` and `put`.
 *
 * @param c {Client} the client
 * @param n {int} retries, 0 for none, at most `MAX_RETRIES`
 * @return {Client} the changed copy
 * @throws {Error} kind `"koofr"` when `n` is negative or over `MAX_RETRIES`
 */
export func withRetries(c as Client, n as int) {
    if ($n < 0 or $n > MAX_RETRIES) {
        fail("retries are 0 to " + convert.toString(MAX_RETRIES) + ", got " + convert.toString($n));
    }
    $c.retries = $n;
    return $c;
}

/**
 * Refuse an API path that would not address what it says.
 *
 * @param path {string} the path under `/api/v2.1`, query string allowed
 */
func ensurePath(path as string) {
    if (not strings.startsWith($path, "/")) {
        fail("an API path starts with /, got " + shown($path));
    }
    def route as string init $path;
    if (strings.contains($route, "?")) {
        $route = strings.substring($route, 0, strings.indexOf($route, "?"));
    }
    if (strings.contains($route, "//") or strings.contains($path, "#") or
        regex.matches("[\\x00-\\x20\\x7f]", $path)) {
        fail("an API path holds no //, # or spaces: " + shown($path));
    }
    for (def segment in strings.split($route, "/")) {
        if ($segment == "." or $segment == "..") {
            fail("an API path has no . or .. segments: " + shown($path));
        }
    }
}

/**
 * A mount, link or receiver id, checked.
 *
 * @param id {string} the id
 * @param what {string} what it is, for the error message
 * @return {string} the id
 */
func checkId(id as string, what as string) {
    if (not regex.matches(ID_PATTERN, $id)) {
        fail("a " + $what + " id is letters, digits, - and _, got " + shown($id));
    }
    return $id;
}

/**
 * A path in a mount, checked: absolute, no empty, `.` or `..` segments, no
 * control characters, no trailing `/` but on the root.
 *
 * @param path {string} e.g. `/docs/a.txt` or `/`
 * @return {string} the path
 */
func checkPath(path as string) {
    if (not strings.startsWith($path, "/") or regex.matches("[\\x00-\\x1f\\x7f]", $path)) {
        fail("a path starts with / and holds no control characters, got " + shown($path));
    }
    if ($path == "/") {
        return $path;
    }
    for (def segment in strings.split(strings.substring($path, 1, len($path)), "/")) {
        if ($segment == "" or $segment == "." or $segment == "..") {
            fail("a path has no empty, . or .. segments, got " + shown($path));
        }
    }
    return $path;
}

/**
 * A file or folder name, checked: not empty, not `.` or `..`, no `/` or
 * control characters.
 *
 * @param name {string} the name
 * @return {string} the name
 */
func checkName(name as string) {
    if ($name == "" or $name == "." or $name == ".." or strings.contains($name, "/") or
        regex.matches("[\\x00-\\x1f\\x7f]", $name)) {
        fail("a name is not empty, . or .. and holds no / or control characters, got " +
            shown($name));
    }
    return $name;
}

/**
 * The folder a path is in.
 *
 * @param path {string} a checked path other than `/`
 * @return {string} the parent, `/` at the top
 */
func parentOf(path as string) {
    def at as int init strings.lastIndexOf($path, "/");
    if ($at <= 0) {
        return "/";
    }
    return strings.substring($path, 0, $at);
}

/**
 * The last segment of a path.
 *
 * @param path {string} a checked path other than `/`
 * @return {string} the name
 */
func nameOf(path as string) {
    return strings.substring($path, strings.lastIndexOf($path, "/") + 1, len($path));
}

/**
 * A path below a folder.
 *
 * @param dir {string} the folder
 * @param rest {string} a name, or a path starting with `/`
 * @return {string} the joined path
 */
func joined(dir as string, rest as string) {
    def tail as string init $rest;
    while (strings.startsWith($tail, "/")) {
        $tail = strings.substring($tail, 1, len($tail));
    }
    if ($tail == "") {
        return $dir;
    }
    if ($dir == "/") {
        return "/" + $tail;
    }
    return $dir + "/" + $tail;
}

/**
 * The API path of a file operation on a mount.
 *
 * @param mountId {string} the mount
 * @param verb {string} e.g. `info`, `list`
 * @param path {string} the path in the mount
 * @return {string} `/mounts/<id>/files/<verb>?path=<path>`
 */
func filesPath(mountId as string, verb as string, path as string) {
    return "/mounts/" + checkId($mountId, "mount") + "/files/" + $verb + "?path=" +
        uri.encode(checkPath($path));
}

/**
 * Whether a base URL names a loopback host: `localhost`, `[::1]` or an
 * address in 127.0.0.0/8.
 *
 * @param url {string} a base URL from `normalUrl`
 * @return {bool} whether it is loopback
 */
func isLoopback(url as string) {
    def host as string init strings.lower(uri.parse($url).host);
    return $host == "localhost" or $host == "[::1]" or
        regex.matches('^127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$', $host);
}

/**
 * The headers of every request. Refuses credentials over `http://` to a host
 * that is not loopback unless `plainHttp` is set.
 *
 * @param c {Client} the client
 * @return {map of string to string} the headers
 */
func baseHeaders(c as Client) {
    def headers as map of string to string init {"Accept": "application/json"};
    if ($c.auth != "") {
        if (strings.startsWith($c.url, "http://") and not $c.plainHttp and
            not isLoopback($c.url)) {
            fail("credentials go over http:// only to a loopback host; use https:// or " +
                "withPlainHttp, got " + shown($c.url));
        }
        $headers["Authorization"] = $c.auth;
    }
    return $headers;
}

/**
 * The reply cap `http` takes.
 *
 * @param c {Client} the client
 * @return {int} bytes; negative for none
 */
func replyCap(c as Client) {
    if ($c.replyLimit == 0) {
        return REPLY_LIMIT;
    }
    return $c.replyLimit;
}

/**
 * The idle timeout for the `http` calls that take it directly, where 0
 * would mean no timeout at all.
 *
 * @param c {Client} the client
 * @return {int} milliseconds
 */
func idleMs(c as Client) {
    if ($c.timeoutMs == 0) {
        return DEFAULT_TIMEOUT_MS;
    }
    return $c.timeoutMs;
}

/**
 * Send a request and return the response, whatever its status.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method, upper case
 * @param route {string} the path under the base URL, `/api/...` or
 *   `/content/...`
 * @param body {string} JSON, or "" for none
 * @return {http.Response} the response
 */
func sendRaw(c as Client, method as string, route as string, body as string) {
    def headers as map of string to string init baseHeaders($c);
    if ($body != "") {
        $headers["Content-Type"] = "application/json";
    }
    def o as http.Options;
    $o.tls = $c.tls;
    $o.timeoutMs = $c.timeoutMs;
    $o.maxBytes = replyCap($c);
    if ($method == "GET") {
        $o.maxRetries = $c.retries;
        $o.backoffMs = 500;
    }
    def r as http.Response;
    try {
        $r = http.send($method, $c.url + $route, $headers, $body, $o);
    } catch (e) {
        fail($method + " " + $route + ": " + $e.message);
    }
    return $r;
}

/**
 * Send a request and return the response, a non-2xx refused.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method, upper case
 * @param route {string} the path under the base URL
 * @param body {string} JSON, or "" for none
 * @return {http.Response} the response
 */
func exchange(c as Client, method as string, route as string, body as string) {
    def r as http.Response init sendRaw($c, $method, $route, $body);
    if ($r.status < 200 or $r.status >= 300) {
        fail($method + " " + $route + ": " + failureText($r.status, $r.statusText, $r.body));
    }
    return $r;
}

/**
 * Explain a refused request: Koofr's `error.message` and `error.code`, cut
 * to `REASON` characters of printable ASCII.
 *
 * @param status {int} the HTTP status
 * @param statusText {string} the reason phrase
 * @param body {string} the body
 * @return {string} `HTTP <status>: <reason> (<code>)`
 */
func failureText(status as int, statusText as string, body as string) {
    def text as string init "HTTP " + convert.toString($status);
    def reason as string init strings.trim($statusText);
    def doc as json.Value init json.decode("null");
    try {
        $doc = json.decode($body);
    } catch (e) {
        $doc = json.decode("null");
    }
    if (json.typeOf($doc) == "map") {
        def said as string init strings.trim(field($doc, "/error/message"));
        def code as string init strings.trim(field($doc, "/error/code"));
        if ($said != "") {
            $reason = $said;
        }
        if ($code != "") {
            $reason = $reason + " (" + $code + ")";
        }
    }
    if ($reason != "") {
        $text = $text + ": " + plain($reason, REASON);
    }
    return $text;
}

/**
 * Decode a reply body.
 *
 * @param body {string} the body
 * @param what {string} the request, for the error message
 * @return {json.Value} the document; JSON `null` for an empty body
 */
func decoded(body as string, what as string) {
    if (strings.trim($body) == "") {
        return json.decode("null");
    }
    try {
        return json.decode($body);
    } catch (e) {
        fail($what + ": the reply is not JSON");
    }
    return json.decode("null");
}

/**
 * A request to the API, its reply decoded.
 *
 * @param c {Client} the client
 * @param method {string} the HTTP method, upper case
 * @param path {string} the path under `/api/v2.1`
 * @param body {string} JSON, or "" for none
 * @return {json.Value} the reply; JSON `null` when it is empty
 */
func api(c as Client, method as string, path as string, body as string) {
    def r as http.Response init exchange($c, $method, API + $path, $body);
    return decoded($r.body, $method + " " + API + $path);
}

/**
 * Call any endpoint of the API.
 *
 * @param c {Client} the client
 * @param method {string} `GET`, `POST`, `PUT`, `PATCH` or `DELETE`
 * @param path {string} the path under `/api/v2.1`, query string included,
 *   e.g. `/user/attributes`
 * @param body {string} the JSON body; "" for none
 * @return {json.Value} the reply; JSON `null` when it is empty
 * @throws {Error} kind `"koofr"` on a bad path, a network failure, a reply
 *   that is not 2xx (the message names the status and Koofr's reason), a
 *   2xx reply that is not JSON, or a reply over the client's reply limit
 * @example
 *   def places as json.Value init koofr.call($c, "GET", "/places", "");
 */
export func call(c as Client, method as string, path as string, body as string) {
    def verb as string init strings.upper($method);
    if (not lists.contains(["GET", "POST", "PUT", "PATCH", "DELETE"], $verb)) {
        fail("unsupported method " + shown($method));
    }
    ensurePath($path);
    return api($c, $verb, $path, $body);
}

/**
 * Build a JSON object from text members.
 *
 * @param fields {map of string to string} the members, all sent
 * @return {json.Value} the object
 */
func objectOf(fields as map of string to string) {
    def doc as json.Value init json.decode('{}');
    for (def key in $fields) {
        $doc = json.set($doc, "/" + $key, $fields[$key]);
    }
    return $doc;
}

/**
 * An account from a reply.
 *
 * @param d {json.Value} the document
 * @return {User} the account
 */
func userFrom(d as json.Value) {
    return User{
        id: field($d, "/id"),
        firstName: field($d, "/firstName"),
        lastName: field($d, "/lastName"),
        email: field($d, "/email"),
        level: numberAt($d, "/level")
    };
}

/**
 * The account the credentials belong to.
 *
 * @param c {Client} the client
 * @return {User} the account
 * @throws {Error} kind `"koofr"` without valid credentials (HTTP 401), or as
 *   `call`
 */
export func user(c as Client) {
    return userFrom(api($c, "GET", "/user", ""));
}

/**
 * The account's limits, as Koofr sends them. The API description defines no
 * schema for this reply, so it is handed back undecoded.
 *
 * @param c {Client} the client
 * @return {json.Value} the reply; JSON `null` when it is empty
 * @throws {Error} kind `"koofr"` as `call`
 */
export func limits(c as Client) {
    return api($c, "GET", "/user/limits", "");
}

/**
 * A mount from a reply.
 *
 * @param d {json.Value} the document
 * @param p {string} the mount's pointer; "" for the root
 * @return {Mount} the mount
 */
func mountFrom(d as json.Value, p as string) {
    return Mount{
        id: field($d, $p + "/id"),
        name: field($d, $p + "/name"),
        type: field($d, $p + "/type"),
        origin: field($d, $p + "/origin"),
        owner: field($d, $p + "/owner/name"),
        isPrimary: flag($d, $p + "/isPrimary"),
        isShared: flag($d, $p + "/isShared"),
        online: flag($d, $p + "/online"),
        canWrite: flag($d, $p + "/canWrite"),
        canUpload: flag($d, $p + "/canUpload"),
        spaceTotal: numberAt($d, $p + "/spaceTotal"),
        spaceUsed: numberAt($d, $p + "/spaceUsed"),
        overQuota: flag($d, $p + "/overQuota")
    };
}

/**
 * The mounts the account reaches: its storage, connected devices and
 * folders shared with it.
 *
 * @param c {Client} the client
 * @return {list of Mount} the mounts
 * @throws {Error} kind `"koofr"` as `call`
 */
export func mounts(c as Client) {
    def d as json.Value init api($c, "GET", "/mounts", "");
    def out as list of Mount init [];
    for (def p in items($d, "/mounts")) {
        $out[] = mountFrom($d, $p);
    }
    return $out;
}

/**
 * One mount.
 *
 * @param c {Client} the client
 * @param id {string} the mount id
 * @return {Mount} the mount
 * @throws {Error} kind `"koofr"` on a bad id, when it does not exist, or as
 *   `call`
 */
export func mount(c as Client, id as string) {
    return mountFrom(api($c, "GET", "/mounts/" + checkId($id, "mount"), ""), "");
}

/**
 * The account's primary storage: the first mount with `isPrimary`.
 *
 * @param c {Client} the client
 * @return {Mount} the mount
 * @throws {Error} kind `"koofr"` when no mount is primary, or as `call`
 */
export func primaryMount(c as Client) {
    for (def m in mounts($c)) {
        if ($m.isPrimary) {
            return $m;
        }
    }
    fail("the account has no primary mount");
    def none as Mount;
    return $none;
}

/**
 * A file from a reply. Takes the file's own node (`json.get`). Reads the
 * fields the API marks required with the typed `json.as*` calls (one pointer
 * walk each) and falls back to the tolerant accessors when one is absent or
 * of another type.
 *
 * @param d {json.Value} the file object
 * @param path {string} its path in the mount
 * @return {File} the file
 */
func fileFrom(d as json.Value, path as string) {
    try {
        def hash as string init "";
        if (json.typeOf($d, "/hash") == "string") {
            $hash = json.asString($d, "/hash");
        }
        return File{
            name: json.asString($d, "/name"),
            path: $path,
            type: json.asString($d, "/type"),
            size: json.asInt($d, "/size"),
            modified: json.asInt($d, "/modified"),
            contentType: json.asString($d, "/contentType"),
            hash: $hash
        };
    } catch (e) {
        return tolerantFile($d, $path);
    }
    return tolerantFile($d, $path);
}

/**
 * A file from a reply that does not match the API's types: every field
 * through `field`/`numberAt`.
 *
 * @param d {json.Value} the file object
 * @param path {string} its path in the mount
 * @return {File} the file
 */
func tolerantFile(d as json.Value, path as string) {
    return File{
        name: field($d, "/name"),
        path: $path,
        type: field($d, "/type"),
        size: numberAt($d, "/size"),
        modified: numberAt($d, "/modified"),
        contentType: field($d, "/contentType"),
        hash: field($d, "/hash")
    };
}

/**
 * A file or folder.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the path, e.g. `/docs/a.txt`
 * @return {File} the file
 * @throws {Error} kind `"koofr"` when it does not exist (HTTP 404), or as
 *   `call`
 */
export func info(c as Client, mountId as string, path as string) {
    return fileFrom(api($c, "GET", filesPath($mountId, "info", $path), ""), $path);
}

/**
 * Whether a reply says the file is not there: 404 with Koofr's error code
 * `NotFound` or none. A 404 with another code (`DeviceOffline`, a missing
 * mount) says nothing about the file.
 *
 * @param r {http.Response} the reply
 * @return {bool} whether the file is missing
 */
func isMissing(r as http.Response) {
    if ($r.status != 404) {
        return false;
    }
    def code as string init "";
    try {
        $code = strings.trim(field(json.decode($r.body), "/error/code"));
    } catch (e) {
        $code = "";
    }
    return $code == "" or $code == "NotFound";
}

/**
 * Whether a file or folder exists.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the path
 * @return {bool} false when Koofr answers 404 with error code `NotFound` or
 *   none
 * @throws {Error} kind `"koofr"` on any other refusal, a 404 with another
 *   code (e.g. `DeviceOffline`), or as `call`
 */
export func exists(c as Client, mountId as string, path as string) {
    def route as string init API + filesPath($mountId, "info", $path);
    def r as http.Response init sendRaw($c, "GET", $route, "");
    if (isMissing($r)) {
        return false;
    }
    if ($r.status < 200 or $r.status >= 300) {
        fail("GET " + $route + ": " + failureText($r.status, $r.statusText, $r.body));
    }
    return true;
}

/**
 * The entries of a folder.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the folder, `/` for the root
 * @return {list of File} the entries, with their full paths
 * @throws {Error} kind `"koofr"` when it does not exist, or as `call`; a
 *   reply over the client's reply limit (`REPLY_LIMIT`, 64 MiB, by default)
 *   is refused
 */
export func listFolder(c as Client, mountId as string, path as string) {
    def d as json.Value init api($c, "GET", filesPath($mountId, "list", $path), "");
    def out as list of File init [];
    for (def p in items($d, "/files")) {
        def node as json.Value init json.get($d, $p);
        $out[] = fileFrom($node, joined($path, field($node, "/name")));
    }
    return $out;
}

/**
 * Everything below a folder, at every depth, in one request. The first
 * entry is the folder itself. Koofr streams the list as NDJSON; it is read
 * whole before it is parsed, so the client's reply limit (`REPLY_LIMIT`,
 * 64 MiB, by default; see `withReplyLimit`) bounds the listing.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the folder, `/` for the root
 * @return {list of File} the entries, with their full paths
 * @throws {Error} kind `"koofr"` when the folder does not exist, when the
 *   stream ends with an error item (e.g. a device went offline), on an item
 *   without a `path` or `file`, on a reply over the reply limit, or as
 *   `call`
 */
export func listRecursive(c as Client, mountId as string, path as string) {
    def route as string init CONTENT + filesPath($mountId, "listrecursive", $path);
    def r as http.Response init exchange($c, "GET", $route, "");
    def lines as list of json.Value init [];
    try {
        $lines = jsonl.decode($r.body);
    } catch (e) {
        fail("GET " + $route + ": the reply is not NDJSON");
    }
    def out as list of File init [];
    for (def item in $lines) {
        if (field($item, "/type") == "error") {
            def reason as string init field($item, "/error/message") + " (" +
                field($item, "/error/code") + ")";
            fail("GET " + $route + ": the listing broke off after " +
                convert.toString(len($out)) + " entries: " + plain($reason, REASON));
        }
        if (json.typeOf($item, "/path") != "string" or json.typeOf($item, "/file") != "map") {
            fail("GET " + $route + ": entry " + convert.toString(len($out)) +
                " has no path or file");
        }
        $out[] = fileFrom(json.get($item, "/file"), joined($path, json.asString($item, "/path")));
    }
    return $out;
}

/**
 * Make a folder. Its parent must exist; see `mkdirAll`.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the new folder, e.g. `/docs/2026`
 * @throws {Error} kind `"koofr"` on a bad path, when the parent does not
 *   exist or the name is taken, or as `call`
 */
export func mkdir(c as Client, mountId as string, path as string) {
    if (checkPath($path) == "/") {
        fail("the root exists already");
    }
    def body as json.Value init objectOf({"name": nameOf($path)});
    api($c, "POST", filesPath($mountId, "folder", parentOf($path)), json.encode($body));
}

/**
 * Whether a folder is there, by `files/info`.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the folder
 * @return {bool} true for a folder, false when missing (`isMissing`)
 */
func isFolder(c as Client, mountId as string, path as string) {
    def route as string init API + filesPath($mountId, "info", $path);
    def r as http.Response init sendRaw($c, "GET", $route, "");
    if (isMissing($r)) {
        return false;
    }
    if ($r.status < 200 or $r.status >= 300) {
        fail("GET " + $route + ": " + failureText($r.status, $r.statusText, $r.body));
    }
    if (field(decoded($r.body, "GET " + $route), "/type") != "dir") {
        fail(shown($path) + " is a file, not a folder");
    }
    return true;
}

/**
 * Make a folder and every missing parent. A folder that exists is left as
 * it is. One `files/info` on the full path; when it is missing, one per
 * parent from the top down to the first missing one, then one `mkdir` for
 * that one and each below it.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the folder, e.g. `/backups/2026/11`
 * @throws {Error} kind `"koofr"` when a part of the path is a file, on a 404
 *   whose error code is not `NotFound` (e.g. `DeviceOffline`), or as `call`
 */
export func mkdirAll(c as Client, mountId as string, path as string) {
    if (checkPath($path) == "/" or isFolder($c, $mountId, $path)) {
        return;
    }
    def at as string init "/";
    def probing as bool init true;
    for (def segment in strings.split(strings.substring($path, 1, len($path)), "/")) {
        $at = joined($at, $segment);
        if ($probing and $at != $path) {
            $probing = isFolder($c, $mountId, $at);
        }
        if (not $probing or $at == $path) {
            mkdir($c, $mountId, $at);
        }
    }
}

/**
 * Download a file. `maxBytes` caps the whole reply as `http` reads it,
 * status line and headers included, so a file within a few hundred bytes of
 * the cap is refused too.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the file
 * @param maxBytes {int} the largest reply accepted; 0 for `DOWNLOAD_LIMIT`,
 *   negative for no limit
 * @return {bytes} the content
 * @throws {Error} kind `"koofr"` on a bad mount id or path, when it does not
 *   exist or Koofr refuses (non-2xx), on a network failure, or for a file
 *   over `maxBytes`
 */
export func get(c as Client, mountId as string, path as string, maxBytes as int) {
    def route as string init CONTENT + filesPath($mountId, "get", $path);
    def cap as int init $maxBytes;
    if ($cap == 0) {
        $cap = DOWNLOAD_LIMIT;
    }
    def headers as map of string to string init baseHeaders($c);
    $headers["Accept"] = "*/*";
    def r as http.BytesResponse;
    try {
        $r = http.requestWithBytes("GET", $c.url + $route, $headers, "", idleMs($c), $cap, $c.tls);
    } catch (e) {
        fail("GET " + $route + ": " + $e.message);
    }
    if ($r.status < 200 or $r.status >= 300) {
        def text as string init "";
        try {
            $text = convert.stringFromBytes($r.body, "utf-8");
        } catch (e) {
            $text = "";
        }
        fail("GET " + $route + ": " + failureText($r.status, $r.statusText, $text));
    }
    return $r.body;
}

/**
 * The query of an upload.
 *
 * @param dir {string} the folder
 * @param name {string} the file name
 * @param opts {PutOptions} the options
 * @return {string} the query string, without `?`
 */
func putQuery(dir as string, name as string, opts as PutOptions) {
    def q as string init "path=" + uri.encode($dir) + "&filename=" + uri.encode($name) +
        "&info=true&overwrite=" + convert.toString($opts.overwrite) + "&autorename=" +
        convert.toString($opts.autorename);
    if ($opts.overwriteIfHash != "") {
        $q = $q + "&overwriteIfHash=" + uri.encode($opts.overwriteIfHash);
    }
    if ($opts.overwriteIfModified != 0) {
        $q = $q + "&overwriteIfModified=" + convert.toString($opts.overwriteIfModified);
    }
    if ($opts.overwriteIgnoreNonexistent) {
        $q = $q + "&overwriteIgnoreNonexistent=true";
    }
    if ($opts.modified != 0) {
        $q = $q + "&modified=" + convert.toString($opts.modified);
    }
    return $q;
}

/**
 * Upload a file. The folder must exist; see `mkdirAll`. The content is the
 * raw request body (`application/octet-stream`), the name goes in the
 * `filename` query parameter.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the file, e.g. `/docs/a.txt`
 * @param data {bytes} the content
 * @param opts {PutOptions} what to do when the file exists; the zero value
 *   refuses
 * @return {File} the stored file; its name differs when `autorename` chose
 *   another
 * @throws {Error} kind `"koofr"` on a bad path, when the file exists and
 *   `opts` does not allow replacing it (HTTP 409), or on a network failure
 *   or refusal
 */
export func put(c as Client, mountId as string, path as string, data as bytes, opts as PutOptions) {
    if (checkPath($path) == "/") {
        fail("a file needs a name");
    }
    def dir as string init parentOf($path);
    def name as string init nameOf($path);
    def route as string init CONTENT + "/mounts/" + checkId($mountId, "mount") + "/files/put?" +
        putQuery($dir, $name, $opts);
    def headers as map of string to string init baseHeaders($c);
    $headers["Content-Type"] = "application/octet-stream";
    def r as http.Response;
    try {
        $r = http.requestRawBodyTls(
            "POST",
            $c.url + $route,
            $headers,
            $data,
            idleMs($c),
            replyCap($c),
            $c.tls);
    } catch (e) {
        fail("POST " + $route + ": " + $e.message);
    }
    if ($r.status < 200 or $r.status >= 300) {
        fail("POST " + $route + ": " + failureText($r.status, $r.statusText, $r.body));
    }
    def d as json.Value init decoded($r.body, "POST " + $route);
    return fileFrom($d, joined($dir, field($d, "/name")));
}

/**
 * Delete a file or a folder with everything in it. It goes to the trash.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the file or folder; not `/`
 * @throws {Error} kind `"koofr"` on the root, or as `call`
 */
export func remove(c as Client, mountId as string, path as string) {
    if (checkPath($path) == "/") {
        fail("the root cannot be removed");
    }
    api($c, "DELETE", filesPath($mountId, "remove", $path), "");
}

/**
 * Rename a file or folder in place.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the file or folder
 * @param name {string} the new name, without `/`
 * @throws {Error} kind `"koofr"` on the root, a bad name, when it is taken,
 *   or as `call`
 */
export func rename(c as Client, mountId as string, path as string, name as string) {
    if (checkPath($path) == "/") {
        fail("the root cannot be renamed");
    }
    def body as json.Value init objectOf({"name": checkName($name)});
    api($c, "PUT", filesPath($mountId, "rename", $path), json.encode($body));
}

/**
 * Copy or move: the shared request.
 *
 * @param c {Client} the client
 * @param verb {string} `copy` or `move`
 * @param mountId {string} the source mount
 * @param path {string} the source
 * @param toMountId {string} the target mount
 * @param toPath {string} the target path
 * @return {string} the name it got
 */
func transfer(
    c as Client,
    verb as string,
    mountId as string,
    path as string,
    toMountId as string,
    toPath as string) {
    if (checkPath($path) == "/" or checkPath($toPath) == "/") {
        fail("the root cannot be a source or target of " + $verb);
    }
    def body as json.Value init objectOf({
        "toMountId": checkId($toMountId, "mount"),
        "toPath": $toPath
    });
    def d as json.Value init api($c, "PUT", filesPath($mountId, $verb, $path), json.encode($body));
    return field($d, "/name");
}

/**
 * Copy a file or folder, on the same mount or to another.
 *
 * @param c {Client} the client
 * @param mountId {string} the source mount
 * @param path {string} the source
 * @param toMountId {string} the target mount; the same id for a copy in place
 * @param toPath {string} the full target path, name included
 * @return {string} the name of the copy, as Koofr reports it
 * @throws {Error} kind `"koofr"` on a bad path, when the target exists, or
 *   as `call`
 */
export func copy(
    c as Client,
    mountId as string,
    path as string,
    toMountId as string,
    toPath as string) {
    return transfer($c, "copy", $mountId, $path, $toMountId, $toPath);
}

/**
 * Move a file or folder, on the same mount or to another.
 *
 * @param c {Client} the client
 * @param mountId {string} the source mount
 * @param path {string} the source
 * @param toMountId {string} the target mount
 * @param toPath {string} the full target path, name included
 * @return {string} the name it got, as Koofr reports it
 * @throws {Error} kind `"koofr"` on a bad path, when the target exists, or
 *   as `call`
 */
export func move(
    c as Client,
    mountId as string,
    path as string,
    toMountId as string,
    toPath as string) {
    return transfer($c, "move", $mountId, $path, $toMountId, $toPath);
}

/**
 * The query of a search, checked.
 *
 * @param query {string} the words
 * @param opts {SearchOptions} the filters
 * @return {string} the query string, without `?`
 */
func searchQuery(query as string, opts as SearchOptions) {
    if ($opts.limit < 0 or $opts.limit > SEARCH_MAX or $opts.offset < 0) {
        fail("a search limit is 0 to " + convert.toString(SEARCH_MAX) +
            " and an offset not negative");
    }
    if ($opts.fileType != "" and not lists.contains(FILE_TYPES, $opts.fileType)) {
        fail("a file type is one of " + strings.join(FILE_TYPES, ", ") + ", got " +
            shown($opts.fileType));
    }
    def q as string init "query=" + uri.encode($query);
    if ($opts.offset > 0) {
        $q = $q + "&offset=" + convert.toString($opts.offset);
    }
    if ($opts.limit > 0) {
        $q = $q + "&limit=" + convert.toString($opts.limit);
    }
    if ($opts.mountId != "") {
        $q = $q + "&mountId=" + checkId($opts.mountId, "mount");
    }
    if ($opts.path != "") {
        if ($opts.mountId == "") {
            fail("a search below a path needs a mountId");
        }
        $q = $q + "&path=" + uri.encode(checkPath($opts.path));
    }
    if ($opts.contentType != "") {
        $q = $q + "&contentType=" + uri.encode($opts.contentType);
    }
    if ($opts.fileType != "") {
        $q = $q + "&fileType=" + $opts.fileType;
    }
    for (def tag in $opts.tags) {
        if (not regex.matches("^[^=]+=", $tag)) {
            fail("a tag filter is key=value, got " + shown($tag));
        }
        $q = $q + "&tag=" + uri.encode($tag);
    }
    return $q;
}

/**
 * Search files and folders by name across the account's mounts.
 *
 * @param c {Client} the client
 * @param query {string} the words to look for
 * @param opts {SearchOptions} filters and paging; the zero value for none
 * @return {list of SearchHit} the results, best first
 * @throws {Error} kind `"koofr"` on a bad filter, or as `call`
 */
export func search(c as Client, query as string, opts as SearchOptions) {
    def d as json.Value init api($c, "GET", "/search?" + searchQuery($query, $opts), "");
    def out as list of SearchHit init [];
    for (def p in items($d, "/hits")) {
        $out[] = SearchHit{
            mountId: field($d, $p + "/mountId"),
            path: field($d, $p + "/path"),
            name: field($d, $p + "/name"),
            type: field($d, $p + "/type"),
            size: numberAt($d, $p + "/size"),
            modified: numberAt($d, $p + "/modified"),
            contentType: field($d, $p + "/contentType"),
            score: floatAt($d, $p + "/score")
        };
    }
    return $out;
}

/**
 * A link from a reply.
 *
 * @param d {json.Value} the document
 * @param p {string} the link's pointer; "" for the root
 * @return {Link} the link
 */
func linkFrom(d as json.Value, p as string) {
    return Link{
        id: field($d, $p + "/id"),
        name: field($d, $p + "/name"),
        mountId: field($d, $p + "/mountId"),
        path: field($d, $p + "/path"),
        url: field($d, $p + "/url"),
        shortUrl: field($d, $p + "/shortUrl"),
        counter: numberAt($d, $p + "/counter"),
        hasPassword: flag($d, $p + "/hasPassword"),
        downloadable: flag($d, $p + "/downloadable"),
        message: field($d, $p + "/message"),
        created: numberAt($d, $p + "/created"),
        validFrom: numberAt($d, $p + "/validFrom"),
        validTo: numberAt($d, $p + "/validTo")
    };
}

/**
 * The links of a list member.
 *
 * @param d {json.Value} the document
 * @return {list of Link} the links under `/links`
 */
func linksFrom(d as json.Value) {
    def out as list of Link init [];
    for (def p in items($d, "/links")) {
        $out[] = linkFrom($d, $p);
    }
    return $out;
}

/**
 * The API path of a link or receiver.
 *
 * @param mountId {string} the mount
 * @param kind {string} `links` or `receivers`
 * @param id {string} the id
 * @return {string} `/mounts/<mount>/<kind>/<id>`
 */
func sharePath(mountId as string, kind as string, id as string) {
    def what as string init "link";
    if ($kind == "receivers") {
        $what = "receiver";
    }
    return "/mounts/" + checkId($mountId, "mount") + "/" + $kind + "/" + checkId($id, $what);
}

/**
 * The body that sets a validity window.
 *
 * @param validFrom {int} ms since the epoch; 0 for no start
 * @param validTo {int} ms since the epoch; 0 for no end
 * @return {string} the JSON
 */
func validityOf(validFrom as int, validTo as int) {
    if ($validFrom < 0 or $validTo < 0 or ($validTo != 0 and $validTo <= $validFrom)) {
        fail("a validity window ends after it starts and is not negative");
    }
    def doc as json.Value init json.decode('{}');
    if ($validFrom != 0) {
        $doc = json.set($doc, "/validFrom", $validFrom);
    }
    if ($validTo != 0) {
        $doc = json.set($doc, "/validTo", $validTo);
    }
    return json.encode($doc);
}

/**
 * The body that sets a password.
 *
 * @param password {string} the password
 * @return {string} the JSON
 */
func passwordOf(password as string) {
    if ($password == "") {
        fail("a password is not empty");
    }
    return json.encode(objectOf({"password": $password}));
}

/**
 * The public links of one mount.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @return {list of Link} the links
 * @throws {Error} kind `"koofr"` as `call`
 */
export func links(c as Client, mountId as string) {
    return linksFrom(api($c, "GET", "/mounts/" + checkId($mountId, "mount") + "/links", ""));
}

/**
 * The public links of every mount.
 *
 * @param c {Client} the client
 * @return {list of Link} the links
 * @throws {Error} kind `"koofr"` as `call`
 */
export func allLinks(c as Client) {
    return linksFrom(api($c, "GET", "/links", ""));
}

/**
 * Share a file or folder with a public link.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the file or folder
 * @return {Link} the new link
 * @throws {Error} kind `"koofr"` on a bad path, when the account's link
 *   limit is reached (HTTP 429), or as `call`
 */
export func createLink(c as Client, mountId as string, path as string) {
    def body as json.Value init objectOf({"path": checkPath($path)});
    def route as string init "/mounts/" + checkId($mountId, "mount") + "/links";
    return linkFrom(api($c, "POST", $route, json.encode($body)), "");
}

/**
 * One public link.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the link id
 * @return {Link} the link
 * @throws {Error} kind `"koofr"` as `call`
 */
export func link(c as Client, mountId as string, id as string) {
    return linkFrom(api($c, "GET", sharePath($mountId, "links", $id), ""), "");
}

/**
 * Delete a public link. The file stays.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the link id
 * @throws {Error} kind `"koofr"` as `call`
 */
export func deleteLink(c as Client, mountId as string, id as string) {
    api($c, "DELETE", sharePath($mountId, "links", $id), "");
}

/**
 * Protect a public link with a password.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the link id
 * @param password {string} the password visitors must give
 * @return {Link} the changed link
 * @throws {Error} kind `"koofr"` on an empty password, or as `call`
 */
export func setLinkPassword(c as Client, mountId as string, id as string, password as string) {
    def route as string init sharePath($mountId, "links", $id) + "/password/set";
    return linkFrom(api($c, "PUT", $route, passwordOf($password)), "");
}

/**
 * Remove the password of a public link.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the link id
 * @return {Link} the changed link
 * @throws {Error} kind `"koofr"` as `call`
 */
export func clearLinkPassword(c as Client, mountId as string, id as string) {
    def route as string init sharePath($mountId, "links", $id) + "/password";
    return linkFrom(api($c, "DELETE", $route, ""), "");
}

/**
 * Limit when a public link works.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the link id
 * @param validFrom {int} ms since the epoch; 0 for no start
 * @param validTo {int} ms since the epoch; 0 for no end
 * @return {Link} the changed link
 * @throws {Error} kind `"koofr"` on a window that ends before it starts, or
 *   as `call`
 */
export func setLinkValidity(
    c as Client,
    mountId as string,
    id as string,
    validFrom as int,
    validTo as int) {
    def route as string init sharePath($mountId, "links", $id) + "/validity";
    return linkFrom(api($c, "PUT", $route, validityOf($validFrom, $validTo)), "");
}

/**
 * A receiver from a reply.
 *
 * @param d {json.Value} the document
 * @param p {string} the receiver's pointer; "" for the root
 * @return {Receiver} the receiver
 */
func receiverFrom(d as json.Value, p as string) {
    return Receiver{
        id: field($d, $p + "/id"),
        name: field($d, $p + "/name"),
        mountId: field($d, $p + "/mountId"),
        path: field($d, $p + "/path"),
        url: field($d, $p + "/url"),
        shortUrl: field($d, $p + "/shortUrl"),
        counter: numberAt($d, $p + "/counter"),
        hasPassword: flag($d, $p + "/hasPassword"),
        alert: flag($d, $p + "/alert"),
        message: field($d, $p + "/message"),
        created: numberAt($d, $p + "/created"),
        validFrom: numberAt($d, $p + "/validFrom"),
        validTo: numberAt($d, $p + "/validTo")
    };
}

/**
 * The receivers of a list member.
 *
 * @param d {json.Value} the document
 * @return {list of Receiver} the receivers under `/receivers`
 */
func receiversFrom(d as json.Value) {
    def out as list of Receiver init [];
    for (def p in items($d, "/receivers")) {
        $out[] = receiverFrom($d, $p);
    }
    return $out;
}

/**
 * The receivers of one mount.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @return {list of Receiver} the receivers
 * @throws {Error} kind `"koofr"` as `call`
 */
export func receivers(c as Client, mountId as string) {
    def route as string init "/mounts/" + checkId($mountId, "mount") + "/receivers";
    return receiversFrom(api($c, "GET", $route, ""));
}

/**
 * The receivers of every mount.
 *
 * @param c {Client} the client
 * @return {list of Receiver} the receivers
 * @throws {Error} kind `"koofr"` as `call`
 */
export func allReceivers(c as Client) {
    return receiversFrom(api($c, "GET", "/receivers", ""));
}

/**
 * Let others upload into a folder through a link.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param path {string} the folder
 * @return {Receiver} the new receiver
 * @throws {Error} kind `"koofr"` on a bad path, when the account's limit is
 *   reached (HTTP 429), or as `call`
 */
export func createReceiver(c as Client, mountId as string, path as string) {
    def body as json.Value init objectOf({"path": checkPath($path)});
    def route as string init "/mounts/" + checkId($mountId, "mount") + "/receivers";
    return receiverFrom(api($c, "POST", $route, json.encode($body)), "");
}

/**
 * One receiver.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the receiver id
 * @return {Receiver} the receiver
 * @throws {Error} kind `"koofr"` as `call`
 */
export func receiver(c as Client, mountId as string, id as string) {
    return receiverFrom(api($c, "GET", sharePath($mountId, "receivers", $id), ""), "");
}

/**
 * Delete a receiver. The folder and what was uploaded stay.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the receiver id
 * @throws {Error} kind `"koofr"` as `call`
 */
export func deleteReceiver(c as Client, mountId as string, id as string) {
    api($c, "DELETE", sharePath($mountId, "receivers", $id), "");
}

/**
 * Protect a receiver with a password.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the receiver id
 * @param password {string} the password uploaders must give
 * @return {Receiver} the changed receiver
 * @throws {Error} kind `"koofr"` on an empty password, or as `call`
 */
export func setReceiverPassword(c as Client, mountId as string, id as string, password as string) {
    def route as string init sharePath($mountId, "receivers", $id) + "/password/set";
    return receiverFrom(api($c, "PUT", $route, passwordOf($password)), "");
}

/**
 * Remove the password of a receiver.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the receiver id
 * @return {Receiver} the changed receiver
 * @throws {Error} kind `"koofr"` as `call`
 */
export func clearReceiverPassword(c as Client, mountId as string, id as string) {
    def route as string init sharePath($mountId, "receivers", $id) + "/password";
    return receiverFrom(api($c, "DELETE", $route, ""), "");
}

/**
 * Limit when a receiver accepts uploads.
 *
 * @param c {Client} the client
 * @param mountId {string} the mount
 * @param id {string} the receiver id
 * @param validFrom {int} ms since the epoch; 0 for no start
 * @param validTo {int} ms since the epoch; 0 for no end
 * @return {Receiver} the changed receiver
 * @throws {Error} kind `"koofr"` on a window that ends before it starts, or
 *   as `call`
 */
export func setReceiverValidity(
    c as Client,
    mountId as string,
    id as string,
    validFrom as int,
    validTo as int) {
    def route as string init sharePath($mountId, "receivers", $id) + "/validity";
    return receiverFrom(api($c, "PUT", $route, validityOf($validFrom, $validTo)), "");
}

/**
 * One page of the trash: up to 1000 files sorted by name, ascending
 * (Koofr's defaults).
 *
 * @param c {Client} the client
 * @param cursor {string} "" for the first page, else the `cursor` of the
 *   page before
 * @return {TrashPage} the page
 * @throws {Error} kind `"koofr"` as `call`
 */
export func trash(c as Client, cursor as string) {
    def path as string init "/trash";
    if ($cursor != "") {
        $path = $path + "?cursor=" + uri.encode($cursor);
    }
    def d as json.Value init api($c, "GET", $path, "");
    def page as TrashPage;
    for (def p in items($d, "/files")) {
        $page.files[] = TrashFile{
            mountId: field($d, $p + "/mountId"),
            path: field($d, $p + "/path"),
            name: field($d, $p + "/name"),
            size: numberAt($d, $p + "/size"),
            deleted: numberAt($d, $p + "/deleted"),
            contentType: field($d, $p + "/contentType"),
            versionId: field($d, $p + "/versionId")
        };
    }
    $page.cursor = field($d, "/pageInfo/cursor");
    $page.retentionDays = numberAt($d, "/retentionDays");
    return $page;
}

/**
 * Every file in the trash, following the cursor. Stops at an empty cursor,
 * an empty page or a cursor it has followed before.
 *
 * @param c {Client} the client
 * @return {list of TrashFile} the files
 * @throws {Error} kind `"koofr"` as `call`, past `MAX_PAGES` pages, or on a
 *   page over the client's reply limit (`REPLY_LIMIT`, 64 MiB, by default)
 */
export func trashAll(c as Client) {
    def out as list of TrashFile init [];
    def cursor as string init "";
    def seen as map of string to bool init {"": true};
    def pages as int init 0;
    while (true) {
        if ($pages >= MAX_PAGES) {
            fail("GET " + API + "/trash: more than " + convert.toString(MAX_PAGES) + " pages");
        }
        def page as TrashPage init trash($c, $cursor);
        $pages = $pages + 1;
        for (def f in $page.files) {
            $out[] = $f;
        }
        if ($page.cursor == "" or len($page.files) == 0 or maps.has($seen, $page.cursor)) {
            return $out;
        }
        $seen[$page.cursor] = true;
        $cursor = $page.cursor;
    }
    return $out;
}

/**
 * The body of an undelete.
 *
 * @param files {list of TrashFile} the files
 * @return {string} the JSON
 */
func undeleteBody(files as list of TrashFile) {
    def entries as list of json.Value init [];
    for (def f in $files) {
        def at as string init checkPath($f.path);
        $entries[] = objectOf({"mountId": checkId($f.mountId, "mount"), "path": $at});
    }
    return json.encode(json.set(json.decode('{}'), "/files", json.list($entries)));
}

/**
 * Restore files from the trash to where they were. Koofr runs a background
 * job; it may still be running when this returns.
 *
 * @param c {Client} the client
 * @param files {list of TrashFile} the files, e.g. from `trashAll`
 * @throws {Error} kind `"koofr"` on an empty list (`undeleteAll` restores
 *   everything), or as `call`
 */
export func undelete(c as Client, files as list of TrashFile) {
    if (len($files) == 0) {
        fail("undelete needs files; undeleteAll restores everything");
    }
    api($c, "POST", "/trash/undelete", undeleteBody($files));
}

/**
 * Restore everything in the trash, as a background job at Koofr.
 *
 * @param c {Client} the client
 * @throws {Error} kind `"koofr"` as `call`
 */
export func undeleteAll(c as Client) {
    api($c, "POST", "/trash/undelete", undeleteBody([]));
}

/**
 * Empty the trash of every mount, as a background job at Koofr. There is no
 * undo.
 *
 * @param c {Client} the client
 * @throws {Error} kind `"koofr"` as `call`
 */
export func emptyTrash(c as Client) {
    api($c, "DELETE", "/trash", "");
}

# The accessors below call `json.typeOf` with a pointer, which returns
# `missing` for a pointer that does not resolve (0.26.0; 0.25.0 threw).

/**
 * Read a node as text, whatever its type.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {string} the text; "" for absent or `null`
 */
func field(v as json.Value, ptr as string) {
    def kind as string init json.typeOf($v, $ptr);
    if ($kind == "string") {
        return json.asString($v, $ptr);
    } elseif ($kind == "int") {
        return convert.toString(json.asInt($v, $ptr));
    } elseif ($kind == "float") {
        return convert.toString(json.asFloat($v, $ptr));
    } elseif ($kind == "bool") {
        if (json.asBool($v, $ptr)) {
            return "true";
        }
        return "false";
    }
    return "";
}

/**
 * Read a node as an int: a number (truncated) or a numeric string.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {int} the number; 0 for absent, `null`, not numeric or outside
 *   the int range
 */
func numberAt(v as json.Value, ptr as string) {
    def kind as string init json.typeOf($v, $ptr);
    if ($kind == "int") {
        return json.asInt($v, $ptr);
    } elseif ($kind == "float") {
        try {
            return convert.toInt(json.asFloat($v, $ptr));
        } catch (e) {
            return 0;
        }
    } elseif ($kind == "string") {
        try {
            return convert.toInt(strings.trim(json.asString($v, $ptr)));
        } catch (e) {
            return 0;
        }
    }
    return 0;
}

/**
 * Read a node as a float: a number or a numeric string.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {float} the number; 0.0 for absent, `null` or not numeric
 */
func floatAt(v as json.Value, ptr as string) {
    def kind as string init json.typeOf($v, $ptr);
    if ($kind == "float") {
        return json.asFloat($v, $ptr);
    } elseif ($kind == "int") {
        return convert.toFloat(json.asInt($v, $ptr));
    } elseif ($kind == "string") {
        try {
            return convert.toFloat(strings.trim(json.asString($v, $ptr)));
        } catch (e) {
            return 0.0;
        }
    }
    return 0.0;
}

/**
 * Read a flag: `true` or `"true"`.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the pointer
 * @return {bool} the flag; false for absent or `null`
 */
func flag(v as json.Value, ptr as string) {
    return field($v, $ptr) == "true";
}

/**
 * The pointers of a list's elements.
 *
 * @param v {json.Value} the document
 * @param ptr {string} the list's pointer
 * @return {list of string} `<ptr>/0`, `<ptr>/1`, ...; empty when it is no list
 */
func items(v as json.Value, ptr as string) {
    def out as list of string init [];
    if (json.typeOf($v, $ptr) != "list") {
        return $out;
    }
    def n as int init json.length($v, $ptr);
    def i as int init 0;
    while ($i < $n) {
        $out[] = $ptr + "/" + convert.toString($i);
        $i = $i + 1;
    }
    return $out;
}
