when defined(windows):
  when defined(nimOldDlls):
    const Lib = "sqlite3.dll"
  elif defined(cpu64):
    const Lib = "sqlite3_64.dll"
  else:
    const Lib = "sqlite3_32.dll"
elif defined(macosx):
  const
    Lib = "libsqlite3(|.0).dylib"
else:
  const
    Lib = "libsqlite3.so(|.0)"

type
    Sqlite3* = ptr object

    Stmt* = ptr object

    Callback* = proc (p: pointer, para2: cint, para3, para4: cstringArray): cint
        {.cdecl, raises: [].}

    SqliteDestructor* = proc (p: pointer)
        {.cdecl, locks: 0, tags: [], raises: [], gcsafe.}

const
    SQLITE_OK*         = 0.cint
    SQLITE_ERROR*      = 1.cint # SQL error or missing database
    SQLITE_INTERNAL*   = 2.cint # An internal logic error in SQLite
    SQLITE_PERM*       = 3.cint # Access permission denied
    SQLITE_ABORT*      = 4.cint # Callback routine requested an abort
    SQLITE_BUSY*       = 5.cint # The database file is locked
    SQLITE_LOCKED*     = 6.cint # A table in the database is locked
    SQLITE_NOMEM*      = 7.cint # A malloc() failed
    SQLITE_READONLY*   = 8.cint # Attempt to write a readonly database
    SQLITE_INTERRUPT*  = 9.cint # Operation terminated by sqlite3_interrupt()
    SQLITE_IOERR*      = 10.cint # Some kind of disk I/O error occurred
    SQLITE_CORRUPT*    = 11.cint # The database disk image is malformed
    SQLITE_NOTFOUND*   = 12.cint # (Internal Only) Table or record not found
    SQLITE_FULL*       = 13.cint # Insertion failed because database is full
    SQLITE_CANTOPEN*   = 14.cint # Unable to open the database file
    SQLITE_PROTOCOL*   = 15.cint # Database lock protocol error
    SQLITE_EMPTY*      = 16.cint # Database is empty
    SQLITE_SCHEMA*     = 17.cint # The database schema changed
    SQLITE_TOOBIG*     = 18.cint # Too much data for one row of a table
    SQLITE_CONSTRAINT* = 19.cint # Abort due to contraint violation
    SQLITE_MISMATCH*   = 20.cint # Data type mismatch
    SQLITE_MISUSE*     = 21.cint # Library used incorrectly
    SQLITE_NOLFS*      = 22.cint # Uses OS features not supported on host
    SQLITE_AUTH*       = 23.cint # Authorization denied
    SQLITE_FORMAT*     = 24.cint # Auxiliary database format error
    SQLITE_RANGE*      = 25.cint # 2nd parameter to sqlite3_bind out of range
    SQLITE_NOTADB*     = 26.cint # File opened that is not a database file
    SQLITE_NOTICE*     = 27.cint
    SQLITE_WARNING*    = 28.cint
    SQLITE_ROW*        = 100.cint # sqlite3_step() has another row ready
    SQLITE_DONE*       = 101.cint # sqlite3_step() has finished executing

const
  SQLITE_INTEGER* = 1.cint
  SQLITE_FLOAT* = 2.cint
  SQLITE_TEXT* = 3.cint
  SQLITE_BLOB* = 4.cint
  SQLITE_NULL* = 5.cint
  SQLITE_UTF8* = 1.cint
  SQLITE_UTF16LE* = 2.cint
  SQLITE_UTF16BE* = 3.cint         # Use native byte order
  SQLITE_UTF16* = 4.cint           # sqlite3_create_function only
  SQLITE_ANY* = 5.cint             #sqlite_exec return values
  SQLITE_COPY* = 0.cint
  SQLITE_CREATE_INDEX* = 1.cint
  SQLITE_CREATE_TABLE* = 2.cint
  SQLITE_CREATE_TEMP_INDEX* = 3.cint
  SQLITE_CREATE_TEMP_TABLE* = 4.cint
  SQLITE_CREATE_TEMP_TRIGGER* = 5.cint
  SQLITE_CREATE_TEMP_VIEW* = 6.cint
  SQLITE_CREATE_TRIGGER* = 7.cint
  SQLITE_CREATE_VIEW* = 8.cint
  SQLITE_DELETE* = 9.cint
  SQLITE_DROP_INDEX* = 10.cint
  SQLITE_DROP_TABLE* = 11.cint
  SQLITE_DROP_TEMP_INDEX* = 12.cint
  SQLITE_DROP_TEMP_TABLE* = 13.cint
  SQLITE_DROP_TEMP_TRIGGER* = 14.cint
  SQLITE_DROP_TEMP_VIEW* = 15.cint
  SQLITE_DROP_TRIGGER* = 16.cint
  SQLITE_DROP_VIEW* = 17.cint
  SQLITE_INSERT* = 18.cint
  SQLITE_PRAGMA* = 19.cint
  SQLITE_READ* = 20.cint
  SQLITE_SELECT* = 21.cint
  SQLITE_TRANSACTION* = 22.cint
  SQLITE_UPDATE* = 23.cint
  SQLITE_ATTACH* = 24.cint
  SQLITE_DETACH* = 25.cint
  SQLITE_ALTER_TABLE* = 26.cint
  SQLITE_REINDEX* = 27.cint
  SQLITE_DENY* = 1.cint
  SQLITE_IGNORE* = 2.cint 
  SQLITE_DETERMINISTIC* = 0x800.cint

