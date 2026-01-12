pub mod client;
pub mod qido;
pub mod wado;
pub mod stow;
pub mod config;

use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DicomWebEndpoint {
    pub name: String,
    pub base_url: String,
    pub auth_type: AuthType,
    pub headers: HashMap<String, String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AuthType {
    None,
    Basic { username: String, password: String },
    Bearer { token: String },
    Custom,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DicomWebRequest {
    pub method: String,
    pub endpoint: String,
    pub headers: HashMap<String, String>,
    pub body: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct DicomWebResponse {
    pub status: u16,
    pub headers: HashMap<String, String>,
    pub body: String,
}
