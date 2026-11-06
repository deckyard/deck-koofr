# SPDX-License-Identifier: LGPL-3.0-only
# SPDX-FileCopyrightText: Copyright (C) 2026 mplx <mplx@jennifer-lang.dev>
# pragma-jennifer-version: >=0.26.0

/**
 * White-box tests for koofr: jennifer test src/koofr_test.j
 *
 * The checking and parsing helpers are tested directly. The requests go to an
 * `httpd` server on a loopback port that answers with canned Koofr replies
 * and hands back what it received.
 */
use httpd;
use task;
use testing;

/** A canned reply. */
def struct Reply {
    status as int,
    contentType as string,
    body as string
};

/** One request as the fake server saw it. */
def struct Seen {
    method as string,
    path as string,
    query as string,
    auth as string,
    contentType as string,
    body as bytes
};

/** A running fake server. */
def struct Fake {
    srv as httpd.Server,
    url as string,
    t as task of list of Seen
};

/**
 * Answer one request per reply, in order.
 *
 * @param srv {httpd.Server} the listening server
 * @param replies {list of Reply} the replies
 * @return {list of Seen} the requests
 */
func serve(srv as httpd.Server, replies as list of Reply) {
    def seen as list of Seen init [];
    for (def r in $replies) {
        def req as httpd.Request init httpd.accept($srv);
        $seen[] = Seen{
            method: httpd.method($req),
            path: httpd.path($req),
            query: httpd.rawQuery($req),
            auth: httpd.header($req, "Authorization"),
            contentType: httpd.header($req, "Content-Type"),
            body: httpd.body($req)
        };
        httpd.setHeader($req, "Content-Type", $r.contentType);
        httpd.respond($req, $r.status, $r.body);
    }
    return $seen;
}

/**
 * Start a fake server that gives these replies.
 *
 * @param replies {list of Reply} the replies
 * @return {Fake} the server
 */
func fake(replies as list of Reply) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def t as task of list of Seen init spawn {
        return serve($srv, $replies);
    };
    return Fake{srv: $srv, url: "http://" + httpd.address($srv), t: $t};
}

/**
 * Stop a fake server.
 *
 * @param f {Fake} the server
 * @return {list of Seen} what it received
 */
func finish(f as Fake) {
    def seen as list of Seen init task.wait($f.t);
    httpd.shutdown($f.srv);
    return $seen;
}

/**
 * A 200 reply with JSON.
 *
 * @param body {string} the JSON
 * @return {Reply} the reply
 */
func ok(body as string) {
    return Reply{status: 200, contentType: "application/json; charset=utf-8", body: $body};
}

/**
 * A refusal with Koofr's error body.
 *
 * @param status {int} the HTTP status
 * @param code {string} Koofr's error code
 * @param message {string} Koofr's message
 * @return {Reply} the reply
 */
func refused(status as int, code as string, message as string) {
    def body as string init '{"error":{"code":"' + $code + '","message":"' + $message +
        '"},"requestId":"r-1"}';
    return Reply{status: $status, contentType: "application/json; charset=utf-8", body: $body};
}

/**
 * A client for a fake server with an app password.
 *
 * @param f {Fake} the server
 * @return {Client} the client
 */
func authed(f as Fake) {
    return withAppPassword(client($f.url), "me@example.com", "app-pw");
}

/**
 * A request body as text.
 *
 * @param s {Seen} the request
 * @return {string} the body
 */
func textOf(s as Seen) {
    return convert.stringFromBytes($s.body, "utf-8");
}

/**
 * The message of the deck's error.
 *
 * @param e {Error} the error
 * @return {string} its message
 */
func messageOf(e as Error) {
    testing.assertEqual($e.kind, ERROR_KIND);
    return $e.message;
}

/**
 * Fail a test whose call was meant to throw.
 */
func missed() {
    throw Error{kind: "test", message: "the call did not fail"};
}

# `me@example.com:app-pw` in base64.
def const BASIC as string init "Basic bWVAZXhhbXBsZS5jb206YXBwLXB3";

def const MOUNT as string init '{"id":"m-1","name":"Koofr","type":"device","origin":"hosted",' +
    '"owner":{"id":"u1","name":"Ada"},"isPrimary":true,"isShared":false,"online":true,' +
    '"canWrite":true,"canUpload":true,"spaceTotal":10240,"spaceUsed":512,"overQuota":false}';

def const SHARED as string init '{"id":"m-2","name":"Team","type":"export","origin":"share",' +
    '"isPrimary":false,"isShared":true,"online":true}';

def const FILE as string init '{"name":"a b.txt","type":"file","modified":1494936799097,' +
    '"size":36494,"contentType":"text/plain","hash":"2eedb741f199ecc19f1ba815d3d9914d","tags":{}}';

def const LINK as string init '{"id":"0b6e-11","name":"a b.txt","mountId":"m-1",' +
    '"path":"/docs/a b.txt","counter":3,"url":"https://app.koofr.net/links/0b6e-11",' +
    '"shortUrl":"https://k00.fr/x","hash":"h","host":"app.koofr.net","hasPassword":false,' +
    '"passwordRequired":false,"downloadable":true,"created":1700000000000,"message":"hi"}';

def const RECEIVER as string init '{"id":"9c2d-22","name":"inbox","mountId":"m-1",' +
    '"path":"/inbox","counter":1,"url":"https://app.koofr.net/receivers/9c2d-22",' +
    '"shortUrl":"https://k00.fr/y","hash":"h","host":"app.koofr.net","hasPassword":true,' +
    '"alert":true,"created":1700000000000,"validTo":1800000000000}';

func testClientUrl() {
    testing.assertEqual(client(DEFAULT_URL).url, "https://app.koofr.net");
    testing.assertEqual(client("app.koofr.net/").url, "https://app.koofr.net");
    testing.assertEqual(
        client("https://example.com/koofr/api/v2.1/").url,
        "https://example.com/koofr");
    testing.assertEqual(client("http://localhost:8080").url, "http://localhost:8080");
    for (def bad in [" ", "a b"]) {
        try {
            client($bad);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "base URL");
        }
    }
}

func testClientSettings() {
    def c as Client init withRetries(withTimeout(withInsecure(client("x")), 5000), 2);
    testing.assertTrue($c.tls.skipVerify);
    testing.assertEqual($c.timeoutMs, 5000);
    testing.assertEqual($c.retries, 2);
    $c = withCaCert($c, convert.bytesFromString("PEM", "utf-8"));
    testing.assertFalse($c.tls.skipVerify);
    testing.assertEqual(withToken($c, "abc").auth, "Bearer abc");
    testing.assertEqual(withAppPassword($c, "me@example.com", "app-pw").auth, BASIC);
    try {
        withToken($c, "abc\r\nX-Evil: 1");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a token is not empty");
    }
    try {
        withAppPassword($c, "me@example.com", "pw\nX: 1");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a password is not empty");
    }
    try {
        withAppPassword($c, "me:you", "pw");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: an e-mail address holds no :");
    }
}

func testIdleTimeout() {
    testing.assertEqual(idleMs(client("x")), 30000);
    testing.assertEqual(idleMs(withTimeout(client("x"), 500)), 500);
}

