// DICOMweb HTTP client

use super::{AuthType, DicomWebEndpoint, DicomWebRequest, DicomWebResponse};
use anyhow::Result;
use reqwest::Client;
use std::collections::HashMap;

pub struct DicomWebClient {
    client: Client,
    endpoint: DicomWebEndpoint,
}

impl DicomWebClient {
    pub fn new(endpoint: DicomWebEndpoint) -> Self {
        Self {
            client: Client::new(),
            endpoint,
        }
    }

    /// Execute a DICOMweb request
    pub async fn execute(&self, request: DicomWebRequest) -> Result<DicomWebResponse> {
        let url = format!("{}/{}", self.endpoint.base_url, request.endpoint);

        let mut req = match request.method.as_str() {
            "GET" => self.client.get(&url),
            "POST" => self.client.post(&url),
            "DELETE" => self.client.delete(&url),
            _ => return Err(anyhow::anyhow!("Unsupported method: {}", request.method)),
        };

        // Add authentication
        req = self.add_auth(req);

        // Add headers
        for (key, value) in &request.headers {
            req = req.header(key, value);
        }

        // Add body if present
        if let Some(body) = request.body {
            req = req.body(body);
        }

        // Execute request
        let response = req.send().await?;
        let status = response.status().as_u16();
        let headers: HashMap<String, String> = response
            .headers()
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_str().unwrap_or("").to_string()))
            .collect();
        let body = response.text().await?;

        Ok(DicomWebResponse {
            status,
            headers,
            body,
        })
    }

    fn add_auth(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match &self.endpoint.auth_type {
            AuthType::None => req,
            AuthType::Basic { username, password } => req.basic_auth(username, Some(password)),
            AuthType::Bearer { token } => req.bearer_auth(token),
            AuthType::Custom => req, // Custom headers already added
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Add tests with mock HTTP server
}
