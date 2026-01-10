-- Aufgabe 2: Bücherverwaltung erweitert um CDs, DVDs, Music Scores (--> Tabelle items, anstatt nur books)
-- Ansonsten Trigger hinzugefügt.


/*
DISKUSSION: Präfix im Primärschlüssel (B12345, C12345, N12345)

PROBLEME:
- Primärschlüssel sollten numerisch/automatisch sein (SERIAL PRIMARY KEY).
- Präfix macht Abfragen komplizierter (String-Vergleiche statt numerisch).
- Nicht normalisiert - Typ-Information redundant.
- Schwer zu sortieren (B12345, B12346, C12345 statt 1,2,3).
- Keine saubere Referenzintegrität.

BESSERE ALTERNATIVEN:
1. Separate Tabellen (books, cds, dvds, music_scores) - viel Redundanz
2. Eine Tabelle mit item_type Feld - besser, da gemeinsame Attribute
3. Generalisierung: Basis-Tabelle + spezifische Tabellen - komplexer

GEWÄHLTE LÖSUNG: Eine Tabelle "items" mit item_type
- Alle Gegenstände haben gemeinsame Attribute (Titel, Autor, etc.)
- item_type unterscheidet: 'book', 'cd', 'dvd', 'music_score'
- Spezifische Attribute als optionale Felder
- Einheitlicher Primärschlüssel (item_id)
*/

-- Autoren
CREATE TABLE authors (
    author_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL
);

-- Tabelle für alle Gegenstände (Bücher, CDs, DVDs, Music Scores)
CREATE TABLE items (
    item_id SERIAL PRIMARY KEY,
    item_type CHAR(1) NOT NULL CHECK (item_type IN ('B', 'C', 'D', 'N')), -- B=Book, C=CD, D=DVD, N=Music Scores/Noten
    item_title VARCHAR(500) NOT NULL,
    item_publication_year INTEGER,
    item_language CHAR(3), -- ISO 639-3 Sprachcode (z.B. 'deu' für Deutsch)
    -- Gemeinsame optionale Felder
    item_publisher VARCHAR(200),
    item_condition VARCHAR(100),
    item_cover_photo BYTEA,
    item_notes TEXT,
    -- Bücher-spezifisch (Pflichtfelder für item_type='B' müssen über App-Logik sichergestellt werden --> hier nicht über Trigger)
    item_page_count INTEGER,
    item_isbn VARCHAR(20),
    item_udk VARCHAR(50),
    item_editor VARCHAR(200), -- Herausgeber (für Bücher optional, für Noten Pflicht --> App-Logik sicherstellen)
    item_series VARCHAR(200),
    item_volume_number VARCHAR(50),
    item_publication_place VARCHAR(200),
    item_table_of_contents TEXT -- Inhaltsverzeichnis (für Bücher) / Sammlung von Musikstücken (für Noten)
);

-- Items <-> Autoren (n:n Kardinalität)
CREATE TABLE item_authors (
    item_id INTEGER REFERENCES items(item_id) ON DELETE CASCADE,
    author_id INTEGER REFERENCES authors(author_id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, author_id)
);


-- Trigger: Bücher müssen Jahr, Seitenanzahl und Sprache haben
CREATE OR REPLACE FUNCTION check_book_required_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.item_type = 'B' THEN
        IF NEW.item_publication_year IS NULL THEN
            RAISE EXCEPTION 'Bücher müssen ein Jahr der Ausgabe haben';
        END IF;
        IF NEW.item_page_count IS NULL THEN
            RAISE EXCEPTION 'Bücher müssen eine Gesamtanzahl von Seiten haben';
        END IF;
        IF NEW.item_language IS NULL THEN
            RAISE EXCEPTION 'Bücher müssen eine Sprache haben';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_book_fields
BEFORE INSERT OR UPDATE ON items
FOR EACH ROW
EXECUTE FUNCTION check_book_required_fields();

-- Trigger: Noten müssen Herausgeber haben
CREATE OR REPLACE FUNCTION check_music_score_editor()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.item_type = 'N' AND NEW.item_editor IS NULL THEN
        RAISE EXCEPTION 'Noten müssen einen Herausgeber haben';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_music_editor
BEFORE INSERT OR UPDATE ON items
FOR EACH ROW
EXECUTE FUNCTION check_music_score_editor();

-- Trigger: Bücher und Noten müssen mindestens einen Autor haben
CREATE OR REPLACE FUNCTION check_item_has_author()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM item_authors WHERE item_id = OLD.item_id) THEN
        IF EXISTS (SELECT 1 FROM items WHERE item_id = OLD.item_id AND item_type IN ('B', 'N')) THEN
            RAISE EXCEPTION 'Bücher und Noten müssen mindestens einen Autor haben';
        END IF;
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_prevent_last_author_deletion
AFTER DELETE ON item_authors
FOR EACH ROW
EXECUTE FUNCTION check_item_has_author();
