## .. include:: ./tiny_sqlite/private/documentation.rst

import std / [options, macros, typetraits, tables, sequtils]
from tiny_sqlite / sqlite_wrapper as sqlite import nil

when not declared(tupleLen):
    macro tupleLen(typ: typedesc[tuple]): int =
        let impl = getType(typ)
        result = newIntlitNode(impl[1].len - 1)

type
    DbConnImpl = ref object 
        handle: sqlite.Sqlite3 ## The underlying SQLite3 handle
        cache: OrderedTable[string, sqlite.Stmt]
        cacheSize: int

    DbConn* = distinct DbConnImpl ## Encapsulates a database connection.

    SqlStatementImpl = ref object
        handle: sqlite.Stmt
        db: DbConn

    SqlStatement* = distinct SqlStatementImpl ## A prepared SQL statement.

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

    Rc = cint

    ResultRow* = object
        values: seq[DbValue]
        columns: seq[string]

const SqliteRcOk = [ sqlite.SQLITE_OK, sqlite.SQLITE_DONE, sqlite.SQLITE_ROW ]


# Forward declarations
proc isInTransaction*(db: DbConn): bool {.noSideEffect.}
proc isOpen*(db: DbConn): bool {.noSideEffect, inline.}

template handle(db: DbConn): sqlite.Sqlite3 = DbConnImpl(db).handle
template handle(statement: SqlStatement): sqlite.Stmt = SqlStatementImpl(statement).handle
template db(statement: SqlStatement): DbConn = SqlStatementImpl(statement).db
template cache(db: DbConn): OrderedTable[string, sqlite.Stmt] = DbConnImpl(db).cache
template cacheSize(db: DbConn): int = DbConnImpl(db).cacheSize

template assertCanUseDb(db: DbConn) =
    doAssert (not DbConnImpl(db).isNil) and (not db.handle.isNil), "Database is closed"

template assertCanUseStatement(statement: SqlStatement, busyOk: static[bool] = false) =
    doAssert (not SqlStatementImpl(statement).isNil) and (not statement.handle.isNil),
        "Statement cannot be used because it has already been finalized."
    doAssert not statement.db.handle.isNil,
        "Statement cannot be used because the database connection has been closed"
    when not busyOk:
        doAssert not sqlite.stmt_busy(statement.handle),
            "Statement cannot be used while inside the 'all' iterator"

proc newSqliteError(db: DbConn): ref SqliteError =
    ## Raises a SqliteError exception.
    (ref SqliteError)(msg: $sqlite.errmsg(db.handle))

proc newSqliteError(msg: string): ref SqliteError =
    ## Raises a SqliteError exception.
    (ref SqliteError)(msg: msg)

template checkRc(db: DbConn, rc: Rc) =
    if rc notin SqliteRcOk:
        raise newSqliteError(db)

proc addToCache(db: DbConn, sql: string, prepared: sqlite.Stmt): void =
    db.cache[sql] = prepared
    if db.cache.len > db.cacheSize:
        for k, v in db.cache:
            discard sqlite.finalize(v)
            db.cache.del k
            break

#
# DbValue
#

proc toDbValue*[T: Ordinal](val: T): DbValue =
    ## Convert an ordinal value to a Dbvalue.
    DbValue(kind: sqliteInteger, intVal: val.int64)

proc toDbValue*[T: SomeFloat](val: T): DbValue =
    ## Convert a float to a DbValue.
    DbValue(kind: sqliteReal, floatVal: val)

proc toDbValue*[T: string](val: T): DbValue =
    ## Convert a string to a DbValue.
    DbValue(kind: sqliteText, strVal: val)

proc toDbValue*[T: seq[byte]](val: T): DbValue =
    ## Convert a sequence of bytes to a DbValue.
    DbValue(kind: sqliteBlob, blobVal: val)

proc toDbValue*[T: Option](val: T): DbValue =
    ## Convert an optional value to a DbValue.
    if val.isNone:
        DbValue(kind: sqliteNull)
    else:
        toDbValue(val.get)

proc toDbValue*[T: type(nil)](val: T): DbValue =
    ## Convert a nil literal to a DbValue.
    DbValue(kind: sqliteNull)

proc toDbValues*(values: varargs[DbValue, toDbValue]): seq[DbValue] =
    ## Convert several values to a sequence of DbValue's.
    runnableExamples:
        doAssert toDbValues("string", 23) == @[toDbValue("string"), toDbValue(23)] 
    @values

