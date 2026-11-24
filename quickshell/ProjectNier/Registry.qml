pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Applications the user has assigned to a menu and sub-function (stored in ~/.local/share/ProjectNier/apps.json),
// merged into the menus at run time. An app that is not part of a sub-function may not open at all.
QtObject {
    id: root

    readonly property string file: Quickshell.env("HOME") + "/.local/share/ProjectNier/apps.json"
    property var apps: []                 // [{ cls, name, cmd, tab, sub }]
    property var hidden: []               // ["Menu/Sub"] sub-functions taken out of their menu
    property var removed: []              // ["Menu/Sub"] built-in sub-functions removed for good (not even restorable)
    property var order: ({})              // menu -> [sub names] in the user's order

    // system dialogs that must be able to appear (authentication, file pickers, ...)
    readonly property var systemClasses: ["xdg-desktop-portal", "org.freedesktop.impl.portal", "hyprpolkitagent",
        "polkit", "org.kde.polkit", "hyprland-run", "hyprland-dialog", "org.hyprland"]

    // the file is watched: an edit made outside the shell is picked up (instead of being overwritten by the
    // next save from memory)
    property var store: FileView {
        path: root.file
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.parse()
    }

    Component.onCompleted: parse()

    // a file that is half written or broken keeps what is already loaded
    property string lastText: ""
    property var ownTexts: []             // our own writes not yet seen back by the watcher (oldest first)
    function parse() {
        var t = store.text()
        // the watcher reporting one of our own writes (maybe an older one, when several saves were quick): not an edit
        var k = ownTexts.indexOf(t)
        if (k >= 0) { ownTexts = ownTexts.slice(k + 1); return }
        if (t === lastText) return
        try {
            var d = JSON.parse(t)
            lastText = t
            apps = d.apps || []
            hidden = d.hidden || []
            removed = d.removed || []
            order = d.order || ({})
        } catch (e) {}
    }

    // written through the FileView itself: atomic, and in order (separate writer processes could finish out of order
    // and an older state would win). lastText makes the watcher ignore our own write.
    function save() {
        lastText = JSON.stringify({ apps: apps, hidden: hidden, removed: removed, order: order })
        ownTexts = ownTexts.concat([lastText]).slice(-32)
        store.waitForJob()                  // a write still in progress would swallow this one (tested: quick ▲/▼ clicks)
        store.setText(lastText)
    }

    function isSystem(cls) {
        for (var i = 0; i < systemClasses.length; i++) if (String(cls).indexOf(systemClasses[i]) === 0) return true
        return false
    }

    // one app can show up under two window classes ("keepassxc" and its Wayland id "org.keepassxc.KeePassXC"):
    // compare without case and by the last part of a reverse-DNS name
    function classKey(cls) {
        var c = String(cls).toLowerCase()
        return (c.match(/\./g) || []).length >= 2 ? c.replace(/^.*\./, "") : c
    }
    function sameClass(a, b) { return String(a) === String(b) || classKey(a) === classKey(b) }
    // toolkit classes many unrelated programs share (every Tkinter script is "Tk"): an app registered under one of
    // them also stores its window title, and only a window with that title is that app
    readonly property var genericClasses: ["tk", "toplevel", "python", "python3", "java", "electron", "wine"]
    function isGeneric(cls) { return genericClasses.indexOf(String(cls).toLowerCase()) >= 0 }
    function titleFits(a, title) { return !a.title || !isGeneric(a.cls) || a.title === title }
    function byClass(cls, title) {
        for (var i = 0; i < apps.length; i++) if (apps[i].cls === cls && titleFits(apps[i], title)) return apps[i]
        for (var j = 0; j < apps.length; j++) if (sameClass(apps[j].cls, cls) && titleFits(apps[j], title)) return apps[j]
        return null
    }

    function add(app) {
        var out = apps.filter(a => !(sameClass(a.cls, app.cls) && (!isGeneric(app.cls) || (a.title || "") === (app.title || ""))))
        out.push(app)
        apps = out
        save()
    }

    function remove(cls, title) {
        apps = apps.filter(a => !(a.cls === cls && (!title || (a.title || "") === title)))
        save()
    }

    function isHidden(key) { return hidden.indexOf(key) >= 0 }
    function hide(key) { if (!isHidden(key)) { hidden = hidden.concat([key]); save() } }
    function restore(key) { hidden = hidden.filter(k => k !== key); save() }
    function isRemoved(key) { return removed.indexOf(key) >= 0 }
    // remove a hidden sub-function for good: one made by registered apps loses those apps (their windows are asked
    // about again), a built-in one goes on the removed list (apps.json "removed": delete the entry to get it back)
    function removeSub(key) {
        var tab = key.split("/")[0], sub = key.substring(key.indexOf("/") + 1)
        var page = Pages.list.filter(p => p.label === tab)[0]
        var builtin = page !== undefined && page.subs.some(s => s.name === sub)
        hidden = hidden.filter(k => k !== key)
        apps = apps.filter(a => !(a.tab === tab && a.sub === sub))
        if (builtin && !isRemoved(key)) removed = removed.concat([key])
        if (order[tab]) {
            var o = Object.assign({}, order)
            o[tab] = o[tab].filter(n => n !== sub)
            order = o
        }
        save()
    }

    // what the "Restore Functions" sub-function shows: one button per hidden sub-function (click: bring it back,
    // its "\u2212": remove it for good)
    readonly property string restoreName: "Restore Functions"
    function restoreSpec() {
        var keys = hidden.filter(k => !isRemoved(k))
        return {
            rows: [["HIDDEN", keys.length === 0 ? "nothing: every sub-function is shown"
                                                : keys.length + (keys.length === 1 ? " sub-function" : " sub-functions")]]
                  .concat(keys.length > 0 ? [["CLICK", "restore    \u2212  remove for good"]] : []),
            actions: keys.map(k => ({ label: "Restore " + k.substring(k.indexOf("/") + 1) + "  \u00b7  " + k.split("/")[0],
                                      restoreKey: k, removeKey: k }))
        }
    }

    // the visible sub-functions of a menu, in the user's order (new ones go last)
    function arrange(tab, subs) {
        var vis = subs.filter(s => !isHidden(tab + "/" + s.name) && !isRemoved(tab + "/" + s.name))
        var o = order[tab] || []
        return vis.map((s, i) => ({ s: s, r: o.indexOf(s.name) >= 0 ? o.indexOf(s.name) : o.length + i }))
                  .sort((a, b) => a.r - b.r).map(x => x.s)
    }
    function hiddenSubs(tab, subs) { return subs.filter(s => isHidden(tab + "/" + s.name) && !isRemoved(tab + "/" + s.name)) }
    // move a sub-function up (-1) or down (+1) among the visible ones
    function move(tab, subs, name, delta) {
        var names = arrange(tab, subs).map(s => s.name)
        var i = names.indexOf(name), j = i + delta
        if (i < 0 || j < 0 || j >= names.length) return
        names.splice(j, 0, names.splice(i, 1)[0])
        var o = Object.assign({}, order)
        o[tab] = names
        order = o
        save()
    }

    // sub-functions (beyond the built-in ones) that registered apps add to a menu
    function subsFor(tab, builtin) {
        var seen = {}, out = []
        for (var b = 0; b < (builtin || []).length; b++) seen[builtin[b].name] = true
        for (var i = 0; i < apps.length; i++) {
            if (apps[i].tab !== tab || seen[apps[i].sub]) continue
            seen[apps[i].sub] = true
            out.push({ name: apps[i].sub, desc: "Added applications" })
        }
        return out
    }

    // what the result window shows for a sub-function that has registered apps
    function specFor(key) {
        var p = key.split("/")
        var mine = apps.filter(a => a.tab === p[0] && a.sub === p[1])
        if (mine.length === 0) return undefined
        return {
            rows: mine.map(a => ["APPLICATION", a.name]).concat([["OPENS IN", "the content window"]]),
            actions: mine.map(a => ({ label: "Open " + a.name, cmd: ["sh", "-c", a.cmd], launch: true, removeCls: a.cls, removeTitle: a.title || "" }))
        }
    }
}
