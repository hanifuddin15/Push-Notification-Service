import 'dart:convert';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart' as dio;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:guard_monitoring_app/app/core/config/api_constant.dart';
import 'package:guard_monitoring_app/app/core/models/api_response.dart';
import 'package:guard_monitoring_app/app/core/services/log.dart';
import 'package:guard_monitoring_app/app/core/utils/loader.dart';
import 'package:guard_monitoring_app/app/core/utils/network.dart';
import 'package:guard_monitoring_app/app/core/utils/snackbar.dart';
import '../error/error_handler.dart';
import '../error/failure.dart';

class ApiService {
  ApiService._internal();

  static ApiService instance = ApiService._internal();

  factory ApiService() {
    return instance;
  }
  late dio.Dio _dio;
  late Connectivity connectivity;
  //* Request Valiables
  late String _baseUrl;
  late String token;
  late Map<String, dynamic> header;

  void init({required String token, required String ipPort}) {
    _dio = Dio();
    _dio.options.connectTimeout = const Duration(seconds: 60);
    _dio.options.receiveTimeout = const Duration(seconds: 60);

    _dio.interceptors.add(
      dio.LogInterceptor(
        requestHeader: true,
        requestBody: true,
        responseBody: false,
        responseHeader: false,
        error: true,
        logPrint: (object) {
          debugPrint(object.toString());
        },
      ),
    );

    connectivity = Connectivity();
    //* Request
    updateBaseUrl(ipPort);
    updateTokenAndHeader(token);
  }

  void updateBaseUrl(String ipPort) {
    _baseUrl = '$ipPort/api/v1';
  }

  String get getBaseUrl {
    return _baseUrl;
  }

  void updateTokenAndHeader(String newToken) {
    updateHeader(newToken);
    token = newToken;
  }

  void updateHeader(String newToken) {
    header = {'Accept': '*/*', 'Authorization': 'Bearer $newToken'};
  }

  Future<bool> isConnectedToInternet() async {
    final List<ConnectivityResult> connectivityResult = await (Connectivity()
        .checkConnectivity());

    if (connectivityResult.contains(ConnectivityResult.mobile) ||
        connectivityResult.contains(ConnectivityResult.wifi)) {
      return true;
    } else {
      return false;
    }
  }

  Future<ApiResponse> doGetRequest({
    required String apiEndPoint,
    Map<String, dynamic>? requestData,
    Map<String, dynamic>? queryParams,
    bool enableLoading = true,
    String responseDataKey = ApiConstant.dataResponse,
    String? successMessage,
    bool showSuccessMessage = false,
    bool showErrorMessage = true,
    String? errorMessage,
    bool addUserData = false,
  }) async {
    dio.Response? response;

    String requestUrl = '$_baseUrl/$apiEndPoint';

    /* if (addUserData) {
      UserModel? user = AuthRepository.instance.getUserData();
      requestData?.addAll({
        'companyId': user?.companyId,
        'organizationId': user?.organizationId,
      });
    } */

    debugPrint('Request Url: $requestUrl\n\nIs Request Data: $requestData\n');

    if (await isConnectedToInternet()) {
      try {
        if (enableLoading) showLoader();

        response = await _dio.get(
          requestUrl,
          data: requestData,
          queryParameters: queryParams,
          options: dio.Options(headers: header),
        );
        if (enableLoading) dismissLoader();
        if (response.statusCode == 200) {
          dynamic responseData =
              response.data; // Changed from Map<String, dynamic> to dynamic
          showSuccessMessage
              ? showSuccessSnackkbar(
                  message:
                      successMessage ??
                      (responseData is Map
                          ? responseData['message']
                          : 'Success'),
                )
              : ();
          debugPrint('${response.statusCode}');
          logFullResponse(responseData);

          // Handle generic access safely
          Object? extractedData;
          if (responseDataKey != ApiConstant.fullResponse &&
              responseData is Map) {
            extractedData = responseData[responseDataKey];
          } else {
            extractedData = responseData;
          }

          int? statusCode;
          int? totalCount;
          if (responseData is Map) {
            statusCode = responseData[ApiConstant.statusCodeKey];
            totalCount = responseData[ApiConstant.totalCount];
          } else {
            statusCode = 200;
          }

          return ApiResponse(
            isSuccessful: true,
            statusCode: statusCode,
            data: extractedData,
            totalCount: totalCount,
          );
        } else {
          Map<String, dynamic> responseData = response.data is Map
              ? response.data
              : {'message': 'Error ${response.statusCode}'};
          showErrorMessage
              ? showErrorSnackkbar(message: responseData['message'])
              : ();
          debugPrint('${response.statusCode}');
          logFullResponse(responseData);
          return ApiResponse(
            isSuccessful: false,
            statusCode: response.statusCode,
          );
        }
      } catch (error) {
        if (enableLoading) dismissLoader();
        final Failure failure = ErrorHandler.handleException(error);
        showErrorMessage ? showErrorSnackkbar(message: failure.message) : ();
        debugPrint(failure.message);
        return ApiResponse(isSuccessful: false, errorMessage: failure.message);
      }
    } else {
      errorMessage = 'You are not connected with mobile/wifi network';
      showWarningSnackkbar(message: errorMessage);
      debugPrint(errorMessage);
      return ApiResponse(
        isSuccessful: false,
        statusCode: 503,
        errorMessage: errorMessage,
      );
    }
  }

