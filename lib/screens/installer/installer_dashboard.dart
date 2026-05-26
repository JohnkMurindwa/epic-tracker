import 'dart:io';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/user_model.dart';
import '../../services/auth_service.dart';
import '../../services/firestore_service.dart';
import '../../services/storage_service.dart';
import '../auth/login_screen.dart';

class InstallerDashboard extends StatefulWidget {
  final UserModel user;
  const InstallerDashboard({super.key, required this.user});

  @override
  State<InstallerDashboard> createState() => _InstallerDashboardState();
}

class _InstallerDashboardState extends State<InstallerDashboard> {
  final AuthService _authService = AuthService();
  final FirestoreService _firestoreService = FirestoreService();
  final StorageService _storageService = StorageService();

  bool _isClockedIn = false;
  bool _isOnLunch = false;
  bool _isClockedOut = false;
  DateTime? _clockInTime;
  DateTime? _clockOutTime;
  DateTime? _lunchStartTime;
  DateTime? _lunchEndTime;
  double _morningSqft = 0;
  double _afternoonSqft = 0;
  File? _morningPhoto;
  File? _afternoonPhoto;
  String? _morningPhotoUrl;
  String? _afternoonPhotoUrl;
  bool _isLoading = false;
  bool _isUploadingPhoto = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        foregroundColor: Colors.white,
        title: Text('Hi ${widget.user.name} 👷'),
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Card
            _buildStatusCard(),
            const SizedBox(height: 16),

            // Clock In Button
            if (!_isClockedIn && !_isClockedOut)
              _buildActionButton(
                title: 'Clock In',
                subtitle: 'Start your work day',
                icon: Icons.login,
                color: Colors.green,
                onTap: _clockIn,
              ),

            // Clocked In confirmation
            if (_isClockedIn || _isClockedOut)
              _buildConfirmationCard(
                title: 'Clocked In ✅',
                subtitle: 'at ${_formatTime(_clockInTime!)}',
                color: Colors.green,
              ),

            const SizedBox(height: 16),

            // After Clock In
            if (_isClockedIn && !_isClockedOut) ...[
              // Morning sqft and photo
              _buildProgressCard(
                title: '🌅 Morning Progress',
                subtitle: 'Log morning square footage and photo',
                value: _morningSqft,
                photo: _morningPhoto,
                photoUrl: _morningPhotoUrl,
                isMorning: true,
              ),
              const SizedBox(height: 16),

              // Lunch Break
              if (!_isOnLunch && _lunchEndTime == null)
                _buildActionButton(
                  title: 'Start Lunch Break',
                  subtitle: 'Take your lunch break',
                  icon: Icons.lunch_dining,
                  color: Colors.orange,
                  onTap: _startLunch,
                ),

              if (_isOnLunch)
                _buildActionButton(
                  title: 'End Lunch Break',
                  subtitle: 'Back to work',
                  icon: Icons.work,
                  color: Colors.blue,
                  onTap: _endLunch,
                ),

              // Lunch confirmation
              if (_lunchEndTime != null)
                _buildConfirmationCard(
                  title: 'Lunch Break ✅',
                  subtitle:
                      '${_formatTime(_lunchStartTime!)} - ${_formatTime(_lunchEndTime!)}',
                  color: Colors.orange,
                ),

              // Afternoon sqft and photo
              if (_lunchEndTime != null) ...[
                const SizedBox(height: 16),
                _buildProgressCard(
                  title: '🌆 Afternoon Progress',
                  subtitle: 'Log afternoon square footage and photo',
                  value: _afternoonSqft,
                  photo: _afternoonPhoto,
                  photoUrl: _afternoonPhotoUrl,
                  isMorning: false,
                ),
              ],

              const SizedBox(height: 16),

              // Clock Out Button
              if (!_isClockedOut)
                _buildActionButton(
                  title: 'Clock Out',
                  subtitle: 'End your work day',
                  icon: Icons.logout,
                  color: Colors.red,
                  onTap: _clockOut,
                ),
            ],

