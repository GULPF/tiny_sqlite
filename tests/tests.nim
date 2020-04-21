import std / [unittest, os, options, sequtils]
import .. / src / tiny_sqlite

const SELECT_PERSONS = "SELECT name, age FROM Person"
type SELECT_PERSONS_ROW_TYPE = tuple[name: string, age: Option[int]]

proc writePersons(db: DbConn) {.used.} =
    for row in db.rows(SELECT_PERSONS):
        let (name, age) = row.unpack(SELECT_PERSONS_ROW_TYPE)
        echo name, "\t", age

let db = openDatabase(":memory:")
const seedScript = staticRead("./seed_test_db.sql")
db.execScript(seedScript)

test "db.isReadonly":
    check not db.isReadonly
    let readonlyDb = openDatabase(":memory:", dbRead)
    check readonlyDb.isReadonly

test "db.rows":
    let rows = db.rows(SELECT_PERSONS)
    check rows.len == 2
    let unpackedRows = rows.mapIt(it.unpack(SELECT_PERSONS_ROW_TYPE))
    check unpackedRows.anyIt(it.name == "John Doe" and it.age == some(47))
    check unpackedRows.anyIt(it.name == "Jane Doe" and it.age == none(int))

test "db.exec":
    db.exec("""
        INSERT INTO Person(name, age)
        VALUES(?, ?)
    """, "John Persson", 103)
    check db.changes == 1
    let rows = db.rows(SELECT_PERSONS)
    check rows.len == 3
    db.exec("DELETE FROM Person WHERE name = ?", "John Persson")
    check db.rows(SELECT_PERSONS).len == 2


test "db.transaction with return":
    proc fun() =
        db.transaction:
            db.exec("INSERT INTO Person(name, age) VALUES('John Persson', 103)")
            return
    fun()
    let rows = db.rows("SELECT * FROM Person")
    check rows.len == 3
    db.exec("DELETE FROM Person WHERE name = 'John Persson'")
    check db.rows("SELECT name, age FROM Person").len == 2


test "db.transaction with exception":
    proc fun() =
        db.transaction:
            db.exec("DELETE FROM Person")
            raise newException(Exception, "failure")
    try:
        fun()
    except:
        discard
    check db.rows("SELECT name, age FROM Person").len == 2

test "SqliteError":
    expect SqliteError:
        db.execScript("""
            CREATE TABLE Person(
                name TEXT,
                age INTEGER
            );
        """)
    expect SqliteError:
        discard openDatabase("some/made/up/path", dbRead)
