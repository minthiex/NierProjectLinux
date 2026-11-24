import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import QtQuick

// Pop-out: a sub-function's app window floats on top of everything (every page, every workspace), can be moved and
// resized; closing the pop-up puts the window back in its content window. One instance lives in NierScreen (id pop);
// each popped window gets a PopupFrame (title bar + resize grip) that talks to this object.
//   qs -c ProjectNier ipc call popup toggle      pop the shown app out, or put the current page's pop-up back
Scope {
    id: pop
    required property var view                   // NierScreen

    property var popped: []          // [{ slug, addr, name, sel, term }]
    property var popGeo: ({})        // addr -> { x, y, w, h, fs } of a popped window (polled)
    property var unpinNext: []       // windows just put back: the next placement (NierScreen.syncTerm) unpins them first
    readonly property int headH: view.headH

    function poppedFor(slug) {
        for (var i = 0; i < popped.length; i++) if (popped[i].slug === slug) return popped[i]
        return null
    }
    readonly property bool popCur: view.curSlug !== "" && poppedFor(view.curSlug) !== null
    // only real app / terminal windows can float on their own (the built-in apps are drawn by the shell)
    readonly property bool canPop: view.termOpen && !view.messengerOpen && !view.emailOpen && !view.bluetoothOpen && !popCur

    function popOut() {
        var s = view.curSlug
        if (!canPop) return
        var addr = "", term = false
        var ext = view.extWins.filter(w => w.slug === s)
        if (ext.length > 0) addr = ext[ext.length - 1].addr          // the shown one is the newest
        else {
            var h = Hyprland.toplevels.values
            for (var i = 0; i < h.length; i++)
                if (h[i].title === "projectnier-term:" + s) { addr = String(h[i].address).replace(/^0x/, ""); term = true }
        }
        if (addr === "") return
        var sl = 'window = "address:0x' + addr + '"'
        var b = view.frameBox()
        if (view.maximized) { b.w = Math.round(b.w * 0.6); b.h = Math.round(b.h * 0.6) }
        var g = { w: Math.round(b.w * 0.8), h: Math.round(b.h * 0.8), fs: false }
        g.x = Math.round((view.width - g.w) / 2)
        g.y = Math.round((view.height - g.h + headH) / 2)
        popped = popped.concat([{ slug: s, addr: addr, name: view.appName, sel: sl, term: term }])
        var pg = Object.assign({}, popGeo); pg[addr] = g; popGeo = pg
        view.maximized = false
        var ws = Hyprland.focusedWorkspace ? Hyprland.focusedWorkspace.id : 1
        view.releaseKeys()
        Quickshell.execDetached(["hyprctl", "--batch", [
            'dispatch hl.dsp.window.float({ ' + sl + ', action = "enable" })',
            'dispatch hl.dsp.window.fullscreen({ ' + sl + ', action = "unset" })',
            'dispatch hl.dsp.window.move({ workspace = "' + ws + '", follow = false, ' + sl + ' })',
            'dispatch hl.dsp.window.pin({ ' + sl + ', action = "enable" })'].concat(popProps(sl, true)).concat([
            'dispatch hl.dsp.window.resize({ ' + sl + ', x = ' + g.w + ', y = ' + g.h + ' })',
            'dispatch hl.dsp.window.move({ ' + sl + ', x = ' + g.x + ', y = ' + g.y + ' })',
            'dispatch hl.dsp.focus({ ' + sl + ' })']).join(" ; ")])
    }
    // close the pop-up: the window goes back to its sub-function (shown there if that page is open, else hidden)
    function popBack(addr) {
        var p = popped.filter(x => x.addr === addr)
        if (p.length === 0) return
        if (drag && drag.addr === addr) drag = null
        popped = popped.filter(x => x.addr !== addr)
        var pg = Object.assign({}, popGeo); delete pg[addr]; popGeo = pg
        var mv = Object.assign({}, popMoving); delete mv[addr]; popMoving = mv
        unpinNext = unpinNext.concat([p[0].sel])
        if (p[0].slug === view.curSlug) view.focusUntil = Date.now() + 8000
        view.syncTerm()
    }
    function forgetPopped(addr) {
        if (!popped.some(x => x.addr === addr)) return
        if (drag && drag.addr === addr) drag = null
        popped = popped.filter(x => x.addr !== addr)
        var pg = Object.assign({}, popGeo); delete pg[addr]; popGeo = pg
    }

    // where the popped windows are now (the user may also move / resize them with SUPER + mouse). Read in-process
    // from Hyprland every 50 ms; while a window's place keeps changing its bars are hidden (they cannot follow a
    // window frame by frame), its Hyprland-drawn border frames it the whole time.
    property var popMoving: ({})     // addr -> true while that window is being moved / resized
    function toplevelOf(addr) {
        var h = Hyprland.toplevels.values
        for (var i = 0; i < h.length; i++) if (String(h[i].address).replace(/^0x/, "") === addr) return h[i]
        return null
    }
    Timer {
        interval: 50
        repeat: true
        running: pop.popped.length > 0
        onTriggered: {
            var pg = {}, moved = false
            pop.popped.forEach(p => {
                var t = pop.toplevelOf(p.addr), o = t ? t.lastIpcObject : null
                var old = pop.popGeo[p.addr]
                if (pop.drag && pop.drag.addr === p.addr) { pg[p.addr] = old; return }
                if (!o || !o.at || !o.size) { pg[p.addr] = old; return }
                var g = { x: o.at[0], y: o.at[1], w: o.size[0], h: o.size[1], fs: o.fullscreen !== 0 && o.fullscreen !== undefined }
                if (old && (g.x !== old.x || g.y !== old.y || g.w !== old.w || g.h !== old.h)) {
                    moved = true
                    var mv = Object.assign({}, pop.popMoving); mv[p.addr] = true; pop.popMoving = mv
                }
                pg[p.addr] = g
            })
            if (JSON.stringify(pg) !== JSON.stringify(pop.popGeo)) pop.popGeo = pg
            if (moved) settleTimer.restart()
            Hyprland.refreshToplevels()
        }
    }
    // the window has kept still for a moment: show its bars again
    Timer { id: settleTimer; interval: 250; onTriggered: if (!pop.drag) pop.popMoving = ({}) }

    // moving / resizing from the pop-up's own title bar and corner grip. The bar stays where it was pressed (hidden),
    // so the pointer's offset from the press is exactly how far to move; the window follows once per frame.
    property var drag: null          // { addr, mode: move | resize, g0, g }
    function beginDrag(addr, mode) {
        if (!popGeo[addr]) return
        var g0 = Object.assign({}, popGeo[addr])
        drag = { addr: addr, mode: mode, g0: g0, g: Object.assign({}, g0) }
        var mv = Object.assign({}, popMoving); mv[addr] = true; popMoving = mv
    }
    function dragBy(dx, dy) {
        var d = drag
        if (!d) return
        var g0 = d.g0, g = Object.assign({}, g0)
        if (d.mode === "move") {
            g.x = Math.round(Math.max(-g0.w + 120, Math.min(view.width - 120, g0.x + dx)))
            g.y = Math.round(Math.max(headH, Math.min(view.height - 40, g0.y + dy)))
        } else {
            g.w = Math.round(Math.max(320, Math.min(view.width - g0.x, g0.w + dx)))
            g.h = Math.round(Math.max(180, Math.min(view.height - g0.y - 10, g0.h + dy)))
        }
        d.g = g
        if (!dragFlush.running) dragFlush.start()
    }
    function applyDrag(d) {
        var sl = 'window = "address:0x' + d.addr + '"', g = d.g, cur = d.sent || d.g0
        if (g.w !== cur.w || g.h !== cur.h) Hyprland.dispatch('hl.dsp.window.resize({ ' + sl + ', x = ' + g.w + ', y = ' + g.h + ' })')
        if (g.x !== cur.x || g.y !== cur.y || g.w !== cur.w || g.h !== cur.h)
            Hyprland.dispatch('hl.dsp.window.move({ ' + sl + ', x = ' + g.x + ', y = ' + g.y + ' })')   // a resize keeps the centre
        d.sent = Object.assign({}, g)
    }
    Timer { id: dragFlush; interval: 16; onTriggered: if (pop.drag) pop.applyDrag(pop.drag) }
    function endDrag() {
        var d = drag
        if (!d) return
        applyDrag(d)
        drag = null
        var pg = Object.assign({}, popGeo); pg[d.addr] = Object.assign({ fs: false }, d.g); popGeo = pg
        settleTimer.restart()
    }

    // the Hyprland-drawn frame of a popped window (its colour comes from the theme)
    readonly property int popBorder: 3
    function popProps(sl, on) {
        var c = "rgb(" + String(Theme.ink).replace("#", "") + ")"
        return [["border_size", on ? String(popBorder) : "unset"], ["active_border_color", on ? c : "unset"],
                ["inactive_border_color", on ? c : "unset"], ["rounding", on ? "0" : "unset"]]
               .map(p => 'dispatch hl.dsp.window.set_prop({ ' + sl + ', prop = "' + p[0] + '", value = "' + p[1] + '" })')
    }

    IpcHandler {
        target: "popup"
        function toggle(): void {
            if (pop.popCur) pop.popBack(pop.poppedFor(pop.view.curSlug).addr)
            else pop.popOut()
        }
    }
    Variants {
        model: pop.popped
        PopupFrame { view: pop }
    }
}
