// Database schema constants and query builders
// SQL migrations are in the migrations/ directory

pub const CREATE_STUDIES_TABLE: &str = r#"
    CREATE TABLE IF NOT EXISTS studies (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        study_instance_uid TEXT NOT NULL UNIQUE,
        patient_id TEXT,
        patient_name TEXT,
        study_date TEXT,
        study_description TEXT,
        modality TEXT,
        file_path TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
"#;

pub const CREATE_INSTANCES_TABLE: &str = r#"
    CREATE TABLE IF NOT EXISTS instances (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        study_id INTEGER NOT NULL,
        sop_instance_uid TEXT NOT NULL UNIQUE,
        series_instance_uid TEXT NOT NULL,
        instance_number INTEGER,
        tags_json TEXT NOT NULL,
        file_path TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        FOREIGN KEY (study_id) REFERENCES studies(id) ON DELETE CASCADE
    )
"#;

pub const CREATE_CONNECTIONS_TABLE: &str = r#"
    CREATE TABLE IF NOT EXISTS connections (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        connection_type TEXT NOT NULL CHECK(connection_type IN ('dimse', 'dicomweb')),
        config_json TEXT NOT NULL,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
"#;

pub const CREATE_REQUESTS_TABLE: &str = r#"
    CREATE TABLE IF NOT EXISTS requests (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        request_type TEXT NOT NULL CHECK(request_type IN ('qido', 'wado', 'stow')),
        endpoint TEXT NOT NULL,
        method TEXT NOT NULL,
        headers_json TEXT NOT NULL,
        body TEXT,
        response_status INTEGER,
        response_body TEXT,
        created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
"#;

pub const CREATE_SETTINGS_TABLE: &str = r#"
    CREATE TABLE IF NOT EXISTS settings (
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL,
        updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )
"#;
