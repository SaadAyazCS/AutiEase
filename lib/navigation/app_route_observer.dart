import 'package:flutter/material.dart';

/// Used to refresh parent screens when returning from Settings (e.g. support area toggles).
final RouteObserver<PageRoute<dynamic>> appRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
