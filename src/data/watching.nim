## Reusable file-change tracking for hot-reloaded Owl programs and data.

import std/[os, tables, times]

when defined(linux):
  import std/[atomics, locks]
  from std/posix import O_CLOEXEC, O_NONBLOCK, POLLIN, TPollfd, Tnfds, close,
    poll, read, write
  from posix/linux import pipe2
  import posix/inotify

type
  OwlFileStamp* = object
    exists*: bool
    modified*: Time
    size*: int64

  OwlFileChangeNotifier* = proc() {.gcsafe, raises: [].}

  OwlFileWatcher* = ref object
    files*: Table[string, OwlFileStamp]
    when defined(linux):
      descriptor: cint
      stopRead, stopWrite: cint
      notificationsAvailable: bool
      directories: Table[string, cint]
      directoryPaths: Table[cint, string]
      pending: Atomic[bool]
      notifier: OwlFileChangeNotifier
      notificationThread: Thread[OwlFileWatcher]
      notificationThreadStarted: bool
      stopping: Atomic[bool]
      lock: Lock
      closed: bool

proc fileStamp(path: string): OwlFileStamp =
  try:
    result = OwlFileStamp(exists: fileExists(path))
    if result.exists:
      result.modified = getLastModificationTime(path)
      result.size = getFileSize(path)
  except OSError:
    result = OwlFileStamp()

proc watchedPath(path: string): string {.raises: [].} =
  try:
    path.absolutePath.normalizedPath
  except CatchableError:
    path

when defined(linux):
  const
    WatchMask = IN_CLOSE_WRITE or IN_ATTRIB or IN_CREATE or IN_DELETE or
      IN_MOVED_FROM or IN_MOVED_TO or IN_DELETE_SELF or IN_MOVE_SELF
    EventBufferSize = 16 * 1024

  proc addDirectoryWatch(watcher: OwlFileWatcher, directory: string): bool =
    if watcher.descriptor < 0 or directory in watcher.directories:
      return directory in watcher.directories
    let watchDescriptor = inotify_add_watch(
      watcher.descriptor, directory.cstring, WatchMask)
    if watchDescriptor >= 0:
      watcher.directories[directory] = watchDescriptor
      watcher.directoryPaths[watchDescriptor] = directory
      return true

  proc relevantEvent(watcher: OwlFileWatcher, event: ptr InotifyEvent): bool =
    if (event.mask and IN_Q_OVERFLOW) != 0:
      return true
    if event.wd notin watcher.directoryPaths:
      return false
    let directory = watcher.directoryPaths[event.wd]
    if event.len == 0:
      return true
    let path = directory / $cast[cstring](addr event.name)
    path in watcher.files

  proc drainNotifications(watcher: OwlFileWatcher): bool =
    if watcher.descriptor < 0:
      return false
    var buffer: array[EventBufferSize, byte]
    while true:
      let count = posix.read(watcher.descriptor, addr buffer[0], buffer.len)
      if count <= 0:
        break
      withLock watcher.lock:
        for event in inotify_events(addr buffer[0], count):
          if watcher.relevantEvent(event):
            result = true

  proc watchForNotifications(watcher: OwlFileWatcher) {.thread, raises: [].} =
    var descriptors = [
      TPollfd(fd: watcher.descriptor, events: POLLIN),
      TPollfd(fd: watcher.stopRead, events: POLLIN),
    ]
    while not watcher.stopping.load(moAcquire):
      try:
        if posix.poll(addr descriptors[0], descriptors.len.Tnfds, -1.cint) > 0 and
            (descriptors[1].revents and POLLIN) != 0:
          return
        if (descriptors[0].revents and POLLIN) != 0:
          descriptors[0].revents = 0
          if watcher.drainNotifications():
            watcher.pending.store(true, moRelease)
            let notify = watcher.notifier
            if notify != nil:
              notify()
      except CatchableError:
        discard

