/// The deployment environment a client is configured against.
///
/// Mirrors the dev / staging / prod separation established for the backend in
/// RF-013. This enum carries NO URLs, keys, or secrets - those are injected at
/// runtime from environment/secret stores and are never compiled into a client
/// (DECISION D-011; docs/SECURITY_AND_THREAT_MODEL.md section 12).
enum AppEnvironment { dev, staging, prod }