const
  SQLITE_OPEN_READONLY* =        0x00000001.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_READWRITE* =       0x00000002.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_CREATE* =          0x00000004.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_DELETEONCLOSE* =   0x00000008.cint    #/* VFS only */
  SQLITE_OPEN_EXCLUSIVE* =       0x00000010.cint    #/* VFS only */
  SQLITE_OPEN_AUTOPROXY* =       0x00000020.cint    #/* VFS only */
  SQLITE_OPEN_URI* =             0x00000040.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_MEMORY* =          0x00000080.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_MAIN_DB* =         0x00000100.cint    #/* VFS only */
  SQLITE_OPEN_TEMP_DB* =         0x00000200.cint    #/* VFS only */
  SQLITE_OPEN_TRANSIENT_DB* =    0x00000400.cint    #/* VFS only */
  SQLITE_OPEN_MAIN_JOURNAL* =    0x00000800.cint    #/* VFS only */
  SQLITE_OPEN_TEMP_JOURNAL* =    0x00001000.cint    #/* VFS only */
  SQLITE_OPEN_SUBJOURNAL* =      0x00002000.cint    #/* VFS only */
  SQLITE_OPEN_MASTER_JOURNAL* =  0x00004000.cint    #/* VFS only */
  SQLITE_OPEN_NOMUTEX* =         0x00008000.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_FULLMUTEX* =       0x00010000.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_SHAREDCACHE* =     0x00020000.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_PRIVATECACHE* =    0x00040000.cint  #/* Ok for sqlite3_open_v2() */
  SQLITE_OPEN_WAL* =             0x00080000.cint    #/* VFS only */

const
  SQLITE_STATIC* = nil
  SQLITE_TRANSIENT* = cast[SqliteDestructor](-1)

const
    SQLITE_DBCONFIG_MAINDBNAME* =            1000.cint
    SQLITE_DBCONFIG_LOOKASIDE* =             1001.cint
    SQLITE_DBCONFIG_ENABLE_FKEY* =           1002.cint
    SQLITE_DBCONFIG_ENABLE_TRIGGER* =        1003.cint
    SQLITE_DBCONFIG_ENABLE_FTS3_TOKENIZER* = 1004.cint
    SQLITE_DBCONFIG_ENABLE_LOAD_EXTENSION* = 1005.cint
    SQLITE_DBCONFIG_NO_CKPT_ON_CLOSE* =      1006.cint
    SQLITE_DBCONFIG_ENABLE_QPSG* =           1007.cint
    SQLITE_DBCONFIG_TRIGGER_EQP* =           1008.cint
    SQLITE_DBCONFIG_RESET_DATABASE* =        1009.cint
    SQLITE_DBCONFIG_DEFENSIVE* =             1010.cint
    SQLITE_DBCONFIG_WRITABLE_SCHEMA* =       1011.cint
    SQLITE_DBCONFIG_LEGACY_ALTER_TABLE* =    1012.cint
    SQLITE_DBCONFIG_DQS_DML* =               1013.cint
    SQLITE_DBCONFIG_DQS_DDL* =               1014.cint
    SQLITE_DBCONFIG_ENABLE_VIEW* =           1015.cint
    SQLITE_DBCONFIG_LEGACY_FILE_FORMAT* =    1016.cint
    SQLITE_DBCONFIG_TRUSTED_SCHEMA* =        1017.cint
    SQLITE_DBCONFIG_MAX* =                   1017.cint

