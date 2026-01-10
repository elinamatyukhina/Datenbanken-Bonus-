-- GRUNDLEGENDE TABELLEN
CREATE TABLE item_types (
    item_type CHAR(1) PRIMARY KEY,
    item_type_name VARCHAR(50) NOT NULL,
    item_type_description TEXT
);

CREATE TABLE authors (
    author_id SERIAL PRIMARY KEY,
    name VARCHAR(200) NOT NULL
);

CREATE TABLE collections (
    collection_id SERIAL PRIMARY KEY,
    collection_name VARCHAR(500) NOT NULL,
    collection_description TEXT
);

CREATE TABLE rooms (
    room_id SERIAL PRIMARY KEY,
    room_name VARCHAR(200) NOT NULL
);

CREATE TABLE shelves (
    shelf_id SERIAL PRIMARY KEY,
    room_id INTEGER NOT NULL REFERENCES rooms(room_id) ON DELETE CASCADE,
    shelf_description VARCHAR(500) NOT NULL
);

CREATE TABLE shelf_levels (
    shelf_level_id SERIAL PRIMARY KEY,
    shelf_id INTEGER NOT NULL REFERENCES shelves(shelf_id) ON DELETE CASCADE,
    level_number INTEGER NOT NULL CHECK (level_number > 0),
    UNIQUE (shelf_id, level_number)
);

CREATE TABLE items (
    item_id SERIAL PRIMARY KEY,
    item_type CHAR(1) NOT NULL REFERENCES item_types(item_type),
    item_title VARCHAR(500) NOT NULL,
    item_publication_year INTEGER CHECK (item_publication_year IS NULL OR (item_publication_year >= 0 AND item_publication_year <= EXTRACT(YEAR FROM CURRENT_DATE) + 10)),
    item_language CHAR(3),
    item_publisher VARCHAR(200),
    item_condition VARCHAR(100),
    item_cover_photo BYTEA,
    item_notes TEXT,
    item_page_count INTEGER CHECK (item_page_count IS NULL OR item_page_count > 0),
    item_isbn VARCHAR(20),
    item_udk VARCHAR(50),
    item_editor VARCHAR(200),
    item_series VARCHAR(200),
    item_volume_number VARCHAR(50),
    item_publication_place VARCHAR(200),
    item_table_of_contents TEXT,
    item_medium_type VARCHAR(50),
    item_collection_id INTEGER REFERENCES collections(collection_id) ON DELETE SET NULL,
    item_external_id VARCHAR(100),
    shelf_level_id INTEGER REFERENCES shelf_levels(shelf_level_id) ON DELETE SET NULL,
    item_position VARCHAR(100)
);

CREATE TABLE item_authors (
    item_id INTEGER REFERENCES items(item_id) ON DELETE CASCADE,
    author_id INTEGER REFERENCES authors(author_id) ON DELETE CASCADE,
    PRIMARY KEY (item_id, author_id)
);

CREATE TABLE persons (
    person_id SERIAL PRIMARY KEY,
    first_name VARCHAR(200) NOT NULL,
    last_name VARCHAR(200) NOT NULL,
    address TEXT,
    phone VARCHAR(50),
    birth_date DATE
);

CREATE TABLE loans (
    loan_id SERIAL PRIMARY KEY,
    item_id INTEGER NOT NULL REFERENCES items(item_id) ON DELETE RESTRICT,
    person_id INTEGER NOT NULL REFERENCES persons(person_id) ON DELETE RESTRICT,
    start_date DATE NOT NULL,
    end_date DATE,
    CHECK (end_date IS NULL OR end_date >= start_date)
);


-- MUSIKSTÜCKE
CREATE TABLE music_pieces (
    music_piece_id SERIAL PRIMARY KEY,
    music_piece_title VARCHAR(500) NOT NULL,
    music_piece_subtitle VARCHAR(500),
    music_piece_catalog_number VARCHAR(100),
    music_piece_composer_id INTEGER NOT NULL REFERENCES authors(author_id) ON DELETE RESTRICT,
    music_piece_editor_id INTEGER REFERENCES authors(author_id) ON DELETE SET NULL,
    music_piece_editor_volume VARCHAR(50),
    music_piece_notes TEXT
);