  Future<ApiResponse> doPostRequest({
    required String apiEndPoint,
    Map<String, dynamic>? requestData,
    File? file,
    List<File?>? files,
    String? fileKey,
    String multipleFileKey = 'attachments',
    bool isFormData = false,
    bool enableLoading = true,
    String responseDataKey = ApiConstant.dataResponse,
    String? successMessage,
    bool showSuccessMessage = false,
    bool showErrorMessage = true,
    String? errorMessage,
    bool addUserData = false,
  }) async {
    dio.Response? response;

    String requestUrl = '$_baseUrl/$apiEndPoint';

    // if (addUserData) {
    //   UserModel? user = AuthRepository.instance.getUserData();
    //   requestData = requestData ?? {};
    //   requestData.addAll({
    //     'companyId': user?.companyId,
    //     'organizationId': user?.organizationId,
    //   });
    // }

    debugPrint(
      'Request Url: $requestUrl\n\nIs Form Request: $isFormData \n\n Request Data: $requestData\nFile Key: $fileKey\nFile Path: ${file?.path}\n',
    );

    if (await isConnectedToInternet()) {
      try {
        if (enableLoading) showLoader();
        final Object? requestObject;

        if (isFormData) {
          requestData?.remove('attachments');

          // Create form data map
          FormData requestFormData = FormData.fromMap(requestData ?? {});

          // ----- Single file upload -----
          if (file != null) {
            requestFormData.files.add(
              MapEntry(
                fileKey ?? multipleFileKey,
                dio.MultipartFile.fromFileSync(
                  file.path,
                  contentType: getMediaTypeFromFile(file),
                  filename: getFileNameFromFile(file),
                ),
              ),
            );
          }

          // ----- Multiple file upload -----
          if (files != null && files.isNotEmpty) {
            for (final f in files) {
              if (f == null) continue;

              requestFormData.files.add(
                MapEntry(
                  'attachments', // or 'attachments[]' based on backend
                  await dio.MultipartFile.fromFile(
                    f.path,
                    filename: getFileNameFromFile(f),
                    contentType: getMediaTypeFromFile(f),
                  ),
                ),
              );
            }
          }

          requestObject = requestFormData;
        } else {
          requestObject = requestData;
        }

        response = await _dio.post(
          requestUrl,
          data: requestObject,
          options: dio.Options(
            validateStatus: (_) => true,
            headers: isFormData ? _removeContentType(header) : header,
          ),
        );
        debugPrint('Status: ${response.statusCode}');

        if (enableLoading) dismissLoader();

        if (response.statusCode == 200) {
          Map<String, dynamic> responseData = response.data;

          if (showSuccessMessage) {
            showSuccessSnackkbar(
              message: successMessage ?? responseData['message'],
            );
          }
          logFullResponse(responseData);
          return ApiResponse(
            isSuccessful: true,
            statusCode: responseData[ApiConstant.statusCodeKey],
            data: responseDataKey != ApiConstant.fullResponse
                ? responseData[responseDataKey]
                : responseData,
            totalCount: responseData[ApiConstant.totalCount],
          );
        } else {
          if (showErrorMessage) {
            Map<String, dynamic> responseData = response.data;
            showErrorSnackkbar(message: responseData['message']);
          }
          return ApiResponse(
            isSuccessful: false,
            statusCode: response.statusCode,
          );
        }
      } catch (error) {
        if (enableLoading) dismissLoader();
        final Failure failure = ErrorHandler.handleException(error);
        if (showErrorMessage) {
          showErrorSnackkbar(message: failure.message);
        }
        return ApiResponse(isSuccessful: false, errorMessage: failure.message);
      }
    } else {
      errorMessage = 'You are not connected with mobile/wifi network';
      showWarningSnackkbar(message: errorMessage);
      return ApiResponse(
        isSuccessful: false,
        statusCode: 503,
        errorMessage: errorMessage,
      );
    }
  }

