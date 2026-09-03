import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  visible: false

  property var settings: ({})
  property var posts: []
  state: "loading"
  property string errorText: ""
  property double lastFetchAt: 0
  property bool fetching: false
  property var persisted: ({
    schemaVersion: 1,
    seen: ({}),
    read: ({}),
    notified: [],
    lastFetchAt: 0,
    lastOpenedAt: 0
  })
  property bool stateLoaded: false
  property bool cacheLoaded: false
  property bool stateFileExisted: false
  property bool refreshPending: false
  property int retryCount: 0
  property string fetchOutput: ""
  property string fetchError: ""
  property var availableImages: ({})
  property var imageQueue: []
  property string currentImageUrl: ""
  property string currentImagePath: ""

  readonly property string feedUrl: "https://omarchy.org/news/rss.xml"
  readonly property string homeDir: Quickshell.env("HOME")
  readonly property string cacheDir: homeDir + "/.cache/omarchy-news"
  readonly property string imageDir: cacheDir + "/images"
  readonly property string feedCachePath: cacheDir + "/feed.json"
  readonly property string etagPath: cacheDir + "/feed.etag"
  readonly property string stateDir: homeDir + "/.local/state/omarchy-news"
  readonly property string statePath: stateDir + "/state.json"
  readonly property int refreshMinutes: intSetting("refreshMinutes", 30, 5, 1440)
  readonly property int maxPosts: intSetting("maxPosts", 40, 10, 100)
  readonly property bool notifyEnabled: boolSetting("notify", true)
  readonly property int unseenCount: countMissing(persisted.seen)
  readonly property int unreadCount: countMissing(persisted.read)

  signal postsReplaced()

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, minimum, maximum) {
    var value = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(value)) value = fallback
    return Math.max(minimum, Math.min(maximum, value))
  }

  function boolSetting(name, fallback) {
    var value = setting(name, fallback)
    if (value === true || value === false) return value
    var text = String(value).toLowerCase()
    if (text === "true" || text === "yes" || text === "on" || text === "1") return true
    if (text === "false" || text === "no" || text === "off" || text === "0") return false
    return fallback
  }

  function clone(value) {
    return JSON.parse(JSON.stringify(value))
  }

  function nowSeconds() {
    return Math.floor(Date.now() / 1000)
  }

  function countMissing(map) {
    var count = 0
    var values = map || {}
    for (var i = 0; i < posts.length; i++) {
      var key = String(posts[i].key || "")
      if (key !== "" && values[key] === undefined) count++
    }
    return count
  }

  function refreshIfStale(maxAgeSeconds) {
    var age = Number(maxAgeSeconds)
    if (!isFinite(age) || age <= 0) age = 300
    if (lastFetchAt <= 0 || nowSeconds() - lastFetchAt >= age) refresh()
  }

  function fetchCommand() {
    return [
      "curl", "-fsSL", "--proto", "=https", "--max-time", "15",
      "--max-filesize", "2097152", "--max-redirs", "2",
      "-A", "omarchy-news/0.1.0", "--etag-compare", etagPath,
      "--etag-save", etagPath, feedUrl
    ]
  }

  function refresh() {
    if (!stateLoaded || !cacheLoaded) {
      refreshPending = true
      return
    }
    if (fetchProcess.running) return
    refreshPending = false
    retryTimer.stop()
    watchdog.stop()
    fetchOutput = ""
    fetchError = ""
    fetching = true
    fetchProcess.command = fetchCommand()
    fetchProcess.running = true
    watchdog.restart()
  }

  function finishFetchFailure(message) {
    fetching = false
    state = "error"
    errorText = String(message || "Couldn't reach omarchy.org, showing cached posts").replace(/\s+/g, " ").trim()
    if (errorText === "") errorText = "Couldn't reach omarchy.org, showing cached posts"
  }

  function handleFetchExit(exitCode) {
    watchdog.stop()
    var body = String(fetchCollector.text || fetchOutput || "")
    var error = String(errorCollector.text || fetchError || "").trim()
    if (exitCode === 0) {
      retryCount = 0
      if (body.trim() === "") {
        var unchanged = !stateFileExisted && posts.length > 0
          ? Model.mergeFetched(persisted, posts, true, nowSeconds())
          : clone(persisted)
        unchanged.lastFetchAt = nowSeconds()
        persisted = unchanged
        stateFileExisted = true
        lastFetchAt = unchanged.lastFetchAt
        state = "ready"
        errorText = ""
        fetching = false
        scheduleStateSave()
        return
      }
      var parsed = Model.parseFeed(body).slice(0, maxPosts)
      if (parsed.length === 0) {
        finishFetchFailure("Omarchy News returned an unreadable feed")
        return
      }
      var firstRun = !stateFileExisted
      posts = parsed
      postsReplaced()
      persisted = Model.mergeFetched(persisted, posts, firstRun, nowSeconds())
      stateFileExisted = true
      lastFetchAt = persisted.lastFetchAt
      state = "ready"
      errorText = ""
      fetching = false
      scheduleStateSave()
      persistFeedCache()
      queuePostImages()
      return
    }
    if (retryCount < 3) {
      retryCount++
      fetching = false
      retryTimer.restart()
      return
    }
    retryCount = 0
    finishFetchFailure(error || "Couldn't reach omarchy.org, showing cached posts")
  }

  function loadFeedCache(raw) {
    try {
      var data = JSON.parse(String(raw || ""))
      if (data && Array.isArray(data.posts)) {
        posts = data.posts.slice(0, maxPosts)
        availableImages = data.images && typeof data.images === "object" ? data.images : ({})
        postsReplaced()
      }
    } catch (error) {
      console.warn("omarchy-news: cached feed is unreadable")
    }
    cacheLoaded = true
    if (refreshPending && stateLoaded) Qt.callLater(root.refresh)
  }

  function finishCacheWithoutData() {
    cacheLoaded = true
    if (refreshPending && stateLoaded) Qt.callLater(root.refresh)
  }

  function persistFeedCache() {
    feedCacheFile.setText(JSON.stringify({ schemaVersion: 1, posts: posts, images: availableImages }, null, 2) + "\n")
  }

  function freshState() {
    return { schemaVersion: 1, seen: ({}), read: ({}), notified: [], lastFetchAt: 0, lastOpenedAt: 0 }
  }

  function finishStateLoad(next, existed) {
    persisted = next
    stateFileExisted = existed
    stateLoaded = true
    lastFetchAt = Number(next.lastFetchAt) || 0
    if (refreshPending) Qt.callLater(root.refresh)
  }

  function loadState(raw, existed) {
    var text = String(raw || "")
    if (!existed) {
      finishStateLoad(freshState(), false)
      return
    }
    if (text.length > 262144) {
      preserveCorruptState()
      return
    }
    try {
      var parsed = JSON.parse(text)
      if (!Model.validateState(parsed)) throw new Error("wrong shape")
      finishStateLoad(parsed, true)
    } catch (error) {
      preserveCorruptState()
    }
  }

  function preserveCorruptState() {
    corruptStateProcess.command = ["mv", statePath, statePath + ".corrupt-" + nowSeconds()]
    corruptStateProcess.running = true
    finishStateLoad(freshState(), false)
  }

  function scheduleStateSave() {
    if (stateLoaded) stateSaveTimer.restart()
  }

  function flushState() {
    stateFile.setText(JSON.stringify(persisted, null, 2) + "\n")
  }

  function markSeen(keys) {
    var next = clone(persisted)
    var now = nowSeconds()
    var values = Array.isArray(keys) ? keys : []
    for (var i = 0; i < values.length; i++) {
      var key = String(values[i] || "")
      if (key !== "") next.seen[key] = now
    }
    next.lastOpenedAt = now
    persisted = next
    scheduleStateSave()
  }

  function markRead(key) {
    var value = String(key || "")
    if (value === "") return
    var next = clone(persisted)
    next.read[value] = nowSeconds()
    persisted = next
    scheduleStateSave()
  }

  function toggleRead(key) {
    var value = String(key || "")
    if (value === "") return
    var next = clone(persisted)
    if (next.read[value] === undefined) next.read[value] = nowSeconds()
    else delete next.read[value]
    persisted = next
    scheduleStateSave()
  }

  function markAllRead() {
    var previous = clone(persisted.read)
    var next = clone(persisted)
    var now = nowSeconds()
    for (var i = 0; i < posts.length; i++) {
      var key = String(posts[i].key || "")
      if (key !== "") next.read[key] = now
    }
    persisted = next
    scheduleStateSave()
    return previous
  }

  function restoreRead(previous) {
    if (!previous || typeof previous !== "object" || Array.isArray(previous)) return
    var next = clone(persisted)
    next.read = clone(previous)
    persisted = next
    scheduleStateSave()
  }

  function statusJson() {
    return JSON.stringify({
      state: state,
      fetching: fetching,
      posts: posts.length,
      unseen: unseenCount,
      unread: unreadCount,
      lastFetchAt: lastFetchAt,
      error: errorText
    })
  }

  function imageExtension(url) {
    var clean = String(url || "").split(/[?#]/)[0]
    var match = clean.match(/\.([a-z0-9]{2,5})$/i)
    if (!match) return ".img"
    var extension = match[1].toLowerCase()
    return /^(?:png|jpe?g|webp|avif)$/.test(extension) ? "." + extension : ".img"
  }

  function cachePathForImage(url) {
    return imageDir + "/" + Model.sha1(String(url || "")) + imageExtension(url)
  }

  function imagePath(url) {
    var value = String(url || "")
    return availableImages[value] ? "file://" + String(availableImages[value]) : ""
  }

  function queuePostImages() {
    var pending = imageQueue.slice()
    var known = {}
    for (var queued = 0; queued < pending.length; queued++) known[pending[queued]] = true
    if (currentImageUrl !== "") known[currentImageUrl] = true
    for (var i = 0; i < posts.length; i++) {
      var urls = Array.isArray(posts[i].imageUrls) ? posts[i].imageUrls : []
      for (var j = 0; j < urls.length; j++) {
        var url = String(urls[j] || "")
        if (!/^https:\/\//i.test(url) || availableImages[url] || known[url]) continue
        known[url] = true
        pending.push(url)
      }
    }
    imageQueue = pending
    startNextImage()
  }

  function startNextImage() {
    if (currentImageUrl !== "" || imageCheckProcess.running || imageFetchProcess.running || imageMoveProcess.running || imageQueue.length === 0) return
    currentImageUrl = String(imageQueue[0])
    imageQueue = imageQueue.slice(1)
    currentImagePath = cachePathForImage(currentImageUrl)
    imageCheckProcess.command = ["test", "-s", currentImagePath]
    imageCheckProcess.running = true
  }

  function markCurrentImageAvailable() {
    var next = clone(availableImages)
    next[currentImageUrl] = currentImagePath
    availableImages = next
    persistFeedCache()
    finishCurrentImage()
  }

  function finishCurrentImage() {
    currentImageUrl = ""
    currentImagePath = ""
    Qt.callLater(root.startNextImage)
  }

  Timer {
    id: startupTimer
    interval: 3000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.refreshMinutes * 60000
    repeat: true
    running: true
    triggeredOnStart: false
    onTriggered: root.refresh()
  }

  Timer {
    id: retryTimer
    interval: 2500
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    id: watchdog
    interval: 30000
    repeat: false
    onTriggered: if (fetchProcess.running) fetchProcess.running = false
  }

  Timer {
    id: stateSaveTimer
    interval: 200
    repeat: false
    onTriggered: root.flushState()
  }

  FileView {
    id: feedCacheFile
    path: root.feedCachePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadFeedCache(text())
    onLoadFailed: root.finishCacheWithoutData()
  }

  FileView {
    id: stateFile
    path: root.stateLoaded ? root.statePath : ""
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: ensureDirectories
    running: false
    command: ["mkdir", "-p", root.cacheDir, root.imageDir, root.stateDir]
    onExited: function(exitCode) {
      feedCacheFile.reload()
      stateReadProcess.command = ["head", "-c", "262145", root.statePath]
      stateReadProcess.running = true
      startupTimer.restart()
    }
  }

  Process {
    id: stateReadProcess
    running: false
    command: []
    stdout: StdioCollector { id: stateCollector; waitForEnd: true }
    onExited: function(exitCode) { root.loadState(stateCollector.text, exitCode === 0) }
  }

  Process {
    id: corruptStateProcess
    running: false
    command: []
    onExited: function(exitCode) {
      Quickshell.execDetached([
        "omarchy-notification-send", "--app-name", "Omarchy News", "-u", "low", "-g", "󰑫",
        "Omarchy News state reset", "The previous state file was corrupt and has been preserved."
      ])
    }
  }

  Process {
    id: fetchProcess
    running: false
    command: []
    stdout: StdioCollector {
      id: fetchCollector
      waitForEnd: true
      onStreamFinished: root.fetchOutput = text
    }
    stderr: StdioCollector {
      id: errorCollector
      waitForEnd: true
      onStreamFinished: root.fetchError = text
    }
    onExited: function(exitCode) { root.handleFetchExit(exitCode) }
  }

  Process {
    id: imageCheckProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.markCurrentImageAvailable()
      else {
        imageFetchProcess.command = [
          "curl", "-fsSL", "--proto", "=https", "--max-time", "20",
          "--max-filesize", "3145728", "-o", root.currentImagePath + ".part", root.currentImageUrl
        ]
        imageFetchProcess.running = true
      }
    }
  }

  Process {
    id: imageFetchProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) {
        imageMoveProcess.command = ["mv", "-f", root.currentImagePath + ".part", root.currentImagePath]
        imageMoveProcess.running = true
      } else root.finishCurrentImage()
    }
  }

  Process {
    id: imageMoveProcess
    running: false
    command: []
    onExited: function(exitCode) {
      if (exitCode === 0) root.markCurrentImageAvailable()
      else root.finishCurrentImage()
    }
  }

  Component.onCompleted: ensureDirectories.running = true
}