proc initOwlFileWatcher*(): OwlFileWatcher =
  result = OwlFileWatcher(files: initTable[string, OwlFileStamp]())
  when defined(linux):
    result.descriptor = inotify_init1(O_NONBLOCK or O_CLOEXEC)
    result.notificationsAvailable = result.descriptor >= 0
    var stopDescriptors = [-1.cint, -1.cint]
    if pipe2(stopDescriptors, O_NONBLOCK or O_CLOEXEC) == 0:
      result.stopRead = stopDescriptors[0]
      result.stopWrite = stopDescriptors[1]
    else:
      result.stopRead = -1
      result.stopWrite = -1
    result.directories = initTable[string, cint]()
    result.directoryPaths = initTable[cint, string]()
    initLock(result.lock)

proc usesFileNotifications*(watcher: OwlFileWatcher): bool =
  ## Whether this watcher is backed by operating-system change notifications.
  when defined(linux):
    watcher != nil and watcher.notificationsAvailable
  else:
    false

proc watch*(watcher: OwlFileWatcher, path: string) =
  ## Remember the current state of `path`. Re-watching refreshes its baseline.
  let normalized = watchedPath(path)
  when defined(linux):
    withLock watcher.lock:
      watcher.files[normalized] = fileStamp(normalized)
      if not watcher.addDirectoryWatch(normalized.parentDir):
        watcher.notificationsAvailable = false
  else:
    watcher.files[normalized] = fileStamp(normalized)

proc unwatch*(watcher: OwlFileWatcher, path: string) =
  let normalized = watchedPath(path)
  when defined(linux):
    withLock watcher.lock:
      watcher.files.del(normalized)
  else:
    watcher.files.del(normalized)

proc clear*(watcher: OwlFileWatcher) =
  when defined(linux):
    withLock watcher.lock:
      watcher.files.clear()
  else:
    watcher.files.clear()

proc changed*(watcher: OwlFileWatcher): bool =
  ## Return true when a watched file was created, removed, or modified.
  ## Linux consumes inotify events; the portable fallback compares file stamps.
  when defined(linux):
    if watcher.usesFileNotifications() and watcher.stopRead >= 0:
      if not watcher.notificationThreadStarted and watcher.drainNotifications():
        watcher.pending.store(true, moRelease)
      return watcher.pending.load(moAcquire)
  for path, previous in watcher.files:
    if fileStamp(path) != previous:
      return true

proc refresh*(watcher: OwlFileWatcher) =
  ## Accept every watched file's current state as the new baseline.
  when defined(linux):
    if watcher.usesFileNotifications():
      watcher.pending.store(false, moRelease)
    withLock watcher.lock:
      for path in watcher.files.keys:
        watcher.files[path] = fileStamp(path)
  else:
    for path in watcher.files.keys:
      watcher.files[path] = fileStamp(path)

proc notifyChanges*(watcher: OwlFileWatcher,
                    notifier: OwlFileChangeNotifier): bool =
  ## Arrange for `notifier` to run promptly when Linux reports a watched-file
  ## change. Returns false when only the polling fallback is available.
  when defined(linux):
    if watcher.usesFileNotifications():
      watcher.notifier = notifier
      if not watcher.notificationThreadStarted:
        watcher.notificationThreadStarted = true
        createThread(watcher.notificationThread, watchForNotifications, watcher)
      return true
  false

proc close*(watcher: OwlFileWatcher) =
  ## Stop background notification delivery and release native resources.
  if watcher.isNil:
    return
  when defined(linux):
    if watcher.closed:
      return
    watcher.closed = true
    if watcher.notificationThreadStarted:
      watcher.stopping.store(true, moRelease)
      var signal = 1'u8
      discard posix.write(watcher.stopWrite, addr signal, sizeof(signal))
      joinThread(watcher.notificationThread)
      watcher.notificationThreadStarted = false
    if watcher.descriptor >= 0:
      discard posix.close(watcher.descriptor)
      watcher.descriptor = -1
    if watcher.stopRead >= 0:
      discard posix.close(watcher.stopRead)
      watcher.stopRead = -1
    if watcher.stopWrite >= 0:
      discard posix.close(watcher.stopWrite)
      watcher.stopWrite = -1
    deinitLock(watcher.lock)
