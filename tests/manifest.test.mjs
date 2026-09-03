import assert from "node:assert/strict"
import { lstat, readFile, readdir } from "node:fs/promises"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")

test("manifest declares a loadable combined service and bar widget", async () => {
  const manifest = JSON.parse(await readFile(path.join(root, "manifest.json"), "utf8"))
  assert.equal(manifest.schemaVersion, 1)
  assert.equal(manifest.id, "io.github.eliasstravik.omarchy-news")
  assert.match(manifest.id, /^[A-Za-z0-9][A-Za-z0-9._-]*$/)
  assert.doesNotMatch(manifest.id, /^omarchy\./)
  assert.deepEqual(manifest.kinds, ["service", "bar-widget"])

  const entryPointForKind = { service: "service", "bar-widget": "barWidget" }
  for (const kind of manifest.kinds) {
    const entryPoint = manifest.entryPoints[entryPointForKind[kind]]
    assert.equal(typeof entryPoint, "string")
    assert.equal(path.isAbsolute(entryPoint), false)
    assert.equal(entryPoint.includes(".."), false)
    assert.equal((await lstat(path.join(root, entryPoint))).isFile(), true)
  }
})

test("repository contains no symbolic links", async () => {
  async function walk(directory) {
    for (const entry of await readdir(directory, { withFileTypes: true })) {
      if (entry.name === ".git") continue
      const target = path.join(directory, entry.name)
      assert.equal((await lstat(target)).isSymbolicLink(), false, target)
      if (entry.isDirectory()) await walk(target)
    }
  }
  await walk(root)
})
