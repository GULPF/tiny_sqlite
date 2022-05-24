import pkg / sqlite3_abi

# const SqliteTransient* = cast[abi.SqliteDestructor](-1)

proc bind_text*(stmt: ptr sqlite3_stmt, col: cint, value: cstring, len: cint,
                destructor: SqliteDestructor): cint
    {.cdecl, dynlib: Lib, importc: "sqlite3_bind_text".}


export sqlite3_abi