proc fromDbValue*(value: DbValue, T: typedesc[Ordinal]): T =
    # Convert a DbValue to an ordinal.
    value.intval.T

proc fromDbValue*(value: DbValue, T: typedesc[SomeFloat]): float64 =
    ## Convert a DbValue to a float.
    value.floatVal

proc fromDbValue*(value: DbValue, T: typedesc[string]): string =
    ## Convert a DbValue to a string.
    value.strVal

proc fromDbValue*(value: DbValue, T: typedesc[seq[byte]]): seq[byte] =
    ## Convert a DbValue to a sequence of bytes.
    value.blobVal

proc fromDbValue*[T](value: DbValue, _: typedesc[Option[T]]): Option[T] =
    ## Convert a DbValue to an optional value.
    if value.kind == sqliteNull:
        none(T)
    else:
        some(value.fromDbValue(T))

proc fromDbValue*(value: DbValue, T: typedesc[DbValue]): T =
    ## Special overload that simply return `value`.
    ## The purpose of this overload is to do partial unpacking.
    ## For example, if the type of one column in a result row is unknown,
    ## the DbValue type can be kept just for that column.
    ## 
    ## .. code-block:: nim
    ## 
    ##   for row in db.iterate("SELECT name, extra FROM Person"):
    ##       # Type of 'extra' is unknown, so we don't unpack it.
    ##       # The 'extra' variable will be of type 'DbValue'
    ##       let (name, extra) = row.unpack((string, DbValue))
    value

proc `$`*(dbVal: DbValue): string =
    result.add "DbValue["
    case dbVal.kind
    of sqliteInteger: result.add $dbVal.intVal
    of sqliteReal:    result.add $dbVal.floatVal
    of sqliteText:    result.addQuoted dbVal.strVal
    of sqliteBlob:    result.add "<blob>"
    of sqliteNull:    result.add "nil"
    result.add "]"

proc `==`*(a, b: DbValue): bool =
    ## Returns true if `a` and `b` represents the same value.
    if a.kind != b.kind:
        false
    else:
        case a.kind
        of sqliteInteger: a.intVal == b.intVal
        of sqliteReal:    a.floatVal == b.floatVal
        of sqliteText:    a.strVal == b.strVal
        of sqliteBlob:    a.blobVal == b.blobVal
        of sqliteNull:    true

#
# PStmt
#

proc bindParams(db: DbConn, prepared: sqlite.Stmt, params: varargs[DbValue]): Rc =
    result = sqlite.SQLITE_OK
    let expectedParamsLen = sqlite.bind_parameter_count(prepared) 
    if expectedParamsLen != params.len:
        raise newSqliteError("SQL statement contains " & $expectedParamsLen &
            " parameters but only " & $params.len & " was provided.")

    var idx = 1'i32
    for value in params:
        let rc =
            case value.kind
            of sqliteNull:
                sqlite.bind_null(prepared, idx)
            of sqliteInteger:
                sqlite.bind_int64(prepared, idx, value.intval)
            of sqliteReal:
                sqlite.bind_double(prepared, idx, value.floatVal)
            of sqliteText:   
                sqlite.bind_text(prepared, idx, value.strVal.cstring, value.strVal.len.int32, sqlite.SQLITE_TRANSIENT)
            of sqliteBlob:
                sqlite.bind_blob(prepared, idx.int32, cast[string](value.blobVal).cstring,
                    value.blobVal.len.int32, sqlite.SQLITE_TRANSIENT)

        if rc notin SqliteRcOk:
            return rc
        idx.inc

proc prepareSql(db: DbConn, sql: string): sqlite.Stmt =
    var tail: cstring
    let rc = sqlite.prepare_v2(db.handle, sql.cstring, sql.len.cint, result, tail)
    db.checkRc(rc)
    assert tail.len == 0,
        "Only single SQL statement is allowed in this context. " &
        "To execute several SQL statements, use 'execScript'"

proc prepareSql(db: DbConn, sql: string, params: seq[DbValue]): sqlite.Stmt
        {.raises: [SqliteError].} =
    if db.cacheSize > 0:
        result = db.cache.getOrDefault(sql)
    if result.isNil:
        result = prepareSql(db, sql)
        if db.cacheSize > 0:
            db.addToCache(sql, result)
    let rc = db.bindParams(result, params)
    db.checkRc(rc)

