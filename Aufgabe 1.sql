-- Aufgabe 1: Tabellen books und authors, dazu eine Tabelle mit zwei Fremdschlüsseln (wegen n:n Kardinalität). 
-- Noch keine Trigger hinzugefügt.

-- Haupttabelle für Bücher
CREATE TABLE books (
    book_id SERIAL PRIMARY KEY,
    book_title VARCHAR(500) NOT NULL,
    book_publication_year INTEGER NOT NULL,
    book_page_count INTEGER NOT NULL,
    book_language CHAR(3) NOT NULL, -- ISO 639-3 Sprachcode (z.B. 'deu' für Deutsch)
    -- Optionale Informationen
    book_isbn VARCHAR(20),
    book_udk VARCHAR(50), 
    book_editor VARCHAR(200),
    book_series VARCHAR(200),
    book_publisher VARCHAR(200),
    book_volume_number VARCHAR(50),
    book_publication_place VARCHAR(200),
    book_condition VARCHAR(100),
    book_cover_photo BYTEA,
    book_table_of_contents TEXT,
    book_notes TEXT
);

-- Autoren
CREATE TABLE authors (
    author_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL
);

-- Bücher <-> Autoren (n:n Kardinalität)
CREATE TABLE book_authors (
    book_id INTEGER REFERENCES books(book_id) ON DELETE CASCADE,
    author_id INTEGER REFERENCES authors(author_id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, author_id)
);


-- Die Regel "jedes Buch muss mindestens einen Autor haben" muss dann über die App-Logik sichergestellt werden.

