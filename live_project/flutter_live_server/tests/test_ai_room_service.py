from app.core.config import Settings
from app.services.ai_room_service import (
    DeepSeekChatClient,
    Resident,
    choose_resident,
    sanitize_public_reply,
)


def test_choose_resident_prefers_a_matching_interest_and_is_stable() -> None:
    music = Resident(
        user_id=1,
        name="听雨",
        role="music_fan",
        persona="音乐爱好者",
        interests="音乐、歌单、现场",
        speaking_style="安静自然",
    )
    game = Resident(
        user_id=2,
        name="星野",
        role="game_buddy",
        persona="游戏搭子",
        interests="游戏、开黑、键盘",
        speaking_style="直爽友好",
    )

    first = choose_resident([music, game], room_id=7, cue="这首音乐的前奏真好听")
    second = choose_resident([music, game], room_id=7, cue="这首音乐的前奏真好听")

    assert first == music
    assert second == music


def test_public_reply_is_short_clean_and_rejects_risky_content() -> None:
    assert (
        sanitize_public_reply("  这句一下把我拉回那个画面了。  ", 72)
        == "这句一下把我拉回那个画面了。"
    )
    assert sanitize_public_reply("加我微信一起聊", 72) is None
    assert sanitize_public_reply("我的电话是 13800138000", 72) is None
    assert sanitize_public_reply("x" * 73, 72) is None


def test_client_is_silent_without_a_deepseek_key() -> None:
    client = DeepSeekChatClient(Settings(ai_bots_enabled=True, deepseek_api_key=""))

    assert client.is_available is False