proc readColumn(prepared: sqlite.Stmt, col: int32): DbValue =
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

iterator iterate(db: DbConn, stmtOrHandle: sqlite.Stmt | SqlStatement, params: varargs[DbValue],
        errorRc: var int32): ResultRow =
    let prepared = when stmtOrHandle is sqlite.Stmt: stmtOrHandle else: stmtOrHandle.handle
    errorRc = db.bindParams(prepared, params)
    if errorRc in SqliteRcOk:
        var rowLen = sqlite.column_count(prepared)
        var values = newSeq[DbValue](rowLen)
        var columns = newSeq[string](rowLen)
        while true:
            when stmtOrHandle is sqlite.Stmt:
                assertCanUseDb db
            else:
                assertCanUseStatement stmtOrHandle, busyOk = true
            let rc = sqlite.step(prepared)
            if rc == sqlite.SQLITE_ROW:
                for idx in 0 ..< rowLen:
                    values[idx] = readColumn(prepared, idx)
                    columns[idx] = $sqlite.column_name(prepared, idx)
                yield ResultRow(values: values, columns: columns)
            elif rc == sqlite.SQLITE_DONE:
                break
            else:
                errorRc = rc
                break

#
# DbConn
#

proc exec*(db: DbConn, sql: string, params: varargs[DbValue, toDbValue]) =
    ## Executes ``sql``, which must be a single SQL statement.
    runnableExamples:
        let db = openDatabase(":memory:")
        db.exec("CREATE TABLE Person(name, age)")
        db.exec("INSERT INTO Person(name, age) VALUES(?, ?)",
            "John Doe", 23)
    assertCanUseDb db
    let prepared = db.prepareSql(sql, @params)
    let rc = sqlite.step(prepared)
    if db.cacheSize > 0:
        discard sqlite.reset(prepared)
    else:
        discard sqlite.finalize(prepared)
    db.checkRc(rc)

template transaction*(db: DbConn, body: untyped) =
    ## Starts a transaction and runs `body` within it. At the end the transaction is commited.
    ## If an error is raised by `body` the transaction is rolled back. Nesting transactions is a no-op.
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
    ## Executes ``sql``, which must be a single SQL statement, repeatedly using each element of
    ## ``params`` as parameters. The statements are executed inside a transaction.
    assertCanUseDb db
    db.transaction:
        for p in params:
            db.exec(sql, p)

proc execScript*(db: DbConn, sql: string) =
    ## Executes ``sql``, which can consist of multiple SQL statements.
    ## The statements are executed inside a transaction.
    assertCanUseDb db
    db.transaction:
        var remaining = sql.cstring
        while remaining.len > 0:
            var tail: cstring
            var prepared: sqlite.Stmt
            var rc = sqlite.prepare_v2(db.handle, remaining, sql.len.cint, prepared, tail)
            db.checkRc(rc)
            rc = sqlite.step(prepared)
            discard sqlite.finalize(prepared)
            db.checkRc(rc)
            remaining = tail

iterator iterate*(db: DbConn, sql: string,
        params: varargs[DbValue, toDbValue]): ResultRow =
    ## Executes ``sql``, which must be a single SQL statement, and yields each result row one by one.
    assertCanUseDb db
    let prepared = db.prepareSql(sql, @params)
    var errorRc: int32
    try:
        for row in db.iterate(prepared, params, errorRc):
            yield row
    finally:
        # The database might have been closed while iterating, in which
        # case we don't need to clean up the statement.
        if not db.handle.isNil:
            if db.cacheSize > 0:
                discard sqlite.reset(prepared)
            else:
                discard sqlite.finalize(prepared)
        db.checkRc(errorRc)

proc all*(db: DbConn, sql: string,
        params: varargs[DbValue, toDbValue]): seq[ResultRow] =
    ## Executes ``sql``, which must be a single SQL statement, and returns all result rows.
    for row in db.iterate(sql, params):
        result.add row

proc one*(db: DbConn, sql: string,
        params: varargs[DbValue, toDbValue]): Option[ResultRow] =
    ## Executes `sql`, which must be a single SQL statement, and returns the first result row.
    ## Returns `none(seq[DbValue])` if the result was empty.
    for row in db.iterate(sql, params):
        return some(row)

