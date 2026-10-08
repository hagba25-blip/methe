/// Configuration injectée à la compilation :
/// flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_PUBLISHABLE_KEY=... --dart-define=API_BASE_URL=...
class Env {
  // Valeurs publiques du projet Supabase (non secrètes) ; surchargeables par --dart-define.
  static const supabaseUrl =
      String.fromEnvironment('SUPABASE_URL', defaultValue: 'https://wpudmineqmchekedvwof.supabase.co');
  static const supabasePublishableKey = String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY',
      defaultValue: 'sb_publishable_Ow1_HIRNH7P7h5U-YeXdzw_nvY8-Lqq');
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL', defaultValue: 'http://localhost:8000');

  static void assertConfigured() {
    if (supabaseUrl.isEmpty || supabasePublishableKey.isEmpty) {
      throw StateError('SUPABASE_URL et SUPABASE_PUBLISHABLE_KEY doivent être fournis via --dart-define');
    }
  }
}
