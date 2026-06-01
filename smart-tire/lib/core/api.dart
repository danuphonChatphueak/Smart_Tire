import 'package:dio/dio.dart';

class Api {
  static const String baseUrl = String.fromEnvironment(
    'BASE_URL',
    //defaultValue: 'http://10.0.2.2:8000',
    defaultValue: 'http://192.168.1.13:8000',
  );
  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 120),
      receiveTimeout: const Duration(seconds: 180),
    ),
  );

  static Dio dio() => _dio;
}
