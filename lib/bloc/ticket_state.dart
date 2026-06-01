import 'package:equatable/equatable.dart';
import '../models/ticket_model.dart';

abstract class TicketState extends Equatable {
  const TicketState();

  @override
  List<Object?> get props => [];
}

class TicketInitial extends TicketState {
  const TicketInitial();
}

class TicketLoading extends TicketState {
  const TicketLoading();
}

class TicketSuccess extends TicketState {
  final TicketResponse ticketResponse;
  final String activityType;
  final String ticketType;
  final int currentPage;
  final bool hasReachedMax;
  final bool isLoadingMore;

  const TicketSuccess({
    required this.ticketResponse,
    required this.activityType,
    required this.ticketType,
    this.currentPage = 1,
    this.hasReachedMax = false,
    this.isLoadingMore = false,
  });

  TicketSuccess copyWith({
    TicketResponse? ticketResponse,
    String? activityType,
    String? ticketType,
    int? currentPage,
    bool? hasReachedMax,
    bool? isLoadingMore,
  }) {
    return TicketSuccess(
      ticketResponse: ticketResponse ?? this.ticketResponse,
      activityType: activityType ?? this.activityType,
      ticketType: ticketType ?? this.ticketType,
      currentPage: currentPage ?? this.currentPage,
      hasReachedMax: hasReachedMax ?? this.hasReachedMax,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
    );
  }

  @override
  List<Object?> get props => [
        ticketResponse,
        activityType,
        ticketType,
        currentPage,
        hasReachedMax,
        isLoadingMore,
      ];
}

class TicketFailure extends TicketState {
  final String errorMessage;

  const TicketFailure({required this.errorMessage});

  @override
  List<Object?> get props => [errorMessage];
}

class TicketRefresh extends TicketState {
  const TicketRefresh();
}
