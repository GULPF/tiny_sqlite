import std / [unittest, options, sequtils, times]
import .. / src / tiny_sqlite

const SelectPersons = "SELECT name, age FROM Person"
const SelectJohnDoe = "SELECT name, age FROM Person WHERE name = 'John Doe'"
type SelectPersonsRowType = tuple[name: string, age: Option[int]]

proc writePersons(db: DbConn) {.used.} =
    for row in db.all(SelectPersons):
        let (name, age) = row.unpack(SelectPersonsRowType)
        echo name, "\t", age

const seedScript = staticRead("./seed_test_db.sql")

template withDb(body: untyped) =
    block:
        let db {.inject.} = openDatabase(":memory:")
        db.execScript(seedScript)
        try:
            body
        finally:
            db.close()

test "db.all":
    withDb:
        let rows = db.all(SelectPersons)
        check rows.len == 2
        let unpackedRows = rows.mapIt(it.unpack(SelectPersonsRowType))
        check unpackedRows.anyIt(it.name == "John Doe" and it.age == some(47))
        check unpackedRows.anyIt(it.name == "Jane Doe" and it.age == none(int))

test "db.all with break":
    # This tests that the prepared statement is cleaned up even when the iterator does
    # not run to completion
    withDb:
        for row in db.all("SELECT name, age FROM Person WHERE name = ?", "John Doe"):
            break
        for row in db.all("SELECT name, age FROM Person WHERE name = ?", "John Doe"):
            break

test "db.iterate close":
    withDb:
        expect AssertionDefect:
            for row in db.iterate(SelectPersons):
                db.close()

test "db.one":
    withDb:
        discard db.one(SelectPersons).get.unpack((string, int))
        check db.one(SelectJohnDoe).get[0].strVal == "John Doe"
        check db.one("SELECT * FROM Person WHERE name = ?", "John Person") == none(ResultRow)

test "db.value":
    withDb:
        db.exec("PRAGMA user_version = 1")
        check db.value("PRAGMA user_version").get.intVal == 1

test "db.value no rows":
    withDb:
        check db.value("SELECT * FROM Person Where age = 0") == none(DbValue)

test "db.exec":
    withDb:
        db.exec("""
            INSERT INTO Person(name, age)
            VALUES(?, ?)
        """, "John Persson", 103)
        check db.changes == 1
        let rows = db.all(SelectPersons)
        check rows.len == 3
        db.exec("DELETE FROM Person WHERE name = ?", "John Persson")
        check db.all(SelectPersons).len == 2

test "db.exec trailing comment":
    withDb:
        db.exec("""
            INSERT INTO Person(name, age)
            VALUES(?, ?);
            -- comment
            /*
            comment
            */
        """, "John Persson", 103)
        check db.changes == 1
        let rows = db.all(SelectPersons)
        check rows.len == 3
        db.exec("DELETE FROM Person WHERE name = ?", "John Persson")
        check db.all(SelectPersons).len == 2

test "db.exec trailing syntax error":
    withDb:
        expect AssertionDefect:
            db.exec("""
                INSERT INTO Person(name, age)
                VALUES(?, ?);
                /*
                comment
                *
            """, "John Persson", 103)

test "db.exec with multiple SQL statements":
    withDb:
        expect AssertionDefect:
            db.exec("""
                INSERT INTO Person(name, age)
                VALUES(?, ?);
                INSERT INTO Person(name, age)
                VALUES(?, ?);
            """, "John Persson", 103, "John Persson", 103)

test "db.execMany":
    withDb:
        db.execMany("""
            INSERT INTO Person(name, age)
            VALUES(?, ?)
        """, @[toDbValues("John Doe", 23), toDbValues("Jane Doe", 22)])
        let rows = db.all(SelectPersons)
        check rows.len == 4

