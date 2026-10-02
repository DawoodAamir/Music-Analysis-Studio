# Privacy

Music Analysis Studio copies only an audio file selected through the system file picker. Copies and reports live in the app's local Application Support directory. Analysis runs on device. There is no account, analytics, app network permission, microphone access, or Photos/Music library browsing permission.

Original audio files remain unchanged. Copies retain embedded audio metadata. Exported JSON reports contain the display name and derived measurements, not the source audio or original filesystem path. Export occurs only through the system save interface.

Cancelling or failing an import removes its newly staged copy. Completed reports remain in the library; this version has no permanent-delete interface or cloud synchronization. Local storage follows the device's standard protection and backup settings and is not a separate encrypted vault.
