import Foundation

/// Returns "Untitled — <formatted timestamp>" for the given date.
/// Locale and timezone default to the device's current settings;
/// pass explicit values in tests for deterministic output.
func placeholderName(for date: Date, locale: Locale = .current, timeZone: TimeZone = .current) -> String {
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = timeZone
    formatter.dateFormat = "MMM d, h:mm a"
    return "Untitled \u{2014} \(formatter.string(from: date))"
}
