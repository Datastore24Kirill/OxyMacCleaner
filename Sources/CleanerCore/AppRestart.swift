import Foundation

/// Wait for the current process to exit before asking Launch Services to reopen
/// the same bundle. Never starts a second instance while the first is alive.
public enum AppRestart {
  public static let script = #"""
  set -eu
  old_pid="$1"; app="$2"
  case "$old_pid" in ''|*[!0-9]*) exit 2;; esac
  [ "$old_pid" -gt 1 ] || exit 2
  [ -d "$app" ] || exit 2
  n=0
  while kill -0 "$old_pid" 2>/dev/null; do
    n=$((n+1)); [ "$n" -lt 60 ] || exit 1
    sleep 1
  done
  exec /usr/bin/open -n "$app"
  """#
}
