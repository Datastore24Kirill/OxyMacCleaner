import Foundation

public enum UpdateInstaller {
  public static let script = #"""
  set -eu
  old_pid="$1"; app="$2"; next="$3"; stage="$4"
  case "$old_pid" in ''|*[!0-9]*) echo 'Invalid process ID' >&2; exit 2;; esac
  [ "$old_pid" -gt 1 ] || { echo 'Invalid process ID' >&2; exit 2; }
  [ -d "$app" ] && [ -d "$next" ] && [ -d "$stage" ] || { echo 'Update paths are missing' >&2; exit 2; }
  [ ! -e "$stage/healthy" ] || { echo 'Existing launch confirmation; update cancelled' >&2; exit 2; }
  [ ! -e "$stage/rollback" ] && [ ! -e "$stage/failed-update" ] || { echo 'Recovery paths already exist' >&2; exit 2; }
  /bin/mkdir -p "$stage/rollback"
  backup="$stage/rollback/OxyMac Cleaner.app"
  n=0
  while kill -0 "$old_pid" 2>/dev/null; do
    n=$((n+1)); [ "$n" -lt 60 ] || exit 1
    sleep 1
  done
  /bin/mv "$app" "$backup"
  if ! /bin/mv "$next" "$app"; then /bin/mv "$backup" "$app"; /usr/bin/open "$app"; exit 1; fi
  /usr/bin/open -n -W "$app" --args --oxy-update-health "$stage/healthy" &
  launcher=$!
  n=0
  while [ "$n" -lt 45 ]; do
    if [ -f "$stage/healthy" ]; then echo 'Update launched successfully; rollback copy retained'; exit 0; fi
    if ! kill -0 "$launcher" 2>/dev/null; then break; fi
    n=$((n+1)); sleep 1
  done
  if [ -f "$stage/healthy" ]; then echo 'Update launched successfully; rollback copy retained'; exit 0; fi
  # The child is Launch Services' waiting launcher, not the application. Never
  # signal it as a substitute for stopping the app, or replace a possibly live app.
  if kill -0 "$launcher" 2>/dev/null; then
    echo 'No launch confirmation; app may still be running. Manual recovery required. Backup retained.'
    exit 1
  fi
  wait "$launcher" || true
  echo 'Launch ended without confirmation; restoring previous version'
  /bin/mv "$app" "$stage/failed-update"
  /bin/mv "$backup" "$app"
  /usr/bin/open "$app"
  """#
}