proc close*(db: Sqlite3): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_close".}

proc exec*(db: Sqlite3, sql: cstring, cb: Callback, p: pointer, errmsg: var cstring): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_exec".}

proc last_insert_rowid*(db: Sqlite3): int64
    {.cdecl, dynlib: Lib, importc: "sqlite3_last_insert_rowid".}

proc changes*(db: Sqlite3): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_changes".}

proc total_changes*(db: Sqlite3): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_total_changes".}

proc busy_handler*(db: Sqlite3,
                   handler: proc (p: pointer, x: cint): cint {.cdecl.},
                   p: pointer): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_busy_handler".}

proc busy_timeout*(db: Sqlite3, ms: cint): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_busy_timeout".}

proc open*(filename: cstring, db: var Sqlite3): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_open".}

proc open_v2*(filename: cstring, db: var Sqlite3, flags: cint, zVfsName: cstring ): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_open_v2".}

proc errcode*(db: Sqlite3): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_errcode".}

proc errmsg*(db: Sqlite3): cstring
    {.cdecl, dynlib: Lib, importc: "sqlite3_errmsg".}

proc prepare_v2*(db: Sqlite3, zSql: cstring, nByte: cint, stmt: var Stmt,
                pzTail: var cstring): cint
    {.importc: "sqlite3_prepare_v2", cdecl, dynlib: Lib.}

proc bind_blob*(stmt: Stmt, col: cint, value: pointer, len: cint,
                para5: SqliteDestructor): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_blob".}

proc bind_double*(stmt: Stmt, col: cint, value: float64): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_double".}

proc bind_int*(stmt: Stmt, col: cint, value: cint): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_int".}

proc bind_int64*(stmt: Stmt, col: cint, value: int64): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_int64".}

proc bind_null*(stmt: Stmt, col: cint): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_null".}

proc bind_text*(stmt: Stmt, col: cint, value: cstring, len: cint,
                destructor: SqliteDestructor): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_text".}

proc bind_parameter_count*(stmt: Stmt): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_parameter_count".}

proc bind_parameter_name*(stmt: Stmt, col: cint): cstring
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_parameter_name".}

proc bind_parameter_index*(stmt: Stmt, colName: cstring): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_parameter_index".}

proc clear_bindings*(stmt: Stmt): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_clear_bindings".}

proc column_count*(stmt: Stmt): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_count".}

proc column_name*(stmt: Stmt, col: cint): cstring
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_name".}

proc column_table_name*(stmt: Stmt, col: cint): cstring
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_table_name".}

proc column_decltype*(stmt: Stmt, col: cint): cstring
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_decltype".}

proc step*(stmt: Stmt): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_step".}

proc data_count*(stmt: Stmt): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_data_count".}

proc column_blob*(stmt: Stmt, col: cint): pointer
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_blob".}

proc column_bytes*(stmt: Stmt, col: cint): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_bytes".}

proc column_double*(stmt: Stmt, col: cint): float64
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_double".}

proc column_int*(stmt: Stmt, col: cint): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_int".}

proc column_int64*(stmt: Stmt, col: cint): int64
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_int64".}

proc column_text*(stmt: Stmt, col: cint): cstring
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_text".}

proc column_type*(stmt: Stmt, col: cint): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_column_type".}

proc finalize*(stmt: Stmt): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_finalize".}

proc reset*(stmt: Stmt): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_reset".}

proc libversion*(): cstring
    {.cdecl, dynlib: Lib, importc: "sqlite3_libversion".}

proc libversion_number*(): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_libversion_number".}

proc db_handle*(stmt: Stmt): Sqlite3
    {.cdecl, dynlib: Lib, importc: "sqlite3_db_handle".}

proc get_autocommit*(db: Sqlite3): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_get_autocommit".}

proc db_readonly*(db: Sqlite3, dbname: cstring): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_db_readonly".}

proc next_stmt*(db: Sqlite3, stmt: Stmt): Stmt
    {.cdecl, dynlib: Lib, importc: "sqlite3_next_stmt".}

proc stmt_busy*(stmt: Stmt): bool
    {.cdecl, dynlib: Lib, importc: "sqlite3_stmt_busy".}

proc db_config*(db: Sqlite3, op: cint, a, b: cint): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_db_config".}

proc load_extension*(db: Sqlite3, filename: cstring, entry: cstring, error: var cstring): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_load_extension".}

proc free*(z: cstring)
    {.cdecl, dynlib: Lib, importc: "sqlite3_free".}