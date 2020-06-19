include tiny_sqlite / private / documentation

import std / [options, macros, typetraits, tables]
from tiny_sqlite/sqlite_wrapper as sqlite import nil

type
    DbConnImpl = ref object 
        handle: sqlite.PSqlite3 ## The underlying SQLite3 handle
        cache: OrderedTable[string, PreparedSql]
        cacheSize: int

    DbConn* = distinct DbConnImpl ## Encapsulates a database connection.

    PreparedSql = sqlite.Pstmt

    DbMode* = enum
        dbRead,
        dbReadWrite

    SqliteError* = object of CatchableError ## \
        ## Raised when whenever a database related error occurs.
        ## Errors are typically a result of API misuse,
        ## e.g trying to close an already closed database connection.

    DbValueKind* = enum ## \
        ## Enum of all possible value types in a SQLite database.
        sqliteNull,
        sqliteInteger,
        sqliteReal,
        sqliteText,
        sqliteBlob

    DbValue* = object ## \
        ## Can represent any value in a SQLite database.
        case kind*: DbValueKind
        of sqliteInteger:
            intVal*: int64
        of sqliteReal:
            floatVal*: float64
        of sqliteText:
            strVal*: string
        of sqliteBlob:
            blobVal*: seq[byte]
        of sqliteNull:
            discard

    DbConnOrHandle = DbConn | sqlite.PSqlite3

const SqliteRcOk = [ sqlite.SQLITE_OK, sqlite.SQLITE_DONE, sqlite.SQLITE_ROW ]

# Forward declarations
proc isInTransaction*(db: DbConn): bool {.noSideEffect.}

template handle(db: DbConn): sqlite.PSqlite3 = DbConnImpl(db).handle
template handle(handle: sqlite.PSqlite3): sqlite.PSqlite3 = handle
template cache(db: DbConn): OrderedTable[string, PreparedSql] = DbConnImpl(db).cache
template cacheSize(db: DbConn): int = DbConnImpl(db).cacheSize

template assertDbOpen(db: DbConn) =
    assert not db.handle.isNil, "Database is closed"

proc newSqliteError(db: DbConnOrHandle): ref SqliteError =
    ## Raises a SqliteError exception.
    (ref SqliteError)(msg: $sqlite.errmsg(db.handle))

proc newSqliteError(msg: string): ref SqliteError =
    ## Raises a SqliteError exception.
    (ref SqliteError)(msg: msg)

template checkRc(db: DbConnOrHandle, rc: int32) =
    if rc notin SqliteRcOk:
        raise newSqliteError(db)

proc addToCache(db: DbConn, sql: string, prepared: PreparedSql): void =
    db.cache[sql] = prepared
    if db.cache.len > db.cacheSize:
        for k, v in db.cache:
            # Discard rc: rc can be ignored - an error code does not indicate that finalize failed
            discard sqlite.finalize(v)
            db.cache.del k
            break

proc prepareSql(db: DbConn, sql: string, params: seq[DbValue]): PreparedSql
        {.raises: [SqliteError].} =
    if db.cacheSize > 0:
        result = db.cache.getOrDefault(sql)
    if result.isNil:
        var tail: cstring
        let rc = sqlite.prepare_v2(db.handle, sql.cstring, sql.len.cint, result, tail)
        db.checkRc(rc)
        assert tail.len == 0,
            "'exec' and 'execMany' can only be used with a single SQL statement. " &
            "To execute several SQL statements, use 'execScript'"
        if db.cacheSize > 0:
            db.addToCache(sql, result)

    let expectedParamsLen = sqlite.bind_parameter_count(result) 
    if expectedParamsLen != params.len:
        raise newSqliteError("SQL statement contains " & $expectedParamsLen &
            " parameters but only " & $params.len & " was provided.")

    var idx = 1'i32
    for value in params:
        let rc =
            case value.kind
            of sqliteNull:
                sqlite.bind_null(result, idx)
            of sqliteInteger:
                sqlite.bind_int64(result, idx, value.intval)
            of sqliteReal:
                sqlite.bind_double(result, idx, value.floatVal)
            of sqliteText:   
                sqlite.bind_text(result, idx, value.strVal.cstring, value.strVal.len.int32, sqlite.SQLITE_TRANSIENT)
            of sqliteBlob:
                sqlite.bind_blob(result, idx.int32, cast[string](value.blobVal).cstring,
                    value.blobVal.len.int32, sqlite.SQLITE_TRANSIENT)

        sqlite.db_handle(result).checkRc(rc)
        idx.inc

proc toDbValue*[T: Ordinal](val: T): DbValue =
    DbValue(kind: sqliteInteger, intVal: val.int64)

