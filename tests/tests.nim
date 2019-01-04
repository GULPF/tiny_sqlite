import std / [unittest, os, options]
import tiny_sqlite

let path = paramStr(1)
if path.fileExists:
    echo "File already exists: ", path
    quit(1)

let db = openDatabase(path)

db.execScript("""
    CREATE TABLE Person(
        name TEXT,
        age INTEGER
    );
""")

db.exec("""
    INSERT INTO Person(name, age)
    VALUES(?, ?)
""", "John Doe", none(int))

let rows = db.rows("SELECT name, age FROM Person")

check rows.len == 1
let (name, age) = rows[0].unpack((Option[string], Option[int]))
check name.get == "John Doe"
check age.isNone

removeFile(path)
