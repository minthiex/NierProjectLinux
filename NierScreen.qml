import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Blank NieR-style screen: paper ground, scanline + dot texture, thin frame with
// corner squares, and a few small status labels.
Item {
    // the screen should drop keyboard focus so the content window just focused gets the keys (shell.qml)
    signal releaseKeys()
    id: root

    property int page: 0    // selected top tab (Entertainment first); one is always selected
    // the panel on the right has a text field: let the window take keyboard focus (only then)
    readonly property bool wantsKeys: messengerOpen || emailOpen || bluetoothOpen || (pane !== "" && specOf(pane) !== undefined && specOf(pane).input !== undefined)
    property string pane: ""   // sub-function whose result is shown

    // menus: the built-in ones plus whatever sub-functions registered apps added
    // (all: every sub-function of the menu, also the hidden ones, for the arrange mode)
    readonly property var basePages: Pages.list.map(p => ({ icon: p.icon, label: p.label, subtitle: p.subtitle, purpose: p.purpose,
                                                            all: p.subs.concat(Registry.subsFor(p.label, p.subs)),
                                                            subs: Registry.arrange(p.label, p.subs.concat(Registry.subsFor(p.label, p.subs))) }))

    // ---- the "Super" tab: switch between the open apps (the Apps list) and go to the sub-function each one lives in ----
    readonly property string superLabel: "Super"
    readonly property string superHome: "Super/Overview"
    // [{ slug, name, key }] every open app that sits in a sub-function
    readonly property var superApps: {
        var out = [], seen = {}, names = {}
        var add = (slug, name) => {
            var k = keyForSlug(slug)
            if (k === "" || seen[slug]) return
            seen[slug] = true
            var n = name, i = 2
            while (names[n]) n = name + " (" + (i++) + ")"
            names[n] = true
            out.push({ slug: slug, name: n, key: k })
        }
        for (var i = 0; i < contentApps.length; i++) add(contentApps[i].slug, contentApps[i].name)
        for (var j = 0; j < extWins.length; j++) add(extWins[j].slug, pretty(extWins[j].cls))
        return out
    }
    readonly property var pages: {
        var sw = { icon: "\uf0ec", label: superLabel, subtitle: "APPLICATION SWITCH / QUICK TRANSFER",
                   purpose: "For jumping from one open application to the sub-function it lives in.",
                   subs: [{ name: "Overview", desc: "Every open application and where it lives" }]
                         .concat(superApps.map(a => ({ name: a.name, desc: a.key.replace("/", " / "), slug: a.slug }))) }
        sw.all = sw.subs
        var out = basePages.slice()
        out.splice(Math.max(0, out.length - 1), 0, sw)     // just before Logout
        return out
    }
    // Super+Tab: most recently used first. Presses within 1.5 s of each other walk one frozen list (like Alt+Tab);
    // after a pause the app you stopped on becomes the most recent and a new list starts.
    property var mru: []              // slugs, most recently shown first
    property var cycleList: []
    property int cycleIdx: 0
    function touch(s) { if (s !== "") mru = [s].concat(mru.filter(x => x !== s)) }
    onCurSlugChanged: if (!cycleTimer.running) touch(curSlug)
    Timer { id: cycleTimer; interval: 1500; onTriggered: root.touch(root.curSlug) }
    function cycleApp(delta) {
        var first = !cycleTimer.running
        if (first) {
            var open = superApps.map(a => a.slug)
            var list = mru.filter(x => open.indexOf(x) >= 0)
            open.forEach(x => { if (list.indexOf(x) < 0) list.push(x) })
            var ci = list.indexOf(curSlug)
            if (ci > 0) { list.splice(ci, 1); list.unshift(curSlug) }
            cycleList = list
            cycleIdx = (ci >= 0) ? 0 : (delta > 0 ? -1 : 0)      // not on an app: the first press goes to the most recent (or the oldest)
        }
        var n = cycleList.length
        if (n === 0) return
        cycleIdx = (cycleIdx + delta + n) % n
        cycleTimer.restart()
        gotoSlug(cycleList[cycleIdx])
    }
    IpcHandler {
        target: "switcher"
        function next(): void { root.cycleApp(1) }
        function prev(): void { root.cycleApp(-1) }
    }
    function specOf(key) {
        if (key === superHome)
            return { noHide: true, rows: superApps.length > 0 ? superApps.map(a => [a.name.toUpperCase(), a.key.replace("/", " / ")])
                                                              : [["OPEN APPS", "none: nothing is running"]] }
        if (key === "Configuration/" + Registry.restoreName) return Registry.restoreSpec()
        var b = Panes.specs[key], r = Registry.specFor(key)
        if (b && r) return Object.assign({}, b, { rows: (b.rows ? b.rows : []).concat(r.rows), actions: (b.actions ? b.actions : []).concat(r.actions) })
        return b ? b : r
    }
    // apps.json was changed outside the shell and the open sub-function is gone: show the first one instead
    Connections {
        target: Registry
        function onAppsChanged() { if (root.pane !== "" && root.specOf(root.pane) === undefined) Qt.callLater(root.selectFirst) }
        function onHiddenChanged() { if (root.pane !== "" && Registry.isHidden(root.pane)) Qt.callLater(root.selectFirst) }
    }
    // a menu always has a sub-function selected: the first one when it opens
    function selectFirst() {
        var e = page >= 0 && page < pages.length ? pages[page] : null
        pane = e && e.label === superLabel ? superHome : (e && e.subs.length > 0 ? e.label + "/" + e.subs[0].name : "")
    }
    onPageChanged: selectFirst()
    property bool maximized: false   // content window shown full screen (10 px margin)
    readonly property int fsMargin: 10
    onPaneChanged: { maximized = false; syncTerm() }
    onMaximizedChanged: syncTerm()

    // ---- pop-out: an app window floating on top of everything (PopOut.qml) ----
    PopOut { id: pop; view: root }

    // ---- layout of the right-hand side -------------------------------------------------
    // sub-function list | small result window | big content window (terminal lives here)
    readonly property real paneX: sub.x + sub.implicitWidth + 24
    readonly property int paneW: 420
    readonly property real contentX: paneX + paneW + 24
    readonly property real contentR: width - Theme.frameMargin - Theme.tabInset
    readonly property real contentY: sub.y + sub.listTop
    readonly property real contentB: height - Theme.frameMargin - 14 - 56 - 16
    readonly property int headH: 30

    // ---- content windows: one per sub-function, shown only while it is selected ----------
    // Each sub-function gets its own kitty window with a fixed title "projectnier-term:<slug>".
    // Selecting a sub-function shows its window (if it has one), every other window is
    // parked on a hidden workspace; nothing is reopened while the window still exists.
    function slugOf(key) { return key.replace(/[^A-Za-z0-9]+/g, "_") }
    function hypr(expr) { Quickshell.execDetached(["hyprctl", "dispatch", expr]) }
    function sel(slug) { return 'window = "title:^projectnier-term:' + slug + '$"' }

    property var termSlugs: []        // slugs that currently have a window
    property var appNames: ({})       // slug -> name of the app started there
    property string pendingSlug: ""   // sub-function that just asked for a new window
    property string shownSlug: ""     // slug whose window has been placed in the frame
    // the file manager's content window belongs to the whole Archive menu: every Archive sub-function shows it once it is open
    readonly property string fmHome: "Archive_File_Manager"
    function effSlug(p) {
        if (p === "") return ""
        if (p.indexOf("Archive/") === 0 && extFor(fmHome) !== null) return fmHome
        return slugOf(p)
    }
    readonly property string curSlug: effSlug(pane)
    readonly property bool termOpen: curSlug !== "" && shownSlug === curSlug
    // the Messenger connection runs all the time so unread messages can be shown even while it is closed
    MatrixClient {
        id: matrix
        viewing: root.messengerOpen
        Component.onCompleted: start()
    }
    readonly property int unread: matrix.unreadTotal
    // Gmail: every account is checked in the background for the badge and new-mail notices
    MailClient {
        id: mail
        viewing: root.emailOpen
        Component.onCompleted: start()
        onIncoming: (account, from, subject) => Quickshell.execDetached(["notify-send", "-a", "Email", "-i", "mail-unread",
            from + (accounts.length > 1 ? "  ·  " + account.replace(/@.*/, "") : ""), root.markupSafe(subject)])
    }
    readonly property int mailUnread: mail.totalUnread
    // health light (top right): Messenger, its bridge and mail; one notice when something breaks
    // (passed through root.*: inside Health "matrix: matrix" would find Health's own property, not the id)
    readonly property var matrixClient: matrix
    readonly property var mailClient: mail
    Health {
        id: health
        matrix: root.matrixClient
        mail: root.mailClient
        // Facebook logged the bridge out: show the bridge chat in Messenger so "login" can be sent to it
        onFbLoggedOutChanged: matrix.showBridge = fbLoggedOut
        onBroke: summary => Quickshell.execDetached(["notify-send", "-a", "System", "-i", "dialog-warning",
            "Something needs attention", root.markupSafe(summary) + ". Open System → Self Check (or click the mark at the top right) to repair."])
    }
    // Bluetooth pairing agent: BlueZ's questions (passkeys, PINs) are answered in the Bluetooth manager. A request that
    // arrives while the manager is not on screen (a phone pairing on its own) opens it in Network → Bluetooth.
    BluetoothAgent {
        id: btAgent
        onRequested: {
            if (root.bluetoothOpen) return
            Quickshell.execDetached(["notify-send", "-a", "Bluetooth", "-i", "bluetooth", "Pairing request",
                                     root.markupSafe(request.name) + " wants to pair. Answer it in Network → Bluetooth."])
            var key = "Network/Bluetooth"
            if (root.bluetoothSlug === "" && !root.occupied(root.slugOf(key))) root.bluetoothSlug = root.slugOf(key)
            if (root.bluetoothSlug === root.slugOf(key)) root.gotoSlug(root.bluetoothSlug)
        }
    }
    Connections {
        target: matrix
        function onIncoming(room, text) {
            Quickshell.execDetached(["notify-send", "-a", "Messenger", "-i", "mail-unread", room, root.markupSafe(text)])
        }
    }
    // notification bodies are read as markup: a chat message like "<3 u" must not lose text as a "tag"
    function markupSafe(s) { return String(s).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;") }

    // the native messenger lives in the content frame of the sub-function that opened it
    property string messengerSlug: ""
    readonly property bool messengerOpen: messengerSlug !== "" && messengerSlug === curSlug
    // the native email window (Gmail), same idea: it lives in the content frame of its sub-function
    property string emailSlug: ""
    readonly property bool emailOpen: emailSlug !== "" && emailSlug === curSlug
    // the native Bluetooth manager, same idea (the pairing agent below runs all the time)
    property string bluetoothSlug: ""
    readonly property bool bluetoothOpen: bluetoothSlug !== "" && bluetoothSlug === curSlug
    readonly property bool frameOpen: termOpen || messengerOpen || emailOpen || bluetoothOpen
    function openApp(app) {
        if (app === "messenger" && curSlug !== "") messengerSlug = curSlug
        else if (app === "email" && curSlug !== "") emailSlug = curSlug
        else if (app === "bluetooth" && curSlug !== "") bluetoothSlug = curSlug
    }
    readonly property string appName: messengerOpen ? "Messenger" : emailOpen ? "Email" : bluetoothOpen ? "Bluetooth" : appNames[curSlug] ? appNames[curSlug] : (liveNames[curSlug] ? liveNames[curSlug] : (extFor(curSlug) ? pretty(extFor(curSlug).cls) : "Terminal"))

    // One hyprctl call does everything for a switch (hide the others, show + place this one),
    // and the frame is drawn when that call has finished, so frame and window appear together.
    property var queued: null
    // the shell-drawn frame the window lives in (normal or full screen)
    readonly property real fx: maximized ? fsMargin : contentX
    readonly property real fy: maximized ? fsMargin : contentY
    readonly property real fw: maximized ? width - fsMargin * 2 : contentR - contentX
    readonly property real fh: maximized ? height - fsMargin * 2 : contentB - contentY
    function frameBox() {
        // computed straight from `maximized` (not from fx/fy/...: those bindings may not have updated yet)
        var x = maximized ? fsMargin : contentX
        var y = maximized ? fsMargin : contentY
        var w = maximized ? width - fsMargin * 2 : contentR - contentX
        var h = maximized ? height - fsMargin * 2 : contentB - contentY
        return { x: Math.round(x + 3), y: Math.round(y + headH + 4), w: Math.round(w - 6), h: Math.round(h - headH - 7) }
    }
    // ---- apps may only run inside the content window ----------------------------------------------
    // A window that opens is allowed if it is a content terminal, was already open when the shell
    // started, is a system dialog, belongs to a registered or just-launched app. Anything else is
    // closed at once and the user is asked which menu and sub-function it belongs to.
    property var extWins: []            // [{ addr, slug, cls }] application windows placed in the content frame
    property var known: ({})            // addresses that existed when the shell started
    property var claimedCls: ({})       // window class -> slug it belongs to
    // one claim per launch still waiting for its window, oldest first: fast clicks in several places (or several
    // folders in Archive) each get their own window instead of the second one being asked about
    property var claims: []             // [{ slug, until, fm }]   fm = a Dolphin started by openFileManager
    function liveClaims() { var now = Date.now(); return claims.filter(c => c.until > now) }
    function addClaim(slug, fm) {
        if (slug === "") return
        claims = liveClaims().concat([{ slug: slug, until: Date.now() + 20000, fm: fm === true }])
    }
    // the oldest claim this window can answer (a Dolphin takes a file-manager claim first), removed from the list
    function takeClaim(cls) {
        var list = liveClaims(), dol = String(cls).toLowerCase().indexOf("dolphin") >= 0
        var k = -1
        if (dol) k = list.findIndex(c => c.fm)
        if (k < 0) k = list.findIndex(c => !c.fm)
        if (k < 0) { claims = list; return null }
        var c = list[k]
        list.splice(k, 1)
        claims = list
        return c
    }
    function takeClaimFor(slug) {
        var list = liveClaims(), k = list.findIndex(c => !c.fm && c.slug === slug)
        if (k < 0) { claims = list; return null }
        var c = list[k]
        list.splice(k, 1)
        claims = list
        return c
    }
    property var promptQueue: []        // blocked apps waiting for an answer
    readonly property var promptApp: promptQueue.length > 0 ? promptQueue[0] : null

    property real focusUntil: 0              // the next shown content window gets keyboard focus (user opened it)
    function claimNext() { addClaim(curSlug, false); focusUntil = Date.now() + 8000 }

    function extFor(slug) {
        for (var i = 0; i < extWins.length; i++) if (extWins[i].slug === slug) return extWins[i]
        return null
    }

    // the sub-function that owns an installed program whose window class is its command name (discord, steam ...)
    function builtinKey(cls) {
        var c = String(cls).toLowerCase(), m = mappedApps()
        for (var i = 0; i < m.length; i++) if (m[i].cls === "" && m[i].bin === c) return m[i].key
        return ""
    }
    // every image, from wherever it was opened (a list, the file manager ...), is shown in this sub-function
    readonly property string viewerSlug: slugOf("Entertainment/Image Viewer")
    function isViewer(cls) { return String(cls).toLowerCase().indexOf("gwenview") >= 0 }
    function windowOpened(addr, cls) {
        if (known[addr]) return
        if (cls === "") { waitForClass(addr); return }
        if (Registry.isSystem(cls)) return
        // hide it right away: until it is sized and placed (or closed) it must not be seen tiled / full screen
        Quickshell.execDetached(["hyprctl", "--batch", 'dispatch hl.dsp.window.move({ workspace = "special:projectnierterm", follow = false, window = "address:0x' + addr + '" })'])
        // first make sure it is not a dialog of an app that is already open (a delete confirmation, a save dialog ...)
        var q = dialogComp.createObject(root, { addr: addr, cls: cls, command: ["sh", "-c",
            "hyprctl clients -j | jq -r --arg a \"0x$1\" '([.[] | select(.address == $a)][0]) as $w | if $w == null then \"gone\" else " +
            "\"\\($w.floating)\\t\\([.[] | select(.pid == $w.pid and .address != $a)] | length)\" end'", "sh", addr] })
        q.running = true
        q.destroy(10000)
    }
    // Electron / Chromium apps, Steam, Java ... map their window before they set its class: wait (up to ~2 s) for the
    // class, then route the window as usual. A window that never gets one (XWayland drag icons ...) is left alone.
    function waitForClass(addr) {
        var q = classComp.createObject(root, { addr: addr, command: ["sh", "-c",
            "for i in 1 2 3 4 5 6 7 8; do sleep 0.25; c=$(hyprctl clients -j | jq -r --arg a \"0x$1\" " +
            "'([.[] | select(.address == $a)][0]) as $w | if $w == null then \"\\t\" else $w.class end'); " +
            "[ -n \"$c\" ] && { printf '%s' \"$c\"; exit 0; }; done", "sh", addr] })
        q.running = true
        q.destroy(10000)
    }
    Component {
        id: classComp
        Process {
            id: cq
            property string addr
            stdout: StdioCollector {
                onStreamFinished: {
                    var c = text.trim()          // empty: still no class, or the window is gone
                    if (c !== "") root.windowOpened(cq.addr, c)
                }
            }
        }
    }
    // a dialog: a window with a parent window, or a floating window of a process that already has a window.
    // It stays on screen over its app and is never placed, prompted for or counted as an app of its own.
    function isDialogOf(addr) {
        var a = "0x" + String(addr).replace(/^0x/, "").toLowerCase()
        var h = Hyprland.toplevels.values
        for (var i = 0; i < h.length; i++)
            if (String(h[i].address).toLowerCase() === a) return !!(h[i].wayland && h[i].wayland.parent)
        return false
    }
    Component {
        id: dialogComp
        Process {
            id: dq
            property string addr
            property string cls
            stdout: StdioCollector {
                onStreamFinished: {
                    var t = text.trim()
                    if (t === "gone") return
                    var f = t.split("\t")
                    if (root.isDialogOf(dq.addr) || (f[0] === "true" && Number(f[1]) > 0)) {
                        var k = Object.assign({}, root.known); k[dq.addr] = true; root.known = k
                        var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                        var sl = 'window = "address:0x' + dq.addr + '"'
                        Quickshell.execDetached(["hyprctl", "--batch", 'dispatch hl.dsp.window.move({ workspace = "' + ws + '", follow = false, ' + sl + ' }) ; ' +
                                                 'dispatch hl.dsp.focus({ ' + sl + ' })'])
                        root.releaseKeys()      // the keys go to the dialog, not the screen
                    } else root.routeWindow(dq.addr, dq.cls)
                }
            }
        }
    }
    // the sub-function a window class belongs to ("" = none known)
    // title of a window (a registered app with a generic class like "Tk" is told apart by it)
    function titleOf(addr) { var t = pop.toplevelOf(String(addr).replace(/^0x/, "").toLowerCase()); return t ? String(t.title) : "" }
    function slugForClass(cls, addr) {
        if (isViewer(cls)) return viewerSlug
        if (claimedCls[cls]) return claimedCls[cls]
        var reg = Registry.byClass(cls, addr !== undefined ? titleOf(addr) : undefined)
        if (reg) return slugOf(reg.tab + "/" + reg.sub)
        if (builtinKey(cls) !== "") return slugOf(builtinKey(cls))     // e.g. Discord opened from the tray: its own sub-function
        return ""
    }
    function routeWindow(addr, cls) {
        if (cls.toLowerCase().indexOf("dolphin") >= 0 && liveClaims().some(c => c.fm)) {
            var fc = takeClaim(cls)
            // the newest folder click wins: a Dolphin that an earlier quick click opened here is closed
            var older = extWins.filter(w => w.slug === fc.slug && w.cls.toLowerCase().indexOf("dolphin") >= 0)
            if (older.length > 0) {
                Quickshell.execDetached(["bash", Panes.script("close-ext.sh")].concat(older.map(w => w.addr)))
                extWins = extWins.filter(w => older.indexOf(w) < 0)
            }
            placeWindow(addr, cls, fc.slug, true)      // a second file manager for this sub-function: no duplicate check
            return
        }
        var slug = slugForClass(cls, addr)
        var claim = null
        if (slug === "") {
            claim = takeClaim(cls)                     // launched from a button and not known yet: the oldest launch's place
            if (claim) slug = claim.slug
        } else claim = takeClaimFor(slug)              // known app: use up the claim its own launch left (if any)
        if (slug === "") { blockWindow(addr, cls); return }
        var click = claim !== null && claim.slug === curSlug     // started from the page you are on: stay there
        // an app that is already open does not get a second window (starting Firefox again opens one): drop the new
        // window and bring the existing one forward instead
        var d = dupComp.createObject(root, { addr: addr, cls: cls, slug: slug, click: click, command: ["sh", "-c",
            "hyprctl clients -j | jq -r --arg c \"$1\" --arg a \"0x$2\" '([.[] | select(.address == $a)][0].floating // false) as $f | ([.[] | select(.class == $c and .address != $a)][0].address // \"\") as $o | \"\\($f)\\t\\($o)\"'", "sh", cls, addr] })
        d.running = true
        d.destroy(15000)
    }
    Component {
        id: dupComp
        Process {
            id: dp
            property string addr
            property string cls
            property string slug
            property bool click: false
            stdout: StdioCollector {
                onStreamFinished: {
                    var parts = text.trim().split("\t")
                    var other = (parts[1] || "").replace(/^0x/, "")
                    if (other === "") { root.placeWindow(dp.addr, dp.cls, dp.slug, false, dp.click); return }
                    if (parts[0] === "true") {
                        // a dialog of an app that is already open (file picker, "Open database" ...): show it, centred
                        var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                        var sl = 'window = "address:0x' + dp.addr + '"'
                        Quickshell.execDetached(["hyprctl", "--batch", 'dispatch hl.dsp.window.move({ workspace = "' + ws + '", follow = false, ' + sl + ' }) ; dispatch hl.dsp.focus({ ' + sl + ' }) ; dispatch hl.dsp.window.center({ ' + sl + ' })'])
                        return
                    }
                    if (dp.slug === root.viewerSlug) {
                        // a new image: it replaces the one being viewed
                        Quickshell.execDetached(["bash", Panes.script("close-ext.sh"), other])
                        root.extWins = root.extWins.filter(w => w.addr !== other)
                        root.placeWindow(dp.addr, dp.cls, dp.slug, false, dp.click)
                        return
                    }
                    Quickshell.execDetached(["bash", Panes.script("close-ext.sh"), dp.addr])
                    var have = root.extWins.filter(w => w.addr === other)
                    if (have.length === 0) {                 // it was open before the shell started: adopt it
                        var cc = Object.assign({}, root.claimedCls); cc[dp.cls] = dp.slug; root.claimedCls = cc
                        root.extWins = root.extWins.concat([{ addr: other, slug: dp.slug, cls: dp.cls }])
                        root.syncTerm()
                    }
                    root.gotoSlug(have.length > 0 ? have[0].slug : dp.slug)
                }
            }
        }
    }
    function placeWindow(addr, cls, slug, own, click) {
        var byClick = own === true || click === true          // launched from a button on this page: we are already there
        var place = function () {
            if (own !== true) { var cc = Object.assign({}, claimedCls); cc[cls] = slug; claimedCls = cc }
            extWins = extWins.concat([{ addr: addr, slug: slug, cls: cls }])
            syncTerm()
            if (!byClick) gotoSlug(slug)                // opened by a shortcut: take the user to its page
        }
        // the sub-function already holds another app: hide the new window and ask first, replace after the answer
        if (occupied(slug) && pretty(cls) !== nameOfSlug(slug)) {
            if (replaceAsk) { Quickshell.execDetached(["bash", Panes.script("close-ext.sh"), addr]); return }
            Quickshell.execDetached(["hyprctl", "--batch", 'dispatch hl.dsp.window.move({ workspace = "special:projectnierterm", follow = false, window = "address:0x' + addr + '" })'])
            replaceAsk = { name: pretty(cls), old: nameOfSlug(slug), slug: slug, go: place, cancel: addr }
            gotoSlug(slug)
            return
        }
        place()
    }
    function nameOfSlug(slug) {
        if (slug === messengerSlug) return "Messenger"
        if (slug === emailSlug) return "Email"
        if (slug === bluetoothSlug) return "Bluetooth"
        if (appNames[slug]) return appNames[slug]
        if (liveNames[slug]) return liveNames[slug]
        var e = extFor(slug)
        return e ? pretty(e.cls) : "Terminal"
    }

    function blockWindow(addr, cls) {
        var p = blockComp.createObject(root, { addr: addr, cls: cls, command: ["bash", Panes.script("block-window.sh"), addr] })
        p.running = true
        p.destroy(15000)
    }
    Component {
        id: blockComp
        Process {
            id: bp
            property string addr
            property string cls
            stdout: StdioCollector {
                // one JSON line from block-window.sh: { cmd, name, title }
                onStreamFinished: {
                    var d = {}
                    try { d = JSON.parse(text) } catch (e) {}
                    var title = Registry.isGeneric(bp.cls) ? String(d.title || "") : ""
                    for (var i = 0; i < root.promptQueue.length; i++)
                        if (root.promptQueue[i].cls === bp.cls && root.promptQueue[i].title === title) return
                    root.promptQueue = root.promptQueue.concat([{ cls: bp.cls, title: title, name: d.name ? String(d.name) : root.pretty(bp.cls),
                                                                  cmd: d.cmd ? String(d.cmd) : "" }])
                }
            }
        }
    }

    function promptAccept(menu, subName) {
        var a = promptQueue[0]
        if (!a) return
        var cmd = a.cmd !== "" ? a.cmd : a.cls
        var entry = { cls: a.cls, name: a.name, cmd: cmd, tab: menu, sub: subName }
        if (a.title) entry.title = a.title
        Registry.add(entry)
        promptQueue = promptQueue.slice(1)
        var key = menu + "/" + subName
        for (var i = 0; i < pages.length; i++) if (pages[i].label === menu) { page = i; break }
        pane = key
        addClaim(slugOf(key), false); focusUntil = Date.now() + 8000
        Quickshell.execDetached(["sh", "-c", cmd])        // open it again, now inside its new sub-function
    }
    // Gmail in its own Chromium app window, shown in the Webmail sub-function (never in the Firefox of the Browser one)
    function openWebmail(addr) {
        var key = "Communication/Webmail"
        for (var i = 0; i < pages.length; i++) if (pages[i].label === "Communication") { page = i; break }
        pane = key
        addClaim(slugOf(key), false); focusUntil = Date.now() + 8000
        Quickshell.execDetached(["bash", Panes.script("gmail.sh"), addr])
    }
    // "Open in File Manager" from any sub-function: open another Dolphin (at the path in cmd) in the content window of
    // the sub-function you are on; the File Manager sub-function and its own Dolphin are left alone
    // a relaunch waiting for the old Dolphin to close: a newer folder click replaces it (only the newest folder opens)
    Timer { id: fmTimer; property var job: null; interval: 1500; onTriggered: { var j = job; job = null; if (j) j() } }
    function openFileManager(cmd) {
        var slug = pane.indexOf("Archive/") === 0 ? fmHome : curSlug
        if (slug === "") { Quickshell.execDetached(cmd); return }
        // a Dolphin is already shown here and the File Manager button was pressed again: nothing to do
        if (cmd.length === 1 && cmd[0] === "dolphin" && extWins.some(w => w.slug === slug && w.cls.toLowerCase().indexOf("dolphin") >= 0)) return
        // a running Dolphin would open the path as a tab in its existing window: always ask for a window of its own
        var nw = cmd.map(a => a.replace(/^dolphin /, "dolphin --new-window "))
        if (nw[0] === "dolphin") nw.splice(1, 0, "--new-window")
        cmd = nw
        // the claim is made when Dolphin really starts: exactly one claim per window that will open
        var launch = () => { addClaim(slug, true); Quickshell.execDetached(cmd) }
        // a Dolphin already shown here would keep its old folder: close it, then open the new path
        // (anything else shown here, such as the image viewer, is replaced by the file manager)
        var old = extWins.filter(w => w.slug === slug)
        if (old.length > 0) closeExt(slug)
        focusUntil = Date.now() + 8000
        if (old.length > 0 || fmTimer.running) { fmTimer.job = launch; fmTimer.restart() }
        else launch()
    }
    // an image clicked in a list: show it in the Image Viewer sub-function (its window is replaced by the new image).
    // Gwenview windows always go there by class; no claim, so the window takes you to the Image Viewer.
    function openViewer(cmd) {
        focusUntil = Date.now() + 8000
        Quickshell.execDetached(cmd)
    }
    // where an app that opened a file usually belongs: shown pre-selected in the prompt (the user can change it)
    function suggestFor(cls) {
        var c = String(cls).toLowerCase()
        if (c.indexOf("codium") >= 0 || c.indexOf("code") === 0) return { menu: "Console", sub: "Code Editor", creating: true }
        return null
    }
    // an Apps-list chip of a window the shell is not showing: one that is parked out of sight (it never got placed, e.g. the
    // old window of a replaced app) is brought into the sub-function you are on; any other window is just focused
    // the sub-function a window lives in, looked up at click time ("" = it belongs nowhere yet)
    function homeSlug(addr, cls) {
        var a = String(addr).replace(/^0x/, "").toLowerCase()
        for (var i = 0; i < extWins.length; i++) if (String(extWins[i].addr).toLowerCase() === a) return extWins[i].slug
        if (isViewer(cls)) return viewerSlug
        if (claimedCls[cls]) return claimedCls[cls]
        var reg = Registry.byClass(cls, titleOf(addr))
        if (reg) return slugOf(reg.tab + "/" + reg.sub)
        if (builtinKey(cls) !== "") return slugOf(builtinKey(cls))
        return ""
    }
    function appWindowClicked(addr, cls) {
        // a window that has its own sub-function: go there (never pull it into the one on screen)
        var a = String(addr).toLowerCase()
        var placed = extWins.filter(w => String(w.addr).toLowerCase() === a)
        if (placed.length > 0 && keyForSlug(placed[0].slug) !== "") { gotoSlug(placed[0].slug); return }
        var p = chipComp.createObject(root, { addr: addr, cls: cls, command: ["sh", "-c",
            "hyprctl clients -j | jq -r --arg a \"0x$1\" '.[] | select(.address == $a) | .workspace.name'", "sh", addr] })
        p.running = true
        p.destroy(10000)
    }
    Component {
        id: chipComp
        Process {
            id: cp
            property string addr
            property string cls
            stdout: StdioCollector {
                onStreamFinished: {
                    var sl = 'window = "address:0x' + cp.addr + '"'
                    if (text.trim().indexOf("special:") === 0 && root.curSlug !== "") {
                        root.focusUntil = Date.now() + 8000
                        // into its own sub-function if it has one, else the one on screen
                        var home = root.homeSlug(cp.addr, cp.cls)
                        if (home !== "" && root.keyForSlug(home) !== "") {
                            root.placeWindow(cp.addr, cp.cls, home, true)
                            root.gotoSlug(home)
                        } else root.placeWindow(cp.addr, cp.cls, root.curSlug, true)
                    } else Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ " + sl + " })"])
                }
            }
        }
    }
    function promptDismiss() { promptQueue = promptQueue.slice(1) }

    // windows that were open when the shell started are left alone, except an app that sits tiled / full screen on a
    // normal workspace (it opened while the shell was reloading): if it belongs to a sub-function it is put back in
    // the frame. One that belongs to none is not touched (routing it would close it).
    property var strays: []
    Process {
        running: true
        command: ["sh", "-c", "hyprctl clients -j | jq -r '.[] | \"\\(.address)\\t\\(.class)\\t\\(.floating)\\t\\(.fullscreen)\\t\\(.workspace.name)\\t\\(.pinned)\"'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var k = {}, s = []
                text.split("\n").forEach(line => {
                    var f = line.split("\t")
                    if (f[0] === "") return
                    var a = f[0].replace(/^0x/, "")
                    k[a] = true
                    if (f[1] === "projectnier-term" && f[5] === "true") s.push({ addr: a, cls: f[1], pinned: true })
                    else if (f[1] !== "" && f[1] !== "projectnier-term" && (f[2] === "false" || f[3] !== "0" || f[5] === "true") && f[4].indexOf("special:") !== 0)
                        s.push({ addr: a, cls: f[1], pinned: f[5] === "true" })
                })
                root.known = k
                root.strays = s
                if (s.length > 0) strayTimer.start()
            }
        }
    }
    // the app registry is read asynchronously: wait for it before looking the strays up
    Timer {
        id: strayTimer
        interval: 1500
        onTriggered: {
            var add = []
            var unpin = false
            root.strays.forEach(w => {
                if (w.cls === "projectnier-term") {      // a terminal left popped out: it just goes back to its frame
                    pop.unpinNext = pop.unpinNext.concat(['window = "address:0x' + w.addr + '"']); unpin = true
                    return
                }
                if (Registry.isSystem(w.cls) || root.isDialogOf(w.addr)) return
                var slug = root.slugForClass(w.cls, w.addr)
                if (slug === "") return
                add.push({ addr: w.addr, slug: slug, cls: w.cls })
                if (w.pinned) pop.unpinNext = pop.unpinNext.concat(['window = "address:0x' + w.addr + '"'])
            })
            root.strays = []
            if (add.length === 0) { if (unpin) root.syncTerm(); return }
            var cc = Object.assign({}, root.claimedCls)
            add.forEach(w => { cc[w.cls] = w.slug })
            root.claimedCls = cc
            root.extWins = root.extWins.concat(add)
            root.syncTerm()
        }
    }

    function syncTerm() {
        var cur = effSlug(pane)        // (not curSlug: its binding may not have updated yet)
        var cmds = []
        pop.unpinNext.forEach(u => { cmds.push('dispatch hl.dsp.window.pin({ ' + u + ', action = "disable" })'); cmds = cmds.concat(pop.popProps(u, false)) })
        pop.unpinNext = []
        var show = ""
        var showSel = ""
        var curPopped = false
        var wins = termSlugs.filter(s => s.indexOf("popup") !== 0).map(s => ({ slug: s, sel: sel(s) }))
                   .concat(extWins.map(w => ({ slug: w.slug, sel: 'window = "address:0x' + w.addr + '"', ext: true })))
        var popSel = {}
        pop.popped.forEach(p => { popSel[p.term ? sel(p.slug) : p.sel] = true })
        for (var i = 0; i < wins.length; i++) {
            var s = wins[i].slug, sl = wins[i].sel
            // a popped-out window floats on its own: never placed or hidden, its content window just says where it is
            if (popSel[sl] && pop.poppedFor(s) !== null) { if (s === cur) curPopped = true; continue }
            // several app windows in one sub-function (e.g. two browsers): only the newest is shown
            var buried = false
            if (wins[i].ext) for (var j = i + 1; j < wins.length; j++) if (wins[j].ext && wins[j].slug === s) buried = true
            if (s === cur && !buried) {
                var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
                var b = frameBox()
                if (!wins[i].ext) cmds.push('dispatch hl.dsp.window.move({ workspace = "' + ws + '", follow = false, ' + sl + ' })')
                if (wins[i].ext) cmds.push('dispatch hl.dsp.window.float({ ' + sl + ', action = "enable" })')   // application windows start tiled
                if (wins[i].ext) cmds.push('dispatch hl.dsp.window.fullscreen({ ' + sl + ', action = "unset" })')   // apps that start fullscreen stay in the frame
                // resize first: a resize keeps the window's centre, so the move has to come last
                cmds.push('dispatch hl.dsp.window.resize({ ' + sl + ', x = ' + b.w + ', y = ' + b.h + ' })')
                cmds.push('dispatch hl.dsp.window.move({ ' + sl + ', x = ' + b.x + ', y = ' + b.y + ' })')
                // an application window was shaped while hidden: only now bring it to this workspace
                if (wins[i].ext) cmds.push('dispatch hl.dsp.window.move({ workspace = "' + ws + '", follow = false, ' + sl + ' })')
                show = s; showSel = sl
            } else {
                cmds.push('dispatch hl.dsp.window.move({ workspace = "special:projectnierterm", follow = false, ' + sl + ' })')
            }
        }
        if (show === "" && curPopped) shownSlug = cur  // its frame stays, with a note that the app is popped out
        else if (show === "") shownSlug = ""            // nothing to show: the frame goes away at once
        if (cmds.length === 0) return
        var job = { cmd: cmds.join(" ; "), show: show, sel: showSel }
        if (batch.running) { queued = job; return }
        runJob(job)
    }
    function runJob(job) {
        batch.show = job.show
        batch.sel = job.sel
        batch.command = ["hyprctl", "--batch", job.cmd]
        batch.running = true
    }
    Process {
        id: batch
        property string show: ""
        property string sel: ""
        onExited: {
            if (root.queued) { var j = root.queued; root.queued = null; root.runJob(j); return }
            // only draw the frame if this is still the selected sub-function
            if (show !== "" && show === root.curSlug) {
                root.shownSlug = show
                if (Date.now() < root.focusUntil && sel !== "") {
                    root.focusUntil = 0
                    root.releaseKeys()     // the screen still holds the keyboard from the click that opened it
                    Quickshell.execDetached(["hyprctl", "dispatch", "hl.dsp.focus({ " + sel + " })"])
                }
            }
        }
    }

    // content windows, as entries for the Apps list ("Drift" etc.); timer pop-ups are not listed
    function keyForSlug(slug) {
        for (var i = 0; i < basePages.length; i++)
            for (var j = 0; j < basePages[i].subs.length; j++) {
                var k = basePages[i].label + "/" + basePages[i].subs[j].name
                if (slugOf(k) === slug) return k
            }
        return ""
    }
    readonly property var contentApps: termSlugs.filter(s => s.indexOf("popup") !== 0).map(s => {
        var k = keyForSlug(s)
        return { slug: s, name: appNames[s] ? appNames[s] : (liveNames[s] ? liveNames[s] : (k !== "" ? k.split("/")[1] : s)) }
    }).concat(messengerSlug !== "" ? [{ slug: messengerSlug, name: "Messenger" + (unread > 0 ? " (" + unread + ")" : "") }] : [])
      .concat(emailSlug !== "" ? [{ slug: emailSlug, name: "Email" + (mailUnread > 0 ? " (" + mailUnread + ")" : "") }] : [])
      .concat(bluetoothSlug !== "" ? [{ slug: bluetoothSlug, name: "Bluetooth" }] : [])

    // go to the sub-function that owns a content window (which brings its window forward)
    function gotoSlug(slug) {
        focusUntil = Date.now() + 8000
        var k = keyForSlug(slug)
        if (k === "") return
        var label = k.split("/")[0]
        for (var i = 0; i < menu.entries.length; i++) if (menu.entries[i].label === label) { page = i; break }
        pane = k
    }

    // end the application windows (and their processes) a sub-function holds
    function closeExt(slug) {
        var mine = extWins.filter(w => w.slug === slug)
        if (mine.length === 0) return
        Quickshell.execDetached(["bash", Panes.script("close-ext.sh")].concat(mine.map(w => w.addr)))
        extWins = extWins.filter(w => w.slug !== slug)
        if (shownSlug === slug && termSlugs.indexOf(slug) < 0) { shownSlug = ""; maximized = false }
    }

    // ---- don't close a window while Claude Code works in it (scripts/busy.sh, marks set by Claude hooks) ----
    // the first close only warns; closing again within 5 s closes it anyway
    property var forceClose: ({})       // slug -> time until which a close goes through
    function guardClose(slug, go) {
        if (termSlugs.indexOf(slug) < 0 || (forceClose[slug] || 0) > Date.now()) { go(); return }
        var g = busyCheck.jobs.slice(); g.push({ slug: slug, go: go }); busyCheck.jobs = g
        if (!busyCheck.running) busyCheck.next()
    }
    Process {
        id: busyCheck
        property var jobs: []
        property var cur: null
        function next() {
            if (jobs.length === 0) return
            cur = jobs[0]; jobs = jobs.slice(1)
            command = ["bash", Panes.script("busy.sh"), "slug", cur.slug]
            running = true
        }
        onExited: code => {
            var j = cur; cur = null
            if (code === 0) {
                var f = Object.assign({}, root.forceClose); f[j.slug] = Date.now() + 5000; root.forceClose = f
                Quickshell.execDetached(["notify-send", "-a", "ProjectNier", "-i", "dialog-warning", "Claude is still working",
                    "Close again within 5 seconds to close it anyway."])
            } else j.go()
            next()
        }
    }

    // close any content window (and its processes) from the Apps list
    function closeSlug(slug) {
        if (slug === messengerSlug) { messengerSlug = ""; if (curSlug === slug) maximized = false; return }
        if (slug === emailSlug) { emailSlug = ""; if (curSlug === slug) maximized = false; return }
        if (slug === bluetoothSlug) { bluetoothSlug = ""; if (curSlug === slug) maximized = false; return }
        guardClose(slug, () => closeSlugNow(slug))
    }
    function closeSlugNow(slug) {
        closeExt(slug)
        Quickshell.execDetached(["bash", Panes.script("close-term.sh"), slug])
        termSlugs = termSlugs.filter(x => x !== slug)
        if (shownSlug === slug) { shownSlug = ""; maximized = false }
        refreshTimer.restart()
    }

    // close button: ends the current sub-function's window
    function closeTerm() {
        var s = curSlug
        if (s === "") return
        if (messengerOpen) { messengerSlug = ""; maximized = false; return }     // stops the messenger's connection
        if (emailOpen) { emailSlug = ""; maximized = false; return }
        if (bluetoothOpen) { bluetoothSlug = ""; maximized = false; return }
        guardClose(s, () => closeTermNow(s))
    }
    function closeTermNow(s) {
        closeExt(s)
        Quickshell.execDetached(["bash", Panes.script("close-term.sh"), s])   // closes the window and kills its processes
        termSlugs = termSlugs.filter(x => x !== s)
        shownSlug = ""
        maximized = false
        refreshTimer.restart()
    }

    // run something in the content window of the current sub-function (a new tab if it has one)
    function openInContent(title, cmd) {
        if (curSlug === "") return
        var names = Object.assign({}, appNames)
        names[curSlug] = appLabel(cmd)
        appNames = names
        if (termSlugs.indexOf(curSlug) < 0) pendingSlug = curSlug
        Quickshell.execDetached(Panes.openIn(curSlug, title, cmd))
        placeTimer.restart()
    }

    // ---- one app per sub-function: ask before replacing the one that is open --------------------------
    property var replaceAsk: null       // { name: new app, old: name of the open one, slug, go }
    function occupied(slug) { return slug !== "" && (termSlugs.indexOf(slug) >= 0 || extFor(slug) !== null || messengerSlug === slug || emailSlug === slug || bluetoothSlug === slug) }
    // what: a command array or the name of a built-in app; go() does the opening
    function gated(what, go) {
        // a plain terminal while this sub-function already has its terminal: just bring that one forward
        if (typeof what !== "string" && what.length === 0 && termSlugs.indexOf(curSlug) >= 0) {
            focusUntil = Date.now() + 8000
            syncTerm()
            return
        }
        var name = typeof what === "string" ? pretty(what) : appLabel(what)
        if (occupied(curSlug) && !replaceAsk) {   // also when it is the same app: ask before replacing it
            replaceAsk = { name: name, old: appName, slug: curSlug, go: go }
            return
        }
        go()
    }
    function replaceAccept() {
        var a = replaceAsk
        replaceAsk = null
        if (!a) return
        if (a.slug === messengerSlug) { messengerSlug = ""; a.go(); return }
        if (a.slug === emailSlug) { emailSlug = ""; a.go(); return }
        if (a.slug === bluetoothSlug) { bluetoothSlug = ""; a.go(); return }
        guardClose(a.slug, () => replaceNow(a))
    }
    function replaceNow(a) {
        closeExt(a.slug)
        termSlugs = termSlugs.filter(x => x !== a.slug)
        shownSlug = ""; maximized = false
        closer.go = a.go
        closer.command = ["bash", Panes.script("close-term.sh"), a.slug]
        closer.running = true
    }
    function replaceCancel() {
        var a = replaceAsk
        replaceAsk = null
        if (a && a.cancel) Quickshell.execDetached(["bash", Panes.script("close-ext.sh"), a.cancel])   // the new window never showed: close it
    }
    Timer { id: goTimer; property var job: null; interval: 1500; onTriggered: { var j = job; job = null; if (j) j() } }
    Process {
        id: closer
        property var go: null
        // the old app needs a moment to die before the new one starts (same profile: a new launch would just reach the old process)
        onExited: { refreshTimer.restart(); if (go) { var g = go; go = null; goTimer.job = g; goTimer.restart() } }
    }

    // name shown on the content frame: the app that was started
    function appLabel(cmd) {
        var c = cmd.length > 0 ? cmd[0] : "terminal"
        if ((c === "sh" || c === "bash") && cmd.length > 1 && /chromium\.sh$/.test(String(cmd[1]))) return "Chromium"
        if (c === "sh" || c === "bash" || c === "fish") {
            var i = cmd.indexOf("-c")
            if (i >= 0 && cmd[i + 1]) c = String(cmd[i + 1]).trim().split(/\s+/)[0]
        }
        if (c === "sudo") c = (cmd[1] === "-i") ? "root terminal" : (cmd[1] || "sudo")
        return pretty(c.replace(/^.*\//, ""))
    }

    property var liveNames: ({})      // slug -> app running in its active tab (read from kitty)
    Process {
        id: termQuery
        // one line per content window:  title <TAB> name of the program in its active tab
        command: ["sh", "-c", "hyprctl clients -j | jq -r '.[] | select(.class==\"projectnier-term\") | .title' | while IFS= read -r t; do s=${t#projectnier-term:}; app=$(kitty @ --to \"unix:${XDG_RUNTIME_DIR:-/tmp}/projectnier-term-$s.sock\" ls 2>/dev/null | jq -r '[.[].tabs[] | select(.is_active)][0].windows[0].foreground_processes[0].cmdline | if . == null then empty elif (.[0] | test(\"python\")) then (.[1] // .[0]) else .[0] end' | sed 's#.py$##' | sed 's#.*/##'); printf '%s\\t%s\\n' \"$t\" \"$app\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var slugs = [], names = {}
                var lines = text.split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var c = lines[i].split("\t")
                    if (c[0] && c[0].indexOf("projectnier-term:") === 0) {
                        var s = c[0].substring("projectnier-term:".length)
                        slugs.push(s)
                        if (c[1] && !/^(fish|bash|zsh|sh)$/.test(c[1])) names[s] = root.pretty(c[1])
                    }
                }
                // only hand on real changes: a new (equal) array rebuilds every menu that depends on it
                // (SubMenu resets its highlight and replays its entrance animation)
                if (JSON.stringify(names) !== JSON.stringify(root.liveNames)) root.liveNames = names
                if (JSON.stringify(slugs) !== JSON.stringify(root.termSlugs)) root.termSlugs = slugs
                root.syncTerm()
            }
        }
    }
    readonly property var aliases: ({ "drift": "Drift", "chromium.sh": "Chromium", "org.kde.gwenview": "Gwenview", "org.kde.dolphin": "Dolphin" })
    // Steam games have the window class steam_app_<id>: show the game's name from Steam's manifests (scripts/steam-games.sh)
    property var steamNames: ({})
    Process {
        id: steamQuery
        command: ["bash", Panes.script("steam-games.sh")]
        running: true
        stdout: StdioCollector { onStreamFinished: { try { root.steamNames = JSON.parse(text) } catch (e) {} } }
    }
    function pretty(c) {
        if (aliases[c]) return aliases[c]
        var g = /^steam_app_(\d+)$/.exec(String(c))
        if (g) {
            if (steamNames[g[1]]) return steamNames[g[1]]
            if (!steamQuery.running) steamQuery.running = true      // installed since the last look
            return "Steam Game"
        }
        if ((String(c).match(/\./g) || []).length >= 2) c = String(c).replace(/^.*\./, "")   // org.keepassxc.KeePassXC -> KeePassXC
        c = String(c).replace(/-/g, " ")
        return c.charAt(0).toUpperCase() + c.substring(1)
    }
    function refreshTerms() { termQuery.running = false; termQuery.running = true }

    Timer { interval: 30000; running: true; repeat: true; onTriggered: root.refreshTerms() }
    Component.onCompleted: { refreshTerms(); selectFirst() }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            var d = String(event.data)
            if (event.name === "openwindow") {
                var p = d.split(",")
                if (p[2] !== "projectnier-term") root.windowOpened(p[0], p[2])
                if (p[2] === "projectnier-term" && root.pendingSlug !== "") {
                    // the window we just asked for: show it with its frame right away
                    if (root.termSlugs.indexOf(root.pendingSlug) < 0) root.termSlugs = root.termSlugs.concat([root.pendingSlug])
                    root.pendingSlug = ""
                    root.syncTerm()
                }
                refreshTimer.restart()
            } else if (event.name === "activespecial") {
                // the hidden-windows workspace pops up whenever a window in it gets focus (a closed content window hands
                // its focus to a hidden terminal): put it away again and focus the window that belongs on screen
                if (d.split(",")[0] !== "") {
                    var shown = extFor(curSlug)
                    var fsel = shown ? 'window = "address:0x' + shown.addr + '"' : (termSlugs.indexOf(curSlug) >= 0 ? sel(curSlug) : "")
                    var hc = 'dispatch hl.dsp.workspace.toggle_special("projectnierterm")'
                    if (fsel !== "") hc += ' ; dispatch hl.dsp.focus({ ' + fsel + ' })'
                    Quickshell.execDetached(["hyprctl", "--batch", hc])
                }
            } else if (event.name === "fullscreen") {
                if (root.extWins.length > 0) root.syncTerm()          // an app went fullscreen on its own: put it back in the frame
            } else if (event.name === "closewindow" || event.name === "windowtitlev2") {
                if (event.name === "closewindow") {
                    pop.forgetPopped(d)
                    var gone = root.extWins.filter(w => w.addr === d)
                    if (gone.length > 0) {
                        root.extWins = root.extWins.filter(w => w.addr !== d)
                        if (!root.extFor(gone[0].slug) && root.termSlugs.indexOf(gone[0].slug) < 0 && root.shownSlug === gone[0].slug) { root.shownSlug = ""; root.maximized = false }
                    }
                }
                refreshTimer.restart()
            }
        }
    }
    Timer { id: refreshTimer; interval: 250; onTriggered: root.refreshTerms() }
    Timer { id: placeTimer; interval: 600; onTriggered: { root.refreshTerms(); againTimer.restart() } }
    Timer { id: againTimer; interval: 900; onTriggered: root.refreshTerms() }

    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    Rectangle { anchors.fill: parent; color: Theme.paper }

    // a press on empty screen closes an open context menu (presses on buttons close it when the pointer leaves it)
    MouseArea {
        anchors.fill: parent
        z: -10
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => { Menus.closeAll(); mouse.accepted = false }
    }

    Image {
        anchors.fill: parent
        source: "file://" + Quickshell.shellPath("tile.png")
        fillMode: Image.Tile
    }

    // thin frame
    Rectangle {
        anchors.fill: parent
        anchors.margins: Theme.frameMargin
        color: "transparent"
        border.width: Theme.frameWidth
        border.color: Theme.ink
    }

    // corner squares
    Repeater {
        model: [[0, 0], [1, 0], [0, 1], [1, 1]]

        Rectangle {
            required property var modelData
            width: Theme.markSize
            height: Theme.markSize
            color: Theme.ink
            x: modelData[0] === 0 ? Theme.frameMargin - width / 2 : root.width - Theme.frameMargin - width / 2
            y: modelData[1] === 0 ? Theme.frameMargin - height / 2 : root.height - Theme.frameMargin - height / 2
        }
    }

    // clock (12h) with the date under it, centred
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: Theme.frameMargin + Theme.pad
        spacing: 4

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "h:mm AP")
            color: Theme.ink
            font.family: Theme.font
            font.pixelSize: Theme.clockSize
            font.letterSpacing: 4
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatDateTime(clock.date, "yyyy.MM.dd").toUpperCase()
            color: Theme.inkSoft
            font.family: Theme.font
            font.pixelSize: Theme.dateSize
            font.letterSpacing: 3
        }
    }

    // ---- health light (top right, level with the search box): click for System → Self Check ----------
    Item {
        id: healthMark
        anchors.right: parent.right
        anchors.rightMargin: Theme.frameMargin + Theme.tabInset
        y: Theme.frameMargin + Theme.pad
        width: markRow.implicitWidth
        height: Math.max(markRow.implicitHeight, 20)
        readonly property color tone: health.ok ? Theme.inkSoft : Theme.accent

        Row {
            id: markRow
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: Theme.markSize + 2
                height: width
                rotation: 45
                color: healthMark.tone
            }
            Text {
                text: health.summary
                color: healthMark.tone
                font.family: Theme.font
                font.pixelSize: Theme.smallFontSize
                font.letterSpacing: 2
                font.bold: !health.ok
                font.underline: markHit.containsMouse
            }
        }
        MouseArea {
            id: markHit
            anchors.fill: parent
            anchors.margins: -6
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.gotoSlug(root.slugOf("System/Self Check"))
        }
        HeadTip {
            anchors.right: parent.right
            anchors.top: parent.bottom
            anchors.topMargin: 8
            text: markHit.containsMouse ? (health.ok ? "Self Check"
                                   : health.problems.join("  ·  ") + (health.fbLoggedOut ? "  ·  log in again: Messages → bridge chat → send login" : "  ·  click to repair")) : ""
        }
    }

    // ---- application search (top left) ---------------------------------------------------------------
    function baseBin(c) { return String(c).trim().split(/\s+/)[0].replace(/^.*\//, "") }
    // every application that has a sub-function: the ones listed in the built-in panes plus the registered ones
    function mappedApps() {
        var out = []
        for (var key in Panes.specs) {
            var spec = Panes.specs[key]
            var a = spec.args
            if (a && a[0] === "apps")
                for (var i = 1; i < a.length; i++) { var p = String(a[i]).split("|"); out.push({ name: p[0], bin: baseBin(p[1]), cls: "", key: key }) }
            // "Open <App>" buttons that start the program of that name (not "Open Games Folder", which runs a file manager)
            var acts = spec.actions || []
            for (var n = 0; n < acts.length; n++) {
                var mt = /^Open (.+)$/.exec(String(acts[n].label))
                if (!mt || !acts[n].cmd || !acts[n].cmd.length) continue
                var b = baseBin(acts[n].cmd[0]), nm = mt[1].toLowerCase().replace(/\W/g, "")
                if (b.length < 3 || (b.indexOf(nm) < 0 && nm.indexOf(b) < 0)) continue
                out.push({ name: mt[1], bin: b, cls: "", key: key })
            }
        }
        for (var j = 0; j < Registry.apps.length; j++) {
            var r = Registry.apps[j]
            out.push({ name: r.name, bin: baseBin(r.cmd), cls: r.cls, key: r.tab + "/" + r.sub })
        }
        return out
    }
    function entryCmd(e) {
        return e.command.map(t => /[\s"']/.test(t) ? "'" + t.replace(/'/g, "'\\''") + "'" : t).join(" ")
    }
    function searchApps(q) {
        q = q.trim().toLowerCase()
        if (q === "") return []
        var list = DesktopEntries.applications.values
        var have = {}                                        // programs that are installed (they have a desktop entry)
        for (var h = 0; h < list.length; h++) if (list[h].command.length > 0) have[baseBin(list[h].command[0])] = true
        var mapped = mappedApps()
        var found = []
        var rank = function (n) { n = n.toLowerCase(); return n.indexOf(q) === 0 ? 0 : (n.indexOf(" " + q) >= 0 ? 1 : (n.indexOf(q) >= 0 ? 2 : -1)) }
        var seen = {}
        for (var i = 0; i < mapped.length; i++) {
            var m = mapped[i], rk = rank(m.name)
            if (rk < 0) continue
            if (m.cls === "" && m.bin !== "" && !have[m.bin]) continue      // listed in a pane but not installed
            // one app in several sub-functions: list the one named after it, else the first
            var nk = m.name.toLowerCase(), own = m.key.split("/")[1].toLowerCase() === nk
            var item = { name: m.name, key: m.key, loc: m.key.replace("/", " / "), rank: rk }
            if (seen[nk] === undefined) { seen[nk] = found.length; found.push(item) }
            else if (own) found[seen[nk]] = item
        }
        for (var k = 0; k < list.length; k++) {
            var e = list[k]
            if (e.noDisplay) continue
            var r2 = Math.max(rank(e.name), -1)
            if (r2 < 0 && e.genericName) r2 = rank(e.genericName) >= 0 ? 3 : -1
            if (r2 < 0) continue
            var bin = e.command.length > 0 ? baseBin(e.command[0]) : ""
            var cls = (e.startupClass || String(e.id).replace(/\.desktop$/, "")).toLowerCase()
            var dup = false
            for (var j = 0; j < mapped.length; j++)
                if ((mapped[j].cls && mapped[j].cls.toLowerCase() === cls) || (mapped[j].bin !== "" && mapped[j].bin === bin)) { dup = true; break }
            if (dup) continue
            found.push({ name: e.name, key: "", loc: "", rank: r2, cls: e.startupClass || String(e.id).replace(/\.desktop$/, ""), cmd: entryCmd(e) })
        }
        found.sort((a, b) => a.rank - b.rank || (a.key === "" ? 1 : 0) - (b.key === "" ? 1 : 0) || a.name.localeCompare(b.name))
        return found.slice(0, 8)
    }
    function searchPick(it) {
        if (it.key !== "") {
            var p = it.key.split("/")
            for (var i = 0; i < pages.length; i++) if (pages[i].label === p[0]) { page = i; break }
            if (specOf(it.key)) pane = it.key
            focusUntil = Date.now() + 8000
            return
        }
        for (var j = 0; j < promptQueue.length; j++) if (promptQueue[j].cls === it.cls) return
        promptQueue = promptQueue.concat([{ cls: it.cls, name: it.name, cmd: it.cmd }])      // not in any sub-function: ask which one
    }
    // a press anywhere outside the search box clears it (the press still goes through to what was clicked)
    MouseArea {
        anchors.fill: parent
        z: 40
        enabled: search.text !== ""
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => { search.reset(); mouse.accepted = false }
    }
    SearchBox {
        id: search
        x: Theme.frameMargin + Theme.tabInset
        y: Theme.frameMargin + Theme.pad
        z: 50
        results: root.searchApps(search.text)
        onPicked: item => root.searchPick(item)
    }

    // top menu
    TopMenu {
        id: menu
        entries: root.pages
        badges: ({ "Communication": root.unread + root.mailUnread })
        current: root.page
        onPicked: index => root.page = index
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Theme.frameMargin
        anchors.rightMargin: Theme.frameMargin
        y: Theme.menuTop
    }

    // page under the menu
    SubMenu {
        id: sub
        badges: ({ "Messages": root.unread, "Email": root.mailUnread })
        selectedName: root.pane.indexOf("/") >= 0 ? root.pane.split("/")[1] : ""
        visible: root.page >= 0
        opacity: root.page >= 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
        x: Theme.frameMargin + Theme.tabInset
        y: Theme.menuTop + menu.implicitHeight + 28
        height: Math.max(0, root.contentB - y)
        title: root.page >= 0 ? menu.entries[root.page].label.toUpperCase() : ""
        subtitle: root.page >= 0 ? menu.entries[root.page].subtitle : ""
        purpose: root.page >= 0 ? menu.entries[root.page].purpose : ""
        items: root.page >= 0 ? menu.entries[root.page].subs : []
        hiddenItems: root.page >= 0 ? Registry.hiddenSubs(menu.entries[root.page].label, menu.entries[root.page].all) : []
        onMoved: (name, delta) => Registry.move(menu.entries[root.page].label, menu.entries[root.page].all, name, delta)
        onRestored: name => Registry.restore(menu.entries[root.page].label + "/" + name)
        onActivated: name => {
            var key = menu.entries[root.page].label + "/" + name
            if (menu.entries[root.page].label === root.superLabel && name !== "Overview") {
                // an app of the list: go to its own sub-function (its window comes forward there)
                var hit = menu.entries[root.page].subs.filter(s => s.name === name)
                if (hit.length > 0 && hit[0].slug) root.gotoSlug(hit[0].slug)
                return
            }
            if (root.page >= 0 && specOf(key))
                root.pane = key                  // clicking the selected one keeps it selected
        }
    }

    // arrange the sub buttons of this menu: far right, level with the menu label
    ChipButton {
        visible: root.page >= 0 && root.pages[root.page].label !== root.superLabel
        x: root.contentR - width
        y: sub.y + 4
        text: sub.arranging ? "Done" : "Arrange"
        selected: sub.arranging
        onClicked: sub.arranging = !sub.arranging
    }

    // result window (small, next to the list)
    ConsolePane {
        id: cpane
        visible: root.pane !== ""
        x: root.paneX
        y: sub.y + sub.listTop
        width: root.paneW
        height: root.contentB - y
        name: root.pane.indexOf("/") >= 0 ? root.pane.split("/")[1] : ""
        spec: (root.pane !== "" && root.specOf(root.pane)) || ({})
        onOpenTerm: (title, cmd) => root.openInContent(title, cmd)
        onOpenApp: app => root.openApp(app)
        onOpenFm: cmd => root.openFileManager(cmd)
        onOpenViewer: cmd => root.openViewer(cmd)
        onLaunching: root.claimNext()
        onGate: (what, go) => root.gated(what, go)
        onRestoreSub: key => Registry.restore(key)
        onHideSub: { Registry.hide(root.pane); root.selectFirst() }
        onRemoveApp: (cls, title) => { Registry.remove(cls, title); if (root.specOf(root.pane) === undefined) root.selectFirst() }
    }

    // content window: the frame the terminal window is placed in
    // content frame (the terminal window is placed inside it); full screen = bigger frame on top of everything
    Item {
        id: contentFrame
        visible: root.frameOpen
        z: root.maximized ? 100 : 0
        x: root.fx
        y: root.fy
        width: root.fw
        height: root.fh

        // opaque ground when full screen, so the rest of the screen is covered
        Rectangle { anchors.fill: parent; visible: root.maximized; color: Theme.paper }
        Image {
            anchors.fill: parent
            visible: root.maximized
            source: "file://" + Quickshell.shellPath("tile.png")
            fillMode: Image.Tile
        }
        MouseArea { anchors.fill: parent; enabled: root.maximized; hoverEnabled: true }   // keep clicks off what is underneath

        Rectangle { anchors.fill: parent; color: "transparent"; border.width: 1; border.color: Theme.ink }

        Rectangle {
            id: head
            width: parent.width
            height: root.headH
            color: Theme.ink

            Text {
                x: 12
                anchors.verticalCenter: parent.verticalCenter
                text: root.appName
                color: Theme.paper
                font.family: Theme.font
                font.pixelSize: Theme.fontSize
                font.bold: true
                font.letterSpacing: 1
            }

            // right: pop out | full screen   close (the tooltip of the hovered one shows left of them)
            HeadTip {
                anchors.right: buttons.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: popBtn.active ? popBtn.tip : fsBtn.active ? fsBtn.tip : closeBtn.active ? closeBtn.tip : ""
            }
            Row {
                id: buttons
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 6

                HeadButton {
                    id: popBtn
                    visible: pop.canPop || pop.popCur
                    glyph: pop.popCur ? "\uf2d2" : "\uf08e"
                    tip: pop.popCur ? "Back to this window" : "Pop out (always on top)"
                    onClicked: pop.popCur ? pop.popBack(pop.poppedFor(root.curSlug).addr) : pop.popOut()
                }
                HeadButton {
                    id: fsBtn
                    visible: !pop.popCur
                    glyph: root.maximized ? "\uf066" : "\uf065"
                    tip: root.maximized ? "Exit full screen" : "Full screen"
                    onClicked: root.maximized = !root.maximized
                }
                Item { width: 10; height: 1 }      // keeps close apart from the others
                HeadButton {
                    id: closeBtn
                    glyph: "\uf00d"
                    danger: true
                    tip: "Close " + root.appName
                    onClicked: root.closeTerm()
                }
            }
        }

        // the app is popped out: say where it went
        Column {
            visible: pop.popCur
            anchors.centerIn: parent
            anchors.verticalCenterOffset: root.headH / 2
            spacing: 10
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "\uf08e"
                color: Theme.inkSoft
                font.family: Theme.font
                font.pixelSize: Theme.fontSize * 3
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "POPPED OUT"
                color: Theme.ink
                font.family: Theme.font
                font.pixelSize: Theme.fontSize + 2
                font.bold: true
                font.letterSpacing: 2
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.appName + " floats in its own window. Close the pop-up to bring it back here."
                color: Theme.inkSoft
                font.family: Theme.font
                font.pixelSize: Theme.fontSize - 1
            }
        }

        // the native messenger (kept alive while hidden so the open chat and scroll position stay)
        Loader {
            active: root.messengerSlug !== ""
            visible: root.messengerOpen
            x: 12
            y: root.headH + 12
            width: parent.width - 24
            height: parent.height - root.headH - 24
            sourceComponent: Messenger { client: matrix }
        }

        // the native email window (kept alive while hidden so the open mail and a half-written reply stay)
        Loader {
            active: root.emailSlug !== ""
            visible: root.emailOpen
            x: 12
            y: root.headH + 12
            width: parent.width - 24
            height: parent.height - root.headH - 24
            sourceComponent: Email { client: mail; onWebmail: addr => root.openWebmail(addr) }
        }

        // the native Bluetooth manager (kept alive while hidden; it stops a scan it started when it goes out of view)
        Loader {
            active: root.bluetoothSlug !== ""
            visible: root.bluetoothOpen
            x: 12
            y: root.headH + 12
            width: parent.width - 24
            height: parent.height - root.headH - 24
            sourceComponent: Bluetooth { agent: btAgent }
        }
    }

    // asks whether to replace the app that is already open in this sub-function
    ReplacePrompt {
        ask: root.replaceAsk
        onAccepted: root.replaceAccept()
        onCancelled: root.replaceCancel()
    }

    // asks where a blocked application belongs (centre of the screen, above everything)
    AppPrompt {
        app: root.promptApp
        suggestion: root.promptApp ? root.suggestFor(root.promptApp.cls) : null
        pages: root.basePages
        onAccepted: (menu, subName) => root.promptAccept(menu, subName)
        onDismissed: root.promptDismiss()
    }

    // description of the highlighted sub-function, at the bottom
    Item {
        visible: root.page >= 0
        opacity: root.page >= 0 ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Theme.hoverMs } }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.leftMargin: Theme.frameMargin
        anchors.rightMargin: Theme.frameMargin
        anchors.bottomMargin: Theme.frameMargin + 14
        height: 56

        Rectangle { width: parent.width; height: 2; color: Theme.ink }

        Rectangle {
            x: Theme.tabInset
            y: 20
            width: 10; height: 10
            color: Theme.ink
        }

        Text {
            x: Theme.tabInset + 24
            y: 14
            text: sub.curName
            color: Theme.ink
            font.family: Theme.font
            font.pixelSize: Theme.fontSize + 1
            font.bold: true
            font.letterSpacing: 1
        }

        Text {
            x: Theme.tabInset + 24
            y: 34
            width: 500
            elide: Text.ElideRight
            text: sub.curDesc
            color: Theme.inkSoft
            font.family: Theme.font
            font.pixelSize: Theme.fontSize
        }

        // divider | open apps | divider | system tray
        readonly property real divA: Theme.tabInset + 560
        readonly property real divB: parent.width - 260

        Rectangle { x: parent.divA; y: 12; width: 1; height: 36; color: Theme.ink }

        AppsList {
            contentApps: root.contentApps
            steamNames: root.steamNames
            managed: root.claimedCls
            extWins: root.extWins
            onWindowClicked: (addr, cls) => root.appWindowClicked(addr, cls)
            activeSlug: root.shownSlug
            onContentClicked: slug => root.gotoSlug(slug)
            onContentClosed: slug => root.closeSlug(slug)
            x: parent.divA + 20
            y: 10
            width: parent.divB - parent.divA - 40
            height: 40
        }

        Rectangle { x: parent.divB; y: 12; width: 1; height: 36; color: Theme.ink }

        TrayList {
            x: parent.divB + 20
            y: 10
            width: parent.width - parent.divB - 40
            height: 40
        }
    }
}
