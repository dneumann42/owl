## Reusable file-change tracking for hot-reloaded Owl programs and data.

import std/[os, tables, times]

type
  OwlFileStamp* = object
    exists*: bool
    modified*: Time
    size*: int64

  OwlFileWatcher* = object
    files*: Table[string, OwlFileStamp]

proc fileStamp(path: string): OwlFileStamp =
  try:
    result = OwlFileStamp(exists: fileExists(path))
    if result.exists:
      result.modified = getLastModificationTime(path)
      result.size = getFileSize(path)
  except OSError:
    result = OwlFileStamp()

proc initOwlFileWatcher*(): OwlFileWatcher =
  OwlFileWatcher(files: initTable[string, OwlFileStamp]())

proc watch*(watcher: var OwlFileWatcher, path: string) =
  ## Remember the current state of `path`. Re-watching refreshes its baseline.
  watcher.files[path] = fileStamp(path)

proc unwatch*(watcher: var OwlFileWatcher, path: string) =
  watcher.files.del(path)

proc clear*(watcher: var OwlFileWatcher) =
  watcher.files.clear()

proc changed*(watcher: OwlFileWatcher): bool =
  ## Return true when a watched file was created, removed, or modified.
  for path, previous in watcher.files:
    if fileStamp(path) != previous:
      return true

proc refresh*(watcher: var OwlFileWatcher) =
  ## Accept every watched file's current state as the new baseline.
  for path in watcher.files.keys:
    watcher.files[path] = fileStamp(path)
