import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/presentation/screen/navigation/cubit/navigation_cubit.dart';

class NavigationParams {
  final NavigationCubit? cubit;
  final List<Widget>? screens;

  const NavigationParams({
    this.cubit,
    this.screens,
  });
}
