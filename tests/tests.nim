import std / [unittest, options, sequtils]
import .. / src / tiny_sqlite

const SelectPersons = "SELECT name, age FROM Person"
const SelectJohnDoe = "SELECT name, age FROM Person WHERE name = 'John Doe'"
type SelectPersonsRowType = tuple[name: string, age: Option[int]]

proc writePersons(db: DbConn) {.used.} =
    for row in db.rows(SelectPersons):
        let (name, age) = row.unpack(SelectPersonsRowType)
        echo name, "\t", age

const seedScript = staticRead("./seed_test_db.sql")

template withDb(body: untyped) =
    let db {.inject.}= openDatabase(":memory:")
    db.execScript(seedScript)
    try:
        body
    finally:
        db.close()

test "db.rows":
    withDb:
        let rows = db.rows(SelectPersons)
        check rows.len == 2
        let unpackedRows = rows.mapIt(it.unpack(SelectPersonsRowType))
        check unpackedRows.anyIt(it.name == "John Doe" and it.age == some(47))
        check unpackedRows.anyIt(it.name == "Jane Doe" and it.age == none(int))

test "db.rows with break":
    # This tests that the prepared statement is cleaned up even when the iterator does
    # not run to completion
    withDb:
        for row in db.rows("SELECT name, age FROM Person WHERE name = ?", "John Doe"):
            break
        for row in db.rows("SELECT name, age FROM Person WHERE name = ?", "John Doe"):
            break

test "db.exec":
    withDb:
        db.exec("""
            INSERT INTO Person(name, age)
            VALUES(?, ?)
        """, "John Persson", 103)
        check db.changes == 1
        let rows = db.rows(SelectPersons)
        check rows.len == 3
        db.exec("DELETE FROM Person WHERE name = ?", "John Persson")
        check db.rows(SelectPersons).len == 2

test "db.execMany with failure":
    withDb:
        expect SqliteError:
            db.execMany("""
                INSERT INTO Person(name, age)
                VALUES(?, ?)
            """, @[@[toDbValue("John Doe"), toDbValue(23)], @[toDbValue("Jane Doe")]])
        let rows = db.rows(SelectPersons)
        check rows.len == 2

# Fails - known bug
when false:
    test "db.execMany in transaction":
        withDb:
            transaction:
                db.execMany("""
                    INSERT INTO Person(name, age)
                    VALUES(?, ?)
                """, @[@[toDbValue("John Doe"), toDbValue(23)], @[toDbValue("Jane Doe"), toDbValue(20)]])
                let rows = db.rows(SelectPersons)
                check rows.len == 2  

test "db.execScript with failure":
    withDb:
        expect SqliteError:
            db.execScript("""
                INSERT
                    INSERT INTO Person(name, age)
                    VALUES('John Persson', 23);

                    INSERT INTO Wrong(field)
                    VALUES(10);
            """)
        let rows = db.rows(SelectPersons)
        check rows.len == 2

test "db.execScript in transaction":
    withDb:
        expect SqliteError:
            db.execScript("""
                INSERT
                    INSERT INTO Person(name, age)
                    VALUES('John Persson', 23);

                    INSERT INTO Wrong(field)
                    VALUES(10);
            """)
        let rows = db.rows(SelectPersons)
        check rows.len == 2

test "db.transaction with return":
    withDb:
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
    withDb:
        proc fun() =
            db.transaction:
                db.exec("DELETE FROM Person")
                raise newException(Exception, "failure")
        try:
            fun()
        except:
            discard
        check db.rows("SELECT name, age FROM Person").len == 2

test "db.transaction nesting":
    withDb:
        db.transaction:
            db.transaction:
                check db.rows(SelectPersons).len == 2

test "db.isInTransaction":
    withDb:
        check not db.isInTransaction
        db.transaction:
            check db.isInTransaction
        check not db.isInTransaction

test "db.isOpen":
    var db: DbConn
    check not db.isOpen
    db = openDatabase(":memory:")
    check db.isOpen
    db.close()
    check not db.isOpen

test "db.isReadonly":
    withDb:
        check not db.isReadonly
        let readonlyDb = openDatabase(":memory:", dbRead)
        check readonlyDb.isReadonly
        readonlyDb.close()

test "db.close twice":
    let db = openDatabase(":memory:")
    db.close()
    db.close()

test "row.unpack":
    withDb:
        let row = db.rows(SelectJohnDoe)[0]
        let (name, age) = row.unpack((string, int))
        doAssert (name, age) == ("John Doe", 47)
        expect AssertionError:
            discard row.unpack(tuple[name: string])

test "cacheSize=0":
    let db = openDatabase(":memory:", cacheSize = 0)
    db.execScript(seedScript)
    discard db.rows(SelectPersons)
    discard db.rows(SelectPersons)
    db.close()

test "SqliteError":
    withDb:
        expect SqliteError:
            db.execScript("""
                CREATE TABLE Person(
                    name TEXT,
                    age INTEGER
                );
            """)
        expect SqliteError:
            discard openDatabase("some/made/up/path", dbRead)

test "Type mappings":
    withDb:
        let rows = db.rows("SELECT * FROM Types")
        check rows.len == 1
        block:
            let unpackedRow = rows[0].unpack((string, int, float, Option[int], seq[byte]))
            check unpackedRow[0] == "foo åäö 𐐷"
            check unpackedRow[1] == 1
            check unpackedRow[2] == 1.5
            check unpackedRow[3] == none(int)
            check unpackedRow[4] == @[0x01'u8, 0x02'u8, 0xFF'u8]
        block:
            # sqliteInteger can be treated as bool (or any other ordinal as well)
            let unpackedRow = rows[0].unpack((string, bool, float, Option[int], seq[byte]))
            check unpackedRow[1]