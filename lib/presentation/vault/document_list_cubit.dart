import 'package:bloc/bloc.dart';
import 'package:safekeep/core/logging/app_logger.dart';
import 'package:safekeep/data/data_exceptions.dart';
import 'package:safekeep/domain/models/document_category.dart';
import 'package:safekeep/domain/repositories/document_repository.dart';
import 'package:safekeep/presentation/vault/document_list_state.dart';
import 'package:safekeep/security/security_exceptions.dart';

/// Drives the document list: loading, searching, filtering, deleting.
///
/// Search and filter are applied to already-loaded metadata rather than
/// re-queried, because the whole set is metadata-only and small, and
/// keeping it in memory means typing in the search box does not hit the
/// database on every keystroke.
///
/// # Logging
///
/// Document identifiers and counts only — never titles, tags, or notes.
class DocumentListCubit extends Cubit<DocumentListState> {
  DocumentListCubit({required DocumentRepository repository})
    : this._(repository);

  DocumentListCubit._(this._repository) : super(const DocumentListState());

  final DocumentRepository _repository;

  Future<void> load() async {
    emit(state.copyWith(isLoading: true, clearError: true));
    try {
      final documents = await _repository.listDocuments();
      if (isClosed) return;
      emit(state.copyWith(isLoading: false, documents: documents));
    } on VaultLockedException {
      // Reaching here means the vault locked mid-load — an auto-lock
      // timer firing during the query. The gate is already tearing this
      // screen down, so there is nothing useful to show.
      if (!isClosed) emit(state.copyWith(isLoading: false));
    } on DataException catch (error) {
      AppLogger.instance.error('Failed to load documents: ${error.name}');
      if (!isClosed) {
        emit(
          state.copyWith(
            isLoading: false,
            errorMessage: 'Could not open your vault contents.',
          ),
        );
      }
    }
  }

  void search(String query) => emit(state.copyWith(query: query));

  void clearSearch() => emit(state.copyWith(query: ''));

  /// Filters by [category], or clears the filter when null or when the
  /// already-selected category is chosen again.
  void filterByCategory(DocumentCategory? category) {
    if (category == null || category == state.category) {
      emit(state.copyWith(clearCategory: true));
      return;
    }
    emit(state.copyWith(category: category));
  }

  Future<void> deleteDocument(String id) async {
    try {
      await _repository.deleteDocument(id);
      AppLogger.instance.info('Document deleted from list: $id');
      await load();
    } on DataException catch (error) {
      AppLogger.instance.error('Failed to delete document: ${error.name}');
      if (!isClosed) {
        emit(
          state.copyWith(errorMessage: 'Could not delete that document.'),
        );
      }
    }
  }

  /// Re-reads the vault after something outside this cubit changed it —
  /// an import or an edit completing on another screen.
  Future<void> refresh() => load();
}