func testPathsAndNamesAreChecked() {
    testing.assertEqual(checkPath("/"), "/");
    testing.assertEqual(checkPath("/docs/a b.txt"), "/docs/a b.txt");
    for (def bad in ["", "docs", "/docs/", "//a", "/a/../b", "/a/./b", "/a\nb"]) {
        try {
            checkPath($bad);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "a path");
        }
    }
    testing.assertEqual(checkName("a (1).txt"), "a (1).txt");
    for (def bad in ["", ".", "..", "a/b", "a\tb"]) {
        try {
            checkName($bad);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "a name is not empty");
        }
    }
    for (def bad in ["", "a/b", "a?b", "../x"]) {
        try {
            checkId($bad, "mount");
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "a mount id");
        }
    }
    for (def bad in ["user", "/a//b", "/a/../b", "/a b", "/a#x"]) {
        try {
            ensurePath($bad);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "an API path");
        }
    }
    ensurePath("/user/attributes?x=1");
    testing.assertEqual(parentOf("/a"), "/");
    testing.assertEqual(parentOf("/a/b/c"), "/a/b");
    testing.assertEqual(nameOf("/a/b/c"), "c");
    testing.assertEqual(joined("/", "a"), "/a");
    testing.assertEqual(joined("/docs", "/"), "/docs");
    testing.assertEqual(joined("/docs", "/x/y"), "/docs/x/y");
    def long as string init "/" + strings.repeat("x", 100) + convert.fromCodepoint(10);
    try {
        checkPath($long);
        missed();
    } catch (e) {
        testing.assertFalse(strings.contains(messageOf($e), convert.fromCodepoint(10)));
        testing.assertContains(messageOf($e), "...");
    }
}

func testFailureText() {
    testing.assertEqual(
        failureText(404, "Not Found", '{"error":{"code":"NotFound","message":"File not found"}}'),
        "HTTP 404: File not found (NotFound)");
    testing.assertEqual(failureText(502, "Bad Gateway", "<html>"), "HTTP 502: Bad Gateway");
    def said as string init failureText(
        500,
        "",
        '{"error":{"message":"one\nforged: two ' + strings.repeat("x", 500) + '"}}');
    testing.assertFalse(strings.contains($said, convert.fromCodepoint(10)));
    testing.assertContains($said, "one?forged");
    testing.assertTrue(len($said) < 250);
}

func testAccount() {
    def f as Fake init fake([
        ok('{"id":"u1","firstName":"Ada","lastName":"L","email":"ada@example.com","level":1000}'),
        ok('{"spaceTotal":10}'),
        ok('{"mounts":[' + SHARED + "," + MOUNT + ']}'),
        ok(MOUNT),
        ok('{"mounts":[' + SHARED + "," + MOUNT + ']}'),
        ok('{"mounts":[' + SHARED + ']}')
    ]);
    def c as Client init authed($f);
    def u as User init user($c);
    testing.assertEqual($u.firstName, "Ada");
    testing.assertEqual($u.level, 1000);
    testing.assertEqual(json.asInt(limits($c), "/spaceTotal"), 10);
    def ms as list of Mount init mounts($c);
    testing.assertEqual(len($ms), 2);
    testing.assertTrue($ms[0].isShared);
    testing.assertEqual($ms[0].owner, "");
    def m as Mount init mount($c, "m-1");
    testing.assertEqual($m.owner, "Ada");
    testing.assertEqual($m.spaceTotal, 10240);
    testing.assertEqual($m.spaceUsed, 512);
    testing.assertTrue($m.canUpload);
    testing.assertEqual(primaryMount($c).id, "m-1");
    try {
        primaryMount($c);
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: the account has no primary mount");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].method, "GET");
    testing.assertEqual($seen[0].path, "/api/v2.1/user");
    testing.assertEqual($seen[0].auth, BASIC);
    testing.assertEqual($seen[1].path, "/api/v2.1/user/limits");
    testing.assertEqual($seen[2].path, "/api/v2.1/mounts");
    testing.assertEqual($seen[3].path, "/api/v2.1/mounts/m-1");
}

func testCall() {
    def f as Fake init fake([ok('{"a":1}'), Reply{status: 204, contentType: "", body: ""}]);
    def c as Client init withToken(client($f.url), "t0k3n");
    testing.assertEqual(json.asInt(call($c, "get", "/user/attributes?x=1", ""), "/a"), 1);
    testing.assertEqual(json.typeOf(call($c, "PUT", "/user", '{"firstName":"A"}')), "null");
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].method, "GET");
    testing.assertEqual($seen[0].path, "/api/v2.1/user/attributes");
    testing.assertEqual($seen[0].query, "x=1");
    testing.assertEqual($seen[0].auth, "Bearer t0k3n");
    testing.assertEqual($seen[1].contentType, "application/json");
    testing.assertEqual(textOf($seen[1]), '{"firstName":"A"}');
    try {
        call($c, "TRACE", "/user", "");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "unsupported method");
    }
}

func testRefusalsNameTheRequest() {
    def f as Fake init fake([
        refused(404, "NotFound", "File not found"),
        Reply{status: 200, contentType: "text/html", body: "<html>"}
    ]);
    def c as Client init authed($f);
    try {
        info($c, "m-1", "/missing");
        missed();
    } catch (e) {
        testing.assertEqual(
            messageOf($e),
            "koofr: GET /api/v2.1/mounts/m-1/files/info?path=%2Fmissing: " +
                "HTTP 404: File not found (NotFound)");
    }
    try {
        user($c);
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: GET /api/v2.1/user: the reply is not JSON");
    }
    finish($f);
}

func testFiles() {
    def f as Fake init fake([
        ok(FILE),
        ok('{"files":[' + FILE + ',{"name":"sub","type":"dir","modified":1,"size":0,' +
            '"contentType":"","tags":{}}]}'),
        ok(FILE),
        refused(404, "NotFound", "File not found"),
        Reply{status: 500, contentType: "application/json", body: '{"error":{"message":"boom"}}'}
    ]);
    def c as Client init authed($f);
    def one as File init info($c, "m-1", "/docs/a b.txt");
    testing.assertEqual($one.path, "/docs/a b.txt");
    testing.assertEqual($one.size, 36494);
    testing.assertEqual($one.modified, 1494936799097);
    testing.assertEqual($one.hash, "2eedb741f199ecc19f1ba815d3d9914d");
    def got as list of File init listFolder($c, "m-1", "/docs");
    testing.assertEqual(len($got), 2);
    testing.assertEqual($got[0].path, "/docs/a b.txt");
    testing.assertEqual($got[1].path, "/docs/sub");
    testing.assertEqual($got[1].type, "dir");
    testing.assertTrue(exists($c, "m-1", "/docs/a b.txt"));
    testing.assertFalse(exists($c, "m-1", "/nope"));
    try {
        exists($c, "m-1", "/x");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 500: boom");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/v2.1/mounts/m-1/files/info");
    testing.assertEqual($seen[0].query, "path=%2Fdocs%2Fa%20b.txt");
    testing.assertEqual($seen[1].path, "/api/v2.1/mounts/m-1/files/list");
    testing.assertEqual($seen[1].query, "path=%2Fdocs");
    testing.assertEqual($seen[3].query, "path=%2Fnope");
}

func testListRecursive() {
    def stream as string init '{"type":"file","path":"/","file":{"name":"docs","type":"dir",' +
        '"modified":1,"size":0,"contentType":"","tags":{}}}' + "\n" +
        '{"type":"file","path":"/a b.txt","file":' + FILE + '}' + "\n" +
        '{"type":"file","path":"/sub/c.txt","file":{"name":"c.txt","type":"file","size":3}}' + "\n";
    def broken as string init '{"type":"file","path":"/","file":{"name":"docs","type":"dir"}}' +
        "\n" +
        '{"type":"error","error":{"code":"DeviceOffline","message":"Device is offline"}}' + "\n";
    def nd as string init "application/x-ndjson; charset=utf-8";
    def f as Fake init fake([
        Reply{status: 200, contentType: $nd, body: $stream},
        Reply{status: 200, contentType: $nd, body: $broken},
        Reply{status: 200, contentType: $nd, body: '{not json' + "\n"}
    ]);
    def c as Client init authed($f);
    def got as list of File init listRecursive($c, "m-1", "/docs");
    testing.assertEqual(len($got), 3);
    testing.assertEqual($got[0].path, "/docs");
    testing.assertEqual($got[0].type, "dir");
    testing.assertEqual($got[1].path, "/docs/a b.txt");
    testing.assertEqual($got[2].path, "/docs/sub/c.txt");
    testing.assertEqual($got[2].size, 3);
    try {
        listRecursive($c, "m-1", "/");
        missed();
    } catch (e) {
        testing.assertContains(
            messageOf($e),
            "the listing broke off after 1 entries: Device is offline (DeviceOffline)");
    }
    try {
        listRecursive($c, "m-1", "/");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "the reply is not NDJSON");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/content/api/v2.1/mounts/m-1/files/listrecursive");
    testing.assertEqual($seen[0].query, "path=%2Fdocs");
}

