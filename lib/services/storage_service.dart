import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;

  // Upload image to Firebase Storage
  // Kept for future use when photo feature returns.
  Future<String> uploadProgressPhoto({
    required File imageFile,
    required String userId,
    required bool isMorning,
  }) async {
    try {
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

      UploadTask uploadTask = ref.putFile(
        imageFile,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } on FirebaseException catch (e) {
      switch (e.code) {
        case 'storage/unauthorized':
          throw 'Storage permission denied. Check Firebase Storage rules.';
        case 'storage/canceled':
          throw 'Upload was canceled';
        case 'storage/retry-limit-exceeded':
          throw 'Poor connection. Please try again.';
        default:
          throw 'Upload failed: ${e.message ?? e.code}';
      }
    } catch (e) {
      if (e is String) rethrow;
      throw 'Upload failed: $e';
    }
  }
}
