## Implements a least-recently-used cache for prepared statements based on
## https://github.com/jackhftang/lrucache.nim.

import std / [lists, tables]
from .. / sqlite_wrapper as sqlite import nil

type
  Node = object
    key: string
    val: sqlite.Stmt

  StmtCache* = object 
    capacity: int
    list: DoublyLinkedList[Node]
    table: Table[string, DoublyLinkedNode[Node]]

proc initStmtCache*(capacity: Natural): StmtCache =
  ## Create a new Least-Recently-Used (LRU) cache that store the last `capacity`-accessed items.
  StmtCache(
    capacity: capacity,
    list: initDoublyLinkedList[Node](),
    table: initTable[string, DoublyLinkedNode[Node]](capacity)
  )

proc resize(cache: var StmtCache) =
  while cache.table.len > cache.capacity:
    let t = cache.list.tail
    cache.table.del(t.value.key)
    discard sqlite.finalize(t.value.val)
    cache.list.remove t

proc capacity*(cache: StmtCache): int = 
  ## Get the maximum capacity of cache
  cache.capacity

proc len*(cache: StmtCache): int = 
  ## Return number of keys in cache
  cache.table.len

proc contains*(cache: StmtCache, key: string): bool =
  ## Check whether key in cache. Does *NOT* update recentness.
  cache.table.contains(key)

proc clear*(cache: var StmtCache) =
  ## remove all items
  cache.list = initDoublyLinkedList[Node]()
  cache.table.clear()

proc `[]`*(cache: var StmtCache, key: string): sqlite.Stmt =
  ## Read value from `cache` by `key` and update recentness
  ## Raise `KeyError` if `key` is not in `cache`.
  let node = cache.table[key]
  result = node.value.val
  cache.list.remove node
  cache.list.prepend node

proc `[]=`*(cache: var StmtCache, key: string, val: sqlite.Stmt) =
  ## Put value `v` in cache with key `k`.
  ## Remove least recently used value from cache if length exceeds capacity.
  var node = cache.table.getOrDefault(key, nil)
  if node.isNil:
    let node = newDoublyLinkedNode[Node](
      Node(key: key, val: val)
    )
    cache.table[key] = node
    cache.list.prepend node
    cache.resize()
  else:
    # set value 
    node.value.val = val
    # move to head
    cache.list.remove node
    cache.list.prepend node
    
proc getOrDefault*(cache: StmtCache, key: string, val: sqlite.Stmt = nil): sqlite.Stmt =
  ## Similar to get, but return `val` if `key` is not in `cache`
  let node = cache.table.getOrDefault(key, nil)
  if node.isNil:
    result = val
  else:
    result = node.value.val