func testFolders() {
    def dir as string init '{"name":"x","type":"dir","size":0}';
    def f as Fake init fake([
        ok(""),
        refused(404, "NotFound", "File not found"),
        ok($dir),
        refused(404, "NotFound", "File not found"),
        ok(""),
        ok(""),
        ok(FILE)
    ]);
    def c as Client init authed($f);
    mkdir($c, "m-1", "/docs/2026");
    mkdirAll($c, "m-1", "/a/b c/d");
    try {
        mkdirAll($c, "m-1", "/a/f.txt");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: \"/a/f.txt\" is a file, not a folder");
    }
    mkdirAll($c, "m-1", "/");
    try {
        mkdir($c, "m-1", "/");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: the root exists already");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual(len($seen), 7);
    testing.assertEqual($seen[0].method, "POST");
    testing.assertEqual($seen[0].path, "/api/v2.1/mounts/m-1/files/folder");
    testing.assertEqual($seen[0].query, "path=%2Fdocs");
    testing.assertEqual($seen[0].contentType, "application/json");
    testing.assertEqual(textOf($seen[0]), '{"name":"2026"}');
    # The full path is missing, /a exists, /a/b c is missing: /a/b c and
    # /a/b c/d are made without probing /a/b c/d again.
    testing.assertEqual($seen[1].method, "GET");
    testing.assertEqual($seen[1].query, "path=%2Fa%2Fb%20c%2Fd");
    testing.assertEqual($seen[2].query, "path=%2Fa");
    testing.assertEqual($seen[3].query, "path=%2Fa%2Fb%20c");
    testing.assertEqual($seen[4].method, "POST");
    testing.assertEqual($seen[4].query, "path=%2Fa");
    testing.assertEqual(textOf($seen[4]), '{"name":"b c"}');
    testing.assertEqual($seen[5].method, "POST");
    testing.assertEqual($seen[5].query, "path=%2Fa%2Fb%20c");
    testing.assertEqual(textOf($seen[5]), '{"name":"d"}');
    testing.assertEqual($seen[6].query, "path=%2Fa%2Ff.txt");
}

func testGet() {
    def f as Fake init fake([
        Reply{status: 200, contentType: "application/octet-stream", body: "hello"},
        Reply{status: 200, contentType: "application/octet-stream", body: "hello"},
        refused(404, "NotFound", "File not found")
    ]);
    def c as Client init authed($f);
    testing.assertEqual(convert.stringFromBytes(get($c, "m-1", "/a b.txt", 0), "utf-8"), "hello");
    try {
        get($c, "m-1", "/a b.txt", 3);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "koofr: GET /content/api/v2.1/mounts/m-1/files/get");
    }
    try {
        get($c, "m-1", "/gone", -1);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 404: File not found (NotFound)");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/content/api/v2.1/mounts/m-1/files/get");
    testing.assertEqual($seen[0].query, "path=%2Fa%20b.txt");
    testing.assertEqual($seen[0].auth, BASIC);
}

func testPut() {
    def f as Fake init fake([ok(FILE), ok(FILE), refused(409, "Conflict", "File exists")]);
    def c as Client init authed($f);
    def data as bytes init convert.bytesFromString("hello", "utf-8");
    def opts as PutOptions;
    def stored as File init put($c, "m-1", "/docs/a b.txt", $data, $opts);
    testing.assertEqual($stored.path, "/docs/a b.txt");
    testing.assertEqual($stored.size, 36494);
    $opts.overwriteIfHash = "abc";
    $opts.overwriteIfModified = 1700000000000;
    $opts.overwriteIgnoreNonexistent = true;
    $opts.modified = 1600000000000;
    $opts.autorename = true;
    put($c, "m-1", "/top.txt", $data, $opts);
    try {
        def plainPut as PutOptions;
        put($c, "m-1", "/top.txt", $data, $plainPut);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 409: File exists (Conflict)");
    }
    try {
        put($c, "m-1", "/", $data, $opts);
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: a file needs a name");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].method, "POST");
    testing.assertEqual($seen[0].path, "/content/api/v2.1/mounts/m-1/files/put");
    testing.assertEqual(
        $seen[0].query,
        "path=%2Fdocs&filename=a%20b.txt&info=true&overwrite=false&autorename=false");
    # The content is the raw body; the name is only in `filename`.
    testing.assertEqual($seen[0].contentType, "application/octet-stream");
    testing.assertEqual(textOf($seen[0]), "hello");
    testing.assertEqual($seen[0].auth, BASIC);
    testing.assertEqual(
        $seen[1].query,
        "path=%2F&filename=top.txt&info=true&overwrite=false&autorename=true" +
            "&overwriteIfHash=abc&overwriteIfModified=1700000000000" +
            "&overwriteIgnoreNonexistent=true&modified=1600000000000");
}

func testRemoveRenameCopyMove() {
    def f as Fake init fake([ok('{}'), ok(""), ok('{"name":"a (1).txt"}'), ok('{"name":"a.txt"}')]);
    def c as Client init authed($f);
    remove($c, "m-1", "/old");
    rename($c, "m-1", "/docs/a.txt", "b.txt");
    testing.assertEqual(copy($c, "m-1", "/docs/a.txt", "m-2", "/in/a.txt"), "a (1).txt");
    testing.assertEqual(move($c, "m-1", "/docs/a.txt", "m-1", "/arch/a.txt"), "a.txt");
    try {
        remove($c, "m-1", "/");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: the root cannot be removed");
    }
    try {
        rename($c, "m-1", "/docs/a.txt", "x/y");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a name is not empty");
    }
    try {
        move($c, "m-1", "/a", "m-1", "/");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "the root cannot be a source or target of move");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].method, "DELETE");
    testing.assertEqual($seen[0].path, "/api/v2.1/mounts/m-1/files/remove");
    testing.assertEqual($seen[0].query, "path=%2Fold");
    testing.assertEqual($seen[1].method, "PUT");
    testing.assertEqual($seen[1].path, "/api/v2.1/mounts/m-1/files/rename");
    testing.assertEqual(textOf($seen[1]), '{"name":"b.txt"}');
    testing.assertEqual($seen[2].path, "/api/v2.1/mounts/m-1/files/copy");
    testing.assertEqual($seen[2].query, "path=%2Fdocs%2Fa.txt");
    testing.assertEqual(textOf($seen[2]), '{"toMountId":"m-2","toPath":"/in/a.txt"}');
    testing.assertEqual($seen[3].path, "/api/v2.1/mounts/m-1/files/move");
    testing.assertEqual(textOf($seen[3]), '{"toMountId":"m-1","toPath":"/arch/a.txt"}');
}

/**
 * Search options a search refuses, one fault each.
 *
 * @return {list of SearchOptions} the options
 */
func badSearches() {
    def out as list of SearchOptions init [];
    def o as SearchOptions;
    $o.limit = 1001;
    $out[] = $o;
    $o.limit = 0;
    $o.offset = -1;
    $out[] = $o;
    $o.offset = 0;
    $o.fileType = "movie";
    $out[] = $o;
    $o.fileType = "";
    $o.path = "/docs";
    $out[] = $o;
    $o.path = "";
    $o.tags = ["novalue"];
    $out[] = $o;
    return $out;
}

