import 'package:cloud_functions/cloud_functions.dart';

class RecipesService {
  RecipesService({this.region});
  final String? region;

  FirebaseFunctions get _fx =>
      region == null ? FirebaseFunctions.instance
                     : FirebaseFunctions.instanceFor(region: region!);

  Future<List<String>> recommend() async {
    final call = _fx.httpsCallable('recommend_recipes');
    final res = await call();
    final List<dynamic> list = res.data['recipes'] ?? [];
    return list.map((e) => e.toString()).toList();
  }
}
