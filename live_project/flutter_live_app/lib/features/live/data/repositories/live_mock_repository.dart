import '../../domain/repositories/live_repository.dart';
import '../models/live_room.dart';

/// 真机播放器联调使用的本地直播数据。
///
/// 这不是正式业务数据源。它的作用是让开发者在后端、VPN 或局域网暂时
/// 不可用时，仍然可以进入真实直播间页面并验证 HLS、PlatformView 和状态
/// 事件。通过 [Environment.useMockLiveData] 选择它，默认不会启用。
class LiveMockRepository implements LiveRepository {
  const LiveMockRepository();

  static const _demoPlayUrl =
      'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8';

  static const _rooms = <LiveRoom>[
    LiveRoom(
      id: 1,
      title: '一起聊聊 Flutter',
      anchorName: '小林',
      anchorAvatar: '',
      onlineCount: 12800,
      coverUrl: '',
      status: 'living',
      playUrl: _demoPlayUrl,
      pushUrl: '',
      streamName: '',
      category: '科技',
    ),
    LiveRoom(
      id: 2,
      title: '深夜音乐直播间',
      anchorName: 'Summer',
      anchorAvatar: '',
      onlineCount: 8260,
      coverUrl: '',
      status: 'living',
      playUrl: _demoPlayUrl,
      pushUrl: '',
      streamName: '',
      category: '音乐',
    ),
    LiveRoom(
      id: 3,
      title: '游戏娱乐直播',
      anchorName: 'Kevin',
      anchorAvatar: '',
      onlineCount: 5630,
      coverUrl: '',
      status: 'living',
      playUrl: _demoPlayUrl,
      pushUrl: '',
      streamName: '',
      category: '游戏',
    ),
    LiveRoom(
      id: 4,
      title: 'Flutter 插件开发',
      anchorName: 'Leo',
      anchorAvatar: '',
      onlineCount: 3680,
      coverUrl: '',
      status: 'living',
      playUrl: _demoPlayUrl,
      pushUrl: '',
      streamName: '',
      category: '科技',
    ),
  ];

  @override
  Future<List<LiveRoom>> getLiveRooms() async => _rooms;

  @override
  Future<LiveRoom> getLiveRoomDetail(String roomId) async {
    final id = int.tryParse(roomId);
    for (final room in _rooms) {
      if (room.id == id) return room;
    }
    throw StateError('Mock 直播间不存在：$roomId');
  }

  @override
  Future<LiveRoom> createLiveRoom({
    required String title,
    required String anchorName,
    required String category,
  }) => throw UnsupportedError('Mock 数据源不支持真实开播');

  @override
  Future<LiveRoom> startLiveRoom(String roomId) =>
      throw UnsupportedError('Mock 数据源不支持真实开播');

  @override
  Future<LiveRoom> stopLiveRoom(String roomId) =>
      throw UnsupportedError('Mock 数据源不支持真实开播');
}
