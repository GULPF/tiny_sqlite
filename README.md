# tiny_sqlite

A thin SQLite wrapper for Nim.

# Usage

## Opening a database connection.

A database connection is opened with the `openDatabase` procedure. If the file doesn't exist, it will be created. An in-memory database can be created by using the special path `":memory:"` as an argument.

```nim
    let db = openDatabase("path/to/file.db")
```

## Executing SQL

The `exec` procedure can be used to execute a single SQL statement. The `execScript` procedure is used to execute several statements, but it doesn't support parameter substitution.

```nim
    db.execScript("""
        CREATE TABLE Person(
            name TEXT,
            age INTEGER
        );
    """)

    db.exec("""
        INSERT INTO Person(name, age)
        VALUES(?, ?);
    """, "John Doe", 37)
```

## Reading data

To read data from the database, the `row` iterator and proc is used.

```nim
    for row in db.rows("SELECT name, age FROM Person"):
        # The `row` variable is of type `seq[DbValue]`.
        # Each column value can be converted to a normal
        # Nim type with the `fromDbValue` proc
        echo fromDbValue(row[0], string) # Prints the name
        echo fromDbValue(row[1], int)    # Prints the age
        # Alternativly, the entire row can be unpacked at once
        let (name, age) = row.unpack((string, int))
        # To handle NULL values, `Option[T]` is used
        echo fromDbValue(row[0], Option[string]) # Will work even if the db value is NULL
```

## Transactions

The `tiny_sqlite` module never starts or commits transactions on it's own. There are two options for handling transactions:

```nim
    # Option 1: using `db.exec` to begin/commit/rollback transactions.

    db.exec("BEGIN")
    try:
        db.execScript("""
            DELETE FROM Person;
            INSERT INTO Person(name, age) VALUES("Jane Doe", 35);
        """)
    except SqliteError:
        db.exec("ROLLBACK")
    db.exec("COMMIT")

    # Option 2: using the `transaction` template, which is a shortcut for the above code

    db.transaction:
        db.execScript("""
            DELETE FROM Person;
            INSERT INTO Person(name, age) VALUES("Jane Doe", 35);
        """)
```

## Supported types

For a type to be supported for unpacking and parameter substitution the procedures `toDbValue` and `fromDbValue` must both exist. Below is table describing which types are supported by default and to which SQLite type they are mapped to:

| Nim type    | SQLite type                       |
|-------------|-----------------------------------|
| `Ordinal`   | `INTEGER`                         |
| `SomeFloat` | `REAL`                            |
| `string`    | `TEXT`                            |
| `seq[byte]` | `BLOB`                            |
| `Option[T]` | `NULL` if none, otherwise map `T` |

This can be extended by implementing `toDdValue`  and `fromDbValue` on your own. Below is an example how support for `times.Time` can be added:

```nim
    import tiny_sqlite, times

    proc toDbValue(t: Time): DbValue =
        DbValue(kind: sqliteInt, toUnix(t))

    proc fromDbValue(val: DbValue, T: typedesc[Time]): Time =
        fromUnix(val.intval)
```