            // Clock Out confirmation
            if (_isClockedOut) ...[
              const SizedBox(height: 16),
              _buildConfirmationCard(
                title: 'Clocked Out ✅',
                subtitle: 'at ${_formatTime(_clockOutTime!)}',
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              _buildDaySummary(),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildProgressCard({
    required String title,
    required String subtitle,
    required double value,
    required File? photo,
    required String? photoUrl,
    required bool isMorning,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(subtitle, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),

          // Photo Section
          GestureDetector(
            onTap: _isUploadingPhoto
                ? null
                : () => _takePhoto(isMorning: isMorning),
            child: Container(
              width: double.infinity,
              height: 180,
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: photo != null ? Colors.green : Colors.grey.shade300,
                  width: 2,
                ),
              ),
              child: _isUploadingPhoto
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Colors.deepOrange),
                          SizedBox(height: 8),
                          Text('Uploading photo...'),
                        ],
                      ),
                    )
                  : photo != null
                  ? Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(10),
                          child: Image.file(
                            photo,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                          ),
                        ),
                        // Retake button
                        Positioned(
                          top: 8,
                          right: 8,
                          child: GestureDetector(
                            onTap: () => _takePhoto(isMorning: isMorning),
                            child: Container(
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.camera_alt,
                                    color: Colors.white,
                                    size: 16,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Retake',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        // Uploaded badge
                        if (photoUrl != null)
                          Positioned(
                            bottom: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.cloud_done,
                                    color: Colors.white,
                                    size: 14,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Uploaded ✅',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.camera_alt,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tap to take photo',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Show your progress clearly',
                          style: TextStyle(
                            color: Colors.grey[400],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // Sqft Row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '${value.toStringAsFixed(1)} sqft',
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.deepOrange,
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _logSqft(isMorning: isMorning),
                icon: const Icon(Icons.add),
                label: const Text('Log Sqft'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrange,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmationCard({
    required String title,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: color, size: 32),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: color,
                ),
              ),
              Text(subtitle, style: TextStyle(color: color, fontSize: 14)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Today\'s Status',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildStatusItem(
                label: 'Clock In',
                value: _clockInTime != null
                    ? _formatTime(_clockInTime!)
                    : '--:--',
                color: Colors.green,
              ),
              _buildStatusItem(
                label: 'Lunch',
                value: _lunchStartTime != null
                    ? _formatTime(_lunchStartTime!)
                    : '--:--',
                color: Colors.orange,
              ),
              _buildStatusItem(
                label: 'Clock Out',
                value: _clockOutTime != null
                    ? _formatTime(_clockOutTime!)
                    : '--:--',
                color: Colors.red,
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.deepOrange.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total Sqft Today:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${(_morningSqft + _afternoonSqft).toStringAsFixed(1)} sqft',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.deepOrange,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusItem({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ],
    );
  }

  Widget _buildActionButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: _isLoading ? null : onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ],
            ),
            const Spacer(),
            _isLoading
                ? const CircularProgressIndicator(color: Colors.white)
                : const Icon(Icons.arrow_forward_ios, color: Colors.white),
          ],
        ),
      ),
    );
  }

  Widget _buildDaySummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.green,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(Icons.check_circle, color: Colors.white, size: 48),
          const SizedBox(height: 8),
          const Text(
            'Great Work Today! 🎉',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _buildSummaryRow('Clock In', _formatTime(_clockInTime!)),
          _buildSummaryRow('Clock Out', _formatTime(_clockOutTime!)),
          _buildSummaryRow(
            'Morning Sqft',
            '${_morningSqft.toStringAsFixed(1)} sqft',
          ),
          _buildSummaryRow(
            'Afternoon Sqft',
            '${_afternoonSqft.toStringAsFixed(1)} sqft',
          ),
          const Divider(color: Colors.white54),
          _buildSummaryRow(
            'Total Sqft',
            '${(_morningSqft + _afternoonSqft).toStringAsFixed(1)} sqft',
          ),
          const SizedBox(height: 12),
          // Photo summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildPhotoSummary(
                label: 'Morning Photo',
                uploaded: _morningPhotoUrl != null,
              ),
              _buildPhotoSummary(
                label: 'Afternoon Photo',
                uploaded: _afternoonPhotoUrl != null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSummary({required String label, required bool uploaded}) {
    return Column(
      children: [
        Icon(
          uploaded ? Icons.cloud_done : Icons.cloud_off,
          color: uploaded ? Colors.white : Colors.white60,
          size: 32,
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        Text(
          uploaded ? 'Uploaded ✅' : 'Not taken ⚠️',
          style: TextStyle(
            color: uploaded ? Colors.white : Colors.yellow,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70)),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : time.hour;
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute $period';
  }

  Future<void> _takePhoto({required bool isMorning}) async {
    // Show camera or gallery option
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isMorning ? '🌅 Morning Photo' : '🌆 Afternoon Photo',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera_alt, color: Colors.deepOrange),
              title: const Text('Take Photo'),
              subtitle: const Text('Use camera for best quality'),
              onTap: () async {
                Navigator.pop(context);
                await _processPhoto(fromCamera: true, isMorning: isMorning);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.photo_library,
                color: Colors.deepOrange,
              ),
              title: const Text('Choose from Gallery'),
              subtitle: const Text('Select existing photo'),
              onTap: () async {
                Navigator.pop(context);
                await _processPhoto(fromCamera: false, isMorning: isMorning);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _processPhoto({
    required bool fromCamera,
    required bool isMorning,
  }) async {
    File? imageFile = await _storageService.pickImage(fromCamera: fromCamera);

    if (imageFile == null) return;

    setState(() {
      _isUploadingPhoto = true;
      if (isMorning) {
        _morningPhoto = imageFile;
      } else {
        _afternoonPhoto = imageFile;
      }
    });

    // Upload to Firebase Storage
    String? url = await _storageService.uploadProgressPhoto(
      imageFile: imageFile,
      userId: widget.user.id,
      isMorning: isMorning,
    );

    setState(() {
      _isUploadingPhoto = false;
      if (isMorning) {
        _morningPhotoUrl = url;
      } else {
        _afternoonPhotoUrl = url;
      }
    });

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            url != null
                ? '${isMorning ? "Morning" : "Afternoon"} photo uploaded ✅'
                : 'Upload failed. Please try again',
          ),
          backgroundColor: url != null ? Colors.green : Colors.red,
        ),
      );
    }
  }

  Future<void> _clockIn() async {
    setState(() => _isLoading = true);
    try {
      Position position = await _getCurrentLocation();
      setState(() {
        _isClockedIn = true;
        _clockInTime = DateTime.now();
      });

      await _firestoreService.clockIn(
        userId: widget.user.id,
        userName: widget.user.name,
        location: GeoPoint(position.latitude, position.longitude),
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Clocked in at ${_formatTime(_clockInTime!)} ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _startLunch() async {
    setState(() {
      _isOnLunch = true;
      _lunchStartTime = DateTime.now();
    });
    await _firestoreService.updateLunch(
      userId: widget.user.id,
      isStarting: true,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Lunch started at ${_formatTime(_lunchStartTime!)} 🍽️',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  Future<void> _endLunch() async {
    setState(() {
      _isOnLunch = false;
      _lunchEndTime = DateTime.now();
    });
    await _firestoreService.updateLunch(
      userId: widget.user.id,
      isStarting: false,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lunch ended at ${_formatTime(_lunchEndTime!)} 💪'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  Future<void> _clockOut() async {
    setState(() => _isLoading = true);
    try {
      setState(() {
        _isClockedOut = true;
        _isClockedIn = false;
        _clockOutTime = DateTime.now();
      });

      await _firestoreService.clockOut(
        userId: widget.user.id,
        morningSqft: _morningSqft,
        afternoonSqft: _afternoonSqft,
        morningPhotoUrl: _morningPhotoUrl,
        afternoonPhotoUrl: _afternoonPhotoUrl,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Clocked out at ${_formatTime(_clockOutTime!)} ✅'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _logSqft({required bool isMorning}) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isMorning ? '🌅 Morning Sqft' : '🌆 Afternoon Sqft'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Enter square footage',
            suffixText: 'sqft',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              double sqft = double.tryParse(controller.text) ?? 0;
              setState(() {
                if (isMorning) {
                  _morningSqft = sqft;
                } else {
                  _afternoonSqft = sqft;
                }
              });
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepOrange,
              foregroundColor: Colors.white,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<Position> _getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw 'Location services are disabled';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw 'Location permission denied';
      }
    }

    return await Geolocator.getCurrentPosition();
  }

  Future<void> _logout() async {
    await _authService.signOut();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }
}
