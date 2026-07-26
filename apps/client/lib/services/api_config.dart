/// Dev API base URL for local backend.
///
/// Windows / desktop: localhost.
/// Android emulator would need `http://10.0.2.2:8000` instead.
const String apiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://127.0.0.1:8000',
);
