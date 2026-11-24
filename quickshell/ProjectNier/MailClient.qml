import Quickshell
import Quickshell.Io
import QtQuick

// Gmail for the email window: runs scripts/mail.py (IMAP/SMTP with an app password) and keeps its answers.
// One instance lives in the shell all the time: every account is checked every 2 minutes for the unread badge and
// new-mail notices; the full inbox of the account in use is only loaded while the window is on screen.
Item {
    id: root

    // ---- state shown by the UI -----------------------------------------------------------------
    property string status: "STARTING"
    property bool connected: false
    property bool configured: false
    property string address: ""         // the account in use
    property var accounts: []           // every saved address
    property var mails: []              // newest first: [{ uid, from, address, subject, ts, seen }]
    property int unread: 0
    property string currentUid: ""
    property var detail: null           // the open message (see mail.py get)
    property bool loadingDetail: false
    property string notice: ""          // last problem or result, shown in the window
    property bool busy: false           // sending / saving the login
    property bool sending: false
    property bool running: false
    property bool viewing: false        // the email window is on screen
    property var accountUnread: ({})    // address -> unread count (every account)
    readonly property int totalUnread: {
        var t = 0
        for (var k in accountUnread) t += accountUnread[k]
        return t
    }
    property var lastUid: ({})          // address -> newest unread uid already announced
    signal sent()
    signal incoming(string account, string from, string subject, string uid)   // new unread mail (not while the window is shown)
    onViewingChanged: if (viewing && configured) refresh()

    // ---- running the helper --------------------------------------------------------------------
    function run(args, payload, cb) {
        var env = ({})
        if (address !== "") env.MAIL_ACCOUNT = address
        if (payload !== undefined) env.MAIL_PAYLOAD = JSON.stringify(payload)
        var p = job.createObject(root, {
            cb: cb,
            command: ["python3", Quickshell.shellPath("scripts/mail.py")].concat(args),
            environment: env
        })
        p.running = true
    }

    Component {
        id: job
        Process {
            id: pr
            property var cb
            stdout: StdioCollector {
                onStreamFinished: {
                    var d = null
                    try { d = JSON.parse(text) } catch (e) {}
                    pr.cb(d)
                    pr.destroy(200)
                }
            }
        }
    }

    // ---- lifecycle -------------------------------------------------------------------------------
    function start() {
        if (running) return
        running = true
        status = "CONNECTING"
        run(["status"], undefined, function (d) {
            configured = d && d.configured === true
            accounts = d && d.accounts ? d.accounts : []
            address = accounts.length > 0 ? accounts[0] : ""
            if (!configured) { status = "NO LOGIN"; connected = false; return }
            if (viewing) refresh()
            poll.restart()
            checker.restart()
            check()
        })
    }

    function stop() { running = false; poll.stop(); checker.stop() }

    //   qs -c ProjectNier ipc call mail check      check every account now (scripts/repair.sh)
    //   qs -c ProjectNier ipc call mail status     CONNECTED | OFFLINE | LOGIN REFUSED | NO LOGIN ...
    IpcHandler {
        target: "mail"
        function check(): void { if (root.configured) { root.check(); if (root.viewing) root.refresh() } }
        function status(): string { return root.status }
    }

    Timer { id: noticeClear; interval: 4000; onTriggered: if (root.notice === "SENT") root.notice = "" }
    Timer { id: poll; interval: 90000; repeat: true; onTriggered: if (root.configured && root.viewing && !root.busy) root.refresh() }
    Timer { id: checker; interval: 120000; repeat: true; onTriggered: if (root.configured) root.check() }

    function setUnread(addr, n) {
        var u = Object.assign({}, accountUnread)
        u[addr] = n
        accountUnread = u
    }

    // ---- every account: unread counts and new-mail notices -------------------------------------------
    property bool checking: false
    function check() {
        if (checking) return
        checking = true
        run(["check"], undefined, function (d) {
            checking = false
            if (!d || !d.accounts) return
            var u = {}, seen = Object.assign({}, lastUid)
            for (var i = 0; i < d.accounts.length; i++) {
                var a = d.accounts[i]
                if (a.error) { if (accountUnread[a.address] !== undefined) u[a.address] = accountUnread[a.address]; continue }
                u[a.address] = a.unread
                var top = 0
                for (var j = 0; j < a.unseen.length; j++) top = Math.max(top, a.unseen[j].uid)
                if (seen[a.address] !== undefined) {                  // the first check only sets the baseline
                    var fresh = a.unseen.filter(m => m.uid > seen[a.address])
                    var quiet = viewing && a.address === address     // the window shows this inbox already
                    if (!quiet) for (var k = 0; k < fresh.length; k++) root.incoming(a.address, fresh[k].from, fresh[k].subject, String(fresh[k].uid))
                    if (fresh.length > 0 && viewing && a.address === address) refresh()
                }
                seen[a.address] = Math.max(top, seen[a.address] || 0)
            }
            lastUid = seen
            accountUnread = u
            // the connection state also follows the background check, not only the open inbox (the health light reads it)
            var errs = d.accounts.filter(a => a.error)
            if (d.accounts.length > 0 && errs.length === d.accounts.length) {
                connected = false
                status = errs.some(a => a.code === "locked") ? "KEYRING LOCKED" : errs.some(a => a.code === "auth") ? "LOGIN REFUSED" : "OFFLINE"
            } else if (errs.length === 0 && status !== "CONNECTED") {
                connected = true
                status = "CONNECTED"
            }
        })
    }

    // ---- the inbox ---------------------------------------------------------------------------------
    function refresh() {
        if (!configured) return
        var who = address
        run(["list", "60"], undefined, function (d) {
            if (who !== address) return                  // switched to another account meanwhile
            if (!d || d.error) { fail(d) ; return }
            connected = true
            status = "CONNECTED"
            mails = d.messages
            unread = d.unread
            setUnread(who, d.unread)
            if (notice === "offline" || notice === "login" || notice === "locked") notice = ""
        })
    }

    function fail(d) {
        connected = false
        if (d && d.code === "auth") { status = "LOGIN REFUSED"; notice = "login" }
        else if (d && d.code === "locked") { status = "KEYRING LOCKED"; notice = "locked" }
        else { status = "OFFLINE"; notice = "offline" }
    }

    // ---- reading ------------------------------------------------------------------------------------
    function open(uid) {
        currentUid = uid
        detail = null
        loadingDetail = true
        var who = address
        run(["get", uid], undefined, function (d) {
            if (currentUid !== uid || who !== address) return
            loadingDetail = false
            if (!d || d.error) { fail(d); return }
            detail = d
            markSeen(uid)
        })
    }

    function markSeen(uid) {
        for (var i = 0; i < mails.length; i++) {
            if (mails[i].uid === uid) {
                if (!mails[i].seen) {
                    var copy = mails.slice()
                    copy[i] = Object.assign({}, mails[i], { seen: true })
                    mails = copy
                    unread = Math.max(0, unread - 1)
                    setUnread(address, unread)
                    run(["seen", uid], undefined, function () {})
                }
                break
            }
        }
    }

    // ---- writing ------------------------------------------------------------------------------------
    function send(to, subject, body, inReplyTo, references) {
        if (busy) return
        busy = true
        sending = true
        notice = ""
        run(["send"], { to: to, subject: subject, body: body, inReplyTo: inReplyTo || "", references: references || "" }, function (d) {
            busy = false
            sending = false
            if (!d || d.error) { notice = "SEND FAILED: " + (d && d.error ? d.error : "no answer"); return }
            notice = "SENT"
            noticeClear.restart()
            root.sent()
        })
    }

    // first run: check the address + app password with Google, then store them
    function saveLogin(addr, password) {
        if (busy) return
        busy = true
        notice = ""
        status = "CHECKING LOGIN"
        run(["setup"], { address: addr, password: password }, function (d) {
            busy = false
            if (!d || d.error) {
                notice = "LOGIN FAILED: " + (d && d.error ? d.error : "no answer")
                status = "NO LOGIN"
                return
            }
            configured = true
            accounts = d.accounts
            switchTo(d.address)
            poll.restart()
            checker.restart()
            check()
        })
    }

    // use another saved account
    function switchTo(addr) {
        address = addr
        mails = []
        unread = 0
        detail = null
        currentUid = ""
        loadingDetail = false
        connected = false
        notice = ""
        status = "CONNECTING"
        refresh()
    }

    // forget the account in use (its app password is deleted from this computer)
    function removeCurrent() {
        var gone = address
        run(["remove"], { address: gone }, function (d) {
            accounts = d && d.accounts ? d.accounts : []
            var u = Object.assign({}, accountUnread); delete u[gone]; accountUnread = u
            var l = Object.assign({}, lastUid); delete l[gone]; lastUid = l
            if (accounts.length === 0) {
                configured = false
                address = ""
                mails = []; unread = 0; detail = null; currentUid = ""
                connected = false
                status = "NO LOGIN"
                poll.stop()
                checker.stop()
            } else {
                switchTo(accounts[0])
            }
        })
    }
}