proc toDbValue*[T: SomeFloat](val: T): DbValue =
    DbValue(kind: sqliteReal, floatVal: val)

proc toDbValue*[T: string](val: T): DbValue =
    DbValue(kind: sqliteText, strVal: val)

proc toDbValue*[T: seq[byte]](val: T): DbValue =
    DbValue(kind: sqliteBlob, blobVal: val)

proc toDbValue*[T: Option](val: T): DbValue =
    if val.isNone:
        DbValue(kind: sqliteNull)
    else:
        toDbValue(val.get)

proc toDbValue*[T: type(nil)](val: T): DbValue =
    DbValue(kind: sqliteNull)

proc fromDbValue*(val: DbValue, T: typedesc[Ordinal]): T = val.intval.T

proc fromDbValue*(val: DbValue, T: typedesc[SomeFloat]): float64 = val.floatVal

proc fromDbValue*(val: DbValue, T: typedesc[string]): string = val.strVal

proc fromDbValue*(val: DbValue, T: typedesc[seq[byte]]): seq[byte] = val.blobVal

proc fromDbValue*(val: DbValue, T: typedesc[DbValue]): T = val

proc fromDbValue*[T](val: DbValue, _: typedesc[Option[T]]): Option[T] =
    if val.kind == sqliteNull:
        none(T)
    else:
        some(val.fromDbValue(T))

proc unpack*[T: tuple](row: openArray[DbValue], _: typedesc[T]): T =
    ## Call ``fromDbValue`` on each element of ``row`` and return it
    ## as a tuple.
    var idx = 0
    for value in result.fields:
        value = row[idx].fromDbValue(type(value))
        idx.inc

proc `$`*(dbVal: DbValue): string =
    result.add "DbValue["
    case dbVal.kind
    of sqliteInteger: result.add $dbVal.intVal
    of sqliteReal:    result.add $dbVal.floatVal
    of sqliteText:    result.addQuoted dbVal.strVal
    of sqliteBlob:    result.add "<blob>"
    of sqliteNull:    result.add "nil"
    result.add "]"

proc exec*(db: DbConn, sql: string, params: varargs[DbValue, toDbValue]) =
    ## Executes ``sql``, which must be a single SQL statement.
    assertDbOpen db
    let prepared = db.prepareSql(sql, @params)
    let rc = sqlite.step(prepared)
    # Discard rc: Discarding return code here is OK as reset & finalize will never return
    # an error code if step didn't return an error code.
    if db.cacheSize > 0:
        discard sqlite.reset(prepared)
    else:
        discard sqlite.finalize(prepared)
    db.checkRc(rc)

template transaction*(db: DbConn, body: untyped) =
    # Nested transactions are not supported in SQLite so we make it a no-op
    if db.isInTransaction:
        body
    else:
        db.exec("BEGIN")
        var ok = true
        try:
            try:
                body
            except Exception:
                ok = false
                db.exec("ROLLBACK")
                raise
        finally:
            if ok:
                db.exec("COMMIT")

proc execMany*(db: DbConn, sql: string, params: seq[seq[DbValue]]) =
    ## Executes ``sql`` repeatedly using each element of ``params`` as parameters.
    ## The statements are executed inside a transaction.
    assertDbOpen db
    db.transaction:
        for p in params:
            db.exec(sql, p)

proc execScript*(db: DbConn, sql: string) =
    ## Executes ``sql``, which can consist of multiple SQL statements.
    ## The statements are executed inside a transaction.
    assertDbOpen db
    db.transaction:
        var remaining = sql.cstring
        while remaining.len > 0:
            var tail: cstring
            var prepared: PreparedSql
            var rc = sqlite.prepare_v2(db.handle, remaining, sql.len.cint, prepared, tail)
            db.checkRc(rc)
            rc = sqlite.step(prepared)
            # Discard rc: Discarding return code here is OK as finalize will never return
            # an error code if step didn't return an error code.
            discard sqlite.finalize(prepared)
            db.checkRc(rc)
            remaining = tail

proc readColumn(prepared: PreparedSql, col: int32): DbValue =
    let columnType = sqlite.column_type(prepared, col)
    case columnType
    of sqlite.SQLITE_INTEGER:
        result = toDbValue(sqlite.column_int64(prepared, col))
    of sqlite.SQLITE_FLOAT:
        result = toDbValue(sqlite.column_double(prepared, col))
    of sqlite.SQLITE_TEXT:
        result = toDbValue($sqlite.column_text(prepared, col))
    of sqlite.SQLITE_BLOB:
        let blob = sqlite.column_blob(prepared, col)
        let bytes = sqlite.column_bytes(prepared, col)
        var s = newSeq[byte](bytes)
        if bytes != 0:
            copyMem(addr(s[0]), blob, bytes)
        result = toDbValue(s)
    of sqlite.SQLITE_NULL:
        result = toDbValue(nil)
    else:
        raiseAssert "Unexpected column type: " & $columnType

