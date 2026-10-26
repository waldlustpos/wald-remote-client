#!/usr/bin/env python3
"""수신 전용 빌드의 공통 영구 비밀번호 해시 생성기(DSK-01·DSK-02).

평문 비밀번호는 환경변수 WALDLUST_INCOMING_PASSWORD, 솔트는 WALDLUST_INCOMING_SALT 로만
받는다(명령줄 인자로 받지 않는다 — 프로세스 목록·셸 기록에 남지 않게). 출력은 두 줄이다.

  WALDLUST_INCOMING_PW_STORAGE=00<base64(SHA-256(비밀번호 + 솔트))>
  WALDLUST_INCOMING_PW_SALT=<솔트>

hbb_common 의 사전 비밀번호 형식(config/permanent_password.rs 의 compute_permanent_password_h1
+ "00" 접두 + 표준 base64)과 같다. 빌드에는 이 해시만 들어가고 평문은 들어가지 않는다.
출력은 $GITHUB_ENV 나 export 로만 넘기고 로그에 찍지 않는다.

- 비밀번호: 랜덤 16자 이상. SHA-256 1회 해시라 약한 값은 배포 파일에서 역산될 수 있다.
- 솔트: 16자 이상 [A-Za-z0-9_-]. 비밀번호를 바꿀 때만 새로 만든다. 제어측은 기억한 비밀번호를
  솔트에 묶어 저장하므로(src/client.rs handle_login_from_ui) 솔트가 바뀌면 다시 입력해야 한다.
  새 솔트 예: python3 -c "import secrets; print(secrets.token_urlsafe(24))"

사용(저장소 루트에서):
  WALDLUST_INCOMING_PASSWORD=... WALDLUST_INCOMING_SALT=... python3 res/wald-variant/preset_hash.py

--field-key-sha256 을 주면 위 두 줄 대신 현장 앱 안 업데이트(결정 D44)의 받기 키 해시 한 줄만 낸다.
받기 키는 앱이 저장 해시에서 계산한다(src/wald_variant.rs field_update_key — 라벨이 같아야 한다).
어드민은 키가 아니라 이 SHA-256 만 env APP_FIELD_UPDATE_KEYS_SHA256(쉼표 목록)에 둔다.
  APP_FIELD_UPDATE_KEYS_SHA256=<SHA-256(받기 키) hex>
"""

import base64
import hashlib
import os
import re
import sys

MIN_PASSWORD_LEN = 16
SALT_RE = re.compile(r"^[A-Za-z0-9_-]{16,}$")
FIELD_KEY_LABEL = "waldlust-field-update-v1:"


def storage_of(password: str, salt: str) -> str:
    h1 = hashlib.sha256(password.encode("utf-8") + salt.encode("utf-8")).digest()
    return "00" + base64.b64encode(h1).decode("ascii")


def field_key_sha256_of(storage: str) -> str:
    key = hashlib.sha256((FIELD_KEY_LABEL + storage).encode("utf-8")).hexdigest()
    return hashlib.sha256(key.encode("ascii")).hexdigest()


def main() -> int:
    password = os.environ.get("WALDLUST_INCOMING_PASSWORD", "")
    salt = os.environ.get("WALDLUST_INCOMING_SALT", "")
    if len(password) < MIN_PASSWORD_LEN:
        print(f"WALDLUST_INCOMING_PASSWORD 가 없거나 {MIN_PASSWORD_LEN}자보다 짧다", file=sys.stderr)
        return 1
    if not SALT_RE.match(salt):
        print("WALDLUST_INCOMING_SALT 가 없거나 형식이 틀렸다(16자 이상 [A-Za-z0-9_-])", file=sys.stderr)
        return 1
    if "--field-key-sha256" in sys.argv[1:]:
        print(f"APP_FIELD_UPDATE_KEYS_SHA256={field_key_sha256_of(storage_of(password, salt))}")
        return 0
    print(f"WALDLUST_INCOMING_PW_STORAGE={storage_of(password, salt)}")
    print(f"WALDLUST_INCOMING_PW_SALT={salt}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
