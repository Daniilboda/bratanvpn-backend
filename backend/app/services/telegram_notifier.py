"""Send admin alerts via aiogram (no secrets in message text)."""

from __future__ import annotations

import logging

from aiogram import Bot
from aiogram.exceptions import TelegramAPIError

from app.core.config import settings

logger = logging.getLogger(__name__)


class TelegramNotifyError(Exception):
    """Failed to deliver Telegram message."""


def telegram_configured() -> bool:
    return bool(settings.telegram_bot_token and settings.telegram_chat_id)


async def send_telegram_message(text: str) -> None:
    if not telegram_configured():
        raise TelegramNotifyError("Telegram is not configured")

    token = settings.telegram_bot_token
    chat_id = settings.telegram_chat_id
    if token is None or chat_id is None:
        raise TelegramNotifyError("Telegram is not configured")

    bot = Bot(token=token)
    try:
        await bot.send_message(
            chat_id=chat_id,
            text=text,
            disable_web_page_preview=True,
        )
    except TelegramAPIError as exc:
        raise TelegramNotifyError(str(exc)) from exc
    finally:
        await bot.session.close()
