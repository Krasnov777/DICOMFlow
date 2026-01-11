// Logging utilities

use tracing::Level;

pub fn init_logging() {
    tracing_subscriber::fmt()
        .with_max_level(Level::INFO)
        .init();
}

pub fn set_log_level(level: &str) {
    // TODO: Implement dynamic log level setting
}
