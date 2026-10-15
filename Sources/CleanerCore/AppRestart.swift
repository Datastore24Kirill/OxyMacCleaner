import Foundation

/// Wait for the current process to exit before asking Launch Services to reopen
/// the same bundle. Never starts a second instance while the first is alive.
public enum AppRestart {
  public static let script = #"""
  set -eu
  old_pid="$1"; app="$2"
  case "$old_pid" in ''|*[!0-9]*) echo 'Invalid process ID' >&2; exit 2;; esac
  [ "$old_pid" -gt 1 ] || { echo 'Invalid process ID' >&2; exit 2; }
  [ -d "$app" ] || { echo 'Application bundle is missing' >&2; exit 2; }
  echo 'Waiting for the current application to quit'
  n=0
  while kill -0 "$old_pid" 2>/dev/null; do
    n=$((n+1)); [ "$n" -lt 15 ] || { echo 'Application did not quit; restart cancelled' >&2; exit 3; }
    sleep 1
  done
  if /usr/bin/open -n "$app"; then
    echo 'Launch Services accepted the restart request'
  else
    echo 'Launch Services rejected the restart request' >&2
    exit 4
  fi
  """#
}