func testSearch() {
    def hit as string init '{"mountId":"m-1","path":"/docs/a b.txt","score":1.5,"name":"a b.txt",' +
        '"type":"file","modified":5,"size":7,"contentType":"text/plain","tags":{}}';
    def f as Fake init fake([
        ok('{"hits":[' + $hit + '],"mounts":{"m-1":' + MOUNT + '}}'),
        ok('{"hits":[]}')
    ]);
    def c as Client init authed($f);
    def none as SearchOptions;
    def got as list of SearchHit init search($c, "a b", $none);
    testing.assertEqual(len($got), 1);
    testing.assertEqual($got[0].path, "/docs/a b.txt");
    testing.assertEqual($got[0].score, 1.5);
    testing.assertEqual($got[0].size, 7);
    def opts as SearchOptions init SearchOptions{
        offset: 10,
        limit: 1000,
        mountId: "m-1",
        path: "/docs",
        contentType: "image/png",
        fileType: "image",
        tags: ["k=v", "a=b c"]
    };
    testing.assertEqual(len(search($c, "", $opts)), 0);
    for (def bad in badSearches()) {
        try {
            search($c, "x", $bad);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "koofr: a");
        }
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/v2.1/search");
    testing.assertEqual($seen[0].query, "query=a%20b");
    testing.assertEqual(
        $seen[1].query,
        "query=&offset=10&limit=1000&mountId=m-1&path=%2Fdocs&contentType=image%2Fpng" +
            "&fileType=image&tag=k%3Dv&tag=a%3Db%20c");
}

func testLinks() {
    def f as Fake init fake([
        ok('{"links":[' + LINK + ']}'),
        ok('{"links":[' + LINK + "," + LINK + '],"mounts":{}}'),
        Reply{status: 201, contentType: "application/json", body: LINK},
        ok(LINK),
        Reply{status: 204, contentType: "", body: ""},
        ok(LINK),
        ok(LINK),
        ok(LINK)
    ]);
    def c as Client init authed($f);
    def got as list of Link init links($c, "m-1");
    testing.assertEqual($got[0].id, "0b6e-11");
    testing.assertEqual($got[0].shortUrl, "https://k00.fr/x");
    testing.assertEqual($got[0].counter, 3);
    testing.assertTrue($got[0].downloadable);
    testing.assertEqual($got[0].message, "hi");
    testing.assertEqual($got[0].created, 1700000000000);
    testing.assertEqual($got[0].validTo, 0);
    testing.assertEqual(len(allLinks($c)), 2);
    testing.assertEqual(createLink($c, "m-1", "/docs/a b.txt").path, "/docs/a b.txt");
    testing.assertEqual(link($c, "m-1", "0b6e-11").name, "a b.txt");
    deleteLink($c, "m-1", "0b6e-11");
    setLinkPassword($c, "m-1", "0b6e-11", "s3cret");
    clearLinkPassword($c, "m-1", "0b6e-11");
    setLinkValidity($c, "m-1", "0b6e-11", 0, 1800000000000);
    try {
        setLinkPassword($c, "m-1", "0b6e-11", "");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: a password is not empty");
    }
    try {
        setLinkValidity($c, "m-1", "0b6e-11", 20, 10);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a validity window ends after it starts");
    }
    try {
        link($c, "m-1", "../x");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a link id");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/v2.1/mounts/m-1/links");
    testing.assertEqual($seen[1].path, "/api/v2.1/links");
    testing.assertEqual($seen[2].method, "POST");
    testing.assertEqual($seen[2].path, "/api/v2.1/mounts/m-1/links");
    testing.assertEqual(textOf($seen[2]), '{"path":"/docs/a b.txt"}');
    testing.assertEqual($seen[3].path, "/api/v2.1/mounts/m-1/links/0b6e-11");
    testing.assertEqual($seen[4].method, "DELETE");
    testing.assertEqual($seen[4].path, "/api/v2.1/mounts/m-1/links/0b6e-11");
    testing.assertEqual($seen[5].method, "PUT");
    testing.assertEqual($seen[5].path, "/api/v2.1/mounts/m-1/links/0b6e-11/password/set");
    testing.assertEqual(textOf($seen[5]), '{"password":"s3cret"}');
    testing.assertEqual($seen[6].method, "DELETE");
    testing.assertEqual($seen[6].path, "/api/v2.1/mounts/m-1/links/0b6e-11/password");
    testing.assertEqual($seen[7].path, "/api/v2.1/mounts/m-1/links/0b6e-11/validity");
    testing.assertEqual(textOf($seen[7]), '{"validTo":1800000000000}');
}

func testReceivers() {
    def f as Fake init fake([
        ok('{"receivers":[' + RECEIVER + ']}'),
        ok('{"receivers":[' + RECEIVER + '],"mounts":{}}'),
        Reply{status: 201, contentType: "application/json", body: RECEIVER},
        ok(RECEIVER),
        Reply{status: 204, contentType: "", body: ""},
        ok(RECEIVER),
        ok(RECEIVER),
        ok(RECEIVER)
    ]);
    def c as Client init authed($f);
    def got as list of Receiver init receivers($c, "m-1");
    testing.assertEqual($got[0].id, "9c2d-22");
    testing.assertTrue($got[0].hasPassword);
    testing.assertTrue($got[0].alert);
    testing.assertEqual($got[0].validTo, 1800000000000);
    testing.assertEqual(len(allReceivers($c)), 1);
    testing.assertEqual(createReceiver($c, "m-1", "/inbox").path, "/inbox");
    testing.assertEqual(receiver($c, "m-1", "9c2d-22").name, "inbox");
    deleteReceiver($c, "m-1", "9c2d-22");
    setReceiverPassword($c, "m-1", "9c2d-22", "pw");
    clearReceiverPassword($c, "m-1", "9c2d-22");
    setReceiverValidity($c, "m-1", "9c2d-22", 1700000000000, 1800000000000);
    try {
        receiver($c, "m-1", "a b");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a receiver id");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/v2.1/mounts/m-1/receivers");
    testing.assertEqual($seen[1].path, "/api/v2.1/receivers");
    testing.assertEqual(textOf($seen[2]), '{"path":"/inbox"}');
    testing.assertEqual($seen[3].path, "/api/v2.1/mounts/m-1/receivers/9c2d-22");
    testing.assertEqual($seen[4].method, "DELETE");
    testing.assertEqual($seen[5].path, "/api/v2.1/mounts/m-1/receivers/9c2d-22/password/set");
    testing.assertEqual(textOf($seen[5]), '{"password":"pw"}');
    testing.assertEqual($seen[6].path, "/api/v2.1/mounts/m-1/receivers/9c2d-22/password");
    testing.assertEqual($seen[7].path, "/api/v2.1/mounts/m-1/receivers/9c2d-22/validity");
    testing.assertEqual(textOf($seen[7]), '{"validFrom":1700000000000,"validTo":1800000000000}');
}

func testTrash() {
    def gone as string init '{"mountId":"m-1","path":"/old/a.txt","name":"a.txt","deleted":9,' +
        '"size":5,"contentType":"text/plain","versionId":"v1","tags":{}}';
    def job as string init '{"id":"j1","type":"undelete","state":"queued"}';
    def f as Fake init fake([
        ok('{"files":[' + $gone + '],"mounts":{},"retentionDays":30,"pageInfo":{"cursor":"c 2"}}'),
        ok('{"files":[' + $gone + '],"mounts":{},"retentionDays":30,"pageInfo":{"cursor":"c 2"}}'),
        ok('{"files":[' + $gone + "," + $gone + '],"mounts":{},"retentionDays":30,"pageInfo":{}}'),
        ok($job),
        ok($job),
        ok($job)
    ]);
    def c as Client init authed($f);
    def page as TrashPage init trash($c, "");
    testing.assertEqual($page.cursor, "c 2");
    testing.assertEqual($page.retentionDays, 30);
    testing.assertEqual($page.files[0].path, "/old/a.txt");
    testing.assertEqual($page.files[0].versionId, "v1");
    testing.assertEqual($page.files[0].deleted, 9);
    def every as list of TrashFile init trashAll($c);
    testing.assertEqual(len($every), 3);
    undelete($c, [$every[0]]);
    undeleteAll($c);
    emptyTrash($c);
    try {
        undelete($c, []);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "undeleteAll restores everything");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].path, "/api/v2.1/trash");
    testing.assertEqual($seen[0].query, "");
    testing.assertEqual($seen[2].query, "cursor=c%202");
    testing.assertEqual($seen[3].method, "POST");
    testing.assertEqual($seen[3].path, "/api/v2.1/trash/undelete");
    testing.assertEqual(textOf($seen[3]), '{"files":[{"mountId":"m-1","path":"/old/a.txt"}]}');
    testing.assertEqual(textOf($seen[4]), '{"files":[]}');
    testing.assertEqual($seen[5].method, "DELETE");
    testing.assertEqual($seen[5].path, "/api/v2.1/trash");
}

