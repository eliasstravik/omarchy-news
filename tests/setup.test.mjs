import assert from "node:assert/strict"
import { spawnSync } from "node:child_process"
import { chmod, mkdir, mkdtemp, readFile, readdir, stat, writeFile } from "node:fs/promises"
import { tmpdir } from "node:os"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const script = path.join(root, "bin", "omarchy-news-setup")
const pluginId = "io.github.eliasstravik.omarchy-news"
const binding = `o.bind("SUPER + ALT + N", "Omarchy News", "omarchy-shell shell toggle ${pluginId}")`
const originalBindings = [
  "-- Keep only your personal keybinding overrides here.",
  'o.bind("SUPER + SHIFT + R", "SSH", "alacritty -e ssh your-server")',
  "",
].join("\n")

// Stub `omarchy`, `omarchy-shell`, and `hyprctl` so the script's decisions can
// be exercised without an Omarchy session. Each stub records every call and
// reads flag files from $STUB_STATE to fake enabled state, discovery, key
// conflicts, and Hyprland config errors.
const stubs = {
  omarchy: `#!/usr/bin/env bash
echo "omarchy $*" >> "$STUB_LOG"
case "$1 $2" in
  "plugin list")
    if [[ -f $STUB_STATE/missing ]]; then echo '[]'; exit 0; fi
    enabled=false; [[ -f $STUB_STATE/enabled ]] && enabled=true
    printf '[{"id":"${pluginId}","kinds":["service","bar-widget"],"enabled":%s}]\\n' "$enabled" ;;
  "plugin enable") touch "$STUB_STATE/enabled"; echo "Enabled $3" ;;
  *) echo "unexpected omarchy call: $*" >&2; exit 1 ;;
esac
`,
  "omarchy-shell": `#!/usr/bin/env bash
[[ $1 == -q ]] && shift
echo "omarchy-shell $*" >> "$STUB_LOG"
case "$1 $2" in
  "shell ping") echo ok ;;
  "shell rescanPlugins") ;;
  "${pluginId} status") echo '{"state":"ready","fetching":false,"posts":19,"unseen":0,"unread":11,"lastFetchAt":1,"error":""}' ;;
  *) echo "unexpected omarchy-shell call: $*" >&2; exit 1 ;;
esac
`,
  hyprctl: `#!/usr/bin/env bash
echo "hyprctl $*" >> "$STUB_LOG"
case "$1" in
  reload) echo ok ;;
  configerrors) [[ -f $STUB_STATE/configerror ]] && echo "config error in file bindings.lua at line 4: unknown key" ; echo ;;
  binds) if [[ -f $STUB_STATE/conflict ]]; then echo '[{"key":"N","modmask":72,"description":"Notes"}]'; else echo '[]'; fi ;;
  *) echo "unexpected hyprctl call: $*" >&2; exit 1 ;;
esac
`,
}

async function sandbox({ enabled = true, missing = false, conflict = false, configerror = false, bindings = originalBindings } = {}) {
  const home = await mkdtemp(path.join(tmpdir(), "omarchy-news-setup-"))
  const stubDir = path.join(home, "stubs")
  const state = path.join(home, "stub-state")
  await mkdir(stubDir)
  await mkdir(state)
  await mkdir(path.join(home, ".config", "hypr"), { recursive: true })
  for (const [name, body] of Object.entries(stubs)) {
    const file = path.join(stubDir, name)
    await writeFile(file, body)
    await chmod(file, 0o755)
  }
  if (bindings !== null) await writeFile(path.join(home, ".config", "hypr", "bindings.lua"), bindings)
  for (const [flag, on] of Object.entries({ enabled, missing, conflict, configerror })) {
    if (on) await writeFile(path.join(state, flag), "")
  }
  return { home, stubDir, state, bindingsPath: path.join(home, ".config", "hypr", "bindings.lua") }
}

function run(box, { args = [], input = "" } = {}) {
  const result = spawnSync("bash", [script, ...args], {
    input,
    encoding: "utf8",
    env: {
      PATH: `${box.stubDir}:${process.env.PATH}`,
      HOME: box.home,
      STUB_LOG: path.join(box.home, "stub.log"),
      STUB_STATE: box.state,
      HYPRLAND_INSTANCE_SIGNATURE: "test",
      NO_COLOR: "1",
    },
  })
  return { ...result, output: result.stdout + result.stderr }
}

async function calls(box) {
  try {
    return await readFile(path.join(box.home, "stub.log"), "utf8")
  } catch {
    return ""
  }
}

async function backups(box) {
  return (await readdir(path.dirname(box.bindingsPath))).filter(name => name.startsWith("bindings.lua.") && name.endsWith(".bak"))
}

test("setup script is executable and never downloads, elevates, or pipes into a shell", async () => {
  assert.ok((await stat(script)).mode & 0o111, "bin/omarchy-news-setup must be executable")
  const source = await readFile(script, "utf8")
  const code = source.split("\n").filter(line => !line.trimStart().startsWith("#")).join("\n")
  for (const forbidden of ["curl", "wget", "sudo", "| sh", "| bash", "eval "]) {
    assert.equal(code.includes(forbidden), false, `setup must not contain ${JSON.stringify(forbidden)}`)
  }
  const readme = await readFile(path.join(root, "README.md"), "utf8")
  assert.ok(readme.includes(binding), "README must document the exact binding setup writes")
  assert.ok(readme.includes("bin/omarchy-news-setup"), "README must tell users where setup lives")
})

