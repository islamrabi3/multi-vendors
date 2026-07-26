import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/tokens.dart';
import '../auth_cubit.dart';
import 'package:multi_vendor/core/utils/l10n_extension.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Scaffold(
      body: BlocBuilder<AuthCubit, AppAuthState>(
        builder: (context, state) {
          final isChecking = state.status == AuthStatus.unknown;

          return Container(
            width: double.infinity,
            height: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFFFF8A5B),
                  Color(0xFFFF5A2C),
                  Color(0xFFE8410F),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: [0.0, 0.48, 1.0],
              ),
            ),
            child: Stack(
              children: [
                // Top-right background circle
                Positioned(
                  top: 120,
                  right: -70,
                  width: 240,
                  height: 240,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.08),
                    ),
                  ),
                ),
                // Bottom-left background circle
                Positioned(
                  bottom: 240,
                  left: -60,
                  width: 180,
                  height: 180,
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white.withValues(alpha: 0.07),
                    ),
                  ),
                ),
                // Central Logo & Tagline
                Align(
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Glassmorphic Smiley Card
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                          child: Container(
                            width: 104,
                            height: 104,
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.25),
                                width: 1,
                              ),
                            ),
                            child: Align(
                              alignment: Alignment.topCenter,
                              child: Container(
                                width: 50,
                                height: 25,
                                margin: const EdgeInsets.only(top: 38),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: Colors.white,
                                      width: 10,
                                      style: BorderStyle.solid,
                                    ),
                                  ),
                                  borderRadius: const BorderRadius.vertical(
                                    bottom: Radius.circular(26),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 22),
                      Text(
                        context.l10n.eaty,
                        style: AppType.display(64, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        context.l10n.cravingsDelivered,
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w500,
                          color: Colors.white.withValues(alpha: 0.9),
                        ),
                      ),
                    ],
                  ),
                ),
                // Bottom CTAs or Loader
                Positioned(
                  bottom: media.padding.bottom + 46,
                  left: 28,
                  right: 28,
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: isChecking
                        ? const Center(
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 3,
                              ),
                            ),
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Get started
                              InkWell(
                                onTap: () => context.push('/signup'),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  height: 54,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(16),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withValues(alpha: 0.15),
                                        blurRadius: 24,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Text(
                                    context.l10n.getStarted,
                                    style: TextStyle(
                                      color: AppColors.primaryDark,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              // I already have an account
                              InkWell(
                                onTap: () => context.push('/login'),
                                borderRadius: BorderRadius.circular(16),
                                child: Container(
                                  height: 46,
                                  alignment: Alignment.center,
                                  child: Text(
                                    context.l10n.iAlreadyHaveAnAccount,
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.92),
                                      fontWeight: FontWeight.w600,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