test "db.execMany with failure":
    withDb:
        expect SqliteError:
            db.execMany("""
                INSERT INTO Person(name, age)
                VALUES(?, ?)
            """, @[@[toDbValue("John Doe"), toDbValue(23)], @[toDbValue("Jane Doe")]])
        let rows = db.all(SelectPersons)
        check rows.len == 2

test "db.execMany in transaction":
    withDb:
        db.transaction:
            db.execMany("""
                INSERT INTO Person(name, age)
                VALUES(?, ?)
            """, @[@[toDbValue("John Doe"), toDbValue(23)], @[toDbValue("Jane Doe"), toDbValue(20)]])
            let rows = db.all(SelectPersons)
            check rows.len == 4

test "db.execScript trailing comment":
    withDb:
        db.execScript("""
            INSERT INTO Person(name, age)
            VALUES('John Persson', 23);
            INSERT INTO Person(name, age)
            VALUES('John Persson', 23);
            -- comment
            /*
            comment
            */
        """)
        let rows = db.all(SelectPersons)
        check rows.len == 4

test "db.execScript in transaction":
    withDb:
        db.transaction:
            db.execScript("""
                INSERT INTO Person(name, age)
                VALUES('John Persson', 23);
                INSERT INTO Person(name, age)
                VALUES('John Persson', 23);
            """)
            let rows = db.all(SelectPersons)
            check rows.len == 4

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
        let rows = db.all(SelectPersons)
        check rows.len == 2

test "db.transaction with return":
    withDb:
        proc fun() =
            db.transaction:
                db.exec("INSERT INTO Person(name, age) VALUES('John Persson', 103)")
                return
        fun()
        let rows = db.all("SELECT * FROM Person")
        check rows.len == 3
        db.exec("DELETE FROM Person WHERE name = 'John Persson'")
        check db.all("SELECT name, age FROM Person").len == 2


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
        check db.all("SELECT name, age FROM Person").len == 2

test "db.transaction nesting":
    withDb:
        db.transaction:
            db.transaction:
                check db.all(SelectPersons).len == 2

test "db.isInTransaction":
    withDb:
        check not db.isInTransaction
        db.transaction:
            check db.isInTransaction
        check not db.isInTransaction

test "db.isOpen":
    var db: DbConn
    check not db.isOpen
    expect AssertionDefect:
        discard db.all(SelectPersons)
    db = openDatabase(":memory:")
    check db.isOpen
    db.close()
    check not db.isOpen
    expect AssertionDefect:
        discard db.all(SelectPersons)

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

test "db.close with live statements":
    let db = openDatabase(":memory:")
    db.execScript(seedScript)
    let stmt {.used.} = db.stmt(SelectPersons)
    db.close()
    check not stmt.isAlive

test "db.close default value":
    var db: DbConn
    db.close()

when not defined(macosx):
    test "db.loadExtension":
        withDb:
            expect SqliteError:
                db.loadExtension("invalid extension path")

test "row.unpack":
    withDb:
        let row = db.one(SelectJohnDoe).get
        let (name, age) = row.unpack((string, int))
        check (name, age) == ("John Doe", 47)
        expect AssertionDefect:
            discard row.unpack(tuple[name: string])

test "stmt.columnMetadata":
    withDb:
        let stmt = db.stmt(SelectPersons)
        check stmt.columnCount == 2
        let col1 = stmt.columnMetadata(1)
        check col1.isSome
        check col1.get.databaseName == "main"
        check col1.get.tableName == "Person"
        check col1.get.originName == "age"
        let col2 = stmt.columnMetadata(2)
        check col2.isNone