proc value*(db: DbConn, sql: string,
        params: varargs[DbValue, toDbValue]): Option[DbValue] =
    ## Executes `sql`, which must be a single SQL statement, and returns the first column of the first result row.
    ## Returns `none(DbValue)` if the result was empty.
    for row in db.iterate(sql, params):
        return some(row.values[0])

proc close*(db: DbConn) =
    ## Closes the database connection. This should be called once the connection will no longer be used
    ## to avoid leaking memory. Closing an already closed database is a harmless no-op.
    if not db.isOpen:
        return
    var prepared = sqlite.next_stmt(db.handle, nil)
    while not prepared.isNil:
        discard sqlite.finalize(prepared)
        prepared = sqlite.next_stmt(db.handle, nil)
    db.cache.clear()
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
    assertCanUseDb db
    sqlite.last_insert_rowid(db.handle)

proc changes*(db: DbConn): int32 =
    ## Get the number of changes triggered by the most recent INSERT, UPDATE or
    ## DELETE statement.
    ##
    ## For more information, refer to the SQLite documentation
    ## (https://www.sqlite.org/c3ref/changes.html).
    assertCanUseDb db
    sqlite.changes(db.handle)

proc isReadonly*(db: DbConn): bool =
    ## Returns true if ``db`` is in readonly mode.
    runnableExamples:
        let db = openDatabase(":memory:")
        doAssert not db.isReadonly
        let db2 = openDatabase(":memory:", dbRead)
        doAssert db2.isReadonly
    assertCanUseDb db
    sqlite.db_readonly(db.handle, "main") == 1

proc isOpen*(db: DbConn): bool {.inline.} =
    ## Returns true if `db` has been opened and not yet closed.
    runnableExamples:
        var db: DbConn
        doAssert not db.isOpen
        db = openDatabase(":memory:")
        doAssert db.isOpen
        db.close()
        doAssert not db.isOpen
    (not DbConnImpl(db).isNil) and (not db.handle.isNil)

proc isInTransaction*(db: DbConn): bool =
    ## Returns true if a transaction is currently active.
    runnableExamples:
        let db = openDatabase(":memory:")
        doAssert not db.isInTransaction
        db.transaction:
            doAssert db.isInTransaction
    assertCanUseDb db
    sqlite.get_autocommit(db.handle) == 0

proc unsafeHandle*(db: DbConn): sqlite.Sqlite3 {.inline.} =
    ## Returns the raw SQLite3 handle. This can be used to interact directly with the SQLite C API
    ## with the `tiny_sqlite/sqlite_wrapper` module. Note that the handle should not be used after `db.close` has
    ## been called as doing so would break memory safety.
    assert not DbConnImpl(db).handle.isNil, "Database is closed"
    DbConnImpl(db).handle

#
# SqlStatement
#

proc stmt*(db: DbConn, sql: string): SqlStatement =
    ## Constructs a prepared statement from `sql`.
    assertCanUseDb db
    let handle = prepareSql(db, sql)
    SqlStatementImpl(handle: handle, db: db).SqlStatement
    
proc exec*(statement: SqlStatement, params: varargs[DbValue, toDbValue]) =
    ## Executes `statement` with `params` as parameters.
    assertCanUseStatement statement
    var rc = statement.db.bindParams(statement.handle, params)
    if rc notin SqliteRcOk:
        discard sqlite.reset(statement.handle)
        statement.db.checkRc(rc)
    else:
        rc = sqlite.step(statement.handle)
        discard sqlite.reset(statement.handle)
        statement.db.checkRc(rc)

proc execMany*(statement: SqlStatement, params: seq[seq[DbValue]]) =
    ## Executes ``statement`` repeatedly using each element of ``params`` as parameters.
    ## The statements are executed inside a transaction.
    assertCanUseStatement statement
    statement.db.transaction:
        for p in params:
            statement.exec(p)

iterator iterate*(statement: SqlStatement, params: varargs[DbValue, toDbValue]): ResultRow =
    ## Executes ``statement`` and yields each result row one by one.
    assertCanUseStatement statement
    var errorRc: int32
    try:
        for row in statement.db.iterate(statement, params, errorRc):
            yield row
    finally:
        # The database might have been closed while iterating, in which
        # case we don't need to clean up the statement.
        if not statement.db.handle.isNil:
            discard sqlite.reset(statement.handle)
        statement.db.checkRc errorRc

