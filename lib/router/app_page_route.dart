import 'package:PiliPlus/router/page_transitions.dart';
import 'package:get/get.dart';
import 'package:material_ui/material_ui.dart';

class AppPageRoute<T> extends GetPageRoute<T> with PredictiveBackPageRoute<T> {
  AppPageRoute({
    required GetPageBuilder page,
    super.settings,
    super.routeName,
    super.parameter,
    super.binding,
    super.bindings,
    super.middlewares,
  }) : super(page: page);

  static Future<T?>? push<T>(
    Object page, {
    String? routeName,
    Object? arguments,
    bool preventDuplicates = true,
  }) {
    var name = routeName ?? '/${page.runtimeType}';
    if (!name.startsWith('/')) name = '/$name';
    name = Uri.tryParse(name)?.toString() ?? name;
    if (preventDuplicates && name == Get.currentRoute) return null;
    return Get.key.currentState?.push<T>(
      AppPageRoute<T>(
        page: page is Widget ? () => page : page as GetPageBuilder,
        routeName: name,
        settings: RouteSettings(name: name, arguments: arguments),
      ),
    );
  }

  static Route<dynamic>? generate(RouteSettings settings) {
    final redirect = PageRedirect(settings: settings);
    while (redirect.needRecheck()) {}
    if (redirect.isUnknown) return null;
    final page = redirect.route!;
    return AppPageRoute(
      page: page.page,
      parameter: page.parameters,
      settings: redirect.settings,
      binding: page.binding,
      bindings: page.bindings,
      middlewares: page.middlewares,
    );
  }
}
