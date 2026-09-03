import assert from "node:assert/strict"
import { createRequire } from "node:module"
import { readFile } from "node:fs/promises"
import path from "node:path"
import test from "node:test"
import { fileURLToPath } from "node:url"

const require = createRequire(import.meta.url)
const Model = require("../Model.js")
const fixture = await readFile(path.join(path.dirname(fileURLToPath(import.meta.url)), "fixtures/omarchy-news-rss.xml"), "utf8")
const posts = Model.parseFeed(fixture)

test("parseFeed reads and stably orders the saved Omarchy feed", () => {
  assert.equal(posts.length, 19)
  assert.deepEqual(posts.slice(0, 3).map(post => post.title), [
    "Omarchy Patronage is now open to everyone",
    "Omacom Foundation hires kernel developer Krzysztof Wilczyński",
    "Omacom Foundation accelerates spending goals"
  ])
  assert.equal(posts[0].author, "DHH")
  assert.equal(new Date(posts[0].publishedAt * 1000).toISOString(), "2026-09-03T00:00:00.000Z")
  assert.equal(new Date(posts[3].publishedAt * 1000).toISOString(), "2026-09-02T00:00:00.000Z")
  assert.equal(posts[0].publishedAt, posts[1].publishedAt)
})

test("parseFeed extracts the five feed images", () => {
  const withImages = posts.filter(post => post.imageUrls.length > 0)
  assert.equal(withImages.length, 5)
  assert.ok(withImages.every(post => post.imageUrls.length === 1))
  assert.equal(withImages[0].imageUrls[0], "https://omarchy.org/news/2026/08/the-first-plugin-competition-winners/plugin-winners.webp")
})

test("parseFeed decodes entities and CDATA and falls back from guid to link", () => {
  const parsed = Model.parseFeed(`
    <rss><channel><item>
      <title><![CDATA[One &amp; &#x54;wo]]></title>
      <link>https://omarchy.org/news/one</link>
      <pubDate>not a date</pubDate>
      <description><![CDATA[A &lt;small&gt; summary]]></description>
      <content:encoded><![CDATA[<p>Hello</p>]]></content:encoded>
    </item></channel></rss>`)
  assert.equal(parsed[0].key, "https://omarchy.org/news/one")
  assert.equal(parsed[0].title, "One & Two")
  assert.equal(parsed[0].summary, "A <small> summary")
  assert.equal(parsed[0].publishedAt, 0)
})

test("htmlToBlocks keeps the patronage article paragraphs and links", () => {
  const blocks = Model.htmlToBlocks(posts[0].contentHtml)
  assert.deepEqual(blocks.map(block => block.type), ["p", "p", "p", "p", "p", "p", "p"])
  assert.match(blocks[0].text, /<a href="https:\/\/omarchy\.org\/foundation\/">Omacom Foundation<\/a>/)
  assert.match(blocks[6].text, /Become a patron today/)
})

test("htmlToBlocks emits document structures and drops active content", () => {
  const blocks = Model.htmlToBlocks(`
    <h2>Heading</h2><p>Before <img src="https://omarchy.org/a.webp" alt="A"> after</p>
    <blockquote>Quoted <b>words</b></blockquote><ul><li>One</li><li>Two</li></ul>
    <ol><li>First</li></ol><pre>&lt;code&gt;</pre><hr><script><p>Bad</p></script>`)
  assert.deepEqual(blocks.map(block => block.type), ["h", "p", "img", "p", "quote", "ul", "ol", "code", "hr"])
  assert.equal(blocks[2].src, "https://omarchy.org/a.webp")
  assert.equal(blocks.some(block => JSON.stringify(block).includes("Bad")), false)
})

test("sanitizeInline keeps safe formatting and rebuilds links", () => {
  const clean = Model.sanitizeInline(`<b onclick="bad()">Bold</b> <a href="https://omarchy.org/x" onclick="bad()">safe</a> <a href="javascript:bad()">bad</a> <blink>text</blink><script>gone()</script>`)
  assert.equal(clean, `<b>Bold</b> <a href="https://omarchy.org/x">safe</a> bad text`)
  assert.equal(clean.includes("onclick"), false)
  assert.equal(clean.includes("javascript:"), false)
  assert.equal(clean.includes("gone"), false)
})

test("URL, relative time, date, image, and reading helpers cover boundaries", () => {
  const now = Date.UTC(2026, 8, 3, 12)
  assert.equal(Model.isSafeHttpUrl("https://omarchy.org/news"), true)
  assert.equal(Model.isSafeHttpUrl("http://example.test"), true)
  assert.equal(Model.isSafeHttpUrl("https://example.test/a b"), false)
  assert.equal(Model.isSafeHttpUrl("javascript:alert(1)"), false)
  assert.equal(Model.relativeTime(now / 1000 - 59, now), "now")
  assert.equal(Model.relativeTime(now / 1000 - 60, now), "1m")
  assert.equal(Model.relativeTime(now / 1000 - 3600, now), "1h")
  assert.equal(Model.relativeTime(now / 1000 - 86400, now), "1d")
  assert.equal(Model.relativeTime(now / 1000 - 604800, now), "1w")
  assert.equal(Model.relativeTime(Date.UTC(2026, 6, 1) / 1000, now), "1 Jul")
  assert.equal(Model.formatDate(Date.UTC(2026, 8, 3) / 1000), "3 Sep 2026")
  assert.equal(Model.firstImage([]), "")
  assert.equal(Model.firstImage(["https://omarchy.org/a.webp"]), "https://omarchy.org/a.webp")
  assert.equal(Model.readingTime("one two", 0), "1 min read")
  assert.equal(Model.readingTime(Array(531).fill("word").join(" "), 0), "3 min read")
})

test("validateState accepts only the persisted state shape", () => {
  const valid = { schemaVersion: 1, seen: { a: 1 }, read: {}, notified: ["a"], lastFetchAt: 2, lastOpenedAt: 3 }
  assert.equal(Model.validateState(valid), true)
  assert.equal(Model.validateState({ ...valid, schemaVersion: "1" }), false)
  assert.equal(Model.validateState({ ...valid, seen: [] }), false)
  assert.equal(Model.validateState({ ...valid, notified: [2] }), false)
  assert.equal(Model.validateState({ ...valid, lastFetchAt: -1 }), false)
})

test("mergeFetched makes first run silent without marking posts read", () => {
  const empty = { schemaVersion: 1, seen: {}, read: {}, notified: [], lastFetchAt: 0, lastOpenedAt: 0 }
  const merged = Model.mergeFetched(empty, [{ key: "a" }, { key: "b" }], true, 10)
  assert.deepEqual(merged.seen, { a: 10, b: 10 })
  assert.deepEqual(merged.read, {})
  assert.deepEqual(merged.notified, [])
  assert.equal(merged.lastFetchAt, 10)
})

test("newKeysToNotify excludes seen and previously notified posts", () => {
  const state = { seen: { a: 1 }, notified: ["b"] }
  assert.deepEqual(Model.newKeysToNotify(state, [{ key: "a" }, { key: "b" }, { key: "c" }]), ["c"])
})

test("sha1 produces stable cache keys for ASCII and Unicode URLs", () => {
  assert.equal(Model.sha1("abc"), "a9993e364706816aba3e25717850c26c9cd0d89d")
  assert.equal(Model.sha1("https://omarchy.org/å.webp"), "a0d3b9e6687626f96b70860be106741a76670cd5")
})
