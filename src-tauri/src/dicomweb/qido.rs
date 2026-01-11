// QIDO-RS (Query based on ID for DICOM Objects)

use super::client::DicomWebClient;
use super::DicomWebRequest;
use anyhow::Result;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct QidoQuery {
    pub level: QueryLevel,
    pub params: HashMap<String, String>,
    pub limit: Option<u32>,
    pub offset: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum QueryLevel {
    Studies,
    Series,
    Instances,
}

impl QueryLevel {
    fn to_path(&self) -> &str {
        match self {
            QueryLevel::Studies => "studies",
            QueryLevel::Series => "series",
            QueryLevel::Instances => "instances",
        }
    }
}

/// Perform QIDO-RS query
pub async fn query(client: &DicomWebClient, query: QidoQuery) -> Result<Vec<serde_json::Value>> {
    let mut endpoint = format!("qido-rs/{}", query.level.to_path());

    // Build query string
    let mut query_params = Vec::new();
    for (key, value) in &query.params {
        query_params.push(format!("{}={}", key, value));
    }
    if let Some(limit) = query.limit {
        query_params.push(format!("limit={}", limit));
    }
    if let Some(offset) = query.offset {
        query_params.push(format!("offset={}", offset));
    }

    if !query_params.is_empty() {
        endpoint.push('?');
        endpoint.push_str(&query_params.join("&"));
    }

    let request = DicomWebRequest {
        method: "GET".to_string(),
        endpoint,
        headers: {
            let mut headers = HashMap::new();
            headers.insert("Accept".to_string(), "application/dicom+json".to_string());
            headers
        },
        body: None,
    };

    let response = client.execute(request).await?;

    if response.status != 200 {
        return Err(anyhow::anyhow!(
            "QIDO-RS query failed with status {}: {}",
            response.status,
            response.body
        ));
    }

    let results: Vec<serde_json::Value> = serde_json::from_str(&response.body)?;
    Ok(results)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Add tests
}
