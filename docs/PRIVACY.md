# Privacy and local storage

Scanning reads user-selected roots and stores scan metadata in memory. It does not send file names or contents to a remote service. History import is explicit and limited to one exported inactive session. Original files are not rewritten.

Application data lives under `~/Library/Application Support/OxyMacCleaner`:

- `Quarantine/`: moved files and a per-item recovery journal with original path, size, time and hash.
- `HistoryBackups/`: verified original imported histories. These may contain sensitive text. They remain until the user removes them separately.
- `operations.log`: local operation status and file paths, capped at 1,000 lines. Not uploaded automatically.
- `Downloads/`: temporary installer data, removed after completion or failure.

Preferences and exclusions are stored with macOS UserDefaults. Quarantine and backup directories use owner-only permissions. Original imported histories remain at their original location.

The model client uses only `http://127.0.0.1:11434`, disables configured HTTP proxies for this connection and refuses redirects. It rejects known cloud/remote models and requires local GGUF metadata before sending transcript text. Existing Ollama configuration remains under the user's control.

Network activity is initiated through installer/model/download buttons or opening GitHub Releases. Ollama app installation contacts GitHub and its HTTPS asset infrastructure; model downloads are performed by the locally running Ollama engine against its configured registry. Normal network metadata (such as IP address) reaches those services; no histories are included in model-download requests.

There are no analytics, ads or automatic diagnostic uploads. macOS notifications are optional. No screen-recording permission is required.

Deleting the app does not delete quarantine contents, history backups, local models or preferences. Restore wanted quarantined files before removing application data.