iterator rows*(db: DbConn, sql: string,
               params: varargs[DbValue, toDbValue]): seq[DbValue] =
    ## Executes ``sql`` and yield each resulting row.
    assertDbOpen db
    let prepared = db.prepareSql(sql, @params)
    var errorRc: int32 = sqlite.SQLITE_OK
    try:
        var row = newSeq[DbValue](sqlite.column_count(prepared))
        while true:
            let rc = sqlite.step(prepared)
            if rc == sqlite.SQLITE_ROW:
                for col, _ in row:
                    row[col] = readColumn(prepared, col.int32)
                yield row
            elif rc == sqlite.SQLITE_DONE:
                break
            else:
                errorRc = rc
                break
    finally:
        # Discard rc: Discarding return code here is OK as reset & finalize will never return
        # an error code if step didn't return an error code.
        if db.cacheSize > 0:
            discard sqlite.reset(prepared)
        else:
            discard sqlite.finalize(prepared)
        db.checkRc(errorRc)

proc rows*(db: DbConn, sql: string,
           params: varargs[DbValue, toDbValue]): seq[seq[DbValue]] =
    ## Executes ``sql`` and returns all resulting rows.
    for row in db.rows(sql, params):
        result.add row

proc openDatabase*(path: string, mode = dbReadWrite, cacheSize = 50): DbConn =
    ## Open a new database connection to a database file. To create a
    ## in-memory database the special path `":memory:"` can be used.
    ## If the database doesn't already exist and ``mode`` is ``dbReadWrite``,
    ## the database will be created. If the database doesn't exist and ``mode``
    ## is ``dbRead``, a ``SqliteError`` exception will be raised.
    ##
    ## NOTE: To avoid memory leaks, ``db.close`` must be called when the
    ## database connection is no longer needed.
    runnableExamples:
        let memDb = openDatabase(":memory:")
    var handle: sqlite.PSqlite3
    case mode
    of dbReadWrite:
        let rc = sqlite.open(path, handle)
        handle.checkRc(rc)
    of dbRead:
        let rc = sqlite.open_v2(path, handle, sqlite.SQLITE_OPEN_READONLY, nil)
        handle.checkRc(rc)
    let db = new DbConnImpl
    db.handle = handle
    db.cacheSize = cacheSize
    result = DbConn(db)

proc close*(db: DbConn) =
    ## Closes the database connection. This should be called once the connection will no longer be used
    ## to avoid leaking memory.
    assertDbOpen db
    for prepared in db.cache.values:
        let rc = sqlite.finalize(prepared)
        db.checkRc(rc)
    let rc = sqlite.close(db.handle)
    db.checkRc(rc)
    DbConnImpl(db).handle = nil

proc lastInsertRowId*(db: DbConn): int64 =
    ## Get the row id of the last inserted row.
    ## For tables with an integer primary key,
    ## the row id will be the primary key.
    ##
    ## For more information, refer to the SQLite documentation
    ## (https://www.sqlite.org/c3ref/last_insert_rowid.html).
    assertDbOpen db
    sqlite.last_insert_rowid(db.handle)

proc changes*(db: DbConn): int32 =
    ## Get the number of changes triggered by the most recent INSERT, UPDATE or
    ## DELETE statement.
    ##
    ## For more information, refer to the SQLite documentation
    ## (https://www.sqlite.org/c3ref/changes.html).
    assertDbOpen db
    sqlite.changes(db.handle)

proc isReadonly*(db: DbConn): bool =
    ## Returns true if ``db`` is in readonly mode.
    assertDbOpen db
    sqlite.db_readonly(db.handle, "main") == 1

proc isOpen*(db: DbConn): bool {.inline.} =
    (not DbConnImpl(db).isNil) and (not db.handle.isNil)

proc isInTransaction*(db: DbConn): bool =
    ## Returns true if a transaction is currently active.
    sqlite.get_autocommit(db.handle) == 0

proc handle*(db: DbConn): sqlite.PSqlite3 {.inline.} =
    ## Returns the raw SQLite3 handle. This can be used to interact directly with the SQLite C API
    ## with the `tiny_sqlite/sqlite_wrapper` module.
    assert not DbConnImpl(db).handle.isNil, "Database is closed"
    DbConnImpl(db).handle