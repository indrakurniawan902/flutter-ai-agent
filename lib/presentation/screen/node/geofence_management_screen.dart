import 'package:flutter/material.dart';
import 'package:flutter_ai_agent/common/injection/injection.dart';
import 'package:flutter_ai_agent/data/datasources/local/settings/secure_storage_service.dart';
import 'package:flutter_ai_agent/domain/entities/chat/ambient_event.dart';
import 'package:flutter_ai_agent/domain/tools/chat/ambient_trigger_service.dart';
import 'package:flutter_ai_agent/domain/tools/chat/location_service.dart';
import 'package:flutter_ai_agent/presentation/screen/chat/widgets/permission_rationale_modal.dart';
import 'package:flutter_ai_agent/presentation/screen/node/cubit/geofence_management_cubit.dart';
import 'package:flutter_ai_agent/presentation/screen/node/cubit/geofence_management_state.dart';
import 'package:flutter_ai_agent/utils/hermes_theme.dart';
import 'package:flutter_ai_agent/utils/permission_gate.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Geofence region management screen.
///
/// Reachable from the Pocket Node screen. [cubit] is optional for tests; when
/// omitted it is built from the registered services.
class GeofenceManagementScreen extends StatelessWidget {
  final GeofenceManagementCubit? cubit;
  final PermissionGate? permissionGate;

  const GeofenceManagementScreen({super.key, this.cubit, this.permissionGate});

  @override
  Widget build(BuildContext context) {
    final provided = cubit;
    if (provided != null) {
      return BlocProvider<GeofenceManagementCubit>.value(
        value: provided,
        child: _GeofenceScaffold(permissionGate: permissionGate),
      );
    }
    return BlocProvider<GeofenceManagementCubit>(
      create: (_) => GeofenceManagementCubit(
        storage: getIt<SecureStorageService>(),
        ambient: getIt<AmbientTriggerServiceBase>(),
        location: getIt<LocationServiceBase>(),
      )..load(),
      child: _GeofenceScaffold(permissionGate: permissionGate),
    );
  }
}

class _GeofenceScaffold extends StatelessWidget {
  final PermissionGate? permissionGate;

  const _GeofenceScaffold({this.permissionGate});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HermesColors.deepObsidian,
      appBar: AppBar(
        title: const Text(
          'Manage Geofences',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      body: BlocListener<GeofenceManagementCubit, GeofenceManagementState>(
        listenWhen: (prev, cur) =>
            cur.error != null && cur.error != prev.error,
        listener: (context, state) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(
              SnackBar(
                content: Text(
                  state.error!,
                  style: HermesTypography.monospace(
                    fontSize: 12,
                    color: Colors.white,
                  ),
                ),
                backgroundColor: HermesColors.cardSurface,
                behavior: SnackBarBehavior.floating,
              ),
            );
        },
        child: BlocBuilder<GeofenceManagementCubit, GeofenceManagementState>(
          builder: (context, state) {
            if (state.isLoading && state.regions.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(
                  color: HermesColors.accentTeal,
                ),
              );
            }
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                _AddGeofenceForm(permissionGate: permissionGate),
                const SizedBox(height: 20),
                _buildSectionHeader('Saved Geofences'),
                const SizedBox(height: 8),
                if (state.regions.isEmpty)
                  const _EmptyState()
                else
                  ...state.regions.map((region) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _GeofenceTile(
                          region: region,
                          permissionGate: permissionGate,
                        ),
                      )),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Row(
      children: [
        const Icon(Icons.place_outlined, size: 16, color: HermesColors.electricTeal),
        const SizedBox(width: 8),
        Text(
          title,
          style: HermesTypography.monospace(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: HermesColors.inkSecondary,
          ),
        ),
      ],
    );
  }
}

class _GeofenceTile extends StatelessWidget {
  final GeofenceRegion region;
  final PermissionGate? permissionGate;

