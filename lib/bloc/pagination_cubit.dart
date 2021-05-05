import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

part 'pagination_state.dart';

class PaginationCubit extends Cubit<PaginationState> {
  PaginationCubit(
    this._query,
    this._limit,
    this._startAfterDocument, {
    this.isLive = false,
  }) : super(PaginationInitial());

  DocumentSnapshot<Map<String, dynamic>>? _lastDocument;
  final int _limit;
  final Query<Map<String, dynamic>> _query;
  final DocumentSnapshot<Map<String, dynamic>>? _startAfterDocument;
  final bool isLive;

  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>> _streams = List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>();

  void filterPaginatedList(String searchTerm) {
    if (state is PaginationLoaded) {
      final loadedState = state as PaginationLoaded;

      final filteredList = loadedState.documentSnapshots
          .where((document) => document
              .data()
              .toString()
              .toLowerCase()
              .contains(searchTerm.toLowerCase()))
          .toList();

      emit(loadedState.copyWith(
        documentSnapshots: filteredList,
        hasReachedEnd: loadedState.hasReachedEnd,
      ));
    }
  }

  void refreshPaginatedList() async {
    _lastDocument = null;
    final localQuery = _getQuery();
    if (isLive) {
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>> listener = localQuery.snapshots().listen((querySnapshot) {
        _emitPaginatedState(querySnapshot.docs);
      });

      _streams.add(listener);
    } else {
      final querySnapshot = await localQuery.get();
      _emitPaginatedState(querySnapshot.docs);
    }
  }

  void fetchPaginatedList() {
    isLive ? _getLiveDocuments() : _getDocuments();
  }

  _getDocuments() async {
    final localQuery = _getQuery();
    try {
      if (state is PaginationInitial) {
        refreshPaginatedList();
      } else if (state is PaginationLoaded) {
        final loadedState = state as PaginationLoaded;
        if (loadedState.hasReachedEnd) return;
        final querySnapshot = await localQuery.get();
        _emitPaginatedState(
          querySnapshot.docs,
          previousList:
              loadedState.documentSnapshots as List<QueryDocumentSnapshot<Map<String, dynamic>>>,
        );
      }
    } on PlatformException catch (exception) {
      print(exception);
      rethrow;
    }
  }

  _getLiveDocuments() {
    final localQuery = _getQuery();
    if (state is PaginationInitial) {
      refreshPaginatedList();
    } else if (state is PaginationLoaded) {
      final loadedState = state as PaginationLoaded;
      if (loadedState.hasReachedEnd) return;
      StreamSubscription<QuerySnapshot<Map<String, dynamic>>> listener =  localQuery.snapshots().listen((querySnapshot) {
        _emitPaginatedState(
          querySnapshot.docs,
          previousList:
              loadedState.documentSnapshots as List<QueryDocumentSnapshot<Map<String, dynamic>>>,
        );
      });

      _streams.add(listener);
    }
  }

  void _emitPaginatedState(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> newList, {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> previousList = const [],
  }) {
    print(newList.length);
    _lastDocument = newList.isNotEmpty ? newList.last : null;
    emit(PaginationLoaded(
      documentSnapshots: previousList + newList,
      hasReachedEnd: newList.isEmpty,
    ));
  }

  Query<Map<String, dynamic>> _getQuery() {
    var localQuery = (_lastDocument != null)
        ? _query.startAfterDocument(_lastDocument!)
        : _startAfterDocument != null
            ? _query.startAfterDocument(_startAfterDocument!)
            : _query;
    localQuery = localQuery.limit(_limit);
    return localQuery;
  }

  void dispose() {
    _streams.forEach((listener) => listener.cancel());
  }
}
