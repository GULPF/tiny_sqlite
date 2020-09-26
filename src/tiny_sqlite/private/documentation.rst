***********
tiny_sqlite
***********

Opening a database connection.
##############################

A database connection is opened by calling the `openDatabase <#openDatabase,string,Natural>`_ procedure with the
path to the database file as an argument. If the file doesn't exist, it will be created. An in-memory database can
be created by using the special path `":memory:"` as an argument. Once the database connection is no longer needed
`close <#close,DbConn>`_ must be called to prevent memory leaks.

.. code-block:: nim

    let db = openDatabase("path/to/file.db")
    # ... (do something with `db`)
    db.close()

Executing SQL
#############

The `exec <#exec,DbConn,string,varargs[DbValue,toDbValue]>`_ procedure can be used to execute a single SQL statement.
The `execScript <#execScript,DbConn,string>`_ procedure is used to execute several statements, but it doesn't support
parameter substitution.

.. code-block:: nim

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

Reading data
############

Four different procedures for reading data are available:

- `all <#all,DbConn,string,varargs[DbValue,toDbValue]>`_: procedure returning all result rows
- `iterate <#iterate.i,DbConn,string,varargs[DbValue,toDbValue]>`_: iterator yielding each result row one by one
- `one <#one,DbConn,string,varargs[DbValue,toDbValue]>`_: procedure returning the first result row, or `none` if no result row exists
- `value <#value,DbConn,string,varargs[DbValue,toDbValue]>`_: procedure returning the first column of the first result row, or `none` if no result row exists

Note that the procedures `one` and `value` returns the result wrapped in an `Option`. See the standard library
`options module <https://nim-lang.org/docs/options.html>`_ for documentation on how to deal with `Option` values.
For convenience the `tiny_sqlite` module exports the `options.get`, `options.isSome`, and `options.isNone` procedures so the options
module doesn't need to be explicitly imported for typical usage.

.. code-block:: nim

    for row in db.iterate("SELECT name, age FROM Person"):
        # The 'row' variable is of type ResultRow.
        # The column values can be accesed by both index and column name:
        echo row[0].strVal      # Prints the name
        echo row["name"].strVal # Prints the name
        echo row[1].intVal      # Prints the age
        # Above we're using the raw DbValue's directly. Instead, we can unpack the
        # DbValue using the fromDbValue procedure:
        echo fromDbValue(row[0], string) # Prints the name
        echo fromDbValue(row[1], int)    # Prints the age
        # Alternatively, the entire row can be unpacked at once:
        let (name, age) = row.unpack((string, int))
        # Unpacking the value is preferable as it makes it possible to handle
        # bools, enums, distinct types, nullable types and more. For example, nullable
        # types are handled using Option[T]:
        echo fromDbValue(row[0], Option[string]) # Will work even if the db value is NULL
    
    # Example of reading a single value. In this case, 'value' will be of type `Option[DbValue]`.
    let value = db.one("SELECT age FROM Person WHERE name = ?", "John Doe")
    if value.isSome:
        echo fromDbValue(value.get, int) # Prints age of John Doe


Inserting data in bulk
######################

The `exec <#exec,DbConn,string,varargs[DbValue,toDbValue]>`_ procedure works fine for inserting single rows,
but it gets awkward when inserting many rows. For this purpose the `execMany <#execMany,DbConn,string,varargs[DbValue,toDbValue]>`_
procedure can be used instead. It executes the same SQL repeatedly, but with different parameters each time.

.. code-block:: nim

    let parameters = @[toDbValues("Person 1", 17), toDbValues("Person 2", 55)]
    # Will insert two rows
    db.execMany("""
        INSERT INTO Person(name, age)
        VALUES(?, ?);
    """, parameters)

Transactions
############

The procedures that can execute multiple SQL statements (`execScript` and `execMany`) are wrapped in a transaction by
`tiny_sqlite`. Transactions can also be controlled manually by using one of these two options:

- Option 1: using the `transaction <#transaction.t,DbConn,untyped>`_ template

.. code-block:: nim

    db.transaction:
        # Anything inside here is executed inside a transaction which
        # will be rolled back in case of an error
        db.exec("DELETE FROM Person")
        db.exec("""INSERT INTO Person(name, age) VALUES("Jane Doe", 35)""")

- Option 2: using the `exec` procedure manually

.. code-block:: nim

    db.exec("BEGIN")
    try:
        db.exec("DELETE FROM Person")
        db.exec("""INSERT INTO Person(name, age) VALUES("Jane Doe", 35)""")
        db.exec("COMMIT")
    except:
        db.exec("ROLLBACK")

Prepared statements
###################

All the procedures for executing SQL described above create and execute prepared statements internally. In addition to
those procedures, ``tiny_sqlite`` also offers an API for preparing SQL statements explicitly. Prepared statements are
created with the `stmt <#stmt,DbConn,string>`_ procedure, and the same procedures for executing SQL that are available
directly on the connection object are also available for the prepared statement:


.. code-block:: nim
    
    let stmt = db.stmt("INSERT INTO Person(name, age) VALUES (?, ?)")
    stmt.exec("John Doe", 21)
    # Once the statement is no longer needed it must be finalized
    # to prevent memory leaks.
    stmt.finalize()

There are performance benefits of reusing prepared statements, since the preparation only needs to be done once.
However, `tiny_sqlite` keeps an internal cache of prepared statements, so it's typically not necesarry to manage
prepared statements manually. If you prefer if `tiny_sqlite` doesn't perform this caching, you can disable it by
setting the `cacheSize` parameter when opening the database:

.. code-block:: nim

    let db = openDatabase(":memory:", cacheSize = 0)

Supported types
###############

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

.. code-block:: nim

    import times

    proc toDbValue(t: Time): DbValue =
        DbValue(kind: sqliteInteger, intVal: toUnix(t))

    proc fromDbValue(value: DbValue, T: typedesc[Time]): Time =
        fromUnix(value.intval)
