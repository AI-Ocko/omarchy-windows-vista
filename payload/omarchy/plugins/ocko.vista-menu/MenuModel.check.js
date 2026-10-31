// node omarchy/plugins/ocko.vista-menu/MenuModel.check.js
// Self-check for the Vista helpers in MenuModel.js, against the real menu JSONC.
const assert = require("assert")
const fs = require("fs")
const M = require("./MenuModel.js")

const omarchy = process.env.OMARCHY_PATH || "/usr/share/omarchy"
const raw = fs.readFileSync(omarchy + "/default/omarchy/omarchy-menu.jsonc", "utf8")
const menu = M.mergeMenuSources(M.parseMenuJsonc(raw), [])

const apps = M.mergeAppRows(menu.items, menu.itemOrder, [
  M.appRow({ id: "firefox", keywords: ["web"] }, "Firefox", "Web Browser"),
])

// Ranking: a query finds its menu entry first, apps are searchable, and an
// empty query or a `when:` that evaluated false yields nothing.
const theme = M.searchRows(apps.items, apps.itemOrder, {}, "theme")
assert.ok(theme.length > 0 && /theme/i.test(theme[0].label), "theme -> " + (theme[0] || {}).label)
assert.strictEqual(M.searchRows(apps.items, apps.itemOrder, {}, "fire")[0].id, "apps.firefox")
assert.deepStrictEqual(M.searchRows(apps.items, apps.itemOrder, {}, "  "), [])
const guarded = Object.assign({}, apps.items)
guarded[theme[0].id] = Object.assign({}, theme[0], { when: "false" })
const hidden = {}; hidden[theme[0].id] = false
assert.ok(M.searchRows(guarded, apps.itemOrder, hidden, "theme").every(e => e.id !== theme[0].id))
assert.deepStrictEqual(M.searchRows(apps.items, apps.itemOrder, {}, "zzqqxx"), [])

const g = M.parseGuardOutput("style.theme:w:1\nsetup.dns:c:0\nbogus\n")
assert.deepStrictEqual(g, { when: { "style.theme": true }, checked: { "setup.dns": false } })

assert.strictEqual(M.vistaCommand("omarchy-launch-screensaver force", "/h"), "'/h/.config/omarchy/vista/bin/vista-screensaver' force")
assert.strictEqual(M.vistaCommand("omarchy-theme-set x", "/h"), "omarchy-theme-set x")
assert.strictEqual(M.vistaIconId("style.theme", "menu", ""), 185)
assert.strictEqual(M.vistaIconId("nothing", "action", ""), 3)

console.log("MenuModel Vista helpers: ok (theme -> " + theme[0].id + ")")
