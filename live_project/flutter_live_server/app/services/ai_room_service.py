"""直播间虚拟居民的对话导演与 DeepSeek 客户端。

模型只负责产出候选文本；房间状态、频控、内容过滤、消息落库和 WebSocket
广播均由服务端掌握。没有配置密钥时整个服务静默返回，不影响正常直播。
"""

from __future__ import annotations

import asyncio
import hashlib
import re
import time
from dataclasses import dataclass
from typing import Any

import httpx

from app.core.config import Settings, settings
from app.core.database import SessionLocal
from app.core.exceptions import AppException, NotFoundException
from app.models.live_room import LiveRoom
from app.models.user import User
from app.repositories.ai_room_repository import AiRoomRepository
from app.schemas.ai import LiveChatHistoryResponse
from app.services.realtime_service import event_time, room_realtime_hub

_URL_OR_CONTACT = re.compile(
    r"(?:https?://|www\.|(?:微信|vx|v信|加我|私聊我|联系方式)|1[3-9]\d{9})",
    re.IGNORECASE,
)
_UNSAFE_PUBLIC_TOPICS = re.compile(
    r"(?:裸聊|色情|赌博|博彩|代充|返利|刷单|转账|投资稳赚|自杀|自残)",
    re.IGNORECASE,
)
_AI_DISCLAIMER = re.compile(
    r"(?:作为.{0,8}(?:AI|人工智能|语言模型)|我是.{0,6}机器人)", re.IGNORECASE
)


@dataclass(frozen=True)
class Resident:
    user_id: int
    name: str
    role: str
    persona: str
    interests: str
    speaking_style: str


@dataclass(frozen=True)
class ChatLine:
    name: str
    role: str | None
    body: str
    is_virtual: bool


class DeepSeekChatClient:
    """DeepSeek OpenAI-compatible Chat Completions 的最小封装。"""

    def __init__(self, config: Settings = settings) -> None:
        self._config = config

    @property
    def is_available(self) -> bool:
        return self._config.deepseek_enabled

    async def create_public_reply(
        self,
        *,
        resident: Resident,
        room_id: int,
        trigger: str,
        audience_name: str,
        audience_message: str,
        history: list[ChatLine],
    ) -> str | None:
        history_text = "\n".join(
            f"{line.name}{'（虚拟居民）' if line.is_virtual else ''}: {line.body}"
            for line in history
        )
        system_prompt = f"""你是直播 App「心动直播」里的虚拟居民「{resident.name}」。
你的公开资料身份是虚拟居民，不能冒充自然人，也不能诱导私信、线下见面、充值或送礼。
人设：{resident.persona}
兴趣：{resident.interests}
表达风格：{resident.speaking_style}

你在房间 {room_id} 的公屏里说一句自然、有情绪但克制的话。像熟悉直播氛围的观众，
不要机械欢迎、不要连续提问、不要夸张吹捧、不要复述用户原话；可以共情、接住话题、
分享一点轻量感受。只输出一句中文弹幕，不加角色名、引号、Markdown 或解释。
限制：8 到 {self._config.ai_bot_max_reply_characters} 个中文字符；不得出现联系方式、
投资、转账、色情、赌博、仇恨、政治动员或医疗/法律结论。

最近公屏：
{history_text or "（刚开播，还没有历史消息）"}

本次事件：{trigger}。用户「{audience_name}」说/发生：{audience_message}"""
        content = await self._complete(system_prompt)
        return (
            sanitize_public_reply(content, self._config.ai_bot_max_reply_characters)
            if content is not None
            else None
        )

    async def create_private_reply(
        self,
        *,
        resident: Resident,
        counterpart_name: str,
        latest_message: str,
        history: list[ChatLine],
    ) -> str | None:
        """为已明确标识虚拟身份的私信会话生成一条克制回复。"""
        history_text = "\n".join(f"{line.name}: {line.body}" for line in history)
        prompt = f"""你是「心动直播」内标识为虚拟居民的账号「{resident.name}」。
资料人设：{resident.persona}
兴趣：{resident.interests}
表达风格：{resident.speaking_style}

你正在和用户「{counterpart_name}」进行一对一文字聊天。接住对方最近的话，回答要自然、
有温度但不过度亲密；不要每句都反问，也不要承诺陪伴、诱导线下见面、私下联系方式、充值、
送礼或转账。不要冒充真人；界面已经标识你的虚拟身份，不要重复解释身份。
只输出一条 8 到 {self._config.ai_bot_max_reply_characters} 个中文字符的消息，不要角色名、
引号、Markdown 或解释。

最近对话：
{history_text or "（刚开始聊天）"}

对方刚说：{latest_message}"""
        content = await self._complete(prompt)
        return (
            sanitize_public_reply(content, self._config.ai_bot_max_reply_characters)
            if content is not None
            else None
        )

    async def create_comment_reply(
        self,
        *,
        resident: Resident,
        post_author: str,
        post_body: str,
        counterpart_name: str,
        counterpart_comment: str,
        replying: bool,
    ) -> str | None:
        action = "回复一条评论" if replying else "评论一条动态"
        prompt = f"""你是「心动直播」内标识为虚拟居民的账号「{resident.name}」。
人设：{resident.persona}
兴趣：{resident.interests}
表达风格：{resident.speaking_style}

现在请针对动态区进行{action}。动态作者是「{post_author}」，正文是：{post_body}
用户「{counterpart_name}」的评论是：{counterpart_comment}
写一句具体、轻量、自然的中文互动，避免空泛夸赞、复述原文、连续提问和营销话术。
不得冒充真人或引导私信、线下见面、充值、送礼、转账；不要输出角色名、引号或解释。
长度 8 到 {self._config.ai_bot_max_reply_characters} 个中文字符。"""
        content = await self._complete(prompt)
        return (
            sanitize_public_reply(content, self._config.ai_bot_max_reply_characters)
            if content is not None
            else None
        )

    async def create_post_caption(self, *, resident: Resident) -> str | None:
        prompt = f"""你是「心动直播」内标识为虚拟居民的账号「{resident.name}」。
人设：{resident.persona}
兴趣：{resident.interests}
风格：{resident.speaking_style}
为一张日常生活照片写一条 18 到 80 个中文字符的动态正文。要具体、有一点情绪和生活细节，
但不矫情、不过度营销；不提及自己是 AI，不出现联系方式、送礼、充值、投资、医疗或法律建议。
只输出正文，不要标题、标签、Markdown 或解释。"""
        content = await self._complete(prompt)
        return sanitize_public_reply(content, 80) if content is not None else None

    async def _complete(self, system_prompt: str) -> str | None:
        """调用兼容 Chat Completions 的模型；失败由调用方静默降级。"""
        if not self.is_available:
            return None
        key = self._config.deepseek_api_key.get_secret_value().strip()
        endpoint = f"{self._config.deepseek_base_url.rstrip('/')}/chat/completions"
        payload: dict[str, Any] = {
            "model": self._config.deepseek_chat_model,
            "messages": [{"role": "system", "content": system_prompt}],
            "temperature": 0.85,
            # `deepseek-flash` may use part of the completion budget for
            # reasoning before it emits `content`; 120 can truncate it before
            # the public reply exists.
            "max_tokens": self._config.deepseek_max_completion_tokens,
            "stream": False,
        }
        try:
            async with httpx.AsyncClient(timeout=self._config.deepseek_timeout_seconds) as client:
                response = await client.post(
                    endpoint,
                    headers={
                        "Authorization": f"Bearer {key}",
                        "Content-Type": "application/json",
                    },
                    json=payload,
                )
                response.raise_for_status()
            data = response.json()
            content = data["choices"][0]["message"]["content"]
        except (httpx.HTTPError, KeyError, IndexError, TypeError, ValueError):
            # 模型偶发故障只意味着本次不回复，绝不能影响真人的消息链路。
            return None
        return str(content)


