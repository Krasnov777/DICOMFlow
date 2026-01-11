// STOW-RS (Store Over the Web)

use super::client::DicomWebClient;
use super::DicomWebRequest;
use anyhow::Result;
use std::collections::HashMap;

/// Store DICOM instances
pub async fn store_instances(
    client: &DicomWebClient,
    study_uid: Option<&str>,
    instances: Vec<Vec<u8>>,
) -> Result<StowResponse> {
    let endpoint = if let Some(uid) = study_uid {
        format!("stow-rs/studies/{}", uid)
    } else {
        "stow-rs/studies".to_string()
    };

    // TODO: Implement multipart/related encoding for DICOM instances
    // This is a placeholder - need to properly encode multiple DICOM files

    let request = DicomWebRequest {
        method: "POST".to_string(),
        endpoint,
        headers: {
            let mut headers = HashMap::new();
            headers.insert(
                "Content-Type".to_string(),
                "multipart/related; type=\"application/dicom\"".to_string(),
            );
            headers.insert("Accept".to_string(), "application/dicom+json".to_string());
            headers
        },
        body: None, // TODO: Build multipart body
    };

    let response = client.execute(request).await?;

    if response.status != 200 {
        return Err(anyhow::anyhow!(
            "STOW-RS failed with status {}: {}",
            response.status,
            response.body
        ));
    }

    let stow_response: StowResponse = serde_json::from_str(&response.body)?;
    Ok(stow_response)
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct StowResponse {
    pub success: Vec<String>,  // Successfully stored instance UIDs
    pub failed: Vec<FailedInstance>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct FailedInstance {
    pub instance_uid: String,
    pub reason: String,
}

#[cfg(test)]
mod tests {
    use super::*;

    // Add tests
}