CREATE TABLE music_piece_parts (
    music_piece_part_id SERIAL PRIMARY KEY,
    music_piece_id INTEGER NOT NULL REFERENCES music_pieces(music_piece_id) ON DELETE CASCADE,
    part_number INTEGER NOT NULL CHECK (part_number > 0),
    part_title VARCHAR(500) NOT NULL,
    part_notes TEXT,
    UNIQUE (music_piece_id, part_number)
);

CREATE TABLE interpreters (
    interpreter_id SERIAL PRIMARY KEY,
    interpreter_name VARCHAR(500) NOT NULL,
    interpreter_type VARCHAR(50),
    interpreter_notes TEXT
);

CREATE TABLE music_piece_interpreters (
    music_piece_id INTEGER REFERENCES music_pieces(music_piece_id) ON DELETE CASCADE,
    interpreter_id INTEGER REFERENCES interpreters(interpreter_id) ON DELETE CASCADE,
    PRIMARY KEY (music_piece_id, interpreter_id)
);

CREATE TABLE item_music_pieces (
    item_music_piece_id SERIAL PRIMARY KEY,
    item_id INTEGER NOT NULL REFERENCES items(item_id) ON DELETE CASCADE,
    music_piece_id INTEGER NOT NULL REFERENCES music_pieces(music_piece_id) ON DELETE CASCADE,
    track_number INTEGER CHECK (track_number IS NULL OR track_number > 0),
    track_duration_minutes INTEGER CHECK (track_duration_minutes IS NULL OR track_duration_minutes >= 0),
    track_duration_seconds INTEGER CHECK (track_duration_seconds IS NULL OR (track_duration_seconds >= 0 AND track_duration_seconds <= 59)),
    notes TEXT,
    CONSTRAINT unique_track_per_cd EXCLUDE (item_id WITH =, track_number WITH =) WHERE (track_number IS NOT NULL)
);


-- TRIGGER
CREATE OR REPLACE FUNCTION check_book_required_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.item_type = 'B' AND (NEW.item_publication_year IS NULL OR NEW.item_page_count IS NULL OR NEW.item_language IS NULL) THEN
        RAISE EXCEPTION 'Bücher müssen Jahr, Seitenanzahl und Sprache haben';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_book_fields
BEFORE INSERT OR UPDATE ON items FOR EACH ROW
EXECUTE FUNCTION check_book_required_fields();

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
BEFORE INSERT OR UPDATE ON items FOR EACH ROW
EXECUTE FUNCTION check_music_score_editor();

CREATE OR REPLACE FUNCTION check_item_has_author_on_create()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.item_type IN ('B', 'N', 'D', 'F') AND NOT EXISTS (SELECT 1 FROM item_authors WHERE item_id = NEW.item_id) THEN
        RAISE EXCEPTION 'Bücher, Noten und Filme müssen mindestens einen Autor/Regisseur haben';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_item_has_author_on_create
AFTER INSERT ON items FOR EACH ROW
EXECUTE FUNCTION check_item_has_author_on_create();

CREATE OR REPLACE FUNCTION check_item_has_author_on_delete()
RETURNS TRIGGER AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM item_authors WHERE item_id = OLD.item_id) AND
       EXISTS (SELECT 1 FROM items WHERE item_id = OLD.item_id AND item_type IN ('B', 'N', 'D', 'F')) THEN
        RAISE EXCEPTION 'Bücher, Noten und Filme müssen mindestens einen Autor/Regisseur haben';
    END IF;
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_prevent_last_author_deletion
AFTER DELETE ON item_authors FOR EACH ROW
EXECUTE FUNCTION check_item_has_author_on_delete();

CREATE OR REPLACE FUNCTION check_item_music_piece_type()
RETURNS TRIGGER AS $$
DECLARE
    v_item_type CHAR(1);
