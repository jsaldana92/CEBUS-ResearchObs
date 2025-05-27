// lib/navigation_helpers.dart
import 'package:flutter/material.dart';

Route createSlideRoute(Widget page, {required bool fromLeft}) {
  return PageRouteBuilder(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final beginOffset = fromLeft ? Offset(-1, 0) : Offset(1, 0);
      return SlideTransition(
        position: Tween<Offset>(
          begin: beginOffset,
          end: Offset.zero,
        ).animate(animation),
        child: child,
      );
    },
    transitionDuration: Duration(milliseconds: 500),
    reverseTransitionDuration: Duration(milliseconds: 500),
  );
}
