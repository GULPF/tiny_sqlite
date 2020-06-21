# tiny_sqlite

NOTE: the API is still evolving and breaking changes might be introduced

`tiny_sqlite` is a comparatively thin wrapper for the SQLite database library. It differs from the standard library module `std/sqlite` in several ways:

- `tiny_sqlite` represents database values with a type safe case object called `DbValue` instead of treating every value as a string, which among other things means that SQLite `NULL` values can be properly supported.

- `tiny_sqlite` is not designed as a generic database API, only SQLite will ever be supported. The database modules in the standard library are built with replaceability in mind so that the code might work with several different database engines just by replacing an import. This is not the case for `tiny_sqlite`.

## Installation

`tiny_sqlite` is available on Nimble:

```
nimble install tiny_sqlite
```

## Usage

```nim
import tiny_sqlite, std / options

let db = openDatabase(":memory:")
db.execScript("""
CREATE TABLE Person(
    name TEXT,
    age INTEGER
);

INSERT INTO
    Person(name, age)
VALUES
    ('John Doe', 47);
""")

db.exec("INSERT INTO Person VALUES(?, ?)", "Jane Doe", nil)

for row in db.all("SELECT name, age FROM Person"):
    let (name, age) = row.unpack((string, Option[int]))
    echo name, " ", age

# Output:
# John Doe Some(47)
# Jane Doe None[int]
```

## Documentation

- [Documentation available here](https://gulpf.github.io/tiny_sqlite/tiny_sqlite.html).


