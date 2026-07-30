import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  // Pick image from camera or gallery
  Future<File?> pickImage({bool fromCamera = true}) async {
    final XFile? image = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 90,
      maxWidth: 1920,
      maxHeight: 1080,
      preferredCameraDevice: CameraDevice.rear,
    );

    if (image == null) return null;
    return File(image.path);
  }

  // Upload image to Firebase Storage
  // Returns the download URL on success, or throws with a clear message on failure.
  Future<String> uploadProgressPhoto({
    required File imageFile,
    required String userId,
    required bool isMorning,
  }) async {
    try {
      // Verify the file exists before uploading
      if (!await imageFile.exists()) {
        throw 'Photo file not found on device';
      }

      String fileName =
          '${userId}_${isMorning ? "morning" : "afternoon"}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      Reference ref = _storage
          .ref()
          .child('progress_photos')
          .child(userId)
          .child(fileName);

      // Upload with metadata
      UploadTask uploadTask = ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // Monitor upload progress (useful for debugging)
      uploadTask.snapshotEvents.listen(
        (TaskSnapshot snapshot) {
          // Progress tracking available if needed in the future
        },
        onError: (e) {
          throw 'Upload stream error: $e';
        },
      );

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } on FirebaseException catch (e) {
      // Surface the actual Firebase error
      switch (e.code) {
        case 'storage/unauthorized':
          throw 'Storage permission denied. Check Firebase Storage rules.';
        case 'storage/canceled':
          throw 'Upload was canceled';
        case 'storage/retry-limit-exceeded':
          throw 'Poor connection. Please try again.';
        case 'storage/quota-exceeded':
          throw 'Storage quota exceeded. Contact admin.';
        case 'storage/object-not-found':
          throw 'Storage path not found';
        default:
          throw 'Upload failed: ${e.message ?? e.code}';
      }
    } catch (e) {
      // Re-throw with context if it's not already a clear message
      if (e is String) rethrow;
      throw 'Upload failed: $e';
    }
  }
}
