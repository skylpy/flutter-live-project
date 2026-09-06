import '../datasources/profile_remote_data_source.dart';
import '../models/profile.dart';
import 'profile_repository.dart';

class ProfileRepositoryImpl implements ProfileRepository {
  const ProfileRepositoryImpl(this._dataSource);

  final ProfileRemoteDataSource _dataSource;

  @override
  Future<Profile> getProfile() => _dataSource.getProfile();

  @override
  Future<Profile> updateDisplayName(String displayName) =>
      _dataSource.updateDisplayName(displayName);
}