func testTrashAllStopsOnARepeatedCursor() {
    def page as string init '{"files":[{"path":"/a"}],"pageInfo":{"cursor":"same"}}';
    def f as Fake init fake([ok($page), ok($page)]);
    testing.assertEqual(len(trashAll(authed($f))), 2);
    finish($f);
}

func testAccessorsTolerateOddValues() {
    def d as json.Value init json.decode(
        '{"n":"12","f":2,"s":" 1.5 ","b":"true","z":null,"x":"q"}');
    testing.assertEqual(numberAt($d, "/n"), 12);
    testing.assertEqual(numberAt($d, "/x"), 0);
    testing.assertEqual(numberAt($d, "/missing"), 0);
    testing.assertEqual(floatAt($d, "/f"), 2.0);
    testing.assertEqual(floatAt($d, "/s"), 1.5);
    testing.assertEqual(floatAt($d, "/x"), 0.0);
    testing.assertTrue(flag($d, "/b"));
    testing.assertEqual(field($d, "/z"), "");
    testing.assertEqual(len(items($d, "/n")), 0);
}

# Regression tests: each fails on the code before the fix it names.

/**
 * Answer one request with a raw body.
 *
 * @param srv {httpd.Server} the listening server
 * @param status {int} the HTTP status
 * @param body {bytes} the body
 * @return {int} 0
 */
func serveBytes(srv as httpd.Server, status as int, body as bytes) {
    def req as httpd.Request init httpd.accept($srv);
    httpd.setHeader($req, "Content-Type", "application/octet-stream");
    httpd.respond($req, $status, $body);
    return 0;
}

/**
 * A client that gives up on a silent server after 2 s, so a test that sends
 * more requests than its fake answers fails instead of hanging.
 *
 * @param f {Fake} the server
 * @return {Client} the client
 */
func impatient(f as Fake) {
    return withTimeout(authed($f), 2000);
}

func testNumberOutOfRangeIsZero() {
    # A float outside the int range reads as 0, like a numeric string does.
    def d as json.Value init json.decode(
        '{"a":1e20,"b":-1e20,"c":18446744073709551616,"d":2.9,"e":"18446744073709551616"}');
    testing.assertEqual(numberAt($d, "/a"), 0);
    testing.assertEqual(numberAt($d, "/b"), 0);
    testing.assertEqual(numberAt($d, "/c"), 0);
    testing.assertEqual(numberAt($d, "/d"), 2);
    testing.assertEqual(numberAt($d, "/e"), 0);
    def f as Fake init fake([
        ok('{"name":"a","type":"file","size":1e20,"modified":1,"contentType":"x","tags":{}}')
    ]);
    def got as File init info(authed($f), "m-1", "/a");
    testing.assertEqual($got.size, 0);
    testing.assertEqual($got.name, "a");
    testing.assertEqual($got.modified, 1);
    finish($f);
}

func testGetErrorBodyNotUtf8() {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def junk as bytes;
    for (def b in [255, 254, 0, 195, 40]) {
        $junk[] = $b;
    }
    def t as task of int init spawn {
        return serveBytes($srv, 500, $junk);
    };
    def c as Client init client("http://" + httpd.address($srv));
    try {
        get($c, "m-1", "/a.bin", 0);
        missed();
    } catch (e) {
        testing.assertContains(
            messageOf($e),
            "koofr: GET /content/api/v2.1/mounts/m-1/files/get?path=%2Fa.bin: HTTP 500");
    }
    task.wait($t);
    httpd.shutdown($srv);
}

func testExistsOnlyNotFoundIsMissing() {
    def f as Fake init fake([
        refused(404, "DeviceOffline", "Device is offline"),
        refused(404, "Other", "Mount not found"),
        refused(404, "NotFound", "File not found"),
        Reply{status: 404, contentType: "application/json", body: '{"error":{}}'},
        Reply{status: 404, contentType: "application/json", body: '{"error":{"code":""}}'}
    ]);
    def c as Client init authed($f);
    try {
        exists($c, "dev-1", "/backups");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 404: Device is offline (DeviceOffline)");
    }
    try {
        exists($c, "gone", "/backups");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 404: Mount not found (Other)");
    }
    testing.assertFalse(exists($c, "m-1", "/a"));
    testing.assertFalse(exists($c, "m-1", "/b"));
    testing.assertFalse(exists($c, "m-1", "/c"));
    finish($f);
}

func testMkdirAllStopsOnAnOfflineDevice() {
    def f as Fake init fake([refused(404, "DeviceOffline", "Device is offline")]);
    try {
        mkdirAll(impatient($f), "dev-1", "/a/b");
        missed();
    } catch (e) {
        testing.assertEqual(
            messageOf($e),
            "koofr: GET /api/v2.1/mounts/dev-1/files/info?path=%2Fa%2Fb: " +
                "HTTP 404: Device is offline (DeviceOffline)");
    }
    testing.assertEqual(len(finish($f)), 1);
}

func testMkdirAllRequestCount() {
    def dir as string init '{"name":"k2","type":"dir","size":0}';
    def missing as Reply init refused(404, "NotFound", "File not found");
    def f as Fake init fake([ok($dir), $missing, $missing, ok(""), ok(""), ok("")]);
    def c as Client init impatient($f);
    # An existing folder: one request, whatever its depth.
    mkdirAll($c, "m-1", "/k1/k2");
    # Nothing exists: the full path, the top, then three mkdir.
    mkdirAll($c, "m-1", "/n1/n2/n3");
    def seen as list of Seen init finish($f);
    testing.assertEqual(len($seen), 6);
    testing.assertEqual($seen[0].query, "path=%2Fk1%2Fk2");
    testing.assertEqual($seen[1].query, "path=%2Fn1%2Fn2%2Fn3");
    testing.assertEqual($seen[2].query, "path=%2Fn1");
    testing.assertEqual($seen[3].method, "POST");
    testing.assertEqual($seen[3].query, "path=%2F");
    testing.assertEqual(textOf($seen[3]), '{"name":"n1"}');
    testing.assertEqual($seen[4].query, "path=%2Fn1");
    testing.assertEqual(textOf($seen[4]), '{"name":"n2"}');
    testing.assertEqual($seen[5].query, "path=%2Fn1%2Fn2");
    testing.assertEqual(textOf($seen[5]), '{"name":"n3"}');
}

func testCredentialsNeedHttpsOffLoopback() {
    def remote as Client init withAppPassword(
        client("http://example.com"),
        "me@example.com",
        "app-pw");
    try {
        baseHeaders($remote);
        missed();
    } catch (e) {
        testing.assertEqual(
            messageOf($e),
            "koofr: credentials go over http:// only to a loopback host; use https:// or " +
                "withPlainHttp, got \"http://example.com\"");
    }
    for (def url in ["http://10.0.0.1", "http://127.0.0.1.example.com", "http://[::2]"]) {
        try {
            baseHeaders(withToken(client($url), "t"));
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "credentials go over http://");
        }
    }
    testing.assertEqual(baseHeaders(withPlainHttp($remote))["Authorization"], BASIC);
    for (def url in [
        "https://example.com",
        "http://127.0.0.1:8080",
        "http://127.9.9.9",
        "http://localhost",
        "http://LOCALHOST:1",
        "http://[::1]:8080"
    ]) {
        def c as Client init withAppPassword(client($url), "me@example.com", "app-pw");
        testing.assertEqual(baseHeaders($c)["Authorization"], BASIC);
    }
    testing.assertFalse(maps.has(baseHeaders(client("http://example.com")), "Authorization"));
}

