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