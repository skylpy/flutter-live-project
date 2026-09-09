import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_live_app/features/discover/data/models/feed_post.dart';

void main() {
  test('FeedPost parses signed media returned by the backend', () {
    final post = FeedPost.fromJson({
      'id': 9,
      'authorId': 1,
      'author': 'Kevin',
      'body': '图片动态',
      'timeLabel': '刚刚',
      'likes': 0,
      'comments': 0,
      'shares': 0,
      'liked': false,
      'mediaKind': 'image',
      'media': [
        {
          'fileId': 3,
          'mediaType': 'image',
          'url': 'https://oss.example.invalid/flutter/image/1/photo.jpg',
        },
      ],
      'commentsPreview': [
        {
          'id': 18,
          'authorId': 2,
          'author': 'Summer',
          'body': '看起来很棒',
          'timeLabel': '刚刚',
        },
      ],
      'canDelete': true,
    });

    expect(post.mediaKind, FeedMediaKind.image);
    expect(post.media.single.fileId, 3);
    expect(post.media.single.isVideo, isFalse);
    expect(post.commentsPreview.single.body, '看起来很棒');
    expect(post.canDelete, isTrue);
  });

  test('FeedAuthorProfile parses follow state and posts', () {
    final profile = FeedAuthorProfile.fromJson({
      'id': 3,
      'username': 'summer',
      'displayName': 'Summer',
      'followingCount': 2,
      'followerCount': 6,
      'postCount': 1,
      'following': true,
      'isSelf': false,
      'posts': const [],
    });

    expect(profile.displayName, 'Summer');
    expect(profile.following, isTrue);
    expect(profile.isSelf, isFalse);
  });
}
