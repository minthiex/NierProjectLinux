import Quickshell
import QtQuick

// What the search box (top left) finds: applications (mapped to their sub-function, or installed but not in any),
// sub-functions and menus. One instance in NierScreen (id finder); pages = NierScreen.basePages (hidden ones are not in it).
//   search(q) -> up to 10 results [{ name, key, loc, kind, rank, cls?, cmd? }]   kind: "" app | "function" | "menu"
QtObject {
    id: finder
    required property var pages

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
    function search(q) {
        q = q.trim().toLowerCase()
        if (q === "") return []
        var list = DesktopEntries.applications.values
        var have = {}                                        // programs that are installed (they have a desktop entry)
        for (var h = 0; h < list.length; h++) if (list[h].command.length > 0) have[baseBin(list[h].command[0])] = true
        var mapped = mappedApps()
        var found = []
        // compared without punctuation, so "wifi" finds "Wi-Fi" and "self check" finds "Self Check"
        var norm = function (s) { return String(s).toLowerCase().replace(/[^a-z0-9 ]+/g, "") }
        var nq = norm(q)
        var rank = function (n) { n = norm(n); return nq === "" ? -1 : n.indexOf(nq) === 0 ? 0 : (n.indexOf(" " + nq) >= 0 ? 1 : (n.indexOf(nq) >= 0 ? 2 : -1)) }
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
        // the menus themselves: tabs and the sub-functions in them (hidden ones are not in pages), by name and,
        // weaker, by their description. A pick goes there like an app result does.
        var taken = {}, leads = {}
        found.forEach(f => { if (f.key !== "") { taken[f.key + "|" + f.name.toLowerCase()] = true; leads[f.key] = true } })
        for (var t = 0; t < pages.length; t++) {
            var pg = pages[t]
            if (pg.subs.length === 0) continue
            var rt = rank(pg.label)
            if (rt >= 0) found.push({ name: pg.label, key: pg.label + "/" + pg.subs[0].name, loc: "menu", kind: "menu", rank: rt })
            for (var u = 0; u < pg.subs.length; u++) {
                var sb = pg.subs[u], key = pg.label + "/" + sb.name
                if (taken[key + "|" + sb.name.toLowerCase()]) continue          // an app of that name already leads there
                var rs = rank(sb.name)
                // a match in the description only counts if no app result already leads there ("fire": Firefox, not also Browser)
                if (rs < 0 && nq.length >= 3 && sb.desc && rank(sb.desc) >= 0 && !leads[key]) rs = 4
                if (rs >= 0) found.push({ name: sb.name, key: key, loc: pg.label, kind: "function", rank: rs })
            }
        }
        found.sort((a, b) => a.rank - b.rank || (a.key === "" ? 1 : 0) - (b.key === "" ? 1 : 0) || a.name.localeCompare(b.name))
        return found.slice(0, 10)
    }
}