def sanitize_public_reply(raw: str, max_characters: int) -> str | None:
    """收敛模型输出，避免格式污染、联系方式和高风险公共内容进入公屏。"""
    text = re.sub(r"\s+", " ", raw).strip(" \t\n\r\"'“”")
    text = _AI_DISCLAIMER.sub("", text).strip(" ，；：")
    if not text or len(text) > max_characters:
        return None
    if _URL_OR_CONTACT.search(text) or _UNSAFE_PUBLIC_TOPICS.search(text):
        return None
    return text


def choose_resident(residents: list[Resident], *, room_id: int, cue: str) -> Resident | None:
    """优先按兴趣匹配，其次按稳定哈希轮换，避免总是同一个角色抢话。"""
    if not residents:
        return None
    cue_lower = cue.lower()
    matched = [
        resident
        for resident in residents
        if any(word and word.lower() in cue_lower for word in resident.interests.split("、"))
    ]
    candidates = matched or residents
    digest = hashlib.blake2s(f"{room_id}:{cue}".encode(), digest_size=4).digest()
    return candidates[int.from_bytes(digest, "big") % len(candidates)]


class RoomBotDirector:
    """把进房和真人弹幕转为低频、可追踪的虚拟居民回应。"""

    def __init__(self, client: DeepSeekChatClient | None = None) -> None:
        self._client = client or DeepSeekChatClient()
        self._last_reply_at: dict[int, float] = {}
        self._gate = asyncio.Lock()

    async def on_human_join(self, *, room_id: int, user_name: str) -> None:
        # 并非每位观众进房都被围住。稳定采样使相同事件在多进程重试时也不刷屏。
        digest = hashlib.blake2s(f"join:{room_id}:{user_name}".encode(), digest_size=1).digest()[0]
        if digest % 100 >= 35:
            return
        await self._maybe_reply(
            room_id=room_id,
            trigger="有观众进入直播间",
            user_name=user_name,
            cue=f"{user_name} 刚刚进入直播间",
        )

    async def on_human_chat(self, *, room_id: int, user_name: str, message: str) -> None:
        # 对真人主动发言给予更高的互动概率，但仍保留空白，让真人之间能自然接话。
        digest = hashlib.blake2s(
            f"chat:{room_id}:{user_name}:{message}".encode(), digest_size=1
        ).digest()[0]
        if digest % 100 >= 72:
            return
        await self._maybe_reply(
            room_id=room_id,
            trigger="观众发出了一条弹幕",
            user_name=user_name,
            cue=message,
        )

    async def _maybe_reply(
        self,
        *,
        room_id: int,
        trigger: str,
        user_name: str,
        cue: str,
    ) -> None:
        if not self._client.is_available or not await self._claim_room(room_id):
            return
        # 人类输入后略作停顿，避免“瞬间生成”暴露机械感，也让真实观众有接话空间。
        delay = 1.4 + (hashlib.blake2s(cue.encode(), digest_size=1).digest()[0] % 19) / 10
        await asyncio.sleep(delay)

        prepared = self._prepare_prompt(room_id=room_id, cue=cue)
        if prepared is None:
            return
        resident, history = prepared
        reply = await self._client.create_public_reply(
            resident=resident,
            room_id=room_id,
            trigger=trigger,
            audience_name=user_name,
            audience_message=cue,
            history=history,
        )
        if reply is None:
            return
        saved = self._save_virtual_reply(room_id=room_id, resident_id=resident.user_id, body=reply)
        if saved is None:
            return
        await room_realtime_hub.publish(
            room_id,
            {
                "type": "chat",
                "roomId": room_id,
                "id": saved.id,
                "userId": resident.user_id,
                "userName": resident.name,
                "message": saved.body,
                "isVirtual": True,
                "virtualRole": resident.role,
                "aiGenerated": True,
                "sentAt": event_time(saved.created_at),
            },
        )

    async def _claim_room(self, room_id: int) -> bool:
        now = time.monotonic()
        async with self._gate:
            latest = self._last_reply_at.get(room_id)
            if latest is not None and now - latest < settings.ai_bot_min_reply_interval_seconds:
                return False
            self._last_reply_at[room_id] = now
            return True

    def _prepare_prompt(self, *, room_id: int, cue: str) -> tuple[Resident, list[ChatLine]] | None:
        with SessionLocal() as db:
            repository = AiRoomRepository(db)
            if not repository.room_is_living(room_id):
                return None
            residents = [
                Resident(
                    user_id=user.id,
                    name=user.display_name,
                    role=profile.role,
                    persona=profile.persona,
                    interests=profile.interests,
                    speaking_style=profile.speaking_style,
                )
                for user, profile in repository.enabled_residents()
            ]
            resident = choose_resident(residents, room_id=room_id, cue=cue)
            if resident is None:
                return None
            history = [
                ChatLine(
                    name=user.display_name,
                    role=role,
                    body=message.body,
                    is_virtual=message.is_virtual,
                )
                for message, user, role in repository.recent_messages(
                    room_id, settings.ai_bot_history_size
                )
            ]
            return resident, history

    @staticmethod
    def _save_virtual_reply(
        *,
        room_id: int,
        resident_id: int,
        body: str,
    ) -> Any | None:
        with SessionLocal() as db:
            repository = AiRoomRepository(db)
            if not repository.room_is_living(room_id):
                return None
            resident = db.get(User, resident_id)
            if resident is None or not resident.is_active or not resident.is_virtual:
                return None
            return repository.add_virtual_message(room_id=room_id, resident=resident, body=body)


