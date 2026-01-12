// DICOM anonymization utilities

use anyhow::Result;
use dicom_core::Tag;
use dicom_core::header::Header;
use dicom_dictionary_std::tags;
use dicom_object::InMemDicomObject;
use serde::{Deserialize, Serialize};
use std::collections::HashMap;
use uuid::Uuid;

/// Anonymization template defining which tags to modify
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnonymizationTemplate {
    pub name: String,
    pub description: String,
    pub rules: Vec<AnonymizationRule>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AnonymizationRule {
    pub tag: String,        // Tag identifier
    pub action: AnonymizationAction,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum AnonymizationAction {
    Remove,                 // Delete the tag
    Blank,                  // Set to empty value
    Replace(String),        // Replace with specific value
    Hash,                   // Hash the value
    GenerateUID,            // Generate new UID
    Increment,              // Increment numeric value
}

/// Anonymize a DICOM object using a template
pub fn anonymize(obj: &mut InMemDicomObject, template: &AnonymizationTemplate) -> Result<()> {
    for rule in &template.rules {
        apply_rule(obj, rule)?;
    }
    Ok(())
}

/// Apply a single anonymization rule
fn apply_rule(obj: &mut InMemDicomObject, rule: &AnonymizationRule) -> Result<()> {
    use dicom_object::mem::InMemElement;
    use dicom_core::value::{PrimitiveValue, Value};
    use dicom_core::VR;
    use sha2::{Sha256, Digest};
    use dicom_core::Tag;

    // Parse tag string
    let tag = parse_tag_string(&rule.tag)?;

    match &rule.action {
        AnonymizationAction::Remove => {
            obj.remove_element(tag);
        }
        AnonymizationAction::Blank => {
            if let Ok(existing) = obj.element(tag) {
                let vr = existing.vr();
                let new_elem = InMemElement::new(
                    tag,
                    vr,
                    Value::Primitive(PrimitiveValue::Str(String::new())),
                );
                obj.put_element(new_elem);
            }
        }
        AnonymizationAction::Replace(new_value) => {
            let vr = obj.element(tag).map(|e| e.vr()).unwrap_or(VR::LO);
            let new_elem = InMemElement::new(
                tag,
                vr,
                Value::Primitive(PrimitiveValue::Str(new_value.clone())),
            );
            obj.put_element(new_elem);
        }
        AnonymizationAction::Hash => {
            if let Ok(existing) = obj.element(tag) {
                if let Ok(value_str) = existing.to_str() {
                    let mut hasher = Sha256::new();
                    hasher.update(value_str.as_bytes());
                    let hash = format!("{:x}", hasher.finalize());
                    let hash_short = &hash[0..16]; // Take first 16 chars

                    let vr = existing.vr();
                    let new_elem = InMemElement::new(
                        tag,
                        vr,
                        Value::Primitive(PrimitiveValue::Str(hash_short.to_string())),
                    );
                    obj.put_element(new_elem);
                }
            }
        }
        AnonymizationAction::GenerateUID => {
            let new_uid = format!("2.25.{}", Uuid::new_v4().as_u128());
            let new_elem = InMemElement::new(
                tag,
                VR::UI,
                Value::Primitive(PrimitiveValue::Str(new_uid)),
            );
            obj.put_element(new_elem);
        }
        AnonymizationAction::Increment => {
            // For increment, we'll just add 1 to numeric values
            if let Ok(existing) = obj.element(tag) {
                if let Ok(num) = existing.to_int::<i32>() {
                    let new_value = (num + 1).to_string();
                    let vr = existing.vr();
                    let new_elem = InMemElement::new(
                        tag,
                        vr,
                        Value::Primitive(PrimitiveValue::Str(new_value)),
                    );
                    obj.put_element(new_elem);
                }
            }
        }
    }

    Ok(())
}

fn parse_tag_string(tag_str: &str) -> Result<Tag> {
    let cleaned = tag_str.replace("(", "").replace(")", "").replace(",", "");

    if cleaned.len() != 8 {
        return Err(anyhow::anyhow!("Invalid tag format: {}", tag_str));
    }

    let group = u16::from_str_radix(&cleaned[0..4], 16)?;
    let element = u16::from_str_radix(&cleaned[4..8], 16)?;

    Ok(Tag(group, element))
}

/// Get built-in anonymization templates
pub fn get_builtin_templates() -> Vec<AnonymizationTemplate> {
    vec![
        basic_template(),
        full_template(),
        research_template(),
    ]
}

/// Basic anonymization template (removes patient identifiers)
fn basic_template() -> AnonymizationTemplate {
    AnonymizationTemplate {
        name: "Basic".to_string(),
        description: "Removes basic patient identifiers".to_string(),
        rules: vec![
            AnonymizationRule {
                tag: "(0010,0010)".to_string(), // Patient Name
                action: AnonymizationAction::Replace("ANONYMOUS".to_string()),
            },
            AnonymizationRule {
                tag: "(0010,0020)".to_string(), // Patient ID
                action: AnonymizationAction::Hash,
            },
            AnonymizationRule {
                tag: "(0010,0030)".to_string(), // Patient Birth Date
                action: AnonymizationAction::Blank,
            },
        ],
    }
}

/// Full anonymization template (comprehensive)
fn full_template() -> AnonymizationTemplate {
    AnonymizationTemplate {
        name: "Full".to_string(),
        description: "Comprehensive anonymization following DICOM PS3.15".to_string(),
        rules: vec![
            // TODO: Add comprehensive list of tags to anonymize
        ],
    }
}

/// Research-safe template (preserves study relationships)
fn research_template() -> AnonymizationTemplate {
    AnonymizationTemplate {
        name: "Research".to_string(),
        description: "Anonymizes while preserving study relationships".to_string(),
        rules: vec![
            // TODO: Add research-appropriate anonymization rules
        ],
    }
}

/// Delete all private tags
pub fn delete_private_tags(obj: &mut InMemDicomObject) -> Result<usize> {
    let private_tags: Vec<Tag> = obj
        .iter()
        .filter(|e| e.tag().group() % 2 == 1) // Private tags have odd group numbers
        .map(|e| e.tag())
        .collect();

    let count = private_tags.len();
    for tag in private_tags {
        obj.remove_element(tag);
    }

    Ok(count)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_builtin_templates() {
        let templates = get_builtin_templates();
        assert_eq!(templates.len(), 3);
    }
}
