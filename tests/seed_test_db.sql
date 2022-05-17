CREATE TABLE Person(
    id INTEGER PRIMARY KEY,
    name TEXT,
    age INTEGER
);

INSERT INTO
    Person(name, age)
VALUES
    ('John Doe', 47),
    ('Jane Doe', NULL);


CREATE TABLE Types(
    textVal TEXT,
    integerVal INTEGER,
    realVal REAL,
    nullVal INTEGER,
    blobVal BLOB
);

INSERT INTO
    Types(textVal, integerval, realVal, nullVal, blobVal)
VALUES
    ("foo åäö 𐐷", 1, 1.5, null, x'0102FF')