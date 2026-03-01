import 'package:marketflow/app/app.dart';
import 'package:marketflow/config/supabase_config.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final hasSupabaseConfig = SupabaseConfig.isConfigured;
  if (hasSupabaseConfig) {
    await Supabase.initialize(
      url: SupabaseConfig.url,
      anonKey: SupabaseConfig.anonKey,
    );
  }

  runApp(EcommerceApp(hasSupabaseConfig: hasSupabaseConfig));
}
