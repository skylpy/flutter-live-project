import '../models/profile.dart';

abstract interface class ProfileRepository {
  Future<Profile> getProfile();

  Future<Profile> updateDisplayName(String displayName);
}
