// Prevents additional console window on Windows in release
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod commands;
mod database;
mod dicom;
mod dicomweb;
mod dimse;
mod utils;

use tauri::Manager;
use tracing_subscriber;

#[tokio::main]
async fn main() {
    // Initialize logging
    tracing_subscriber::fmt::init();

    // Initialize database
    let db = database::init()
        .await
        .expect("Failed to initialize database");

    tauri::Builder::default()
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_fs::init())
        .manage(db)
        .invoke_handler(tauri::generate_handler![
            // File operations
            commands::file::open_dicom_file,
            commands::file::open_dicom_directory,

            // DICOM viewing
            commands::viewer::get_image_data,
            commands::viewer::get_metadata,
            commands::viewer::apply_windowing,

            // Tag operations
            commands::tags::get_all_tags,
            commands::tags::update_tag,
            commands::tags::delete_tag,
            commands::tags::anonymize_study,

            // DIMSE operations
            commands::dimse::start_scp,
            commands::dimse::stop_scp,
            commands::dimse::c_echo,
            commands::dimse::c_find,
            commands::dimse::c_move,

            // DICOMweb operations
            commands::dicomweb::qido_rs,
            commands::dicomweb::wado_rs,
            commands::dicomweb::stow_rs,

            // Export operations
            commands::export::export_tags_json,
            commands::export::export_tags_xml,
            commands::export::export_image_png,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
