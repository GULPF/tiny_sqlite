# Package

version       = "0.1.3"
author        = "Oscar Nihlgård"
description   = "A thin SQLite wrapper"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 1.0.0", "sqlite3_abi"

task test, "Run tests":
    exec "nim c -r tests/tests"
    rmFile "tests/tests"

task docs, "Generate docs":
    exec "nim doc -o:docs/tiny_sqlite.html src/tiny_sqlite.nim"