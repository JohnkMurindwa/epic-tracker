import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';

class StorageService {
  final FirebaseStorage _storage = FirebaseStorage.instance;
  final ImagePicker _picker = ImagePicker();

  // Pick image from camera or gallery
  // Pick image from camera or gallery
  Future<File?> pickImage({bool fromCamera = true}) async {
    final XFile? image = await _picker.pickImage(
      source: fromCamera ? ImageSource.camera : ImageSource.gallery,
      imageQuality: 90, // Higher quality ✅
      maxWidth: 1920, // Full HD width ✅
      maxHeight: 1080, // Full HD height ✅
      preferredCameraDevice: CameraDevice.rear, // Always use rear camera ✅
    );

    if (image == null) return null;
    return File(image.path);
  }

  // Upload image to Firebase Storage
  Future<String?> uploadProgressPhoto({
    required File imageFile,
    required String userId,
    required bool isMorning,
  }) async {
    try {
      String fileName =
          '${userId}_${isMorning ? "morning" : "afternoon"}_${DateTime.now().millisecondsSinceEpoch}.jpg';

      Reference ref = _storage
          .ref()
          .child('progress_photos')
          .child(userId)
          .child(fileName);

      UploadTask uploadTask = ref.putFile(imageFile);
      TaskSnapshot snapshot = await uploadTask;
      String downloadUrl = await snapshot.ref.getDownloadURL();

      return downloadUrl;
    } catch (e) {
      print('Upload error: $e');
      return null;
    }
  }
}