func testBaseUrlIsChecked() {
    testing.assertEqual(client("https://h/content/api/v2.1").url, "https://h");
    testing.assertEqual(client("HTTPS://h:8443/sub/api/v2.1/").url, "https://h:8443/sub");
    testing.assertEqual(client("[::1]:8080").url, "https://[::1]:8080");
    testing.assertEqual(client("localhost:8080").url, "https://localhost:8080");
    for (def bad in [
        "http://h#x",
        "http://h?a=1",
        "http://h/?",
        "http://",
        "https:///path",
        "javascript:alert(1)",
        "ftp://host",
        "https://user:pw@host",
        "https://@host",
        "https://h:0",
        "https://h:70000",
        "https://h:",
        "https://h%41"
    ]) {
        try {
            client($bad);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "a base URL");
        }
    }
}

func testTimeoutNotNegative() {
    testing.assertEqual(withTimeout(client("x"), 0).timeoutMs, 0);
    try {
        withTimeout(client("x"), -1);
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: a timeout is 0 or more ms, got -1");
    }
}

func testRetriesAreBounded() {
    testing.assertEqual(MAX_RETRIES, 10);
    testing.assertEqual(withRetries(client("x"), MAX_RETRIES).retries, 10);
    for (def n in [-1, MAX_RETRIES + 1, 1000000000]) {
        try {
            withRetries(client("x"), $n);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "koofr: retries are 0 to 10, got");
        }
    }
}

func testCallRefusesAFragmentInTheQuery() {
    try {
        ensurePath("/search?query=a#b&limit=5");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "an API path holds no //, # or spaces");
    }
}

func testRenameRefusesTheRoot() {
    # Port 1 on loopback: a request that is sent fails with another message.
    try {
        rename(client("http://127.0.0.1:1"), "m-1", "/", "x");
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: the root cannot be renamed");
    }
}

func testTrashAllStopsOnACursorCycle() {
    def page as string init '{"files":[{"path":"/a"}],"pageInfo":{"cursor":"';
    def f as Fake init fake([ok($page + 'A"}}'), ok($page + 'B"}}'), ok($page + 'A"}}')]);
    testing.assertEqual(len(trashAll(impatient($f))), 3);
    def seen as list of Seen init finish($f);
    testing.assertEqual(len($seen), 3);
    testing.assertEqual($seen[0].query, "");
    testing.assertEqual($seen[1].query, "cursor=A");
    testing.assertEqual($seen[2].query, "cursor=B");
}

func testReplyLimit() {
    def f as Fake init fake([ok('{"files":[' + FILE + ']}'), ok('{"files":[' + FILE + ']}')]);
    def c as Client init withReplyLimit(authed($f), 100);
    try {
        listFolder($c, "m-1", "/");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "exceeds 100 bytes");
    }
    testing.assertEqual(len(listFolder(withReplyLimit($c, 0), "m-1", "/")), 1);
    finish($f);
    testing.assertEqual(REPLY_LIMIT, 67108864);
    testing.assertEqual(replyCap(client("x")), REPLY_LIMIT);
    testing.assertEqual(replyCap(withReplyLimit(client("x"), -1)), -1);
}

func testListRecursiveRefusesAnEntryWithoutPathOrFile() {
    def top as string init '{"type":"file","path":"/","file":{"name":"d","type":"dir"}}' + "\n";
    def nd as string init "application/x-ndjson";
    def f as Fake init fake([
        Reply{
            status: 200,
            contentType: $nd,
            body: $top + '{"type":"file","file":{"name":"a.txt","type":"file"}}' + "\n"
        },
        Reply{status: 200, contentType: $nd, body: $top + '{"type":"file","path":"/a.txt"}' + "\n"}
    ]);
    def c as Client init authed($f);
    for (def i in [1, 2]) {
        try {
            listRecursive($c, "m-1", "/d");
            missed();
        } catch (e) {
            testing.assertEqual(
                messageOf($e),
                "koofr: GET /content/api/v2.1/mounts/m-1/files/listrecursive?path=%2Fd: " +
                    "entry 1 has no path or file");
        }
    }
    finish($f);
}

func testSearchTagNeedsAKey() {
    def o as SearchOptions;
    $o.tags = ["=v"];
    try {
        searchQuery("x", $o);
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: a tag filter is key=value, got \"=v\"");
    }
    $o.tags = ["k="];
    testing.assertEqual(searchQuery("x", $o), "query=x&tag=k%3D");
}

func testIdMessageNamesUnderscore() {
    testing.assertEqual(checkId("a_b-1", "mount"), "a_b-1");
    try {
        checkId("a.b", "mount");
        missed();
    } catch (e) {
        testing.assertEqual(
            messageOf($e),
            "koofr: a mount id is letters, digits, - and _, got \"a.b\"");
    }
}

# Coverage of verbs and fields the tests above do not reach.

func testFileFieldsOfOtherTypes() {
    # Fields of another type than the API's take the tolerant path.
    def f as Fake init fake([
        ok('{"name":"a","type":"file","size":"12","modified":3.0,"contentType":null}'),
        ok('{"name":"d","type":"dir","size":0,"modified":4,"contentType":""}')
    ]);
    def c as Client init authed($f);
    def a as File init info($c, "m-1", "/a");
    testing.assertEqual($a.size, 12);
    testing.assertEqual($a.modified, 3);
    testing.assertEqual($a.contentType, "");
    testing.assertEqual($a.hash, "");
    def d as File init info($c, "m-1", "/d");
    testing.assertEqual($d.type, "dir");
    testing.assertEqual($d.modified, 4);
    testing.assertEqual($d.hash, "");
    finish($f);
}

func testUserAndMountFields() {
    def f as Fake init fake([
        ok('{"id":"u1","firstName":"Ada","lastName":"L","email":"ada@example.com","level":"7"}'),
        ok(MOUNT),
        Reply{status: 204, contentType: "", body: ""}
    ]);
    def c as Client init authed($f);
    testing.assertEqual(
        user($c),
        User{id: "u1", firstName: "Ada", lastName: "L", email: "ada@example.com", level: 7});
    testing.assertEqual(
        mount($c, "m-1"),
        Mount{
            id: "m-1",
            name: "Koofr",
            type: "device",
            origin: "hosted",
            owner: "Ada",
            isPrimary: true,
            isShared: false,
            online: true,
            canWrite: true,
            canUpload: true,
            spaceTotal: 10240,
            spaceUsed: 512,
            overQuota: false
        });
    testing.assertEqual(json.typeOf(limits($c)), "null");
    finish($f);
}

func testRetriesOnlyForGet() {
    def busy as Reply init Reply{status: 503, contentType: "text/plain", body: ""};
    def f as Fake init fake([$busy, ok('{"id":"u1"}'), $busy, $busy]);
    def c as Client init withRetries(authed($f), 1);
    testing.assertEqual(user($c).id, "u1");
    try {
        call($c, "POST", "/user", "");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "POST /api/v2.1/user: HTTP 503");
    }
    try {
        get($c, "m-1", "/a", 0);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 503");
    }
    def seen as list of Seen init finish($f);
    testing.assertEqual(len($seen), 4);
    testing.assertEqual($seen[1].path, "/api/v2.1/user");
    testing.assertEqual($seen[2].method, "POST");
    testing.assertEqual($seen[3].path, "/content/api/v2.1/mounts/m-1/files/get");
}

func testGetCap() {
    def body as Reply init Reply{
        status: 200,
        contentType: "application/octet-stream",
        body: "hello"
    };
    def f as Fake init fake([$body, $body, $body]);
    def c as Client init authed($f);
    testing.assertEqual(len(get($c, "m-1", "/a", 5)), 5);
    testing.assertEqual(len(get($c, "m-1", "/a", -1)), 5);
    # The cap counts the body only: a 5-byte file is refused at 4.
    try {
        get($c, "m-1", "/a", 4);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "exceeds 4 bytes");
    }
    testing.assertEqual(finish($f)[0].contentType, "");
}