  const _GeofenceTile({required this.region, this.permissionGate});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<GeofenceManagementCubit>();
    return Container(
      key: Key('geofence_tile_${region.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HermesColors.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HermesColors.border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  region.displayName,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HermesColors.inkPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${region.latitude.toStringAsFixed(5)}, '
                  '${region.longitude.toStringAsFixed(5)} • '
                  '${region.radiusMeters.toStringAsFixed(0)} m',
                  style: const TextStyle(
                    fontSize: 11,
                    color: HermesColors.inkMuted,
                  ),
                ),
              ],
            ),
          ),
          Switch.adaptive(
            key: Key('geofence_switch_${region.id}'),
            value: region.isEnabled,
            activeThumbColor: HermesColors.electricTeal,
            activeTrackColor: HermesColors.electricTeal.withValues(alpha: 0.3),
            inactiveThumbColor: HermesColors.inkMuted,
            inactiveTrackColor: HermesColors.deepObsidian,
            onChanged: (_) => cubit.toggleGeofence(region.id),
          ),
          IconButton(
            key: Key('geofence_edit_${region.id}'),
            tooltip: 'Edit',
            onPressed: () => _openEditSheet(context, cubit),
            icon: const Icon(Icons.edit_outlined,
                size: 20, color: HermesColors.inkSecondary),
          ),
          IconButton(
            key: Key('geofence_delete_${region.id}'),
            tooltip: 'Delete',
            onPressed: () => _confirmDelete(context, cubit),
            icon: const Icon(Icons.delete_outline,
                size: 20, color: HermesColors.rose),
          ),
        ],
      ),
    );
  }

  Future<void> _openEditSheet(
    BuildContext context,
    GeofenceManagementCubit cubit,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: HermesColors.deepObsidian,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
        return BlocProvider<GeofenceManagementCubit>.value(
          value: cubit,
          child: SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottomInset),
              child: SingleChildScrollView(
                child: _AddGeofenceForm(
                  permissionGate: permissionGate,
                  editingRegion: region,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    GeofenceManagementCubit cubit,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HermesColors.cardSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: HermesColors.border),
        ),
        title: Text(
          'Delete geofence?',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: HermesColors.inkPrimary,
          ),
        ),
        content: Text(
          'Remove ${region.displayName} and its trigger?',
          style: const TextStyle(
            fontSize: 12,
            color: HermesColors.inkSecondary,
          ),
        ),
        actions: [
          TextButton(
            key: const Key('geofence_delete_cancel'),
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            key: const Key('geofence_delete_confirm'),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text(
              'Delete',
              style: TextStyle(color: HermesColors.rose),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await cubit.removeGeofence(region.id);
    }
  }
}

class _AddGeofenceForm extends StatefulWidget {
  final PermissionGate? permissionGate;

  /// When non-null the form edits this region instead of adding a new one.
  final GeofenceRegion? editingRegion;

  const _AddGeofenceForm({this.permissionGate, this.editingRegion});

  @override
  State<_AddGeofenceForm> createState() => _AddGeofenceFormState();
}

class _AddGeofenceFormState extends State<_AddGeofenceForm> {
  final _formKey = GlobalKey<FormState>();
  final _labelController = TextEditingController();
  final _latController = TextEditingController();
  final _lngController = TextEditingController();
  double _radius = 100;
  bool _capturing = false;
  bool _submitting = false;

  static const List<double> _radiusOptions = [50, 100, 200, 500];

  bool get _isEditing => widget.editingRegion != null;

  PermissionGate get _permissionGate => widget.permissionGate ?? PermissionGate();

  @override
  void initState() {
    super.initState();
    final region = widget.editingRegion;
    if (region != null) {
      _labelController.text = region.rawName;
      _latController.text = region.latitude.toStringAsFixed(6);
      _lngController.text = region.longitude.toStringAsFixed(6);
      _radius = _closestRadiusOption(region.radiusMeters);
    }
  }

  static double _closestRadiusOption(double radius) {
    var closest = _radiusOptions.first;
    var smallestDiff = (radius - closest).abs();
    for (final option in _radiusOptions.skip(1)) {
      final diff = (radius - option).abs();
      if (diff < smallestDiff) {
        closest = option;
        smallestDiff = diff;
      }
    }
    return closest;
  }