BEGIN
    SELECT item_type INTO v_item_type FROM items WHERE item_id = NEW.item_id;
    IF v_item_type IS NULL THEN
        RAISE EXCEPTION 'Item mit ID % existiert nicht', NEW.item_id;
    END IF;
    IF v_item_type NOT IN ('C', 'N') THEN
        RAISE EXCEPTION 'Musikstücke können nur CDs (C) oder Noten (N) zugeordnet werden';
    END IF;
    IF v_item_type = 'C' AND NEW.track_number IS NULL THEN
        RAISE EXCEPTION 'CD-Tracks müssen eine Track-Nummer haben';
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_item_music_piece_type
BEFORE INSERT OR UPDATE ON item_music_pieces FOR EACH ROW
EXECUTE FUNCTION check_item_music_piece_type();

CREATE OR REPLACE FUNCTION check_film_required_fields()
RETURNS TRIGGER AS $$
BEGIN
    IF NEW.item_type IN ('D', 'F') THEN
        IF NEW.item_publication_year IS NULL THEN
            RAISE EXCEPTION 'Filme müssen ein Jahr haben';
        END IF;
        IF NOT EXISTS (SELECT 1 FROM item_authors WHERE item_id = NEW.item_id) THEN
            RAISE EXCEPTION 'Filme müssen mindestens einen Regisseur haben';
        END IF;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_check_film_fields
AFTER INSERT OR UPDATE ON items FOR EACH ROW
EXECUTE FUNCTION check_film_required_fields();


-- Initialdaten für item_types
INSERT INTO item_types (item_type, item_type_name) VALUES
('B', 'Buch'),
('C', 'CD'),
('D', 'DVD'),
('F', 'Blu-ray'),
('N', 'Noten');



-- BEISPIELDATEN (Abschnitt: Umsetzung) --> nur Beispieldaten für die 5 Fragen am Ende

INSERT INTO authors (name) VALUES
('Edgar Allan Poe'),
('Agatha Christie'),
('Frédéric Chopin'),
('Christopher Nolan'),
('Charles Dickens');

INSERT INTO rooms (room_name) VALUES
('Wohnzimmer'),
('Arbeitszimmer');

INSERT INTO shelves (room_id, shelf_description) VALUES
(1, 'das zweite Regal rechts'),
(1, 'das Notenregal'),
(2, 'Filme-Regal');

INSERT INTO shelf_levels (shelf_id, level_number) VALUES
(1, 1), (1, 2),
(2, 1), (2, 2),
(3, 1);

INSERT INTO items (item_type, item_title, item_publication_year, item_language, item_page_count, item_series, item_volume_number, shelf_level_id) VALUES
('B', 'The Raven', 1845, 'eng', 48, 'Gesammelte Werke', '1', 1),
('B', 'The Tell-Tale Heart', 1843, 'eng', 32, 'Gesammelte Werke', '2', 1),
('B', 'Murder on the Orient Express', 1934, 'eng', 256, NULL, NULL, 2),
('B', 'David Copperfield', 1850, 'eng', 624, 'Gesammelte Werke', '15', 1);

INSERT INTO item_authors (item_id, author_id) VALUES
(1, 1), (2, 1), (3, 2), (4, 5);

INSERT INTO items (item_type, item_title, item_publication_year, item_editor, item_medium_type, shelf_level_id) VALUES
('N', 'Chopin: Fantaisie-Impromptu', 2020, 'Edition Paderewski', 'Notenband', 3),
('N', 'Chopin: Fantaisie-Impromptu', 2015, 'Henle Verlag', 'Notenband', 4);

INSERT INTO item_authors (item_id, author_id) VALUES
(5, 3), (6, 3);

INSERT INTO items (item_type, item_title, item_publication_year, item_medium_type, item_external_id) VALUES
('D', 'Inception', 2010, 'DVD', 'tt1375666'),
('F', 'The Dark Knight', 2008, 'Blu-ray', 'tt0468569');

INSERT INTO item_authors (item_id, author_id) VALUES
(7, 4), (8, 4);

INSERT INTO persons (first_name, last_name, address, phone) VALUES
('Anna', 'Schmidt', NULL, '0987-654321'),
('Tobias', 'Werner', 'Beispielstraße 5, 54321 Beispielstadt', '0555-123456');