func testCallMethodsAndTls() {
    def f as Fake init fake([ok('{"a":1}'), Reply{status: 204, contentType: "", body: ""}]);
    def c as Client init authed($f);
    testing.assertEqual(json.asInt(call($c, "patch", "/user", '{"lastName":"B"}'), "/a"), 1);
    testing.assertEqual(json.typeOf(call($c, "DELETE", "/devices/d-1", "")), "null");
    def seen as list of Seen init finish($f);
    testing.assertEqual($seen[0].method, "PATCH");
    testing.assertEqual(textOf($seen[0]), '{"lastName":"B"}');
    testing.assertEqual($seen[1].method, "DELETE");
    testing.assertEqual($seen[1].path, "/api/v2.1/devices/d-1");
    testing.assertEqual($seen[1].contentType, "");
    def pem as bytes init convert.bytesFromString("PEM", "utf-8");
    def tls as Client init withCaCert(withInsecure(client("x")), $pem);
    testing.assertEqual($tls.tls.caCert, $pem);
    testing.assertFalse($tls.tls.skipVerify);
}

func testCopyMoveRefuseTheRoot() {
    for (def pair in [["/", "/b"], ["/a", "/"]]) {
        try {
            copy(client("x"), "m-1", $pair[0], "m-1", $pair[1]);
            missed();
        } catch (e) {
            testing.assertEqual(
                messageOf($e),
                "koofr: the root cannot be a source or target of copy");
        }
    }
    try {
        move(client("x"), "m-1", "/a", "bad id", "/b");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "a mount id");
    }
}

func testLinkAndReceiverChanges() {
    def locked as string init '{"id":"0b6e-11","hasPassword":true,"validFrom":1700000000000}';
    def f as Fake init fake([
        ok($locked),
        ok('{"id":"9c2d-22","validTo":5}'),
        ok('{"id":"9c2d-22"}')
    ]);
    def c as Client init authed($f);
    def l as Link init setLinkPassword($c, "m-1", "0b6e-11", "s3cret");
    testing.assertTrue($l.hasPassword);
    testing.assertEqual($l.validFrom, 1700000000000);
    testing.assertEqual(setReceiverValidity($c, "m-1", "9c2d-22", 0, 5).validTo, 5);
    testing.assertFalse(clearReceiverPassword($c, "m-1", "9c2d-22").hasPassword);
    def seen as list of Seen init finish($f);
    testing.assertEqual(textOf($seen[1]), '{"validTo":5}');
    testing.assertEqual($seen[2].method, "DELETE");
    for (def w in [[-1, 0], [0, -1], [5, 5]]) {
        try {
            validityOf($w[0], $w[1]);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "a validity window");
        }
    }
    testing.assertEqual(validityOf(0, 0), '{}');
    testing.assertEqual(validityOf(7, 0), '{"validFrom":7}');
}

func testSearchAndTrashFields() {
    def hit as string init '{"mountId":"m-1","path":"/p","score":2,"name":"p","type":"dir",' +
        '"modified":5,"contentType":"","tags":{}}';
    def gone as string init '{"mountId":"m-2","path":"/x","name":"x","deleted":9,"size":"5",' +
        '"contentType":"text/plain","versionId":"v1"}';
    def f as Fake init fake([ok('{"hits":[' + $hit + ']}'), ok('{"files":[' + $gone + ']}')]);
    def c as Client init authed($f);
    def none as SearchOptions;
    testing.assertEqual(
        search($c, "p", $none)[0],
        SearchHit{
            mountId: "m-1",
            path: "/p",
            name: "p",
            type: "dir",
            size: 0,
            modified: 5,
            contentType: "",
            score: 2.0
        });
    def page as TrashPage init trash($c, "");
    testing.assertEqual(
        $page.files[0],
        TrashFile{
            mountId: "m-2",
            path: "/x",
            name: "x",
            size: 5,
            deleted: 9,
            contentType: "text/plain",
            versionId: "v1"
        });
    testing.assertEqual($page.cursor, "");
    testing.assertEqual($page.retentionDays, 0);
    finish($f);
}

/** A canned reply with its own headers and a raw body. */
def struct RawReply {
    status as int,
    headers as map of string to string,
    body as bytes
};

/**
 * Answer one request per raw reply, in order.
 *
 * @param srv {httpd.Server} the listening server
 * @param replies {list of RawReply} the replies
 * @return {list of Seen} the requests
 */
func serveRaw(srv as httpd.Server, replies as list of RawReply) {
    def seen as list of Seen init [];
    for (def r in $replies) {
        def req as httpd.Request init httpd.accept($srv);
        $seen[] = Seen{
            method: httpd.method($req),
            path: httpd.path($req),
            query: httpd.rawQuery($req),
            auth: httpd.header($req, "Authorization"),
            contentType: httpd.header($req, "Content-Type"),
            body: httpd.body($req)
        };
        for (def name in $r.headers) {
            httpd.setHeader($req, $name, $r.headers[$name]);
        }
        httpd.respond($req, $r.status, $r.body);
    }
    return $seen;
}

/**
 * Start a fake server that gives these raw replies.
 *
 * @param replies {list of RawReply} the replies
 * @return {Fake} the server
 */
func rawFake(replies as list of RawReply) {
    def srv as httpd.Server init httpd.listen("127.0.0.1:0");
    def t as task of list of Seen init spawn {
        return serveRaw($srv, $replies);
    };
    return Fake{srv: $srv, url: "http://" + httpd.address($srv), t: $t};
}

/**
 * Bytes that are not UTF-8.
 *
 * @return {bytes} `ff fe 3c`
 */
func notUtf8() {
    def junk as bytes;
    for (def b in [255, 254, 60]) {
        $junk[] = $b;
    }
    return $junk;
}

/**
 * An NDJSON listing of a folder and one item below it.
 *
 * @param path {string} the item's `path`, JSON-quoted by the caller
 * @return {Reply} the reply
 */
func listingWith(path as string) {
    def top as string init '{"type":"file","path":"/","file":{"name":"d","type":"dir"}}';
    def item as string init '{"type":"file","path":' + $path + ',"file":{"name":"x"}}';
    return Reply{
        status: 200,
        contentType: "application/x-ndjson",
        body: $top + "\n" + $item + "\n"
    };
}

func testListFolderRefusesBadNames() {
    def names as list of string init ['""', '"."', '".."', '"a/b"', '"../../etc/passwd"', 'null'];
    def replies as list of Reply init [];
    for (def n in $names) {
        $replies[] = ok('{"files":[' + FILE + ',{"name":' + $n + ',"type":"file","size":1}]}');
    }
    def f as Fake init fake($replies);
    def c as Client init authed($f);
    for (def n in $names) {
        try {
            listFolder($c, "m-1", "/docs");
            missed();
        } catch (e) {
            testing.assertContains(
                messageOf($e),
                "koofr: GET /api/v2.1/mounts/m-1/files/list?path=%2Fdocs: entry 1 has the name ");
            testing.assertContains(messageOf($e), ", not a file name");
        }
    }
    finish($f);
}

func testListRecursiveRefusesBadPaths() {
    def bad as list of string init ['""', '"/"', '"/../../x"', '"/a//b"', '"/a/./b"', '"//"'];
    def replies as list of Reply init [];
    for (def p in $bad) {
        $replies[] = listingWith($p);
    }
    $replies[] = Reply{
        status: 200,
        contentType: "application/x-ndjson",
        body: '{"type":"file","path":"","file":{"name":"d","type":"dir"}}' + "\n"
    };
    def f as Fake init fake($replies);
    def c as Client init authed($f);
    for (def p in $bad) {
        try {
            listRecursive($c, "m-1", "/d");
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "entry 1 has the path ");
            testing.assertContains(messageOf($e), "not one below the folder");
        }
    }
    # The first item is the folder itself, "" or `/`.
    def top as list of File init listRecursive($c, "m-1", "/d");
    testing.assertEqual($top[0].path, "/d");
    finish($f);
}

