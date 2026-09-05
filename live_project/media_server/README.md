# 本地媒体服务器

本目录使用 SRS 接收 Android/iOS 的 RTMP 推流，并生成 HLS 播放地址。FastAPI
会把 `MEDIA_SERVER_HOST`、端口和随机 `stream_name` 拼成每个房间的 `pushUrl`
与 `playUrl`。

## 启动

在已安装 Docker Desktop 的 Mac 上执行：

```bash
cd live_project/media_server
SRS_CANDIDATE=192.168.0.111 docker compose up -d
docker compose logs -f srs
```

手机和 Mac 必须在同一个局域网，且防火墙允许 1935、8080、8000/UDP。验证服务：

```bash
curl http://192.168.0.111:1985/api/v1/versions
```

测试房间创建后，主播推流地址类似：

```text
rtmp://192.168.0.111:1935/live/room_xxx
```

观众播放地址类似：

```text
http://192.168.0.111:8080/live/room_xxx.m3u8
```

当前环境若尚未安装 Docker，只能先完成代码、配置和编译验证；真实一推一拉
需要 Docker Desktop/其他 SRS 部署方式启动后再测。
