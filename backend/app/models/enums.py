from enum import Enum


class AccessKeyStatus(str, Enum):
    CREATED = "created"
    ACTIVATED = "activated"
    REVOKED = "revoked"