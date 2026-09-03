// Pure RSS, article, and persistence helpers shared by QML and node tests.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

function asText(value) {
  return value === undefined || value === null ? "" : String(value)
}

function unwrapCdata(value) {
  var text = asText(value).trim()
  var match = text.match(/^<!\[CDATA\[([\s\S]*)\]\]>$/)
  return match ? match[1] : text
}

function decodeEntities(value) {
  var named = { amp: "&", lt: "<", gt: ">", quot: "\"", apos: "'", "#39": "'" }
  return asText(value).replace(/&(#x[0-9a-f]+|#[0-9]+|amp|lt|gt|quot|apos|#39);/gi, function(entity, code) {
    var key = code.toLowerCase()
    if (Object.prototype.hasOwnProperty.call(named, key)) return named[key]
    var number = key.indexOf("#x") === 0 ? parseInt(key.slice(2), 16) : parseInt(key.slice(1), 10)
    if (!isFinite(number) || number < 0 || number > 0x10ffff) return entity
    try {
      return String.fromCodePoint(number)
    } catch (error) {
      return entity
    }
  })
}

function escapeText(value) {
  return asText(value)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/\"/g, "&quot;")
    .replace(/'/g, "&#39;")
}

function stripUnsafeContainers(html) {
  return asText(html).replace(/<(script|style|iframe|svg)\b[^>]*>[\s\S]*?<\/\1\s*>/gi, "")
}

function stripTags(html) {
  return decodeEntities(stripUnsafeContainers(html).replace(/<br\s*\/?\s*>/gi, "\n").replace(/<[^>]*>/g, ""))
}

function compactWhitespace(value) {
  return asText(value).replace(/\r/g, "").replace(/[ \t\f\v]+/g, " ").replace(/ *\n */g, "\n").trim()
}

function field(itemXml, name) {
  var escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  var match = asText(itemXml).match(new RegExp("<" + escaped + "(?:\\s[^>]*)?>([\\s\\S]*?)<\\/" + escaped + "\\s*>", "i"))
  return match ? unwrapCdata(match[1]) : ""
}

function attribute(tag, name) {
  var escaped = name.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
  var match = asText(tag).match(new RegExp("\\b" + escaped + "\\s*=\\s*([\"'])([\\s\\S]*?)\\1", "i"))
  return match ? decodeEntities(match[2]) : ""
}

function isSafeHttpUrl(url) {
  var text = asText(url)
  return text !== "" && !/[\u0000-\u0020\u007f]/.test(text) && /^https?:\/\/[^/?#]+(?:[/?#]|$)/i.test(text)
}

function imageUrlsFromHtml(html) {
  var urls = []
  var seen = {}
  var image
  var matcher = /<img\b[^>]*>/gi
  while ((image = matcher.exec(stripUnsafeContainers(html))) !== null && urls.length < 6) {
    var src = attribute(image[0], "src")
    var lower = src.toLowerCase()
    if (!/^https:\/\//i.test(src) || /(?:1x1|pixel|\.gif(?:[?#]|$))/.test(lower) || seen[src]) continue
    seen[src] = true
    urls.push(src)
  }
  return urls
}

function readingTime(text, imageCount) {
  var words = compactWhitespace(stripTags(text)).split(/\s+/).filter(function(word) { return word !== "" }).length
  var images = Math.max(0, Math.floor(Number(imageCount) || 0))
  var seconds = words / 265 * 60
  for (var i = 0; i < images; i++) seconds += Math.max(3, 12 - i)
  return Math.max(1, Math.ceil(seconds / 60)) + " min read"
}

function parseFeed(xml) {
  var posts = []
  var item
  var matcher = /<item(?:\s[^>]*)?>([\s\S]*?)<\/item\s*>/gi
  var order = 0
  while ((item = matcher.exec(asText(xml))) !== null) {
    var body = item[1]
    var link = compactWhitespace(stripTags(field(body, "link")))
    var guid = compactWhitespace(stripTags(field(body, "guid")))
    var contentHtml = field(body, "content:encoded")
    var description = field(body, "description")
    var date = Date.parse(compactWhitespace(stripTags(field(body, "pubDate"))))
    var imageUrls = imageUrlsFromHtml(contentHtml)
    posts.push({
      key: guid || link,
      title: compactWhitespace(stripTags(field(body, "title"))),
      link: link,
      author: compactWhitespace(stripTags(field(body, "dc:creator"))),
      publishedAt: isFinite(date) ? Math.floor(date / 1000) : 0,
      summary: compactWhitespace(stripTags(description)),
      contentHtml: contentHtml,
      imageUrls: imageUrls,
      readingMinutes: readingTime(contentHtml, imageUrls.length),
      _feedOrder: order++
    })
  }
  posts.sort(function(a, b) {
    return b.publishedAt - a.publishedAt || a._feedOrder - b._feedOrder
  })
  for (var i = 0; i < posts.length; i++) delete posts[i]._feedOrder
  return posts
}

function pushTextBlock(blocks, type, html, extra) {
  var content = compactWhitespace(html)
  if (compactWhitespace(stripTags(content)) === "") return
  var block = { type: type, text: content }
  if (extra) for (var key in extra) block[key] = extra[key]
  blocks.push(block)
}

function pushImageSplit(blocks, html, textType, extra) {
  var cursor = 0
  var image
  var matcher = /<img\b[^>]*>/gi
  while ((image = matcher.exec(html)) !== null) {
    pushTextBlock(blocks, textType, html.slice(cursor, image.index), extra)
    var src = attribute(image[0], "src")
    if (/^https:\/\//i.test(src) && isSafeHttpUrl(src)) {
      blocks.push({ type: "img", src: src, alt: compactWhitespace(attribute(image[0], "alt")) })
    }
    cursor = image.index + image[0].length
  }
  pushTextBlock(blocks, textType, html.slice(cursor), extra)
}

function htmlToBlocks(html) {
  var source = stripUnsafeContainers(html)
  var blocks = []
  var cursor = 0
  var match
  var matcher = /<(p|h[1-6]|blockquote|ul|ol|pre)\b[^>]*>([\s\S]*?)<\/\1\s*>|<img\b[^>]*>|<hr\b[^>]*>/gi

  function pushLoose(value) {
    var withoutBlockTags = value.replace(/<\/?(?:div|section|article|main|header|footer|figure|figcaption)\b[^>]*>/gi, " ")
    pushImageSplit(blocks, withoutBlockTags, "p")
  }

  while ((match = matcher.exec(source)) !== null) {
    pushLoose(source.slice(cursor, match.index))
    var whole = match[0]
    var tag = match[1] ? match[1].toLowerCase() : ""
    var inner = match[2] || ""
    if (tag === "p") pushImageSplit(blocks, inner, "p")
    else if (/^h[1-6]$/.test(tag)) pushTextBlock(blocks, "h", stripTags(inner), { level: Number(tag.slice(1)) })
    else if (tag === "blockquote") pushTextBlock(blocks, "quote", stripTags(inner))
    else if (tag === "ul" || tag === "ol") {
      var items = []
      var listItem
      var itemMatcher = /<li\b[^>]*>([\s\S]*?)<\/li\s*>/gi
      while ((listItem = itemMatcher.exec(inner)) !== null) {
        var itemText = compactWhitespace(listItem[1])
        if (compactWhitespace(stripTags(itemText)) !== "") items.push(itemText)
      }
      if (items.length) blocks.push({ type: tag, items: items })
      else pushTextBlock(blocks, "p", inner)
    } else if (tag === "pre") {
      var codeText = compactWhitespace(stripTags(inner))
      if (codeText !== "") blocks.push({ type: "code", text: codeText })
    }
    else if (/^<img/i.test(whole)) pushImageSplit(blocks, whole, "p")
    else blocks.push({ type: "hr" })
    cursor = match.index + whole.length
  }
  pushLoose(source.slice(cursor))
  return blocks
}

function sanitizeInline(html) {
  var source = stripUnsafeContainers(html)
  var output = ""
  var cursor = 0
  var anchorOpen = false
  var tag
  var matcher = /<[^>]*>/g
  while ((tag = matcher.exec(source)) !== null) {
    output += escapeText(decodeEntities(source.slice(cursor, tag.index)))
    var raw = tag[0]
    var simple = raw.match(/^<\s*(\/?)\s*(b|strong|i|em|u|code)\b[^>]*>$/i)
    var br = raw.match(/^<\s*br\s*\/?\s*>$/i)
    var anchor = raw.match(/^<\s*(\/?)\s*a\b[^>]*>$/i)
    if (simple) output += "<" + (simple[1] ? "/" : "") + simple[2].toLowerCase() + ">"
    else if (br) output += "<br>"
    else if (anchor && anchor[1] && anchorOpen) {
      output += "</a>"
      anchorOpen = false
    }
    else if (anchor) {
      var href = attribute(raw, "href")
      if (isSafeHttpUrl(href)) {
        output += "<a href=\"" + escapeText(href) + "\">"
        anchorOpen = true
      }
    }
    cursor = tag.index + raw.length
  }
  output += escapeText(decodeEntities(source.slice(cursor)))
  return output
}

function firstImage(imageUrls) {
  return Array.isArray(imageUrls) && imageUrls.length ? imageUrls[0] : ""
}

function relativeTime(timestamp, nowMs) {
  var seconds = Number(timestamp)
  if (!isFinite(seconds) || seconds <= 0) return ""
  var now = nowMs === undefined ? Date.now() : Number(nowMs)
  var diff = Math.max(0, Math.floor((now - seconds * 1000) / 1000))
  if (diff < 60) return "now"
  if (diff < 3600) return Math.floor(diff / 60) + "m"
  if (diff < 86400) return Math.floor(diff / 3600) + "h"
  if (diff < 604800) return Math.floor(diff / 86400) + "d"
  if (diff < 2419200) return Math.floor(diff / 604800) + "w"
  var date = new Date(seconds * 1000)
  return date.getUTCDate() + " " + MONTHS[date.getUTCMonth()]
}

function formatDate(timestamp) {
  var date = new Date(Number(timestamp) * 1000)
  if (!isFinite(date.getTime())) return ""
  return date.getUTCDate() + " " + MONTHS[date.getUTCMonth()] + " " + date.getUTCFullYear()
}

function isPlainObject(value) {
  return value !== null && typeof value === "object" && !Array.isArray(value)
}

function validTimestampMap(value) {
  if (!isPlainObject(value)) return false
  for (var key in value) {
    if (typeof key !== "string" || key === "" || !isFinite(value[key]) || Number(value[key]) < 0) return false
  }
  return true
}

function validateState(value) {
  if (!isPlainObject(value) || value.schemaVersion !== 1) return false
  if (!validTimestampMap(value.seen) || !validTimestampMap(value.read)) return false
  if (!Array.isArray(value.notified)) return false
  for (var i = 0; i < value.notified.length; i++) if (typeof value.notified[i] !== "string" || value.notified[i] === "") return false
  return isFinite(value.lastFetchAt) && Number(value.lastFetchAt) >= 0 && isFinite(value.lastOpenedAt) && Number(value.lastOpenedAt) >= 0
}

function freshState() {
  return { schemaVersion: 1, seen: {}, read: {}, notified: [], lastFetchAt: 0, lastOpenedAt: 0 }
}

function copyMap(value) {
  var result = {}
  if (!isPlainObject(value)) return result
  for (var key in value) result[key] = Number(value[key]) || 0
  return result
}

function pruneMap(map, liveKeys) {
  var result = {}
  var extras = []
  for (var key in map) {
    if (liveKeys[key]) result[key] = map[key]
    else extras.push({ key: key, value: map[key] })
  }
  extras.sort(function(a, b) { return b.value - a.value })
  for (var i = 0; i < Math.min(200, extras.length); i++) result[extras[i].key] = extras[i].value
  return result
}

function mergeFetched(state, posts, isFirstRun, nowSeconds) {
  var next = validateState(state) ? {
    schemaVersion: 1,
    seen: copyMap(state.seen),
    read: copyMap(state.read),
    notified: state.notified.slice(),
    lastFetchAt: Number(state.lastFetchAt),
    lastOpenedAt: Number(state.lastOpenedAt)
  } : freshState()
  var now = nowSeconds === undefined ? Math.floor(Date.now() / 1000) : Number(nowSeconds)
  var liveKeys = {}
  for (var i = 0; i < (posts || []).length; i++) {
    var key = asText(posts[i] && posts[i].key)
    if (!key) continue
    liveKeys[key] = true
    if (isFirstRun) next.seen[key] = now
  }
  next.seen = pruneMap(next.seen, liveKeys)
  next.read = pruneMap(next.read, liveKeys)
  var notified = []
  var notifiedSeen = {}
  for (var j = next.notified.length - 1; j >= 0 && notified.length < 200; j--) {
    var notifiedKey = asText(next.notified[j])
    if (notifiedKey && !notifiedSeen[notifiedKey]) {
      notifiedSeen[notifiedKey] = true
      notified.unshift(notifiedKey)
    }
  }
  next.notified = notified
  next.lastFetchAt = now
  return next
}

function newKeysToNotify(state, posts) {
  var seen = state && isPlainObject(state.seen) ? state.seen : {}
  var notified = {}
  var notifiedList = state && Array.isArray(state.notified) ? state.notified : []
  for (var i = 0; i < notifiedList.length; i++) notified[notifiedList[i]] = true
  var keys = []
  for (var j = 0; j < (posts || []).length; j++) {
    var key = asText(posts[j] && posts[j].key)
    if (key && !Object.prototype.hasOwnProperty.call(seen, key) && !notified[key]) keys.push(key)
  }
  return keys
}

if (typeof module !== "undefined") {
  module.exports = {
    parseFeed: parseFeed,
    htmlToBlocks: htmlToBlocks,
    sanitizeInline: sanitizeInline,
    firstImage: firstImage,
    relativeTime: relativeTime,
    formatDate: formatDate,
    readingTime: readingTime,
    isSafeHttpUrl: isSafeHttpUrl,
    validateState: validateState,
    mergeFetched: mergeFetched,
    newKeysToNotify: newKeysToNotify
  }
}