  @override
  void dispose() {
    _labelController.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  Future<void> _useCurrentLocation() async {
    final cubit = context.read<GeofenceManagementCubit>();
    setState(() => _capturing = true);
    try {
      final granted = await _permissionGate.requestWithRationale(
        context,
        PermissionRationaleType.location,
      );
      if (!granted) return;
      final loc = await cubit.captureCurrentLocation();
      if (!mounted) return;
      if (loc == null) {
        _showFeedback('Unable to capture current location.');
        return;
      }
      setState(() {
        _latController.text = loc.latitude.toStringAsFixed(6);
        _lngController.text = loc.longitude.toStringAsFixed(6);
      });
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final cubit = context.read<GeofenceManagementCubit>();
    final lat = double.parse(_latController.text.trim());
    final lng = double.parse(_lngController.text.trim());
    final region = widget.editingRegion;
    setState(() => _submitting = true);
    try {
      if (region != null) {
        final ok = await cubit.updateGeofence(
          region.id,
          label: _labelController.text.trim(),
          latitude: lat,
          longitude: lng,
          radiusMeters: _radius,
        );
        if (!mounted) return;
        if (!ok) {
          _showFeedback('Failed to update geofence.');
          return;
        }
        _showFeedback('Geofence updated.');
        Navigator.of(context).pop();
        return;
      }
      final id = await cubit.addGeofence(
        label: _labelController.text.trim(),
        latitude: lat,
        longitude: lng,
        radiusMeters: _radius,
      );
      if (!mounted) return;
      if (id == null) {
        _showFeedback('Failed to save geofence.');
        return;
      }
      _labelController.clear();
      _latController.clear();
      _lngController.clear();
      setState(() => _radius = 100);
      _showFeedback('Geofence added.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _showFeedback(String message) {
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: HermesTypography.monospace(fontSize: 12, color: Colors.white),
        ),
        backgroundColor: HermesColors.cardSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  String? _validateLabel(String? value) {
    if (value == null || value.trim().isEmpty) return 'Label required';
    return null;
  }

  String? _validateLatitude(String? value) =>
      _validateCoordinate(value, -90, 90, 'Latitude');

  String? _validateLongitude(String? value) =>
      _validateCoordinate(value, -180, 180, 'Longitude');

  String? _validateCoordinate(
    String? value,
    double min,
    double max,
    String label,
  ) {
    if (value == null || value.trim().isEmpty) return 'Required';
    final parsed = double.tryParse(value.trim());
    if (parsed == null || !parsed.isFinite) return 'Invalid number';
    if (parsed < min || parsed > max) {
      return '$label must be between ${min.toStringAsFixed(0)} '
          'and ${max.toStringAsFixed(0)}';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: HermesColors.cardSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: HermesColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isEditing ? 'Edit Geofence' : 'Add Geofence',
              style: HermesTypography.monospace(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: HermesColors.inkPrimary,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('geofence_label_field'),
              controller: _labelController,
              style: const TextStyle(color: HermesColors.inkPrimary),
              decoration: _inputDecoration('Label'),
              validator: _validateLabel,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    key: const Key('geofence_lat_field'),
                    controller: _latController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    style: const TextStyle(color: HermesColors.inkPrimary),
                    decoration: _inputDecoration('Latitude'),
                    validator: _validateLatitude,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    key: const Key('geofence_lng_field'),
                    controller: _lngController,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    style: const TextStyle(color: HermesColors.inkPrimary),
                    decoration: _inputDecoration('Longitude'),
                    validator: _validateLongitude,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              key: const Key('geofence_use_current_location'),
              style: OutlinedButton.styleFrom(
                foregroundColor: HermesColors.inkPrimary,
                backgroundColor: HermesColors.deepObsidian,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                side: const BorderSide(color: HermesColors.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _capturing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: HermesColors.electricTeal,
                      ),
                    )
                  : const Icon(Icons.my_location_outlined,
                      size: 16, color: HermesColors.electricTeal),
              label: const Text('Use Current Location'),
              onPressed: _capturing ? null : _useCurrentLocation,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              key: const Key('geofence_radius_dropdown'),
              initialValue: _radius,
              dropdownColor: HermesColors.cardSurface,
              style: const TextStyle(color: HermesColors.inkPrimary),
              decoration: _inputDecoration('Radius'),
              items: _radiusOptions
                  .map(
                    (r) => DropdownMenuItem(
                      value: r,
                      child: Text('${r.toStringAsFixed(0)} m'),
                    ),
                  )
                  .toList(),
              onChanged: (val) {
                if (val != null) setState(() => _radius = val);
              },
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('geofence_submit'),
                style: FilledButton.styleFrom(
                  backgroundColor: HermesColors.accentTeal,
                  foregroundColor: Colors.white,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                icon: Icon(_isEditing ? Icons.save_outlined : Icons.add,
                    size: 16),
                label: Text(_isEditing ? 'Save Changes' : 'Add Geofence'),
                onPressed: _submit,
              ),
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: HermesColors.inkMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HermesColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HermesColors.electricTeal),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: HermesColors.border),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('geofence_empty'),
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.location_off_outlined,
            size: 44,
            color: HermesColors.inkMuted,
          ),
          SizedBox(height: 12),
          Text(
            'No geofences yet',
            style: TextStyle(
              color: HermesColors.inkSecondary,
              fontSize: 15,
            ),
          ),
        ],
      ),
    );
  }
}