test("declining the keybinding leaves bindings.lua untouched and still succeeds", async () => {
  const box = await sandbox()
  const result = run(box, { input: "n\n" })
  assert.equal(result.status, 0, result.output)
  assert.equal(await readFile(box.bindingsPath, "utf8"), originalBindings)
  assert.deepEqual(await backups(box), [])
  assert.match(result.output, /skipped at your request/)
  assert.doesNotMatch(await calls(box), /omarchy plugin enable/)
})

test("a typed yes appends the binding once after a byte-identical backup", async () => {
  const box = await sandbox()
  const result = run(box, { input: "y\n" })
  assert.equal(result.status, 0, result.output)
  assert.equal(await readFile(box.bindingsPath, "utf8"), `${originalBindings}\n${binding}\n`)
  const [backup, ...extra] = await backups(box)
  assert.equal(extra.length, 0)
  assert.equal(await readFile(path.join(path.dirname(box.bindingsPath), backup), "utf8"), originalBindings)
  const log = await calls(box)
  assert.match(log, /hyprctl reload/)
  assert.match(log, /hyprctl configerrors/)
  assert.match(result.output, /Next:.*SUPER \+ ALT \+ N/)
})

test("an empty answer without a terminal does not count as consent", async () => {
  const box = await sandbox()
  const result = run(box, { input: "" })
  assert.equal(result.status, 0, result.output)
  assert.equal(await readFile(box.bindingsPath, "utf8"), originalBindings)
  assert.match(result.output, /no terminal to ask.*--yes/)
})

test("--yes accepts the keybinding unattended", async () => {
  const box = await sandbox()
  const result = run(box, { args: ["--yes"], input: "" })
  assert.equal(result.status, 0, result.output)
  assert.equal(await readFile(box.bindingsPath, "utf8"), `${originalBindings}\n${binding}\n`)
  assert.doesNotMatch(result.output, /\[Y\/n\]/)
})

test("--skip-keybinding never asks and never writes", async () => {
  const box = await sandbox()
  const result = run(box, { args: ["--skip-keybinding"], input: "y\n" })
  assert.equal(result.status, 0, result.output)
  assert.equal(await readFile(box.bindingsPath, "utf8"), originalBindings)
  assert.doesNotMatch(result.output, /\[Y\/n\]/)
  assert.match(result.output, /--skip-keybinding/)
})

test("a second run recognises the existing binding and does not ask again", async () => {
  const box = await sandbox({ bindings: `${originalBindings}\n${binding}\n` })
  const result = run(box, { input: "y\n" })
  assert.equal(result.status, 0, result.output)
  assert.equal(await readFile(box.bindingsPath, "utf8"), `${originalBindings}\n${binding}\n`)
  assert.deepEqual(await backups(box), [])
  assert.doesNotMatch(result.output, /\[Y\/n\]/)
  assert.match(result.output, /already/)
})

test("a rejected config is rolled back to the backup and reported", async () => {
  const box = await sandbox({ configerror: true })
  const result = run(box, { input: "y\n" })
  assert.equal(result.status, 1, result.output)
  assert.equal(await readFile(box.bindingsPath, "utf8"), originalBindings)
  assert.equal((await backups(box)).length, 1)
  assert.match(result.output, /restored/)
  assert.equal((await calls(box)).match(/hyprctl reload/g).length, 2, "reload after write and after rollback")
})

test("an already-bound key is called out and defaults to no", async () => {
  const box = await sandbox({ conflict: true })
  const result = run(box, { input: "\n" })
  assert.equal(result.status, 0, result.output)
  assert.equal(await readFile(box.bindingsPath, "utf8"), originalBindings)
  assert.match(result.output, /already bound: Notes/)
  assert.match(result.output, /\[y\/N\]/)
})

test("a disabled plugin is enabled before the keybinding step", async () => {
  const box = await sandbox({ enabled: false })
  const result = run(box, { input: "n\n" })
  assert.equal(result.status, 0, result.output)
  const log = await calls(box)
  assert.match(log, new RegExp(`omarchy plugin enable ${pluginId.replaceAll(".", "\\.")}`))
  assert.ok(log.indexOf("plugin enable") < log.indexOf(`${pluginId} status`), "enable must precede the service check")
})

test("a missing plugin stops before any change with the install command", async () => {
  const box = await sandbox({ missing: true })
  const result = run(box, { args: ["--yes"] })
  assert.equal(result.status, 1)
  assert.match(result.output, /omarchy plugin add https:\/\/github\.com\/eliasstravik\/omarchy-news/)
  assert.equal(await readFile(box.bindingsPath, "utf8"), originalBindings)
})

test("a missing bindings.lua is skipped without failing", async () => {
  const box = await sandbox({ bindings: null })
  const result = run(box, { args: ["--yes"] })
  assert.equal(result.status, 0, result.output)
  assert.match(result.output, /does not exist/)
})