proc all*(statement: SqlStatement, params: varargs[DbValue, toDbValue]): seq[ResultRow] =
    ## Executes ``statement`` and returns all result rows.
    assertCanUseStatement statement
    for row in statement.iterate(params):
        result.add row

proc one*(statement: SqlStatement,
        params: varargs[DbValue, toDbValue]): Option[ResultRow] =
    ## Executes `statement` and returns the first row found.
    ## Returns `none(seq[DbValue])` if no result was found.
    assertCanUseStatement statement
    for row in statement.iterate(params):
        return some(row)

proc value*(statement: SqlStatement,
        params: varargs[DbValue, toDbValue]): Option[DbValue] =
    ## Executes `statement` and returns the first column of the first row found. 
    ## Returns `none(DbValue)` if no result was found.
    assertCanUseStatement statement
    for row in statement.iterate(params):
        return some(row.values[0])

proc finalize*(statement: SqlStatement): void =
    ## Finalize the statement. This needs to be called once the statement is no longer used to
    ## prevent memory leaks. Finalizing an already finalized statement is a harmless no-op.
    if SqlStatementImpl(statement).isNil:
        return
    discard sqlite.finalize(statement.handle)
    SqlStatementImpl(statement).handle = nil

proc isAlive*(statement: SqlStatement): bool =
    ## Returns true if ``statement`` has been initialized and not yet finalized.
    (not SqlStatementImpl(statement).isNil) and (not statement.handle.isNil) and
        (not statement.db.handle.isNil)

proc openDatabase*(path: string, mode = dbReadWrite, cacheSize: Natural = 50): DbConn =
    ## Open a new database connection to a database file. To create an
    ## in-memory database the special path `":memory:"` can be used.
    ## If the database doesn't already exist and ``mode`` is ``dbReadWrite``,
    ## the database will be created. If the database doesn't exist and ``mode``
    ## is ``dbRead``, a ``SqliteError`` exception will be raised.
    ##
    ## NOTE: To avoid memory leaks, ``db.close`` must be called when the
    ## database connection is no longer needed.
    runnableExamples:
        let memDb = openDatabase(":memory:")
    var handle: sqlite.Sqlite3
    let db = new DbConnImpl
    db.handle = handle
    db.cacheSize = cacheSize
    result = DbConn(db)
    case mode
    of dbReadWrite:
        let rc = sqlite.open(path, db.handle)
        result.checkRc(rc)
    of dbRead:
        let rc = sqlite.open_v2(path, db.handle, sqlite.SQLITE_OPEN_READONLY, nil)
        result.checkRc(rc)

#
# ResultRow
#

proc `[]`*(row: ResultRow, idx: int): DbValue =
    ## Access a column in the result row based on index.
    row.values[idx]

proc `[]`*(row: ResultRow, column: string): DbValue =
    ## Access a column in te result row based on column name.
    ## The column name must be unambiguous.
    let idx = row.columns.find(column)
    doAssert idx != -1, "Column does not exist in row: '" & column & "'"
    doAssert count(row.columns, column) == 1, "Column exists multiple times in row: '" & column & "'"
    row.values[idx]

proc len*(row: ResultRow): int =
    ## Returns the number of columns in the result row.
    row.values.len

proc values*(row: ResultRow): seq[DbValue] =
    ## Returns all column values in the result row.
    row.values

proc columns*(row: ResultRow): seq[string] =
    ## Returns all column names in the result row.
    row.columns

proc unpack*[T: tuple](row: ResultRow, _: typedesc[T]): T =
    ## Calls ``fromDbValue`` on each element of ``row`` and returns it
    ## as a tuple.
    doAssert row.len == result.typeof.tupleLen,
        "Unpack expected a tuple with " & $row.len & " field(s) but found: " & $T
    var idx = 0
    for value in result.fields:
        value = row[idx].fromDbValue(type(value))
        idx.inc

#
# Deprecations
#

proc rows*(db: DbConn, sql: string,
        params: varargs[DbValue, toDbValue]): seq[seq[DbValue]] {.deprecated: "use 'all' instead".} =
    db.all(sql, params).mapIt(it.values)
    
iterator rows*(db: DbConn, sql: string,
        params: varargs[DbValue, toDbValue]): seq[DbValue] {.deprecated: "use 'all' instead".} =
    for row in db.all(sql, params):
        yield row.values

proc unpack*[T: tuple](row: seq[DbValue], _: typedesc[T]): T {.deprecated.} =
    ResultRow(values: row).unpack(T)