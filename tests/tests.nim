import std / [unittest, os, options]
import .. / src / tiny_sqlite

let db = openDatabase(":memory:")

doAssert(not db.isReadonly)

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

db.close

let readonly = openDatabase(":memory:", dbRead)
doAssert readonly.isReadonly

doAssertRaises(SqliteError):
    db.execScript("""
        CREATE TABLE Person(
            name TEXT,
            age INTEGER
        );
    """)

doAssertRaises(SqliteError):
    discard openDatabase("some/made/up/path", dbRead)