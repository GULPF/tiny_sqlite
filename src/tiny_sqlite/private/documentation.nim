##[
### Opening a database connection.

A database connection is opened with the `openDatabase` procedure. If the file doesn't exist, it will be created.
An in-memory database can be created by using the special path `":memory:"` as an argument.
Once the database connection is no longer needed `db.close()` must be called to prevent memory leaks.

```nim
let db = openDatabase("path/to/file.db")
# ... (do something with `db`)
db.close()
```

### Executing SQL

The `exec` procedure can be used to execute a single SQL statement. The `execScript` procedure is used to execute
several statements, but it doesn't support parameter substitution.

```nim
db.execScript("""
    CREATE TABLE Person(
        name TEXT,
        age INTEGER
    );

    CREATE TABLE Log(
        message TEXT
    );
""")

db.exec("""
    INSERT INTO Person(name, age)
    VALUES(?, ?);
""", "John Doe", 37)
```

### Reading data

Three different procs for reading data are available:

- `all`: returns all result rows
- `one`: returns the first result row, or `none` if not result row exists
- `value`: returns the first column of the first row, or `none` if not result row exists

```nim
for row in db.all("SELECT name, age FROM Person"):
    # The `row` variable is of type `seq[DbValue]`.
    # Each column value can be converted to a normal
    # Nim type with the `fromDbValue` proc
    echo fromDbValue(row[0], string) # Prints the name
    echo fromDbValue(row[1], int)    # Prints the age
    # Alternatively, the entire row can be unpacked at once
    let (name, age) = row.unpack((string, int))
    # To handle NULL values, `Option[T]` is used
    echo fromDbValue(row[0], Option[string]) # Will work even if the db value is NULL
```

### Inserting data

The `execMany` proc can be used to execute an SQL statement several times with different parameters.
This is especially useful for insertions:

```nim
let parameters = @[@[toDbValue("Person 1")], @[toDbValue("Person 2")]]
# Will insert two rows
db.execMany("""
    INSERT INTO Person(name)
    VALUES(?);
""", parameters)
```

### Transactions

The procedures that can execute multiple SQL statements (`execScript` and `execMany`) are wrapped in a transaction by
`tiny_sqlite`. Transactions can also be controlled manually by using one of these two options:

**Option 1: using tiny_sqlite.transaction**
```nim
db.transaction:
    # Anything inside here is executed inside a transaction which
    # will be rolled back in case of an error
    db.execScript("""
        DELETE FROM Person;
        INSERT INTO Person(name, age) VALUES("Jane Doe", 35);
    """)
```
**Option 2: using tiny_sqlite.exec manually**
```nim
db.exec("BEGIN")
try:
    db.exec("DELETE FROM Person")
    db.exec"INSERT INTO Person(name, age) VALUES("Jane Doe", 35)")
except SqliteError:
    db.exec("ROLLBACK")
db.exec("COMMIT")
```

### Supported types

For a type to be supported when using unpacking and parameter substitution the procedures `toDbValue` and `fromDbValue`
must be implemented for the type. Below is table describing which types are supported by default and to which SQLite
type they are mapped to:

====================  =================================================================================
Nim type              SQLite type
====================  =================================================================================
``Ordinal``           | ``INTEGER``
``SomeFloat``         | ``TEXT``
``string``            | ``REAL``
``seq[byte]``         | ``BLOB``
``Option[T]``         | ``NULL`` if value is ``none(T)``, otherwise the type that ``T`` would use
====================  =================================================================================

This can be extended by implementing `toDdValue`  and `fromDbValue` for other types on your own. Below is an example
how support for `times.Time` can be added:

```nim
import tiny_sqlite, times

proc toDbValue(t: Time): DbValue =
    DbValue(kind: sqliteInt, toUnix(t))

proc fromDbValue(val: DbValue, T: typedesc[Time]): Time =
    fromUnix(val.intval)
```
]##