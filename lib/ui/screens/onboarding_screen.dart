import 'package:flutter/material.dart';

import '../../app/brain2_controller.dart';
import '../widgets.dart';

class GlobalContextOnboardingScreen extends StatelessWidget {
  final Brain2Controller controller;
  const GlobalContextOnboardingScreen(this.controller, {super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const SizedBox(height: 28),
              const GlobalContextPageHeader(
                tag: 'ANDROID · AN11 / AN12 / AN13',
                title: 'Your AI context, under your control',
                description:
                    'Start locally without an account. Import or capture only what you choose, keep source evidence on-device, and approve every cross-AI context handoff.',
              ),
              const GlobalContextSectionCard(
                title: 'Local-first by default',
                children: [
                  GlobalContextActionTile(
                    icon: Icons.lock_outline,
                    title: 'Private local memory',
                    subtitle:
                        'Raw source history stays on this device unless you explicitly export or sync it.',
                    actionLabel: '',
                  ),
                  GlobalContextActionTile(
                    icon: Icons.fact_check_outlined,
                    title: 'Source-backed Current Truth',
                    subtitle:
                        'Current, superseded and conflicting state remain separate and traceable.',
                    actionLabel: '',
                  ),
                  GlobalContextActionTile(
                    icon: Icons.devices_outlined,
                    title: 'Optional device sync',
                    subtitle:
                        'Pair another authorized replica later. No sync permission is required to start.',
                    actionLabel: '',
                  ),
                ],
              ),
              const SizedBox(height: 18),
              const GlobalContextSectionCard(
                title: 'Permissions are just-in-time',
                children: [
                  GlobalContextActionTile(
                    icon: Icons.camera_alt_outlined,
                    title: 'Camera',
                    subtitle:
                        'Requested only when you scan a device-pairing QR.',
                    actionLabel: '',
                  ),
                  GlobalContextActionTile(
                    icon: Icons.share_outlined,
                    title: 'Context sharing',
                    subtitle:
                        'Preview the exact bounded capsule and approve it every time.',
                    actionLabel: '',
                  ),
                ],
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: controller.completeOnboarding,
                icon: const Icon(Icons.arrow_forward_rounded),
                label: const Text('Start with local brain2:inContext'),
              ),
            ],
          ),
        ),
      );
}
