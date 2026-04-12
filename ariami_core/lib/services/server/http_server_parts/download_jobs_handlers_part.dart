part of '../http_server.dart';

extension AriamiHttpServerDownloadJobsHandlersMethods on AriamiHttpServer {
  Future<Response> _handleCreateDownloadJob(
    Request request,
    DownloadJobService downloadJobService,
  ) async {
    try {
      final body = await request.readAsString();
      final data = body.trim().isEmpty
          ? <String, dynamic>{}
          : jsonDecode(body) as Map<String, dynamic>;
      final createRequest = DownloadJobCreateRequest.fromJson(data);
      final response = downloadJobService.createJob(
        userScopeId: _resolveDownloadJobScopeUserId(request),
        request: createRequest,
      );
      return _jsonOk(response.toJson());
    } on DownloadJobServiceException catch (e) {
      return _downloadJobErrorResponse(e);
    } on FormatException {
      return _downloadJobErrorResponse(
        const DownloadJobServiceException(
          statusCode: 400,
          code: DownloadJobErrorCodes.invalidRequest,
          message: 'Invalid JSON body',
        ),
      );
    } on TypeError {
      return _downloadJobErrorResponse(
        const DownloadJobServiceException(
          statusCode: 400,
          code: DownloadJobErrorCodes.invalidRequest,
          message: 'Invalid request body',
        ),
      );
    }
  }

  Response _handleGetDownloadJob(
    Request request,
    String jobId,
    DownloadJobService downloadJobService,
  ) {
    try {
      final response = downloadJobService.getJob(
        userScopeId: _resolveDownloadJobScopeUserId(request),
        jobId: jobId,
      );
      return _jsonOk(response.toJson());
    } on DownloadJobServiceException catch (e) {
      return _downloadJobErrorResponse(e);
    }
  }

  Response _handleGetDownloadJobItems(
    Request request,
    String jobId,
    DownloadJobService downloadJobService,
  ) {
    final rawCursor = request.url.queryParameters['cursor'];
    final rawLimit = request.url.queryParameters['limit'];

    final cursor =
        rawCursor == null || rawCursor.isEmpty ? null : int.tryParse(rawCursor);
    if (rawCursor != null && rawCursor.isNotEmpty && cursor == null) {
      return _downloadJobErrorResponse(
        const DownloadJobServiceException(
          statusCode: 400,
          code: DownloadJobErrorCodes.invalidCursor,
          message: 'cursor must be a non-negative integer',
        ),
      );
    }

    final limit = rawLimit == null || rawLimit.isEmpty
        ? DownloadJobService.defaultPageLimit
        : int.tryParse(rawLimit);
    if (rawLimit != null && rawLimit.isNotEmpty && limit == null) {
      return _downloadJobErrorResponse(
        const DownloadJobServiceException(
          statusCode: 400,
          code: DownloadJobErrorCodes.invalidRequest,
          message: 'limit must be an integer between 1 and 500',
        ),
      );
    }

    try {
      final response = downloadJobService.getJobItems(
        userScopeId: _resolveDownloadJobScopeUserId(request),
        jobId: jobId,
        cursor: cursor,
        limit: limit ?? DownloadJobService.defaultPageLimit,
      );
      return _jsonOk(response.toJson());
    } on DownloadJobServiceException catch (e) {
      return _downloadJobErrorResponse(e);
    }
  }

  Response _handleCancelDownloadJob(
    Request request,
    String jobId,
    DownloadJobService downloadJobService,
  ) {
    try {
      final response = downloadJobService.cancelJob(
        userScopeId: _resolveDownloadJobScopeUserId(request),
        jobId: jobId,
      );
      return _jsonOk(response.toJson());
    } on DownloadJobServiceException catch (e) {
      return _downloadJobErrorResponse(e);
    }
  }

  String _resolveDownloadJobScopeUserId(Request request) {
    final session = request.context['session'] as Session?;
    return session?.userId ?? 'legacy';
  }

  Response _downloadJobErrorResponse(DownloadJobServiceException error) {
    final headers = <String, String>{};
    if (error.statusCode == 429 || error.statusCode == 503) {
      headers['Retry-After'] =
          '${error.retryAfterSeconds ?? AriamiHttpServer._defaultRetryAfterSeconds}';
    }

    return _jsonResponse(
      error.statusCode,
      {
        'error': {
          'code': error.code,
          'message': error.message,
          if (error.details != null) 'details': error.details,
        },
      },
      headers: headers.isEmpty ? null : headers,
    );
  }

  Response _retryableErrorResponse({
    required int statusCode,
    required String error,
    required String message,
    int retryAfterSeconds = AriamiHttpServer._defaultRetryAfterSeconds,
  }) {
    return _jsonResponse(
      statusCode,
      {
        'error': error,
        'message': message,
      },
      headers: {'Retry-After': '$retryAfterSeconds'},
    );
  }

  String? _resolveRequestUserId(Request request) {
    final session = request.context['session'] as Session?;
    if (session != null) {
      return session.userId;
    }

    final streamToken = request.url.queryParameters['streamToken'];
    if (streamToken == null || streamToken.isEmpty) {
      return null;
    }

    final ticket = _streamTracker.validateToken(streamToken);
    return ticket?.userId;
  }
}