INSERT INTO loans (item_id, person_id, start_date, end_date) VALUES
(3, 1, '2023-12-01', NULL),
(7, 2, '2024-02-01', NULL),
(8, 2, '2024-02-01', NULL);



-- Das entgültige Ziel (Antworten auf die Fragen)

-- 1. Alle Bücher von "Edgar Allan Poe" und wo sie stehen
SELECT i.item_title, i.item_publication_year, r.room_name, s.shelf_description, sl.level_number, i.item_position
FROM items i
JOIN item_authors ia ON i.item_id = ia.item_id
JOIN authors a ON ia.author_id = a.author_id
LEFT JOIN shelf_levels sl ON i.shelf_level_id = sl.shelf_level_id
LEFT JOIN shelves s ON sl.shelf_id = s.shelf_id
LEFT JOIN rooms r ON s.room_id = r.room_id
WHERE a.name = 'Edgar Allan Poe' AND i.item_type = 'B';

-- 2. Alle Ausgaben von "Fantaisie-Impromptu" von Chopin (Noten) und wo sie stehen
SELECT i.*, r.room_name, s.shelf_description, sl.level_number, i.item_position
FROM items i
JOIN item_authors ia ON i.item_id = ia.item_id
JOIN authors a ON ia.author_id = a.author_id
LEFT JOIN shelf_levels sl ON i.shelf_level_id = sl.shelf_level_id
LEFT JOIN shelves s ON sl.shelf_id = s.shelf_id
LEFT JOIN rooms r ON s.room_id = r.room_id
WHERE a.name = 'Frédéric Chopin' AND i.item_type = 'N' AND i.item_title LIKE '%Fantaisie-Impromptu%';

-- 3. Wer hat ein Buch von Agatha Christie ausgeliehen und nicht zurückgebracht?
SELECT p.first_name, p.last_name, i.item_title, l.start_date
FROM loans l
JOIN items i ON l.item_id = i.item_id
JOIN item_authors ia ON i.item_id = ia.item_id
JOIN authors a ON ia.author_id = a.author_id
JOIN persons p ON l.person_id = p.person_id
WHERE a.name = 'Agatha Christie' AND i.item_type = 'B' AND l.end_date IS NULL;

-- 4. Welche Filmdatenträger (DVD, aber nicht nur) hat "Tobias Werner" ausgeliehen?
SELECT i.item_title, i.item_type, i.item_medium_type, i.item_external_id, l.start_date
FROM loans l
JOIN items i ON l.item_id = i.item_id
JOIN persons p ON l.person_id = p.person_id
WHERE p.first_name = 'Tobias' AND p.last_name = 'Werner' 
  AND i.item_type IN ('D', 'F') 
  AND l.end_date IS NULL;

-- 5. Stehen alle Buchbände der gesammelten Werke korrekt hintereinander?
-- Prüft ob Bände derselben Serie/Reihe in korrekter Reihenfolge stehen
SELECT a.name AS autor, i.item_series, i.item_volume_number, 
       r.room_name, s.shelf_description, sl.level_number, i.item_position,
       CASE 
         WHEN LAG(sl.shelf_level_id) OVER (PARTITION BY i.item_series, ia.author_id ORDER BY CAST(i.item_volume_number AS INTEGER)) = sl.shelf_level_id 
         THEN 'Korrekt'
         ELSE 'Nicht korrekt'
       END AS reihenfolge
FROM items i
JOIN item_authors ia ON i.item_id = ia.item_id
JOIN authors a ON ia.author_id = a.author_id
LEFT JOIN shelf_levels sl ON i.shelf_level_id = sl.shelf_level_id
LEFT JOIN shelves s ON sl.shelf_id = s.shelf_id
LEFT JOIN rooms r ON s.room_id = r.room_id
WHERE i.item_series IS NOT NULL AND i.item_volume_number IS NOT NULL
ORDER BY a.name, i.item_series, CAST(i.item_volume_number AS INTEGER);