test "stmt.all":
    withDb:
        let stmt = db.stmt(SelectPersons)
        for i in 0 .. 1:
            let rows = stmt.all()
            check rows.len == 2
            let unpackedRows = rows.mapIt(it.unpack(SelectPersonsRowType))
            check unpackedRows.anyIt(it.name == "John Doe" and it.age == some(47))
            check unpackedRows.anyIt(it.name == "Jane Doe" and it.age == none(int))
        stmt.finalize()

    withDb:
        let stmt = db.stmt("SELECT name, age FROM Person WHERE name = ?")
        expect SqliteError:
            discard stmt.all()
        var rows = stmt.all("John Doe")
        check rows.len == 1
        check rows[0][0].fromDbValue(string) == "John Doe"
        check rows[0][1].fromDbValue(int) == 47
        rows = stmt.all("Jane Doe")
        check rows.len == 1
        check rows[0][0].fromDbValue(string) == "Jane Doe"
        check rows[0][1].fromDbValue(Option[int]) == none(int)
        stmt.finalize()

test "stmt.iterate busy":
    withDb:
        let stmt = db.stmt(SelectPersons)
        for row in stmt.iterate():
            expect AssertionDefect:
                discard stmt.all()
            expect AssertionDefect:
                discard stmt.one()
            expect AssertionDefect:
                discard stmt.value()
            expect AssertionDefect:
                stmt.exec()

test "stmt.iterate close/finalize":
    withDb:
        let stmt = db.stmt(SelectPersons)
        expect AssertionDefect:
            for row in stmt.iterate():
                db.close()
    withDb:
        let stmt = db.stmt(SelectPersons)
        expect AssertionDefect:
            for row in stmt.iterate():
                stmt.finalize()

test "stmt.isAlive":
    withDb:
        var stmt: SqlStatement
        check not stmt.isAlive
        expect AssertionDefect:
            discard stmt.all()
        stmt = db.stmt(SelectPersons)
        check stmt.isAlive
        stmt.finalize()
        check not stmt.isAlive
        expect AssertionDefect:
            discard stmt.all()

test "stmt.finalize twice":
    withDb:
        let stmt = db.stmt(SelectPersons)
        stmt.finalize()
        stmt.finalize()

test "stmt.finalize default value":
    var stmt: SqlStatement
    stmt.finalize()

test "cacheSize=0":
    let db = openDatabase(":memory:", cacheSize = 0)
    db.execScript(seedScript)
    discard db.all(SelectPersons)
    discard db.all(SelectPersons)
    db.close()

test "ResultRow":
    withDb:
        let row = db.one(SelectPersons).get
        doAssert row["name"].strVal == "John Doe"
        doAssert row[0].strVal == "John Doe"
        doAssert row["age"].intVal == 47
        doAssert row[1].intVal == 47

    withDb:
        let row = db.one("SELECT a.name, b.name FROM Person a JOIN Person b").get
        check row.columns == @["name", "name"]
        expect AssertionDefect:
            discard row["name"]

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
        let rows = db.all("SELECT * FROM Types")
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

proc toDbValue(t: Time): DbValue =
    DbValue(kind: sqliteInteger, intVal: toUnix(t))

proc fromDbValue(value: DbValue, T: typedesc[Time]): Time =
    fromUnix(value.intval)

test "Custom type mapping":
    withDb:
        db.exec("CREATE TABLE Foo(timestamp INTEGER)")
        db.exec("INSERT INTO Foo(timestamp) VALUES(?)", fromUnix(12))
        let row = db.one("SELECT timestamp FROM Foo")
        check row.isSome
        let (timestamp,) = row.get.unpack((Time,))
        check timestamp == fromUnix(12)

test "Foreign keys":
    withDb:
        db.exec("""
            CREATE TABLE ForeignKey(
                id INTEGER,
                personId INTEGER,
                FOREIGN KEY(personId) REFERENCES Person(id)
            );
        """)
        db.exec("PRAGMA foreign_keys = ON;")
        db.exec("INSERT INTO ForeignKey(personId) VALUES(NULL)")
        db.exec("INSERT INTO ForeignKey(personId) VALUES(1)")
        expect SqliteError:
            db.exec("INSERT INTO ForeignKey(personId) VALUES(100)")
