#pragma once

// Centralized log verbosity control for the solver.
// Keep this tiny and dependency-free so it can be included from hot-path code.
enum class LogLevel : int {
  None = 0,     // No logs in hot loops
  Summary = 1,  // Low-volume milestone logs
  Debug = 2     // Detailed diagnostics (can be expensive)
};

inline constexpr bool logEnabled(LogLevel lvl) noexcept {
  return lvl != LogLevel::None;
}
inline constexpr bool logDebug(LogLevel lvl) noexcept {
  return lvl >= LogLevel::Debug;
}
inline constexpr bool logSummary(LogLevel lvl) noexcept {
  return lvl >= LogLevel::Summary;
}
