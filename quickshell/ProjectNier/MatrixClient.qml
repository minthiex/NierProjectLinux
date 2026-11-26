import Quickshell
import Quickshell.Io
import QtQuick

// Minimal Matrix client for the Messenger bridge (Synapse on localhost), using the login that
// fbtui already stored in ~/.config/fbtui/session.json. Talks plain HTTP from QML.
Item {
    id: root

    // ---- state shown by the UI ---------------------------------------------------------
    property bool connected: false
    property string status: "STARTING"
    property var rooms: []            // sorted: [{ id, name, last, ts, unread }]
    property string currentId: ""
    property string currentName: ""
    property var messages: []         // oldest first: [{ id, sender, name, body, ts, mine, kind }]
    property int unreadTotal: 0
    signal incoming(string room, string text, string roomId)   // a message from someone else in a chat nobody is looking at
    property bool viewing: false      // the messenger is on screen: the open chat counts as read
    onViewingChanged: { if (viewing) seenCurrent() }

    // ---- internals ---------------------------------------------------------------------
    property string hs: ""
    property string token: ""
    property string me: ""
    property string since: ""
    property var byId: ({})
    property var members: ({})        // roomId -> { userId: displayName }
    property bool running: false
    // a login exists (session.json): Messenger is set up. Without one the health light leaves Messenger and the
    // bridge alone, and the Messenger window offers SET UP MESSENGER (scripts/messenger-setup.py)
    property bool hasLogin: false
    property int txn: 0

    FileView {
        id: sessionFile
        path: Quickshell.env("HOME") + "/.config/fbtui/session.json"
        blockLoading: true
        printErrors: false                  // no file = Messenger not set up yet (status NO LOGIN FOUND), not an error
        watchChanges: true
        // a new login was saved (after LOGIN EXPIRED): connect again with it
        onFileChanged: {
            reload()
            if (root.expired) { root.expired = false; root.running = false; root.start() }
        }
    }

    // the server no longer accepts the stored token: say so instead of retrying as OFFLINE forever
    property bool expired: false
    function authFailed(st, d) {
        return st === 401 || (d !== null && d !== undefined && (d.errcode === "M_UNKNOWN_TOKEN" || d.errcode === "M_MISSING_TOKEN"))
    }
    function expire() {
        if (!expired) console.warn("MatrixClient: the login in session.json was rejected (LOGIN EXPIRED)")
        expired = true
        connected = false
        since = ""
        status = "LOGIN EXPIRED"
        retry.stop()
    }

    // qs -c ProjectNier ipc call messenger status   -> CONNECTED | CONNECTING | OFFLINE | LOGIN EXPIRED | ...
    IpcHandler {
        target: "messenger"
        function status(): string { return root.status }
        // start over: read session.json again and do a fresh sync (scripts/repair.sh)
        function reconnect(): void { root.stop(); root.expired = false; root.start() }
    }

    function start() {
        if (running) return
        try {
            var s = JSON.parse(sessionFile.text())
            // "localhost" may resolve to ::1 first, but Synapse's Docker port is published on 127.0.0.1 only
            // and Qt's XMLHttpRequest does not fall back to IPv4, so every request would fail with status 0
            hs = String(s.homeserver).replace(/\/$/, "").replace("://localhost", "://127.0.0.1")
            token = s.access_token
            me = s.user_id
        } catch (e) {
            hasLogin = false
            status = "NO LOGIN FOUND"
            return
        }
        hasLogin = true
        running = true
        status = "CONNECTING"
        firstSync()
        pruneCache.running = true
    }

    // the media cache: drop what was not looked at for 30 days (fetch-media.sh touches a file each time it is reused)
    // and downloads that died half-way
    Process {
        id: pruneCache
        command: ["find", root.cacheDir, "-maxdepth", "1", "-type", "f", "(", "-mtime", "+30", "-o", "-name", "*.part.*", "-mmin", "+60", ")", "-delete"]
    }

    // every (re)start of the sync loop gets a new number; answers to requests of an older loop are dropped, so
    // reconnect() or the watchdog never leave two loops running side by side (each message would come twice)
    property int loopGen: 0

    function stop() {
        loopGen++
        running = false
        connected = false
        status = "STOPPED"
        since = ""
    }

    // ---- http ----------------------------------------------------------------------------
    function call(method, path, body, done, timeoutMs) {
        if (timeoutMs === undefined) timeoutMs = 20000
        var x = new XMLHttpRequest()
        x.open(method, hs + "/_matrix/client/v3" + path)
        x.setRequestHeader("Authorization", "Bearer " + token)
        if (body !== undefined) x.setRequestHeader("Content-Type", "application/json")
        var finished = false
        // QML's XMLHttpRequest has no timeout of its own: a connection that never answers (server frozen,
        // network gone half-way) would leave the sync waiting forever, so a timer gives up on it
        var guard = guardComp.createObject(root, { interval: timeoutMs })
        function finish(timedOut) {
            if (finished) return
            finished = true
            guard.stop()
            guard.destroy()
            var data = null
            if (!timedOut) try { data = JSON.parse(x.responseText) } catch (e) {}
            if (!timedOut && x.status !== 200) console.warn("MatrixClient:", method, path.substring(0, 24), "->", x.status)
            if (timedOut) console.warn("MatrixClient:", method, path.substring(0, 24), "timed out")
            try {
                if (done) done(timedOut ? 0 : x.status, data)
            } catch (e) {
                // a bug while handling a reply must not leave the connection dead
                console.warn("MatrixClient: handler failed:", e)
                if (running && done) { connected = false; status = "OFFLINE"; retry.restart() }
            }
        }
        guard.triggered.connect(function () {
            finish(true)
            try { x.abort() } catch (e) {}
        })
        x.onreadystatechange = function () {
            if (x.readyState === XMLHttpRequest.DONE) finish(false)
        }
        guard.start()
        x.send(body !== undefined ? JSON.stringify(body) : undefined)
    }
    Component { id: guardComp; Timer {} }

    // ---- sync ----------------------------------------------------------------------------
    function firstSync() {
        var filter = {
            room: {
                timeline: { limit: 1, types: ["m.room.message", "m.sticker"] },
                state: { types: ["m.room.name", "m.room.canonical_alias"], lazy_load_members: true },
                ephemeral: { types: [] }, account_data: { types: [] }
            },
            presence: { types: [] }, account_data: { types: [] }
        }
        var gen = ++loopGen
        retry.stop()
        call("GET", "/sync?timeout=0&filter=" + encodeURIComponent(JSON.stringify(filter)), undefined, function (st, d) {
            if (!running || gen !== loopGen) return
            if (authFailed(st, d)) { expire(); return }
            if (st !== 200 || !d) { status = "OFFLINE"; retry.restart(); return }
            since = d.next_batch
            var join = d.rooms && d.rooms.join ? d.rooms.join : {}
            for (var id in join) {
                var r = join[id]
                var name = ""
                var evs = r.state && r.state.events ? r.state.events : []
                for (var i = 0; i < evs.length; i++) {
                    if (evs[i].type === "m.room.name" && evs[i].content.name) name = evs[i].content.name
                    else if (!name && evs[i].type === "m.room.canonical_alias") name = evs[i].content.alias || ""
                }
                var room = { id: id, name: name || id, last: "", ts: 0, unread: 0, server: 0, local: 0 }
                var tl = r.timeline && r.timeline.events ? r.timeline.events : []
                if (tl.length > 0) { room.last = preview(tl[tl.length - 1]); room.ts = tl[tl.length - 1].origin_server_ts }
                room.server = r.unread_notifications ? r.unread_notifications.notification_count : 0
                room.unread = room.server
                byId[id] = room
            }
            rebuild()
            lastOk = Date.now()
            connected = true
            status = "CONNECTED"
            poll(gen)
        })
    }

    function poll(gen) {
        if (!running || gen !== loopGen) return
        var filter = { room: { timeline: { limit: 20, types: ["m.room.message", "m.sticker"] }, state: { types: [] },
                               ephemeral: { types: [] }, account_data: { types: [] } },
                       presence: { types: [] }, account_data: { types: [] } }
        call("GET", "/sync?timeout=25000&since=" + encodeURIComponent(since) + "&filter=" + encodeURIComponent(JSON.stringify(filter)), undefined, function (st, d) {
            if (!running || gen !== loopGen) return
            if (authFailed(st, d)) { expire(); return }
            if (st !== 200 || !d) {
                connected = false
                status = "OFFLINE"
                if (st >= 400 && st < 500 && st !== 429) since = ""      // sync token rejected: start over
                retry.restart()
                return
            }
            lastOk = Date.now()
            connected = true
            status = "CONNECTED"
            since = d.next_batch
            var join = d.rooms && d.rooms.join ? d.rooms.join : {}
            var changed = false
            for (var id in join) {
                var r = join[id]
                var room = byId[id]
                if (!room) { room = { id: id, name: id, last: "", ts: 0, unread: 0, server: 0, local: 0 }; byId[id] = room }
                var tl = r.timeline && r.timeline.events ? r.timeline.events : []
                var watched = (id === currentId && viewing)          // the chat is open and on screen
                for (var i = 0; i < tl.length; i++) {
                    room.last = preview(tl[i]); room.ts = tl[i].origin_server_ts
                    if (id === currentId) addMessage(tl[i])
                    // like fbtui: count messages from other people that nobody is looking at
                    if (!watched && (tl[i].type === "m.room.message" || tl[i].type === "m.sticker") && tl[i].sender !== me) {
                        room.local++
                        if (!/bridge/i.test(room.name)) root.incoming(room.name, preview(tl[i]), id)
                    }
                }
                if (r.unread_notifications) room.server = r.unread_notifications.notification_count
                if (watched) {
                    room.local = 0; room.server = 0
                    if (tl.length > 0) markRead(tl[tl.length - 1].event_id)
                }
                room.unread = Math.max(room.local, room.server)
                changed = true
            }
            if (changed) rebuild()
            poll(gen)
        }, 45000)
    }

    // watchdog: every sync answer refreshes lastOk; if nothing arrived for a long while the loop is dead, restart it
    property double lastOk: Date.now()
    Timer {
        interval: 30000; running: root.running; repeat: true
        onTriggered: {
            if (Date.now() - root.lastOk > 90000 && !retry.running && !root.expired) {
                console.warn("MatrixClient: watchdog restarting sync (status " + root.status + ")")
                root.lastOk = Date.now()
                root.since = ""
                root.firstSync()
            }
        }
    }
    Timer { id: retry; interval: 5000; onTriggered: { if (root.running) { if (root.since === "") root.firstSync(); else root.poll(root.loopGen) } } }

    // the bridge's own chat is hidden, except while Facebook has logged the bridge out (Health.qml): send it "login" there
    property bool showBridge: false
    onShowBridgeChanged: rebuild()
    // just set up: the bridge chat stays in the list until Facebook is connected (NierScreen clears it)
    property bool setupPending: false
    onSetupPendingChanged: rebuild()

    // ---- first-time setup (Messenger window → SET UP MESSENGER; scripts/messenger-setup.py) ----
    property bool settingUp: false
    property string setupStep: ""
    property string setupError: ""
    function runSetup(username, password) {
        if (settingUp) return
        settingUp = true
        setupError = ""
        setupStep = "Starting"
        var p = setupComp.createObject(root, { environment: ({ SETUP_PAYLOAD: JSON.stringify({ username: username, password: password }) }) })
        p.running = true
    }
    function setupLine(line) {
        var d = null
        try { d = JSON.parse(line) } catch (e) { return }
        if (d.step) setupStep = d.step
        else if (d.error) { setupError = d.error; settingUp = false }
        else if (d.ok) {
            settingUp = false
            setupStep = ""
            setupPending = true
            sessionFile.reload()
            start()
            open(d.bot_room)                  // send "login" there to connect Facebook
            if (currentName === "") currentName = "Facebook bridge"     // the room list has not loaded yet
        }
    }
    Component {
        id: setupComp
        Process {
            id: sp
            command: ["python3", "-I", Quickshell.shellPath("scripts/messenger-setup.py")]
            stdout: SplitParser { onRead: line => root.setupLine(line) }
            onExited: code => {
                if (root.settingUp) { root.settingUp = false; if (root.setupError === "") root.setupError = "the setup stopped unexpectedly (exit " + code + ")" }
                sp.destroy(100)
            }
        }
    }
    function rebuild() {
        var out = []
        for (var id in byId) {
            var r = byId[id]
            if (!showBridge && !setupPending && /bridge/i.test(r.name)) continue          // the bridge's own management chats
            out.push(r)
        }
        out.sort(function (a, b) {
            if ((a.unread > 0) !== (b.unread > 0)) return a.unread > 0 ? -1 : 1
            return b.ts - a.ts
        })
        rooms = out
        var t = 0
        for (var i = 0; i < out.length; i++) t += out[i].unread
        unreadTotal = t
    }

    // ---- reading -------------------------------------------------------------------------
    function preview(e) {
        var m = toMessage(e)
        return m ? m.body : ""
    }

    function nameOf(roomId, userId) {
        var m = members[roomId]
        if (m && m[userId]) return m[userId]
        return String(userId).replace(/^@/, "").replace(/:.*$/, "")
    }

    function toMessage(e) {
        if (e.type === "m.sticker" && e.content) {
            var sc = e.content, si = sc.info || {}
            return { id: e.event_id, sender: e.sender, name: nameOf(currentId, e.sender), body: "[sticker] " + (sc.body || ""),
                     ts: e.origin_server_ts, mine: e.sender === me, kind: "image", mxc: sc.url || "", thumb: "", w: si.w || 0, h: si.h || 0, dur: 0 }
        }
        if (e.type !== "m.room.message" || !e.content) return null
        var c = e.content
        var body = c.body ? String(c.body) : ""
        var kind = "text"
        switch (c.msgtype) {
        case "m.image": kind = "image"; body = "[image] " + body; break
        case "m.video": kind = "video"; body = "[video] " + body; break
        case "m.audio": kind = "media"; body = "[audio] " + body; break
        case "m.file":  kind = "media"; body = "[file] " + body; break
        case "m.notice": kind = "notice"; break
        case "m.emote": body = "* " + body; break
        }
        var info = c.info || {}
        return { id: e.event_id, sender: e.sender, name: nameOf(currentId, e.sender), body: body,
                 ts: e.origin_server_ts, mine: e.sender === me, kind: kind,
                 mxc: (kind === "image" || kind === "video") ? (c.url || (c.file ? c.file.url : "") || "") : "",
                 thumb: info.thumbnail_url || "", w: info.w || 0, h: info.h || 0, dur: info.duration || 0 }
    }

    function addMessage(e) {
        var m = toMessage(e)
        if (!m) return
        for (var i = messages.length - 1; i >= 0 && i >= messages.length - 40; i--)
            if (messages[i].id === m.id) return
        messages = messages.concat([m])
    }

    function open(id) {
        if (id === currentId) return
        currentId = id
        currentName = byId[id] ? byId[id].name : ""
        messages = []
        var gen = id
        call("GET", "/rooms/" + encodeURIComponent(id) + "/joined_members", undefined, function (st, d) {
            if (gen !== currentId) return
            var map = {}
            if (st === 200 && d && d.joined) for (var u in d.joined) map[u] = d.joined[u].display_name || ""
            members[id] = map
            var f = { types: ["m.room.message", "m.sticker"] }
            call("GET", "/rooms/" + encodeURIComponent(id) + "/messages?dir=b&limit=60&filter=" + encodeURIComponent(JSON.stringify(f)), undefined, function (st2, d2) {
                if (gen !== currentId || st2 !== 200 || !d2) return
                var out = []
                var ch = d2.chunk || []
                for (var i = ch.length - 1; i >= 0; i--) { var m = toMessage(ch[i]); if (m) out.push(m) }
                messages = out
                if (ch.length > 0) markRead(ch[0].event_id)
                if (byId[id] && viewing) { byId[id].unread = 0; byId[id].local = 0; byId[id].server = 0; rebuild() }
            })
        })
    }

    // the messenger just came on screen (or a chat was opened): everything in the open chat is seen
    function seenCurrent() {
        var r = byId[currentId]
        if (!r || r.unread === 0) return
        r.local = 0; r.server = 0; r.unread = 0
        if (messages.length > 0) markRead(messages[messages.length - 1].id)
        rebuild()
    }

    // ---- media (images, video): downloaded through the authenticated Matrix media API, cached on disk ----
    readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/projectnier-messenger"
    property var queue: []
    property int busy: 0

    function mediaUrl(mxc, w, h) {
        var p = /^mxc:\/\/([^\/]+)\/(.+)$/.exec(String(mxc))
        if (!p) return ""
        var base = hs + "/_matrix/client/v1/media/"
        return w > 0 ? base + "thumbnail/" + p[1] + "/" + p[2] + "?width=" + w + "&height=" + h + "&method=scale&animated=false"
                     : base + "download/" + p[1] + "/" + p[2]
    }

    // cb(path) gets the local file, or "" if it could not be fetched
    function fetch(url, cb) {
        if (url === "") { cb(""); return }
        queue.push({ url: url, cb: cb })
        pump()
    }

    function pump() {
        while (busy < 3 && queue.length > 0) {
            var j = queue.shift()
            busy++
            var out = cacheDir + "/" + Qt.md5(j.url)
            var p = fetchComp.createObject(root, {
                job: j, out: out,
                command: ["sh", Quickshell.shellPath("scripts/fetch-media.sh"), j.url, out],
                environment: ({ TOKEN: token })
            })
            p.running = true
        }
    }

    Component {
        id: fetchComp
        Process {
            id: fp
            property var job
            property string out
            onExited: code => {
                root.busy--
                job.cb(code === 0 ? out : "")
                root.pump()
                fp.destroy(200)
            }
        }
    }

    function markRead(eventId) {
        if (!currentId || !eventId) return
        call("POST", "/rooms/" + encodeURIComponent(currentId) + "/receipt/m.read/" + encodeURIComponent(eventId), {}, null)
    }

    function send(text) {
        var t = String(text).trim()
        if (t === "" || currentId === "") return
        txn++
        var room = currentId
        sendError = false
        call("PUT", "/rooms/" + encodeURIComponent(room) + "/send/m.room.message/tui" + Date.now() + "_" + txn,
             { msgtype: "m.text", body: t }, function (st, d) {
            if (st === 200) return
            sendError = true
            root.sendFailed(room, t)          // the UI gives the text back instead of losing it
        })
    }
    property bool sendError: false            // the last message could not be sent

    // a reply from a notification: straight into that chat, whether it is open or not
    function sendTo(roomId, text) {
        var t = String(text).trim()
        if (t === "" || roomId === "") return
        txn++
        call("PUT", "/rooms/" + encodeURIComponent(roomId) + "/send/m.room.message/tui" + Date.now() + "_" + txn,
             { msgtype: "m.text", body: t }, function (st, d) {
            if (st !== 200) Quickshell.execDetached(["notify-send", "-a", "Messenger", "-u", "critical", "Reply not sent",
                                                     "The reply to " + (byId[roomId] ? byId[roomId].name : "the chat") + " could not be sent: " + (st === 0 ? "offline" : "error " + st) + "."])
        })
    }
    signal sendFailed(string roomId, string text)
}