func testBaseUrlRefusalHidesThePassword() {
    try {
        client("https://me%40x.com:SuperSecretPw@app.koofr.net");
        missed();
    } catch (e) {
        testing.assertEqual(
            messageOf($e),
            "koofr: a base URL holds no user or password, got \"https://app.koofr.net\"");
        testing.assertFalse(strings.contains($e.message, "SuperSecretPw"));
    }
}

func testCredentialsCheckTheParsedScheme() {
    def c as Client init withAppPassword(client("https://example.com"), "me@example.com", "pw");
    for (def url in ["HTTP://example.com", "Http://example.com", "ftp://example.com"]) {
        $c.url = $url;
        try {
            baseHeaders($c);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "credentials go over http://");
        }
    }
    $c.url = "HTTPS://example.com";
    testing.assertContains(baseHeaders($c)["Authorization"], "Basic ");
}

func testLoopbackOctetsAreChecked() {
    for (def url in ["http://127.999.0.1", "http://127.0.0.256", "http://127.01.0.1"]) {
        try {
            baseHeaders(withToken(client($url), "t"));
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "credentials go over http://");
        }
    }
    testing.assertTrue(isLoopback("http://127.255.0.1"));
    testing.assertTrue(isLoopback("http://127.0.0.1:8080"));
}

func testExistsRefusesA404WithoutKoofrsError() {
    def html as Reply init Reply{status: 404, contentType: "text/html", body: "<h1>Not Found</h1>"};
    def f as Fake init fake([
        $html,
        Reply{status: 404, contentType: "text/plain", body: ""},
        Reply{status: 404, contentType: "application/json", body: '{"message":"no"}'},
        $html
    ]);
    def c as Client init impatient($f);
    for (def i in [1, 2, 3]) {
        try {
            exists($c, "m-1", "/a");
            missed();
        } catch (e) {
            testing.assertContains(
                messageOf($e),
                "koofr: GET /api/v2.1/mounts/m-1/files/info?path=%2Fa: HTTP 404");
        }
    }
    # mkdirAll stops too instead of creating folders.
    try {
        mkdirAll($c, "m-1", "/a/b");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 404");
    }
    testing.assertEqual(len(finish($f)), 4);
}

func testPutRefusesAReplyWithoutAName() {
    def f as Fake init fake([ok(""), ok('{"type":"file","size":5}'), ok('{"name":"../x"}')]);
    def c as Client init authed($f);
    def opts as PutOptions;
    for (def i in [1, 2, 3]) {
        try {
            put($c, "m-1", "/docs/a.txt", convert.bytesFromString("hello", "utf-8"), $opts);
            missed();
        } catch (e) {
            testing.assertContains(messageOf($e), "the reply names no file");
        }
    }
    finish($f);
}

func testPutHonoursTheReplyLimit() {
    def f as Fake init fake([ok(FILE)]);
    def opts as PutOptions;
    try {
        put(withReplyLimit(authed($f), 100), "m-1", "/a.txt", notUtf8(), $opts);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "exceeds 100 bytes");
    }
    finish($f);
}

func testRefusalBodyNotUtf8KeepsTheStatus() {
    def busy as RawReply init RawReply{status: 503, headers: {}, body: notUtf8()};
    def fine as RawReply init RawReply{
        status: 200,
        headers: {"Content-Type": "application/json"},
        body: notUtf8()
    };
    def f as Fake init rawFake([$busy, $busy, $fine]);
    def c as Client init authed($f);
    try {
        user($c);
        missed();
    } catch (e) {
        testing.assertEqual(
            messageOf($e),
            "koofr: GET /api/v2.1/user: HTTP 503: Service Unavailable");
    }
    try {
        exists($c, "m-1", "/a");
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "files/info?path=%2Fa: HTTP 503");
    }
    try {
        user($c);
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: GET /api/v2.1/user: the reply is not UTF-8");
    }
    finish($f);
}

func testLongCursorIsCutInMessages() {
    # 4000 characters: `httpd` refuses a much longer request line (431).
    def cursor as string init strings.repeat("c", 4000);
    def f as Fake init fake([refused(500, "Internal", "boom")]);
    try {
        trash(authed($f), $cursor);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "koofr: GET /api/v2.1/trash?cursor=ccc");
        testing.assertContains($e.message, "...: HTTP 500: boom (Internal)");
        testing.assertTrue(len($e.message) < 300);
    }
    testing.assertEqual(len(finish($f)[0].query), 4007);
}

func testRedirectIsNotFollowed() {
    def other as Fake init fake([]);
    def moved as RawReply init RawReply{
        status: 302,
        headers: {"Location": $other.url + "/api/v2.1/user"},
        body: convert.bytesFromString("", "utf-8")
    };
    def f as Fake init rawFake([$moved, $moved, $moved]);
    def c as Client init impatient($f);
    try {
        user($c);
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: GET /api/v2.1/user: HTTP 302: Found");
    }
    try {
        get($c, "m-1", "/a", 0);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 302: Found");
    }
    try {
        def opts as PutOptions;
        put($c, "m-1", "/a", notUtf8(), $opts);
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 302: Found");
    }
    testing.assertEqual(len(finish($f)), 3);
    testing.assertEqual(len(finish($other)), 0);
}

func testRetryDelay() {
    testing.assertEqual(retryDelayMs({}, 0), 500);
    testing.assertEqual(retryDelayMs({}, 2), 2000);
    testing.assertEqual(retryDelayMs({}, 100), 30000);
    testing.assertEqual(retryDelayMs({"retry-after": "2"}, 0), 2000);
    testing.assertEqual(retryDelayMs({"retry-after": " 0 "}, 1), 1000);
    testing.assertEqual(retryDelayMs({"retry-after": "9999999"}, 0), 30000);
    testing.assertEqual(retryDelayMs({"retry-after": "Wed, 21 Oct 2015 07:28:00 GMT"}, 0), 500);
}

func testRetryAfterIsHonoured() {
    def f as Fake init rawFake([
        RawReply{
            status: 429,
            headers: {"Retry-After": "1"},
            body: convert.bytesFromString("", "utf-8")
        },
        RawReply{
            status: 200,
            headers: {"Content-Type": "application/json"},
            body: convert.bytesFromString('{"id":"u1"}', "utf-8")
        }
    ]);
    def start as time.Time init time.now();
    testing.assertEqual(user(withRetries(authed($f), 1)).id, "u1");
    testing.assertTrue(time.milliseconds(time.sub(time.now(), $start)) >= 1000);
    testing.assertEqual(len(finish($f)), 2);
}

func testExistsAndListRecursiveAreRetried() {
    def busy as Reply init Reply{status: 503, contentType: "text/plain", body: ""};
    def f as Fake init fake([
        $busy,
        refused(404, "NotFound", "File not found"),
        $busy,
        listingWith('"/x"'),
        $busy
    ]);
    def c as Client init withRetries(impatient($f), 1);
    testing.assertFalse(exists($c, "m-1", "/a"));
    testing.assertEqual(len(listRecursive($c, "m-1", "/d")), 2);
    # No retries: one request, the 503 refused.
    try {
        user(withRetries($c, 0));
        missed();
    } catch (e) {
        testing.assertContains(messageOf($e), "HTTP 503");
    }
    testing.assertEqual(len(finish($f)), 5);
}

func testTrashAllRefusesPastThePageLimit() {
    def page as string init '{"files":[{"path":"/a"}],"pageInfo":{"cursor":"';
    def f as Fake init fake([ok($page + 'A"}}'), ok($page + 'B"}}')]);
    try {
        trashPages(impatient($f), 2);
        missed();
    } catch (e) {
        testing.assertEqual(messageOf($e), "koofr: GET /api/v2.1/trash: more than 2 pages");
    }
    testing.assertEqual(len(finish($f)), 2);
}