  Future<ApiResponse> doPatchRequest({
    required String apiEndPoint,
    Map<String, dynamic>? requestData,
    File? file,
    List<File?>? files,
    String? fileKey,
    String multipleFileKey = 'attachments',
    bool isFormData = false,
    bool enableLoading = true,
    String responseDataKey = ApiConstant.dataResponse,
    String? successMessage,
    bool showSuccessMessage = false,
    bool showErrorMessage = true,
    String? errorMessage,
    bool addUserData = false,
  }) async {
    dio.Response? response;

    String requestUrl = '$_baseUrl/$apiEndPoint';

    // if (addUserData) {
    //   UserModel? user = AuthRepository.instance.getUserData();
    //   requestData = requestData ?? {};
    //   requestData.addAll({
    //     'companyId': user?.companyId,
    //     'organizationId': user?.organizationId,
    //   });
    // }

    debugPrint(
      'Request Url: $requestUrl\n\nIs Form Request: $isFormData \n\n Request Data: $requestData\nFile Key: $fileKey\nFile Path: ${file?.path}\n',
    );

    if (await isConnectedToInternet()) {
      try {
        if (enableLoading) showLoader();
        final Object? requestObject;

        if (isFormData) {
          requestData?.remove('attachments');

          // Create form data map
          FormData requestFormData = FormData.fromMap(requestData ?? {});

          // ----- Single file upload -----
          if (file != null) {
            requestFormData.files.add(
              MapEntry(
                fileKey ?? multipleFileKey,
                dio.MultipartFile.fromFileSync(
                  file.path,
                  contentType: getMediaTypeFromFile(file),
                  filename: getFileNameFromFile(file),
                ),
              ),
            );
          }

          // ----- Multiple file upload -----
          if (files != null && files.isNotEmpty) {
            for (final f in files) {
              if (f == null) continue;

              requestFormData.files.add(
                MapEntry(
                  'attachments', // or 'attachments[]' based on backend
                  await dio.MultipartFile.fromFile(
                    f.path,
                    filename: getFileNameFromFile(f),
                    contentType: getMediaTypeFromFile(f),
                  ),
                ),
              );
            }
          }

          requestObject = requestFormData;
        } else {
          requestObject = requestData;
        }

        response = await _dio.patch(
          requestUrl,
          data: requestObject,
          options: dio.Options(
            validateStatus: (_) => true,
            headers: isFormData ? _removeContentType(header) : header,
          ),
        );
        debugPrint('Status: ${response.statusCode}');

        if (enableLoading) dismissLoader();

        if (response.statusCode == 200) {
          Map<String, dynamic> responseData = response.data;

          if (showSuccessMessage) {
            showSuccessSnackkbar(
              message: successMessage ?? responseData['message'],
            );
          }
          logFullResponse(responseData);
          return ApiResponse(
            isSuccessful: true,
            statusCode: responseData[ApiConstant.statusCodeKey],
            data: responseDataKey != ApiConstant.fullResponse
                ? responseData[responseDataKey]
                : responseData,
            totalCount: responseData[ApiConstant.totalCount],
          );
        } else {
          if (showErrorMessage) {
            Map<String, dynamic> responseData = response.data;
            showErrorSnackkbar(message: responseData['message']);
          }
          return ApiResponse(
            isSuccessful: false,
            statusCode: response.statusCode,
          );
        }
      } catch (error) {
        if (enableLoading) dismissLoader();
        final Failure failure = ErrorHandler.handleException(error);
        if (showErrorMessage) {
          showErrorSnackkbar(message: failure.message);
        }
        return ApiResponse(isSuccessful: false, errorMessage: failure.message);
      }
    } else {
      errorMessage = 'You are not connected with mobile/wifi network';
      showWarningSnackkbar(message: errorMessage);
      return ApiResponse(
        isSuccessful: false,
        statusCode: 503,
        errorMessage: errorMessage,
      );
    }
  }

  void logFullResponse(dynamic data) {
    if (!kDebugMode) return;

    try {
      final prettyJson = const JsonEncoder.withIndent('  ').convert(data);

      final colored = _colorizeJson(prettyJson);
      _printInChunks(colored);
    } catch (_) {
      _printInChunks(data.toString());
    }
  }

  String _colorizeJson(String json) {
    return json
        // Replace brackets first (NO ANSI)
        .replaceAll('{', LogBracket.objOpen)
        .replaceAll('}', LogBracket.objClose)
        .replaceAll('[', LogBracket.arrOpen)
        .replaceAll(']', LogBracket.arrClose)
        // Keys
        .replaceAllMapped(
          RegExp(r'"(.*?)"\s*:'),
          (m) => '${LogAnsi.key}"${m[1]}"${LogAnsi.reset}:',
        )
        // String values
        .replaceAllMapped(
          RegExp(r':\s*"(.*?)"'),
          (m) => ': ${LogAnsi.string}"${m[1]}"${LogAnsi.reset}',
        )
        // Numbers
        .replaceAllMapped(
          RegExp(r':\s*(-?\d+(\.\d+)?)'),
          (m) => ': ${LogAnsi.number}${m[1]}${LogAnsi.reset}',
        )
        // Boolean
        .replaceAllMapped(
          RegExp(r':\s*(true|false)'),
          (m) => ': ${LogAnsi.boolVal}${m[1]}${LogAnsi.reset}',
        )
        // Null
        .replaceAllMapped(
          RegExp(r':\s*(null)'),
          (m) => ': ${LogAnsi.nullVal}${m[1]}${LogAnsi.reset}',
        );
  }

  void _printInChunks(String text) {
    const int chunkSize = 800;

    for (int i = 0; i < text.length; i += chunkSize) {
      debugPrint(
        text.substring(
          i,
          i + chunkSize > text.length ? text.length : i + chunkSize,
        ),
      );
    }
  }

  void endConnection() => _dio.close(force: true);

  Map<String, dynamic> _removeContentType(Map<String, dynamic> headers) {
    final newHeaders = Map<String, dynamic>.from(headers);
    newHeaders.remove('Content-Type');
    return newHeaders;
  }
}
