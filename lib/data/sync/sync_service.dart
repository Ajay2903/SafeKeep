/// Placeholder for optional, future cloud/remote sync.
///
/// Safekeep is local-first and fully functional offline; sync is an
/// opt-in feature that does not exist yet and has no chosen backend. This
/// interface is a marker for where that integration will eventually live
/// — do not build a real implementation against this without confirming
/// the sync design first, since it directly affects the encryption and
/// key-sharing model.
// TODO(future-phase): design and implement remote sync. Out of scope for
// Phase 0 and not scheduled yet.
abstract interface class SyncService {
  Future<void> sync();

  Future<void> cancel();
}