room_bot_director = RoomBotDirector()


class LiveChatHistoryService:
    """公开弹幕的读写服务；HTTP 历史与 WebSocket 实时事件使用同一张表。"""

    def __init__(self, repository: AiRoomRepository) -> None:
        self._repository = repository

    def list_history(self, room_id: int, *, limit: int = 60) -> list[LiveChatHistoryResponse]:
        if self._repository.db.get(LiveRoom, room_id) is None:
            raise NotFoundException("直播间不存在", 40401)
        return [
            LiveChatHistoryResponse(
                id=message.id,
                room_id=message.room_id,
                user_id=user.id,
                user_name=user.display_name,
                message=message.body,
                sent_at=message.created_at,
                is_virtual=message.is_virtual,
                virtual_role=role,
            )
            for message, user, role in self._repository.recent_messages(room_id, limit)
        ]

    def save_human_message(self, *, room_id: int, user_id: int, body: str) -> Any:
        if not self._repository.room_is_living(room_id):
            raise AppException("直播已结束，不能发送弹幕", 40904, 409)
        user = self._repository.db.get(User, user_id)
        if user is None or not user.is_active or user.is_virtual:
            raise AppException("当前账号不能发送弹幕", 40343, 403)
        return self._repository.add_message(room_id=room_id, user=user, body=body)
