/// Reads launch arguments the way macOS does: `-key value` pairs are settings (the argument domain of
/// `UserDefaults`), anything else is a file to open. `-psn_…` (added by older launchers) takes no value.
public enum LaunchArguments {
    /// The arguments that name files, in order. Pass `CommandLine.arguments.dropFirst()`.
    public static func filePaths(in arguments: some Sequence<String>) -> [String] {
        var paths: [String] = []
        var expectsValue = false
        for argument in arguments {
            if argument.hasPrefix("-") {
                expectsValue = !argument.hasPrefix("-psn_")
            } else if expectsValue {
                expectsValue = false
            } else {
                paths.append(argument)
            }
        }
        return paths
    }
}
