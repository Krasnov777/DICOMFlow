use serde::{Deserialize, Serialize};
use sqlx::FromRow;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Study {
    pub id: i64,
    pub study_instance_uid: String,
    pub patient_id: Option<String>,
    pub patient_name: Option<String>,
    pub study_date: Option<String>,
    pub study_description: Option<String>,
    pub modality: Option<String>,
    pub file_path: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Instance {
    pub id: i64,
    pub study_id: i64,
    pub sop_instance_uid: String,
    pub series_instance_uid: String,
    pub instance_number: Option<i32>,
    pub tags_json: String, // JSON blob of all tags
    pub file_path: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Connection {
    pub id: i64,
    pub name: String,
    pub connection_type: String, // "dimse" or "dicomweb"
    pub config_json: String,     // JSON blob of connection config
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Request {
    pub id: i64,
    pub request_type: String, // "qido", "wado", "stow"
    pub endpoint: String,
    pub method: String,
    pub headers_json: String,
    pub body: Option<String>,
    pub response_status: Option<i32>,
    pub response_body: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Setting {
    pub key: String,
    pub value: String,
    pub updated_at: String,
}
