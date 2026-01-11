// WADO-RS (Web Access to DICOM Objects)

use super::client::DicomWebClient;
use super::DicomWebRequest;
use anyhow::Result;
use std::collections::HashMap;

/// Retrieve DICOM instance
pub async fn retrieve_instance(
    client: &DicomWebClient,
    study_uid: &str,
    series_uid: &str,
    instance_uid: &str,
) -> Result<Vec<u8>> {
    let endpoint = format!(
        "wado-rs/studies/{}/series/{}/instances/{}",
        study_uid, series_uid, instance_uid
    );

    let request = DicomWebRequest {
        method: "GET".to_string(),
        endpoint,
        headers: {
            let mut headers = HashMap::new();
            headers.insert("Accept".to_string(), "application/dicom".to_string());
            headers
        },
        body: None,
    };

    let response = client.execute(request).await?;

    if response.status != 200 {
        return Err(anyhow::anyhow!(
            "WADO-RS retrieve failed with status {}: {}",
            response.status,
            response.body
        ));
    }

    Ok(response.body.into_bytes())
}

/// Retrieve metadata
pub async fn retrieve_metadata(
    client: &DicomWebClient,
    study_uid: &str,
    series_uid: Option<&str>,
    instance_uid: Option<&str>,
) -> Result<serde_json::Value> {
    let endpoint = if let Some(instance) = instance_uid {
        format!(
            "wado-rs/studies/{}/series/{}/instances/{}/metadata",
            study_uid,
            series_uid.unwrap(),
            instance
        )
    } else if let Some(series) = series_uid {
        format!("wado-rs/studies/{}/series/{}/metadata", study_uid, series)
    } else {
        format!("wado-rs/studies/{}/metadata", study_uid)
    };

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
            "WADO-RS metadata failed with status {}: {}",
            response.status,
            response.body
        ));
    }

    let metadata: serde_json::Value = serde_json::from_str(&response.body)?;
    Ok(metadata)
}

#[cfg(test)]
mod tests {
    use super::*;

    // Add tests
}
