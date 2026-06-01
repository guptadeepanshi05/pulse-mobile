import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/foundation.dart';
import '../models/ticket_model.dart';
import '../repositories/ticket_repository.dart';
import 'ticket_state.dart';

class TicketCubit extends Cubit<TicketState> {
  final TicketRepository _ticketRepository;

  TicketCubit({required TicketRepository ticketRepository})
      : _ticketRepository = ticketRepository,
        super(const TicketInitial());

  Future<void> getTickets({
    required String activityType,
    required String ticketType,
    int? pageSize,
    int? pageNo,
  }) async {
    try {
      emit(const TicketLoading());

      final filterParams = TicketFilterParams(
        activityType: activityType,
        type: ticketType,
        pageSize: pageSize,
        pageNo: pageNo,
      );

      final result = await _ticketRepository.getTickets(filterParams);

      if (result.isSuccess) {
        final ticketResponse = result.data as TicketResponse;
        final requestedPage = pageNo ?? 1;
        final requestedPageSize = pageSize ?? ticketResponse.pageSize;
        final hasReachedMax = _computeHasReachedMax(
          loadedSoFar: ticketResponse.tickets.length,
          lastBatchSize: ticketResponse.tickets.length,
          requestedPageSize: requestedPageSize,
          totalRecords: ticketResponse.totalRecords,
        );

        emit(TicketSuccess(
          ticketResponse: ticketResponse,
          activityType: activityType,
          ticketType: ticketType,
          currentPage: requestedPage,
          hasReachedMax: hasReachedMax,
        ));
      } else {
        debugPrint("🔍 TicketCubit: API call failed!");
        debugPrint("   Error: ${result.errorMessage}");
        emit(TicketFailure(
            errorMessage: result.errorMessage ?? 'Failed to fetch tickets'));
      }
    } catch (e) {
      debugPrint("🔍 TicketCubit: Exception occurred!");
      debugPrint("   Error: $e");
      emit(TicketFailure(errorMessage: e.toString()));
    }
  }

  Future<void> refreshTickets({
    required String activityType,
    required String ticketType,
    int? pageSize,
    int? pageNo,
  }) async {
    try {
      emit(const TicketRefresh());
      await getTickets(
        activityType: activityType,
        ticketType: ticketType,
        pageSize: pageSize,
        pageNo: pageNo,
      );
    } catch (e) {
      emit(TicketFailure(errorMessage: e.toString()));
    }
  }

  /// Fetches the next page of tickets and appends them to the existing list.
  ///
  /// Safe to call repeatedly: bails out when there is no current success state,
  /// when a load-more is already in flight, or when [TicketSuccess.hasReachedMax]
  /// is already true.
  Future<void> loadMoreTickets({
    required String activityType,
    required String ticketType,
    int? pageSize,
  }) async {
    final currentState = state;
    if (currentState is! TicketSuccess) return;
    if (currentState.isLoadingMore || currentState.hasReachedMax) return;

    emit(currentState.copyWith(isLoadingMore: true));

    try {
      final nextPage = currentState.currentPage + 1;
      debugPrint(
        "📄 TicketCubit: loading page $nextPage (loaded so far: ${currentState.ticketResponse.tickets.length}, "
        "totalRecords: ${currentState.ticketResponse.totalRecords})",
      );
      final result = await _ticketRepository.getTickets(
        TicketFilterParams(
          activityType: activityType,
          type: ticketType,
          pageSize: pageSize,
          pageNo: nextPage,
        ),
      );

      if (result.isSuccess) {
        final newTicketResponse = result.data as TicketResponse;
        final updatedTickets = [
          ...currentState.ticketResponse.tickets,
          ...newTicketResponse.tickets,
        ];

        final totalRecords = newTicketResponse.totalRecords > 0
            ? newTicketResponse.totalRecords
            : currentState.ticketResponse.totalRecords;

        final requestedPageSize = pageSize ?? newTicketResponse.pageSize;
        final hasReachedMax = _computeHasReachedMax(
          loadedSoFar: updatedTickets.length,
          lastBatchSize: newTicketResponse.tickets.length,
          requestedPageSize: requestedPageSize,
          totalRecords: totalRecords,
        );

        final updatedResponse = TicketResponse(
          pageNo: newTicketResponse.pageNo,
          pageSize: newTicketResponse.pageSize,
          totalRecords: totalRecords,
          tickets: updatedTickets,
        );

        emit(TicketSuccess(
          ticketResponse: updatedResponse,
          activityType: activityType,
          ticketType: ticketType,
          currentPage: nextPage,
          hasReachedMax: hasReachedMax,
          isLoadingMore: false,
        ));
      } else {
        debugPrint("🔍 TicketCubit: loadMore failed: ${result.errorMessage}");
        emit(currentState.copyWith(isLoadingMore: false));
      }
    } catch (e) {
      debugPrint("🔍 TicketCubit: loadMore exception: $e");
      final latest = state;
      if (latest is TicketSuccess) {
        emit(latest.copyWith(isLoadingMore: false));
      }
    }
  }

  bool _computeHasReachedMax({
    required int loadedSoFar,
    required int lastBatchSize,
    required int requestedPageSize,
    required int totalRecords,
  }) {
    // Empty page is always the end.
    if (lastBatchSize == 0) return true;
    // Prefer the server-reported total when available – it's authoritative.
    if (totalRecords > 0) return loadedSoFar >= totalRecords;
    // Unknown total: assume more pages exist as long as we got a full page.
    if (requestedPageSize > 0 && lastBatchSize < requestedPageSize) return true;
    return false;
  }

  void resetState() {
    emit(const TicketInitial());
  }
}
